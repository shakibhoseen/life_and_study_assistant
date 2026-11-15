#!/usr/bin/env python3
"""
Prove a refactor did not quietly change what the app says.

A Fluent restyle once rewrote eleven Bengali labels in the Mistake Notebook
as placeholder tokens — "TITLE_NOTEBOOK", "ST_PENDING" — and they shipped to
the screen. Nothing caught it, because the code still compiled and the
widgets still laid out.

This compares every string literal under lib/ between a git ref and the
working tree, and reports the user-facing ones that disappeared. It is meant
to be run after any change that claims to be visual-only.

    scripts/check_ui_strings.py HEAD
    scripts/check_ui_strings.py 5b797f9^

Exit code is 1 if anything user-facing was lost, so it can gate a commit.

Line re-wrapping is not a loss: a literal broken across two source lines is
still the same text at runtime, so literals are compared after the adjacent
ones are joined.
"""
import collections
import pathlib
import re
import subprocess
import sys
import unicodedata

# Anything with a Bengali codepoint, or a run of words long enough to be a
# sentence someone reads. Identifiers, keys, asset paths and SQL are short,
# snake_case or dotted, and are skipped.
BENGALI = re.compile(r"[ঀ-৿]")
SENTENCE = re.compile(r"^[A-Z][^_/.]*\s\S+\s\S+")

LITERAL = re.compile(
    r"""
    '((?:[^'\\\n]|\\.)*)'   # single-quoted
    |
    "((?:[^"\\\n]|\\.)*)"   # double-quoted
    """,
    re.VERBOSE,
)


def user_facing(text):
    """Is this literal something a person reads on screen?"""
    t = text.strip()
    if len(t) < 2:
        return False
    if BENGALI.search(t):
        return True
    return bool(SENTENCE.match(t))


# Log calls. Their text is for whoever is reading logcat, not for anyone
# using the app, and rewording one is not a regression. Left in, they match
# the sentence heuristic below and cry wolf, which is worse than useless in a
# guard meant to be trusted.
LOG_CALL = re.compile(r"\b(?:debugPrint|print|log|dev\.log)\s*\(", re.M)


def strip_log_calls(source):
    """Removes the arguments of log calls, brackets balanced."""
    out = []
    i = 0
    for m in LOG_CALL.finditer(source):
        if m.start() < i:
            continue
        out.append(source[i:m.end()])
        depth = 1
        j = m.end()
        while j < len(source) and depth:
            c = source[j]
            if c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
            j += 1
        i = j - 1 if depth == 0 else len(source)
    out.append(source[i:])
    return "".join(out)


def literals(source):
    """Every user-facing literal in one file, as a multiset.

    Adjacent string literals are concatenated by Dart, so `'a'\n'b'` is one
    runtime string. They are joined here too, otherwise re-wrapping a long
    sentence reads as two losses and one gain.
    """
    source = strip_log_calls(source)
    joined = re.sub(r"'\s*\n\s*'", "", source)
    joined = re.sub(r'"\s*\n\s*"', "", joined)
    found = collections.Counter()
    for m in LITERAL.finditer(joined):
        text = m.group(1) if m.group(1) is not None else m.group(2)
        if text and user_facing(text):
            # Re-wrapping a sentence can move a space across the split, and
            # Bengali conjuncts have more than one valid byte sequence for
            # the same glyphs. Neither is a change to what the app says.
            key = unicodedata.normalize("NFC", " ".join(text.split()))
            found[key] += 1
    return found


def at_ref(ref, path):
    out = subprocess.run(
        ["git", "show", f"{ref}:{path}"], capture_output=True, text=True
    )
    return out.stdout if out.returncode == 0 else None


def main():
    ref = sys.argv[1] if len(sys.argv) > 1 else "HEAD"

    changed = subprocess.run(
        ["git", "diff", "--name-only", ref, "--", "lib/"],
        capture_output=True,
        text=True,
    ).stdout.split()

    losses = 0
    for path in changed:
        if not path.endswith(".dart") or path.endswith(".g.dart"):
            continue
        before = at_ref(ref, path)
        if before is None:
            continue  # new file
        p = pathlib.Path(path)
        if not p.exists():
            print(f"DELETED  {path}")
            continue
        lost = literals(before) - literals(p.read_text(encoding="utf-8"))
        if lost:
            print(f"\n{path}")
            for text, n in lost.items():
                shown = text if len(text) <= 72 else text[:69] + "..."
                print(f"  -{n}x  {shown}")
            losses += sum(lost.values())

    if losses:
        print(
            f"\n{losses} user-facing string(s) lost since {ref}.\n"
            "A visual change should not alter what the app says. Restore them "
            "from that ref, or say in the commit why the wording changed."
        )
        return 1

    print(f"No user-facing strings lost since {ref}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
