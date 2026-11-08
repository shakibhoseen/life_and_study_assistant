import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the floating bubble has added since the user last looked at the app.
///
/// The bubble runs in its own Flutter engine, with its own isolate and its own
/// database connection, so it can hand the app nothing directly — and its
/// writes do not even reach the connection the app already has open, which is
/// why a question dictated into the bubble used to be invisible in the Mistake
/// Bank until the app was restarted. The two sides meet here instead, in
/// SharedPreferences, which is one file for the whole process.
///
/// Only titles are kept. The questions themselves are already in the database;
/// this is the note saying they are there and have not been looked at.
class BubbleHandoffService {
  BubbleHandoffService._();
  static final BubbleHandoffService instance = BubbleHandoffService._();

  static const String _titlesKey = 'bubble_pending_titles';

  /// Set by the bubble just before it brings the app to the front.
  ///
  /// Without it the app cannot tell the two ways in apart, and taking someone
  /// to the Mistake Bank because they opened the app themselves — to start a
  /// timer, hours after dictating something — is taking the screen away from
  /// the thing they actually came to do.
  static const String _openedKey = 'bubble_opened_app';

  /// Words written in the bubble but not yet turned into a question.
  ///
  /// The bubble is a cramped window over somebody else's app, and finishing a
  /// note there is the hard way to do it. Carrying the words across means the
  /// bubble only has to be good enough to catch the thought; the app's own
  /// voice sheet, with its full keyboard and screen, is where it gets
  /// finished.
  static const String _draftKey = 'bubble_draft_text';

  /// At most this many titles are kept.
  ///
  /// The count is what the app shows; the titles are only there to say which
  /// ones, and a list longer than this would be read by nobody.
  static const int maxTitles = 20;

  Future<SharedPreferences> _prefs() async {
    final prefs = await SharedPreferences.getInstance();
    // Each engine keeps its own cache of this file, so without the reload the
    // app reads what it saw before the bubble ever wrote anything.
    await prefs.reload();
    return prefs;
  }

  /// Notes one more question the bubble has just saved.
  Future<void> noteAdded(String title) async {
    try {
      final prefs = await _prefs();
      final titles = List<String>.from(
        prefs.getStringList(_titlesKey) ?? const <String>[],
      );
      final trimmed = title.trim();
      titles.add(
        trimmed.length > 80 ? '${trimmed.substring(0, 80)}…' : trimmed,
      );
      if (titles.length > maxTitles) {
        titles.removeRange(0, titles.length - maxTitles);
      }
      await prefs.setStringList(_titlesKey, titles);
    } catch (e) {
      debugPrint('Bubble handoff: could not note the addition: $e');
    }
  }

  /// What is waiting to be looked at, oldest first. Empty when there is
  /// nothing, which is the ordinary case.
  Future<List<String>> pending() async {
    try {
      final prefs = await _prefs();
      return prefs.getStringList(_titlesKey) ?? const <String>[];
    } catch (e) {
      debugPrint('Bubble handoff: could not read what is pending: $e');
      return const <String>[];
    }
  }

  /// Hands the half-written note to the app.
  ///
  /// Empty text clears whatever was there, so a draft the user has since
  /// thrown away does not come back on the next trip across.
  Future<void> noteDraft(String text) async {
    try {
      final prefs = await _prefs();
      final trimmed = text.trim();
      if (trimmed.isEmpty) {
        await prefs.remove(_draftKey);
      } else {
        await prefs.setString(_draftKey, trimmed);
      }
    } catch (e) {
      debugPrint('Bubble handoff: could not pass the draft across: $e');
    }
  }

  /// The waiting draft, cleared as it is read so it arrives exactly once.
  Future<String?> takeDraft() async {
    try {
      final prefs = await _prefs();
      final draft = prefs.getString(_draftKey);
      if (draft != null) await prefs.remove(_draftKey);
      return (draft == null || draft.isEmpty) ? null : draft;
    } catch (e) {
      debugPrint('Bubble handoff: could not read the draft: $e');
      return null;
    }
  }

  /// Records that the bubble itself is opening the app.
  Future<void> noteOpeningApp() async {
    try {
      final prefs = await _prefs();
      await prefs.setBool(_openedKey, true);
    } catch (e) {
      debugPrint('Bubble handoff: could not note the app opening: $e');
    }
  }

  /// Whether the bubble opened the app, clearing the flag as it reads it.
  ///
  /// Consumed rather than merely read: it answers for this one arrival, and
  /// leaving it set would make every later resume look like it came from the
  /// bubble.
  Future<bool> takeOpenedFromBubble() async {
    try {
      final prefs = await _prefs();
      final opened = prefs.getBool(_openedKey) ?? false;
      if (opened) await prefs.remove(_openedKey);
      return opened;
    } catch (e) {
      debugPrint('Bubble handoff: could not read how the app was opened: $e');
      return false;
    }
  }

  /// Called once the user has been shown what was added.
  Future<void> clear() async {
    try {
      final prefs = await _prefs();
      await prefs.remove(_titlesKey);
    } catch (e) {
      debugPrint('Bubble handoff: could not clear what is pending: $e');
    }
  }
}
