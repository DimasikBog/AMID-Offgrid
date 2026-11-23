import 'dart:async';

/// Cancels the upstream subscription even while it is waiting for data.
class CancellableReader {
  StreamIterator<List<int>>? _active;

  Stream<List<int>> read(
    Stream<List<int>> source,
    void Function() checkActive,
  ) async* {
    checkActive();
    if (_active != null) throw StateError('Попереднє читання ще триває.');
    final iterator = StreamIterator<List<int>>(source);
    _active = iterator;
    try {
      while (await iterator.moveNext()) {
        checkActive();
        yield iterator.current;
      }
      checkActive();
    } finally {
      if (identical(_active, iterator)) _active = null;
      await iterator.cancel();
    }
  }

  void cancel() => _active?.cancel().ignore();
}
