import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/services/ai/ai_cancellation.dart';

void main() {
  test('a call that finishes first returns its result', () async {
    final token = AiCancellation();
    expect(await token.guard(Future.value('summary')), 'summary');
    expect(token.isCancelled, isFalse);
  });

  test('cancelling mid-flight stops the wait', () async {
    final token = AiCancellation();
    final slow = Completer<String>();
    final guarded = token.guard(slow.future);

    token.cancel();

    expect(guarded, throwsA(isA<AiCancelledException>()));
    expect(token.isCancelled, isTrue);
    // The reply is abandoned, not recalled: completing it changes nothing.
    slow.complete('too late');
  });

  test('a call started after cancelling does not go out', () {
    final token = AiCancellation()..cancel();
    expect(
      () => token.guard(Future.value('x')),
      throwsA(isA<AiCancelledException>()),
    );
  });

  test('cancelling twice is harmless', () {
    final token = AiCancellation()..cancel();
    expect(token.cancel, returnsNormally);
  });
}
