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
import 'log_service.dart';
import 'capture_audio_settings.dart';

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
  int pcmErrors = 0;
  String? attemptedLink;
  final Map<String, DateTime> failedRoutes = {};
  String error = '', outputError = '';
  String? renderedVideoTrack;
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
    LogService.instance.debug(
      'Capture hub: starting discovery windows=$windows',
    );
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
    enabled = true;
    await _prefs!.setBool('capture.autoReceive', true);
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
      LogService.instance.debug('Capture hub: discovery active');
    } catch (e) {
      error = '$e';
      LogService.instance.debug(
        'Capture hub: discovery start failed type=${e.runtimeType}',
      );
    }
    _timer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(tick()),
    );
    _changed();
    LogService.instance.debug(
      'Capture hub: started savedSlots=${_preferredSlots.length}',
    );
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
    LogService.instance.debug(
      'Capture hub: receiver slot=${receiver.slot} route failed attempts=${receiver.failures} alternate=${alternative.link != link} retryDelaySeconds=${receiver.retryAt.difference(DateTime.now()).inSeconds}',
    );
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
        if (obsolete == null) {
          LogService.instance.debug(
            'Capture hub: discovered receiver ignored, all slots occupied',
          );
          return;
        }
        LogService.instance.debug(
          'Capture hub: evicting stale receiver slot=${obsolete.slot}',
        );
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
      LogService.instance.debug(
        'Capture hub: discovered new receiver slot=$slot video=${advertisement.camera} audio=${advertisement.microphone}',
      );
      final preferences = _prefs?.getString(
        'capture.receiver.${advertisement.id}',
      );
      try {
        final saved = jsonDecode(preferences ?? '{}') as Map;
        receiver.enabled = saved['enabled'] != false;
        receiver.video = saved['video'] != false;
        receiver.audio = saved['audio'] != false;
        receiver.output.microphoneEndpoint =
            saved['audioEndpoint'] as String? ?? '';
        if (saved['audioSettings'] is Map) {
          receiver.output.audioSettings = CaptureAudioSettings.fromMap(
            saved['audioSettings'] as Map,
          );
        }
      } catch (_) {}
      _receivers[advertisement.id] = receiver;
      final target = receiver;
      target.capture.addListener(() => unawaited(_syncOutput(target)));
      target.capture.onAudioPcm = (data) {
        if (target.enabled && target.audio && enabled) {
          unawaited(
            target.output.pushPcm(data).catchError((Object error) {
              target.outputError = '$error';
              target.pcmErrors++;
              if (LogService.instance.debugModeEnabled &&
                  (target.pcmErrors == 1 || target.pcmErrors % 100 == 0)) {
                LogService.instance.debug(
                  'Capture hub: slot=${target.slot} PCM relay failures=${target.pcmErrors} type=${error.runtimeType}',
                );
              }
            }),
          );
        }
      };
      target.output.bindCaptureControls(target.capture);
    }
    final changed = receiver.advertisement.link != advertisement.link;
    receiver.advertisement = advertisement;
    receiver.lastSeen = DateTime.now();
    if (changed) {
      LogService.instance.debug(
        'Capture hub: receiver slot=${receiver.slot} signaling route changed, restarting peer',
      );
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
    LogService.instance.debug('Capture hub: automatic receiver enabled=$value');
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
    String? audioEndpoint,
    CaptureAudioSettings? audioSettings,
  }) async {
    LogService.instance.debug(
      'Capture hub: configure slot=${receiver.slot} enabled=$enabled video=$video audio=$audio endpointChanged=${audioEndpoint != null} audioSettingsChanged=${audioSettings != null}',
    );
    if (enabled != null) receiver.enabled = enabled;
    if (video != null) receiver.video = video;
    if (audio != null) receiver.audio = audio;
    if (audioSettings != null) receiver.output.audioSettings = audioSettings;
    if (audioEndpoint != null) {
      receiver.output.microphoneEndpoint = audioEndpoint;
    }
    await _prefs?.setString(
      'capture.receiver.${receiver.advertisement.id}',
      jsonEncode({
        'enabled': receiver.enabled,
        'video': receiver.video,
        'audio': receiver.audio,
        'audioEndpoint': receiver.output.microphoneEndpoint,
        'audioSettings': receiver.output.audioSettings.toMap(),
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
        LogService.instance.debug(
          'Capture hub: discovery unavailable, attempting restart',
        );
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
            if (r.capture.active) {
              LogService.instance.debug(
                'Capture hub: pausing slot=${r.slot} hubEnabled=$enabled slotEnabled=${r.enabled} online=${r.online}',
              );
            }
            if (r.capture.active) await r.capture.stop();
            await _syncOutput(r);
            return;
          }
          if (r.capture.active) {
            // Output failures (e.g. a cable occupied by another receiver) must
            // retry even while signaling and video remain healthy.
            await _syncOutput(r);
            return;
          }
          if (r.capture.busy ||
              DateTime.now().isBefore(r.retryAt) ||
              !FeatureActivityService.instance.allows(
                LocalistFeature.capture,
              )) {
            return;
          }
          r.working = true;
          LogService.instance.debug(
            'Capture hub: connecting slot=${r.slot} attempts=${r.failures} video=${r.advertisement.camera} audio=${r.advertisement.microphone}',
          );
          r.error = '';
          _changed();
          try {
            if (!r.ready && r.advertisement.camera) {
              await r.renderer.initialize().timeout(const Duration(seconds: 8));
              r.ready = true;
            }
            final link = r.advertisement.link;
            LogService.instance.debug(
              'Capture hub: receiver slot=${r.slot} starting local signaling handshake',
            );
            r.attemptedLink = link;
            await r.capture.connect(link);
            LogService.instance.debug(
              'Capture hub: connect finished slot=${r.slot} active=${r.capture.active}',
            );
            if (_stopped ||
                !enabled ||
                !r.enabled ||
                link != r.advertisement.link) {
              await r.capture.stop();
              LogService.instance.debug(
                'Capture hub: discarded outdated session slot=${r.slot}',
              );
            } else {
              r.failedRoutes.remove(link);
            }
            r.failures = 0;
          } catch (e) {
            r.error = '$e';
            LogService.instance.debug(
              'Capture hub: receiver connect failed slot=${r.slot} type=${e.runtimeType}',
            );
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
      LogService.instance.debug(
        'Capture hub: reconciliation failed type=${e.runtimeType}',
      );
      _changed();
    } finally {
      _ticking = false;
    }
  }

  final Set<CaptureReceiver> _syncing = {};
  final Set<CaptureReceiver> _resync = {};
  Future<void> _syncOutput(CaptureReceiver receiver) async {
    if (_stopped) return;
    if (!_syncing.add(receiver)) {
      _resync.add(receiver);
      return;
    }
    try {
      final stream = receiver.capture.remoteStream;
      final videoTrack = stream?.getVideoTracks().firstOrNull?.id;
      final renderStream = videoTrack == null ? null : stream;
      if (receiver.ready &&
          (receiver.renderer.srcObject != renderStream ||
              receiver.renderedVideoTrack != videoTrack)) {
        // Await native detachment/rebinding. A late null-source completion can
        // otherwise clear a new stream's dimensions after its first frame.
        await receiver.renderer.setSrcObject(
          stream: renderStream,
          trackId: videoTrack,
        );
        receiver.renderedVideoTrack = videoTrack;
        LogService.instance.debug(
          'Capture hub: slot=${receiver.slot} renderer stream changed hasVideo=${videoTrack != null}',
        );
      }
      await receiver.capture.setPlaybackMuted(true);
      final failures = <Object>[];
      if (windows) {
        receiver.output.persian = persian;
        final show =
            receiver.enabled &&
            enabled &&
            receiver.video &&
            stream?.getVideoTracks().isNotEmpty == true;
        try {
          if (show &&
              !receiver.output.cameraEnabled &&
              receiver.renderer.textureId != null) {
            await receiver.output.setCameraInstalled(true);
            receiver.output.startCamera(receiver.renderer.textureId!);
            LogService.instance.info(
              'Camera receiver ${receiver.slot + 1}: virtual webcam output started',
            );
          } else if (!show && receiver.output.cameraEnabled) {
            LogService.instance.debug(
              'Capture hub: slot=${receiver.slot} stopping virtual camera output',
            );
            receiver.output.stopCamera();
          }
        } catch (error) {
          failures.add(error);
        }
      }
      receiver.output.audioSettings = receiver.output.audioSettings.withValues({
        'audioUncompressed':
            receiver.capture.captureControlState['audioUncompressed'] == true,
      });
      try {
        await receiver.output.setMicrophoneSource(
          receiver.enabled && enabled && receiver.audio ? stream : null,
        );
      } catch (error) {
        failures.add(error);
      }
      if (failures.isNotEmpty) throw StateError(failures.join(' / '));
      receiver.outputError = '';
    } catch (e) {
      final changed = receiver.outputError != '$e';
      receiver.outputError = '$e';
      if (changed) {
        LogService.instance.debug(
          'Capture hub: output sync failed slot=${receiver.slot} type=${e.runtimeType}',
        );
        LogService.instance.warning(
          'Camera receiver ${receiver.slot + 1} output failed (${e.runtimeType})',
        );
      }
    } finally {
      _syncing.remove(receiver);
      _changed();
      if (_resync.remove(receiver) && !_stopped) {
        unawaited(_syncOutput(receiver));
      }
    }
  }

  Future<void> _disposeReceiver(CaptureReceiver r) async {
    LogService.instance.debug(
      'Capture hub: disposing receiver slot=${r.slot} active=${r.capture.active}',
    );
    r.output.stopCamera();
    await r.capture.stop();
    r.capture.dispose();
    await r.output.stopMicrophone();
    if (r.ready) await r.renderer.dispose();
  }

  Future<void> stop() async {
    LogService.instance.debug(
      'Capture hub: stopping receivers=${_receivers.length} senderActive=${sender.active}',
    );
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
    LogService.instance.debug('Capture hub: stopped');
  }
}
