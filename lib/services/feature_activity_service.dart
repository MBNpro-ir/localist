import 'package:flutter/foundation.dart';

enum LocalistFeature { quickSend, remoteControl, vpnSharing, stream }

/// Discovery and idle listeners never reserve a feature. Only user operations
/// and live sessions do, so a background listener cannot strand navigation.
class FeatureActivityService extends ChangeNotifier {
  static final instance = FeatureActivityService();
  final Map<Object, LocalistFeature> _activities = {};
  LocalistFeature? get owner => _activities.values.firstOrNull;
  bool allows(LocalistFeature feature) => owner == null || owner == feature;

  bool reserve(Object source, LocalistFeature feature) {
    if (!allows(feature)) return false;
    setActive(source, feature, true);
    return true;
  }

  void setActive(Object source, LocalistFeature feature, bool active) {
    final previous = owner;
    if (active) {
      _activities[source] = feature;
    } else {
      _activities.remove(source);
    }
    if (previous != owner) notifyListeners();
  }
}
