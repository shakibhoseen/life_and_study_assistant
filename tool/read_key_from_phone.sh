#!/usr/bin/env bash
# Prints the Gemini API key the app already stores on the connected phone.
#
# Keeps the key out of the repository, out of shell history and out of any
# transcript: it is read at the moment it is needed and goes straight into the
# environment of one command.
#
#   GEMINI_API_KEY=$(tool/read_key_from_phone.sh) dart run tool/prompt_lab.dart text "hi"
#
# Needs a debug build installed, since run-as only works on a debuggable app.
set -euo pipefail
PKG=com.example.life_and_study_assistant

adb exec-out run-as "$PKG" cat shared_prefs/FlutterSharedPreferences.xml 2>/dev/null \
  | tr '<' '\n' \
  | grep 'name="flutter.gemini_api_key"' \
  | sed -E 's/.*>([^<]*)$/\1/' \
  | head -1
