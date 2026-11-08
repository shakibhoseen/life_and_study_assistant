import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Asks the Topics screen to show its Mistake Bank tab.
///
/// The state is a count of requests rather than a flag, so asking twice is two
/// requests and the second one still moves the tab. The screen lives inside an
/// [IndexedStack] and is built once, so its `initState` cannot carry this; it
/// listens to the count instead.
class MistakeBankTabRequest extends Notifier<int> {
  @override
  int build() => 0;

  void request() => state++;
}

final mistakeBankTabRequestProvider =
    NotifierProvider<MistakeBankTabRequest, int>(MistakeBankTabRequest.new);
