import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'capture_discovery_service.dart';
import 'feature_activity_service.dart';
import 'live_capture_service.dart';
import 'native_bridge_service.dart';
import 'windows_virtual_devices_service.dart';

class CaptureReceiver {
  CaptureReceiver(
    this.advertisement,
    this.slot,
    this.capture,
    this.renderer,
    this.output,
  );
  CaptureAdvertisement advertisement;
  final int slot;
  final LiveCaptureService capture;
  final RTCVideoRenderer renderer;
  final WindowsVirtualDevicesService output;
  DateTime lastSeen = DateTime.now(),
      retryAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool enabled = true,
      video = true,
      audio = true,
      working = false,
      ready = false;
  int failures = 0;
  String? attemptedLink;
  final Map<String, DateTime> failedRoutes = {};
  String error = '';
  bool get online =>
      DateTime.now().difference(lastSeen) < const Duration(seconds: 12);
}

/// One sender and four independent receivers. Discovery holds no activity lease;
/// only a live media connection reserves the capture feature.
class CaptureHubService extends ChangeNotifier {
  CaptureHubService({
    LiveCaptureService? sender,
    CaptureDiscoveryService? discovery,
    LiveCaptureService Function()? receiverFactory,
    RTCVideoRenderer Function()? rendererFactory,
    WindowsVirtualDevicesService Function(int)? outputFactory,
    bool? windows,
  }) : sender = sender ?? LiveCaptureService(),
       discovery = discovery ?? CaptureDiscoveryService(),
       _receiverFactory = receiverFactory ?? LiveCaptureService.new,
       _rendererFactory = rendererFactory ?? RTCVideoRenderer.new,
       _outputFactory =
           outputFactory ??
           ((slot) => WindowsVirtualDevicesService(slot: slot)),
       windows = windows ?? Platform.isWindows;
  static final instance = CaptureHubService();
  final LiveCaptureService sender;
  final CaptureDiscoveryService discovery;
  final bool windows;
  final LiveCaptureService Function() _receiverFactory;
  final RTCVideoRenderer Function() _rendererFactory;
  final WindowsVirtualDevicesService Function(int) _outputFactory;
  final Map<String, CaptureReceiver> _receivers = {};
  final Map<String, int> _preferredSlots = {};
  final Map<String, Map<String, ({CaptureAdvertisement value, DateTime seen})>>
  _routes = {};
  List<CaptureReceiver> get receivers =>
      _receivers.values.toList()..sort((a, b) => a.slot.compareTo(b.slot));
  String id = '', name = '', model = '', error = '';
  bool enabled = true, _stopped = false, _ticking = false;
  Future<void>? _starting, _tickTask;
  Timer? _timer;
  SharedPreferences? _prefs;
  bool persian = false;

  Future<void> start() => _starting ??= _start();
  Future<void> _start() async {
    _stopped = false;
    _prefs = await SharedPreferences.getInstance();
    try {
      final slots =
          jsonDecode(_prefs!.getString('capture.receiverSlots') ?? '{}') as Map;
      for (final entry in slots.entries) {
        if (entry.key is String &&
            entry.value is int &&
            entry.value >= 0 &&
            entry.value < 4) {
          _preferredSlots[entry.key as String] = entry.value as int;
        }
      }
    } catch (_) {}
    id =
        _prefs!.getString('capture.identity') ??
        base64UrlEncode(List.generate(18, (_) => Random.secure().nextInt(256)));
    await _prefs!.setString('capture.identity', id);
    enabled = _prefs!.getBool('capture.autoReceive') ?? true;
    final details = await NativeBridgeService.instance.getDeviceDetails();
    name =
        _prefs!.getString('quickSend.alias') ??
        '${details['computerName'] ?? details['name'] ?? Platform.localHostname}';
    model = '${details['model'] ?? Platform.operatingSystem}';
    discovery.advertisement = () => sender.broadcasting
        ? CaptureAdvertisement(
            id: id,
            name: name,
            model: model,
            host: '',
            port: sender.signalingPort,
            key: sender.signalingKey,
            camera: sender.options.camera,
            microphone: sender.options.microphone,
          )
        : null;
    discovery.onAdvertisement = observe;
    sender.addListener(_senderChanged);
    FeatureActivityService.instance.addListener(_activityChanged);
    try {
      await discovery.start();
    } catch (e) {
      error = '$e';
    }
    _timer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(tick()),
    );
    _changed();
  }

  void _senderChanged() {
    unawaited(discovery.announce());
    _changed();
  }

  void _activityChanged() => unawaited(tick());
  void _changed() {
    if (!_stopped) notifyListeners();
  }

  CaptureAdvertisement _preferredRoute(
    String id,
    CaptureAdvertisement fallback,
  ) {
    final receiver = _receivers[id];
    final now = DateTime.now();
    final routes =
        _routes[id]?.values
            .where((r) => now.difference(r.seen).inSeconds < 12)
            .toList()
          ?..sort((a, b) => a.value.priority.compareTo(b.value.priority));
    if (routes == null || routes.isEmpty) return fallback;
    return routes
            .where(
              (r) =>
                  !(receiver?.failedRoutes.containsKey(r.value.link) == true &&
                      (receiver!.capture.active ||
                          receiver.failedRoutes[r.value.link]!.isAfter(now))),
            )
            .firstOrNull
            ?.value ??
        receiver?.advertisement ??
        fallback;
  }

  void _routeFailed(CaptureReceiver receiver, String link) {
    receiver.failedRoutes.removeWhere(
      (_, until) => until.isBefore(DateTime.now()),
    );
    receiver.failedRoutes[link] = DateTime.now().add(
      const Duration(seconds: 30),
    );
    final alternative = _preferredRoute(
      receiver.advertisement.id,
      receiver.advertisement,
    );
    receiver.retryAt = DateTime.now().add(
      alternative.link != link
          ? Duration.zero
          : Duration(seconds: min(30, 2 << min(4, receiver.failures))),
    );
    receiver.failures++;
    receiver.advertisement = alternative;
    receiver.attemptedLink = null;
  }

  void observe(CaptureAdvertisement advertisement) {
    if (_stopped || advertisement.id == id) return;
    final paths = _routes.putIfAbsent(advertisement.id, () => {});
    paths.removeWhere(
      (_, route) =>
          DateTime.now().difference(route.seen).inSeconds >= 12 ||
          route.value.key != advertisement.key,
    );
    if (paths.length >= 4 && !paths.containsKey(advertisement.host)) return;
    paths[advertisement.host] = (value: advertisement, seen: DateTime.now());
    advertisement = _preferredRoute(advertisement.id, advertisement);
    if (_routes.length > 32) _routes.remove(_routes.keys.first);
    var receiver = _receivers[advertisement.id];
    if (receiver == null) {
      if (_receivers.length >= 4) {
        final obsolete = receivers
            .where((r) => !r.online && !r.capture.active && !r.working)
            .firstOrNull;
        if (obsolete == null) return;
        _receivers.remove(obsolete.advertisement.id);
        _routes.remove(obsolete.advertisement.id);
        unawaited(_disposeReceiver(obsolete));
      }
      final occupied = _receivers.values.map((r) => r.slot).toSet();
      final preferred = _preferredSlots[advertisement.id];
      final slot = preferred != null && !occupied.contains(preferred)
          ? preferred
          : [0, 1, 2, 3].firstWhere((s) => !occupied.contains(s));
      _preferredSlots[advertisement.id] = slot;
      if (_preferredSlots.length > 32) {
        _preferredSlots.remove(_preferredSlots.keys.first);
      }
      unawaited(
        _prefs?.setString('capture.receiverSlots', jsonEncode(_preferredSlots)),
      );
      receiver = CaptureReceiver(
        advertisement,
        slot,
        _receiverFactory(),
        _rendererFactory(),
        _outputFactory(slot),
      );
      final preferences = _prefs?.getString(
        'capture.receiver.${advertisement.id}',
      );
      try {
        final saved = jsonDecode(preferences ?? '{}') as Map;
        receiver.enabled = saved['enabled'] != false;
        receiver.video = saved['video'] != false;
        receiver.audio = saved['audio'] != false;
      } catch (_) {}
      _receivers[advertisement.id] = receiver;
      final target = receiver;
      target.capture.addListener(() => unawaited(_syncOutput(target)));
      target.output.bindCaptureControls(target.capture);
    }
    final changed = receiver.advertisement.link != advertisement.link;
    receiver.advertisement = advertisement;
    receiver.lastSeen = DateTime.now();
    if (changed) {
      // A restarted sender has a new signaling key. Retire only this session.
      receiver.retryAt = DateTime.fromMillisecondsSinceEpoch(0);
      // An in-flight handshake checks the new link after it completes. Do not
      // let an obsolete socket's close callback tear down its replacement.
      if (!receiver.working) {
        unawaited(receiver.capture.stop().then((_) => tick()));
      }
    } else {
      unawaited(tick());
    }
    _changed();
  }

  Future<void> setEnabled(bool value) async {
    enabled = value;
    await _prefs?.setBool('capture.autoReceive', value);
    await tick();
    _changed();
  }

  Future<void> configure(
    CaptureReceiver receiver, {
    bool? enabled,
    bool? video,
    bool? audio,
  }) async {
    if (enabled != null) receiver.enabled = enabled;
    if (video != null) receiver.video = video;
    if (audio != null) receiver.audio = audio;
    await _prefs?.setString(
      'capture.receiver.${receiver.advertisement.id}',
      jsonEncode({
        'enabled': receiver.enabled,
        'video': receiver.video,
        'audio': receiver.audio,
      }),
    );
    await tick();
    await _syncOutput(receiver);
    _changed();
  }

  Future<void> tick() {
    if (_stopped) return Future.value();
    return _tickTask ??= _tick().whenComplete(() => _tickTask = null);
  }

  Future<void> _tick() async {
    if (_stopped || _ticking) return;
    _ticking = true;
    try {
      if (!discovery.running) {
        await discovery.start();
        error = '';
      }
      // RTCVideoRenderer initializes the plugin implicitly. Initialize it once
      // before creating several textures so native factories cannot race.
      if (enabled && receivers.any((r) => r.online && r.enabled)) {
        await LiveCaptureService.initializeMedia();
      }
      await Future.wait(
        receivers.map((r) async {
          if (r.working) return;
          if (!r.capture.active &&
              r.capture.error.isNotEmpty &&
              r.attemptedLink != null) {
            r.error = r.capture.error;
            _routeFailed(r, r.attemptedLink!);
          }
          if (!r.capture.active) {
            r.advertisement = _preferredRoute(
              r.advertisement.id,
              r.advertisement,
            );
          }
          if (!enabled || !r.enabled || !r.online) {
            if (r.capture.active) await r.capture.stop();
            await _syncOutput(r);
            return;
          }
          if (r.capture.active ||
              r.capture.busy ||
              DateTime.now().isBefore(r.retryAt) ||
              !FeatureActivityService.instance.allows(
                LocalistFeature.capture,
              )) {
            return;
          }
          r.working = true;
          r.error = '';
          _changed();
          try {
            if (!r.ready) {
              await r.renderer.initialize().timeout(const Duration(seconds: 8));
              r.ready = true;
            }
            final link = r.advertisement.link;
            r.attemptedLink = link;
            await r.capture.connect(link);
            if (_stopped ||
                !enabled ||
                !r.enabled ||
                link != r.advertisement.link) {
              await r.capture.stop();
            } else {
              r.failedRoutes.remove(link);
            }
            r.failures = 0;
          } catch (e) {
            r.error = '$e';
            _routeFailed(r, r.attemptedLink ?? r.advertisement.link);
          } finally {
            r.working = false;
            await _syncOutput(r);
            _changed();
          }
        }),
      );
    } catch (e) {
      error = '$e';
      _changed();
    } finally {
      _ticking = false;
    }
  }

  final Set<CaptureReceiver> _syncing = {};
  Future<void> _syncOutput(CaptureReceiver receiver) async {
    if (_stopped || !_syncing.add(receiver)) return;
    try {
      final stream = receiver.capture.remoteStream;
      if (receiver.ready && receiver.renderer.srcObject != stream) {
        receiver.renderer.srcObject = stream;
      }
      await receiver.capture.setPlaybackMuted(
        !receiver.audio || !receiver.enabled || !enabled,
      );
      if (windows) {
        receiver.output.persian = persian;
        final show =
            receiver.enabled &&
            enabled &&
            receiver.video &&
            stream?.getVideoTracks().isNotEmpty == true;
        if (show &&
            !receiver.output.cameraEnabled &&
            receiver.renderer.textureId != null) {
          await receiver.output.setCameraInstalled(true);
          receiver.output.startCamera(receiver.renderer.textureId!);
        } else if (!show && receiver.output.cameraEnabled) {
          receiver.output.stopCamera();
        }
      }
    } catch (e) {
      receiver.error = '$e';
    } finally {
      _syncing.remove(receiver);
      _changed();
    }
  }

  Future<void> _disposeReceiver(CaptureReceiver r) async {
    r.output.stopCamera();
    await r.capture.stop();
    r.capture.dispose();
    await r.output.stopMicrophone();
    if (r.ready) await r.renderer.dispose();
  }

  Future<void> stop() async {
    _stopped = true;
    _timer?.cancel();
    _timer = null;
    sender.removeListener(_senderChanged);
    FeatureActivityService.instance.removeListener(_activityChanged);
    await discovery.stop();
    await _tickTask;
    await Future.wait(receivers.map(_disposeReceiver));
    _receivers.clear();
    _routes.clear();
    await sender.stop();
    _starting = null;
  }
}
