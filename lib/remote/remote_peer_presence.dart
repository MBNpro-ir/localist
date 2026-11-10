import '../services/log_service.dart';

enum RemotePeerPresence { unknown, online, offline }

/// Native presence is transient. A missing/stale response is not an offline
/// device, and results must be discarded when the rendezvous server changes.
class RemotePeerPresenceStore {
  RemotePeerPresenceStore({DateTime Function()? now})
    : _now = now ?? DateTime.now;
  final DateTime Function() _now;
  final _states = <String, (RemotePeerPresence, DateTime)>{};
  static const lifetime = Duration(seconds: 30);

  void clear() {
    LogService.instance.debug(
      'Remote presence cache cleared previousEntries=${_states.length}',
    );
    _states.clear();
  }

  void applySnapshot(Map<String, String> states) {
    final time = _now();
    var online = 0;
    var offline = 0;
    for (final entry in states.entries) {
      final state = RemotePeerPresence.values.firstWhere(
        (s) => s.name == entry.value,
        orElse: () => RemotePeerPresence.unknown,
      );
      if (state == RemotePeerPresence.unknown) {
        _states.remove(entry.key);
      } else {
        _states[entry.key] = (state, time);
        if (state == RemotePeerPresence.online) online++;
        if (state == RemotePeerPresence.offline) offline++;
      }
    }
    LogService.instance.debug(
      'Remote presence snapshot applied entries=${states.length} online=$online offline=$offline known=${_states.length}',
    );
  }

  void applyEvent(Map<String, dynamic> event) {
    final time = _now();
    var changes = 0;
    for (final (key, state) in [
      ('onlines', RemotePeerPresence.online),
      ('offlines', RemotePeerPresence.offline),
    ]) {
      for (final id in (event[key] as String? ?? '').split(',')) {
        if (id.isNotEmpty) {
          _states[id] = (state, time);
          changes++;
        }
      }
    }
    LogService.instance.debug(
      'Remote presence event applied changed=$changes known=${_states.length}',
    );
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
