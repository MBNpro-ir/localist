enum RemotePeerPresence { unknown, online, offline }

/// Native presence is transient. A missing/stale response is not an offline
/// device, and results must be discarded when the rendezvous server changes.
class RemotePeerPresenceStore {
  RemotePeerPresenceStore({DateTime Function()? now})
    : _now = now ?? DateTime.now;
  final DateTime Function() _now;
  final _states = <String, (RemotePeerPresence, DateTime)>{};
  static const lifetime = Duration(seconds: 30);

  void clear() => _states.clear();

  void applySnapshot(Map<String, String> states) {
    final time = _now();
    for (final entry in states.entries) {
      final state = RemotePeerPresence.values.firstWhere(
        (s) => s.name == entry.value,
        orElse: () => RemotePeerPresence.unknown,
      );
      if (state == RemotePeerPresence.unknown) {
        _states.remove(entry.key);
      } else {
        _states[entry.key] = (state, time);
      }
    }
  }

  void applyEvent(Map<String, dynamic> event) {
    final time = _now();
    for (final (key, state) in [
      ('onlines', RemotePeerPresence.online),
      ('offlines', RemotePeerPresence.offline),
    ]) {
      for (final id in (event[key] as String? ?? '').split(',')) {
        if (id.isNotEmpty) _states[id] = (state, time);
      }
    }
  }

  RemotePeerPresence get(String id) {
    final value = _states[id];
    return value != null && _now().difference(value.$2) < lifetime
        ? value.$1
        : RemotePeerPresence.unknown;
  }

  Map<String, String> snapshot(Iterable<String> ids) => {
    for (final id in ids) id: get(id).name,
  };
}
