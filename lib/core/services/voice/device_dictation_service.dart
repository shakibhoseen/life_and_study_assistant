import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:overlay_bridge/overlay_bridge.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Turns speech into text using the phone's own recogniser.
///
/// Sending the audio to Gemini works, but was measured at up to 159 seconds
/// for a one-minute note and fails outright while the model is busy. The
/// handset already does this: it runs locally, returns as you speak, costs
/// nothing and needs no network. What then goes to the model is a short
/// piece of text, which is the fast path.
class DeviceDictationService {
  DeviceDictationService._();
  static final DeviceDictationService instance = DeviceDictationService._();

  final SpeechToText _speech = SpeechToText();
  bool _available = false;
  bool get isListening => _speech.isListening;

  /// Bengali first, with English as the fallback the recogniser understands
  /// on handsets that have no Bangla pack installed.
  static const String preferredLocale = 'bn_BD';

  /// Set when the recogniser reports a failure, so the caller can say which
  /// one rather than leaving a blank field.
  String? lastError;

  /// True when Bengali needs the network on this handset.
  ///
  /// It does whenever the on-device recogniser has no Bangla: the words then
  /// come from Google's online recognition, and without a connection the
  /// request simply fails. Saying so beats writing English words the user
  /// never spoke.
  bool bengaliNeedsNetwork = true;

  Future<bool> init() async {
    if (_available) return true;
    try {
      _available = await _speech.initialize(
        onError: (e) {
          lastError = e.errorMsg;
          debugPrint('Dictation error: ${e.errorMsg}');
        },
        onStatus: (s) {
          debugPrint('Dictation status: $s');
          // Measured on this handset: a pause ends the session through the
          // status callback and no final result ever arrives, so hooking the
          // restart to finalResult never fired. This is where it belongs.
          if ((s == 'done' || s == 'notListening') &&
              !_userStopped &&
              _onResult != null) {
            _restartSoon();
          }
        },
      );
      debugPrint('Device dictation available: $_available');
      return _available;
    } catch (e) {
      debugPrint('Device dictation init failed: $e');
      return false;
    }
  }

  /// Which locale the handset will actually use.
  ///
  /// Reported rather than assumed: a phone without a Bangla pack silently
  /// transcribes Bengali speech as English-sounding nonsense, and it is
  /// better to say so than to hand the model gibberish.
  Future<String?> resolveLocale() async {
    try {
      final locales = await _speech.locales();
      debugPrint(
        'Dictation locales (${locales.length}): '
        '${locales.map((l) => l.localeId).take(12).join(", ")}',
      );

      for (final l in locales) {
        if (l.localeId.replaceAll('-', '_').toLowerCase().startsWith('bn')) {
          bengaliNeedsNetwork = false;
          debugPrint('Dictation using on-device Bengali: ${l.localeId}');
          return l.localeId;
        }
      }
      bengaliNeedsNetwork = true;

      // Not in the list is not the same as not supported. That list comes
      // from the on-device recogniser, which carries 31 languages on this
      // handset; Google's online recognition handles far more, Bengali
      // included, and that is what a keyboard's voice button is using when
      // it transcribes Bangla on the same phone. So ask for Bengali anyway.
      debugPrint(
        'Dictation: Bengali absent from the on-device list; '
        'requesting $preferredLocale over the network',
      );
      return preferredLocale;
    } catch (e) {
      debugPrint('Dictation locale lookup failed: $e');
      return null;
    }
  }

  /// Whether the handset can actually recognise Bengali speech.
  ///
  /// Worth asking before listening: without the pack the recogniser does not
  /// fail, it transcribes Bengali as English-sounding nonsense, and the user
  /// is left wondering why their words came out wrong. Note this is the
  /// speech-to-text pack, which is separate from the text-to-speech voice in
  /// Settings — setting the latter to Bangla changes nothing here.
  Future<bool> hasBengaliOnDevice() async {
    if (!await init()) return false;
    try {
      final locales = await _speech.locales();
      return locales.any(
        (l) => l.localeId.replaceAll('-', '_').toLowerCase().startsWith('bn'),
      );
    } catch (_) {
      return false;
    }
  }

  /// Everything already finalised in this session.
  ///
  /// The recogniser ends an utterance at each pause and starts the next one
  /// from empty, so a sentence spoken with pauses arrives as a series of
  /// separate results. Writing each one straight into the field made every
  /// new word wipe out the last; they are joined here instead.
  String _committed = '';

  /// Set when the user presses stop, so the session is not restarted.
  ///
  /// Without this, dictation ends at the first pause: the recogniser closes
  /// the utterance and nothing reopens it, so only the first phrase is ever
  /// captured.
  bool _userStopped = false;

  /// When the session now running was opened.
  ///
  /// Used only as the backstop in [_restartSoon]; null whenever nothing is
  /// listening.
  DateTime? _sessionStartedAt;

  /// Whether this session is holding the microphone foreground-service type.
  ///
  /// Tracked rather than inferred, so a second [listen] without a [stop]
  /// between them cannot claim it twice and leave it claimed forever.
  bool _holdingMic = false;

  /// How long the reopen-on-pause loop may keep a session alive.
  ///
  /// Nobody dictates one note for five minutes, so this never cuts a real
  /// session short. It exists for the case where a screen goes away without
  /// calling [stop]: the loop would otherwise reopen the recogniser every
  /// quarter second for as long as the process lives, holding the microphone
  /// away from the camera and every other app on the phone.
  static const Duration maxSessionLifetime = Duration(minutes: 5);

  /// The newest text of the utterance in flight.
  ///
  /// Measured on this handset: every result arrives with finalResult false —
  /// the recogniser never sends a final one. Committing on that flag meant
  /// nothing was ever kept, so each new utterance wiped the last. The
  /// reliable signal is the session closing, so the latest partial is banked
  /// then.
  String _lastPartial = '';
  void Function(String text, bool isFinal)? _onResult;
  Duration _maxDuration = const Duration(seconds: 60);

  /// Streams partial text while the user speaks, then the final transcript.
  ///
  /// [seed] is text already in the box. Dictation adds to it instead of
  /// replacing it, so restarting the mic never costs the user what they
  /// already have; erasing stays theirs to do with the keyboard.
  Future<bool> listen({
    required void Function(String text, bool isFinal) onResult,
    Duration maxDuration = const Duration(seconds: 60),
    String seed = '',
  }) async {
    lastError = null;
    _committed = seed.trim();
    _lastPartial = '';
    _userStopped = false;
    _onResult = onResult;
    _sessionStartedAt = DateTime.now();
    _maxDuration = maxDuration;
    if (!await init()) return false;
    if (!_holdingMic) {
      // Held for the whole session rather than per utterance: the recogniser
      // closes and reopens at every pause, and letting the claim lapse in
      // those gaps would lose the microphone in the background.
      _holdingMic = true;
      await MicForegroundService.instance.acquire(text: 'Listening');
    }
    return _listenOnce();
  }

  /// Reopens the session after the engine closes it at a pause.
  ///
  /// Guarded against re-entry: the status callback can fire twice for one
  /// pause, and two overlapping listen calls lose text between them.
  bool _restarting = false;

  /// Banks the utterance that just ended, so the next one adds to it.
  void _commitPartial() {
    final words = _lastPartial.trim();
    if (words.isEmpty) return;
    _committed = _committed.isEmpty ? words : '$_committed $words';
    _lastPartial = '';
    debugPrint('Dictation committed: "$_committed"');
  }

  Future<void> _restartSoon() async {
    if (_restarting || _userStopped || _onResult == null) return;
    _restarting = true;
    try {
      // The session is closing, which is the only dependable moment to keep
      // what was heard.
      _commitPartial();

      final started = _sessionStartedAt;
      if (started != null &&
          DateTime.now().difference(started) > maxSessionLifetime) {
        debugPrint('Dictation: session past $maxSessionLifetime, closing');
        await stop();
        return;
      }

      await Future<void>.delayed(const Duration(milliseconds: 250));
      // Read again after the wait rather than before it: stop() may have run
      // while it was pending, and reopening then is exactly the leak the
      // guard at the top is there to prevent.
      if (_userStopped || _onResult == null) return;
      debugPrint('Dictation: reopening after pause');
      await _listenOnce();
    } finally {
      _restarting = false;
    }
  }

  Future<bool> _listenOnce() async {
    final onResult = _onResult;
    if (onResult == null || _userStopped) return false;

    final locale = await resolveLocale();
    try {
      await _speech.listen(
        onResult: (r) {
          final words = r.recognizedWords.trim();
          // An empty result is how the engine marks a reset, not something
          // the user said, so it must not wipe the hypothesis in flight.
          if (words.isNotEmpty) {
            // One hypothesis only ever grows by extension: "সরোবর" ->
            // "সরোবর থেকে". A result that is not an extension means the
            // engine dropped the old hypothesis and started a new one
            // mid-session, so bank the old one before it is lost.
            if (_lastPartial.isNotEmpty && !words.startsWith(_lastPartial)) {
              // Whatever the engine has already said is kept. Where the new
              // hypothesis is a shorter re-reading of the same words, this
              // can repeat a word; that is the right side to err on, since
              // the user can delete but cannot recover what was dropped.
              _commitPartial();
            }
            _lastPartial = words;
          }
          // A partial belongs to the utterance in flight, so it is shown
          // after what is already committed rather than replacing it.
          final full = _committed.isEmpty
              ? _lastPartial
              : (_lastPartial.isEmpty
                    ? _committed
                    : '$_committed $_lastPartial');
          if (r.finalResult) {
            _commitPartial();
          }
          debugPrint(
            'Dictation result: final=${r.finalResult} '
            '"$words" -> committed "$_committed"',
          );
          onResult(full, _userStopped);
        },
        listenOptions: SpeechListenOptions(
          localeId: locale,
          listenMode: ListenMode.dictation,
          partialResults: true,
          cancelOnError: false,
          // Explicitly not on-device: the local recogniser has no Bengali
          // and would silently transcribe it as English.
          onDevice: false,
          listenFor: _maxDuration,
          // Long enough that a pause for thought does not end the sentence.
          pauseFor: const Duration(seconds: 4),
        ),
      );
      return true;
    } catch (e) {
      debugPrint('Dictation listen failed: $e');
      return false;
    }
  }

  /// The text gathered so far, across every utterance in this session.
  String get committedText => _committed;

  /// Ends the session and hands the microphone back.
  ///
  /// Dropping the callback is what actually stops it. The status callback
  /// reopens the recogniser at every pause, and that loop is only allowed to
  /// run while somebody is still waiting for the words; [_userStopped] alone
  /// was not enough, because the next [listen] clears it again.
  ///
  /// [committedText] still holds the whole session afterwards: the utterance
  /// in flight is banked first, and the text is not cleared here.
  Future<void> stop() async {
    _userStopped = true;
    _onResult = null;
    _sessionStartedAt = null;
    _commitPartial();
    try {
      await _speech.stop();
    } catch (_) {}
    await _releaseMic();
  }

  /// Ends the session and throws away what was heard.
  Future<void> cancel() async {
    _userStopped = true;
    _onResult = null;
    _sessionStartedAt = null;
    _committed = '';
    _lastPartial = '';
    try {
      await _speech.cancel();
    } catch (_) {}
    await _releaseMic();
  }

  Future<void> _releaseMic() async {
    if (!_holdingMic) return;
    _holdingMic = false;
    await MicForegroundService.instance.release();
  }
}
