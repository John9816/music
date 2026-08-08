class LiveLineFailover {
  LiveLineFailover(Iterable<String> lineIds)
      : _lineIds = List<String>.unmodifiable(
          lineIds.where((id) => id.isNotEmpty).toSet(),
        );

  final List<String> _lineIds;
  final Set<String> _attemptedIds = <String>{};
  List<String> _cycle = const <String>[];
  int _cycleIndex = -1;
  String? _currentId;

  String? get currentId => _currentId;
  Set<String> get attemptedIds => Set<String>.unmodifiable(_attemptedIds);

  String? start({String? preferredId}) => _beginCycle(preferredId);
  String? restart() => _beginCycle(null);

  String? failCurrent() {
    final nextIndex = _cycleIndex + 1;
    if (nextIndex >= _cycle.length) {
      _currentId = null;
      return null;
    }
    _cycleIndex = nextIndex;
    _currentId = _cycle[_cycleIndex];
    _attemptedIds.add(_currentId!);
    return _currentId;
  }

  String? select(String lineId) {
    if (!_lineIds.contains(lineId)) return null;
    return _beginCycle(lineId);
  }

  String? _beginCycle(String? preferredId) {
    if (_lineIds.isEmpty) {
      _cycle = const <String>[];
      _cycleIndex = -1;
      _currentId = null;
      _attemptedIds.clear();
      return null;
    }
    final startIndex = preferredId == null ? 0 : _lineIds.indexOf(preferredId);
    if (startIndex < 0) return null;
    _cycle = <String>[
      ..._lineIds.skip(startIndex),
      ..._lineIds.take(startIndex),
    ];
    _attemptedIds
      ..clear()
      ..add(_cycle.first);
    _cycleIndex = 0;
    _currentId = _cycle.first;
    return _currentId;
  }
}
