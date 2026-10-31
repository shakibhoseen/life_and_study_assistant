import 'dart:async';

/// Thrown by [AiCancellation.guard] when the user stops waiting.
class AiCancelledException implements Exception {
  const AiCancelledException();

  @override
  String toString() => 'AiCancelledException';
}

/// Lets the user stop waiting on an AI call.
///
/// The request itself cannot be recalled once it has left the phone, so
/// cancelling abandons the reply rather than refunding it: anything already
/// spent stays spent, and the usage log still records it. What it buys is
/// control — the screen comes back instead of holding the user on a spinner
/// of unknown length.
///
/// This exists so that nothing has to be trimmed behind the user's back to
/// keep a call small. The whole text goes, the cost is shown, and stopping
/// is the user's decision to make.
class AiCancellation {
  final _completer = Completer<void>();

  bool get isCancelled => _completer.isCompleted;

  void cancel() {
    if (!_completer.isCompleted) _completer.complete();
  }

  /// [work] unless this is cancelled first.
  Future<T> guard<T>(Future<T> work) {
    if (isCancelled) throw const AiCancelledException();
    return Future.any<T>([
      work,
      _completer.future.then((_) => throw const AiCancelledException()),
    ]);
  }
}
