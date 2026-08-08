class LiveOpenQueue {
  Future<void> _tail = Future<void>.value();

  Future<void> enqueue(Future<void> Function() operation) {
    final previous = _tail;
    final current = previous.then<void>(
      (_) => operation(),
      onError: (_, __) => operation(),
    );
    _tail = current.catchError((Object _, StackTrace __) {});
    return current;
  }
}
