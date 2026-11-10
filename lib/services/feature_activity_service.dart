import 'package:flutter/foundation.dart';
import 'log_service.dart';

enum LocalistFeature { quickSend, remoteControl, vpnSharing, capture, stream }

/// Discovery and idle listeners never reserve a feature. Only user operations
/// and live sessions do, so a background listener cannot strand navigation.
class FeatureActivityService extends ChangeNotifier {
  static final instance = FeatureActivityService();
  final Map<Object, LocalistFeature> _activities = {};
  LocalistFeature? get owner => _activities.values.firstOrNull;
  bool allows(LocalistFeature feature) => owner == null || owner == feature;

  bool reserve(Object source, LocalistFeature feature) {
    if (!allows(feature)) {
      LogService.instance.debug(
        'Feature activity: reservation denied feature=${feature.name} owner=${owner?.name} active=${_activities.length}',
      );
      return false;
    }
    LogService.instance.debug(
      'Feature activity: reservation granted feature=${feature.name} active=${_activities.length}',
    );
    setActive(source, feature, true);
    return true;
  }

  void setActive(Object source, LocalistFeature feature, bool active) {
    final previous = owner;
    final wasActive = _activities.containsKey(source);
    if (active) {
      _activities[source] = feature;
    } else {
      _activities.remove(source);
    }
    if (wasActive != active || previous != owner) {
      LogService.instance.debug(
        'Feature activity: feature=${feature.name} active=$active owner=${previous?.name}->${owner?.name} reservations=${_activities.length}',
      );
    }
    if (previous != owner) notifyListeners();
  }
}
