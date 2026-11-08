import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'feature_activity_service.dart';
import 'feature_permission_service.dart';
import 'lan_network_service.dart';

class LiveCaptureOptions {
  const LiveCaptureOptions({
    this.background = true,
    this.camera = true,
    this.microphone = true,
    this.rearCamera = true,
    this.width = 1280,
    this.height = 720,
    this.fps = 30,
    this.bitrateKbps = 2500,
    this.echoCancellation = true,
    this.noiseSuppression = true,
    this.autoGain = true,
    this.cameraId,
    this.microphoneId,
  });
  final String? cameraId, microphoneId;
  final bool background;
  final bool camera,
      microphone,
      rearCamera,
      echoCancellation,
      noiseSuppression,
      autoGain;
  final int width, height, fps, bitrateKbps;
  Map<String, dynamic> get constraints => {
    'video': camera
        ? {
            'facingMode': rearCamera ? 'environment' : 'user',
            'width': width,
            'height': height,
            'frameRate': fps,
            if (cameraId != null) 'deviceId': cameraId,
            if (cameraId != null)
              'optional': [
                {'sourceId': cameraId},
              ],
          }
        : false,
    'audio': microphone
        ? {
            'echoCancellation': echoCancellation,
            'noiseSuppression': noiseSuppression,
            'autoGainControl': autoGain,
            'sampleRate': 48000,
            'channelCount': 1,
            if (microphoneId != null) 'deviceId': microphoneId,
            // Android's native parser still consumes legacy optional APM keys.
            // Flat W3C properties alone do not reach its AudioSource.
            'optional': [
              if (microphoneId != null) {'sourceId': microphoneId},
              {'googEchoCancellation': echoCancellation},
              {'googEchoCancellation2': echoCancellation},
              {'googDAEchoCancellation': echoCancellation},
              {'googNoiseSuppression': noiseSuppression},
              {'googNoiseSuppression2': noiseSuppression},
              {'googAutoGainControl': autoGain},
              {'googAutoGainControl2': autoGain},
              {'echoCancellation': echoCancellation},
              {'noiseSuppression': noiseSuppression},
              {'autoGainControl': autoGain},
            ],
          }
        : false,
  };
  void validate() {
    if ((!camera && !microphone) ||
        ![320, 640, 1280, 1920].contains(width) ||
        ![240, 480, 720, 1080].contains(height) ||
        ![10, 15, 24, 30, 60].contains(fps) ||
        bitrateKbps < 250 ||
        bitrateKbps > 12000) {
      throw const FormatException('Invalid capture settings.');
    }
  }

  LiveCaptureOptions copyWith({
    bool? background,
    String? cameraId,
    String? microphoneId,
    bool clearCameraId = false,
  }) => LiveCaptureOptions(
    background: background ?? this.background,
    camera: camera,
    microphone: microphone,
    rearCamera: rearCamera,
    width: width,
    height: height,
    fps: fps,
    bitrateKbps: bitrateKbps,
    echoCancellation: echoCancellation,
    noiseSuppression: noiseSuppression,
    autoGain: autoGain,
    cameraId: clearCameraId ? null : cameraId ?? this.cameraId,
    microphoneId: microphoneId ?? this.microphoneId,
  );
}

/// Local signaling only; WebRTC encrypts media with DTLS-SRTP. No public STUN,
/// TURN, accounts or external signaling server is used. Each run has a new key.
class CaptureSignalingServer {
  CaptureSignalingServer({
    required this.html,
    required this.accept,
    this.maxViewers = 3,
  });
  final String html;
  final Future<void> Function(WebSocket) accept;
  final int maxViewers;
  final Set<WebSocket> clients = {};
  HttpServer? _server;
  String token = '';
  int get port => _server?.port ?? 0;
  Future<void> start({int port = 0}) async {
    token = base64UrlEncode(
      List.generate(32, (_) => Random.secure().nextInt(256)),
    );
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server!.listen((request) async {
      try {
        request.response.headers.set('Cache-Control', 'no-store');
        request.response.headers.set('Referrer-Policy', 'no-referrer');
        request.response.headers.set('X-Content-Type-Options', 'nosniff');
        request.response.headers.set(
          'Content-Security-Policy',
          "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; media-src blob:; connect-src 'self'; frame-ancestors 'none'",
        );
        if (request.method == 'GET' && request.uri.path == '/') {
          request.response.headers.contentType = ContentType.html;
          request.response.write(html);
          await request.response.close();
        } else if (request.uri.path == '/signal' &&
            WebSocketTransformer.isUpgradeRequest(request)) {
          final origin = request.headers.value('Origin');
          final ownOrigin =
              'http://${request.headers.value(HttpHeaders.hostHeader)}';
          if (request.uri.queryParameters['key'] != token ||
              (origin != null && origin != ownOrigin)) {
            request.response.statusCode = 403;
            await request.response.close();
            return;
          }
          if (clients.length >= maxViewers) {
            request.response.statusCode = 503;
            await request.response.close();
            return;
          }
          final socket = await WebSocketTransformer.upgrade(request);
          clients.add(socket);
          socket.pingInterval = const Duration(seconds: 15);
          unawaited(
            socket.done
                .whenComplete(() => clients.remove(socket))
                .catchError((Object _) => false),
          );
          try {
            await accept(socket);
          } catch (_) {
            await socket.close(WebSocketStatus.internalServerError);
          }
        } else {
          request.response.statusCode = 404;
          await request.response.close();
        }
      } catch (_) {
        await request.response.close().catchError((Object _) {});
      }
    });
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    token = '';
    final sockets = clients.toList();
    clients.clear();
    await server?.close(force: true);
    await Future.wait(
      sockets.map(
        (client) => client
            .close()
            .timeout(const Duration(seconds: 2), onTimeout: () => null)
            .then<void>((_) {})
            .catchError((Object _) {}),
      ),
    );
  }
}

class LiveCaptureService extends ChangeNotifier {
  static Future<void>? _mediaInitialization;
  static Future<void> initializeMedia() => _mediaInitialization ??=
      WebRTC.initialize(
        options: {
          if (Platform.isAndroid) 'androidUseHardwareAudioProcessing': false,
        },
      ).catchError((Object error) {
        _mediaInitialization = null;
        throw error;
      });
  static Future<List<MediaDeviceInfo>> inputDevices() async {
    await initializeMedia();
    return (await navigator.mediaDevices.enumerateDevices())
        .where(
          (device) =>
              device.kind == 'audioinput' || device.kind == 'videoinput',
        )
        .where(
          (device) => !device.label.toLowerCase().contains('localist camera'),
        )
        .toList();
  }

  MediaStream? localStream, remoteStream;
  CaptureSignalingServer? _server;
  WebSocket? _receiver;
  final Map<WebSocket, RTCPeerConnection> _peers = {};
  final List<RTCIceCandidate> _pendingCandidates = [];
  List<String> addresses = [];
  LiveCaptureOptions options = const LiveCaptureOptions();
  bool busy = false, microphoneMuted = false, cameraPaused = false;
  bool playbackMuted = false, torch = false;
  double zoom = 1, maxZoom = 1;
  bool hasTorch = false;
  String? activeCameraId;
  String error = '', status = '';
  bool get broadcasting => _server != null;
  bool get receiving => _receiver != null;
  bool get active => broadcasting || receiving;
  int get viewers => _peers.length;
  List<String> get links => [
    for (final address in addresses)
      'http://$address:${_server?.port}/#${_server?.token}',
  ];
  static const _configuration = <String, dynamic>{
    'iceServers': <dynamic>[],
    'sdpSemantics': 'unified-plan',
  };
  static const _captureChannel = MethodChannel('localist/capture');
  bool _foregroundOwned = false;
  bool _disposed = false;
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> start(LiveCaptureOptions value, {int port = 0}) async {
    if (_disposed || busy || active) return;
    value.validate();
    if (!FeatureActivityService.instance.reserve(
      this,
      LocalistFeature.capture,
    )) {
      throw StateError(
        'ابتدا سرویس فعال را متوقف کنید. / Stop the active service first.',
      );
    }
    busy = true;
    error = '';
    _changed();
    try {
      if (!await FeaturePermissionService.instance.ensure([
        if (value.camera) FeatureAccess.camera,
        if (value.microphone) FeatureAccess.microphone,
      ])) {
        throw StateError(
          'دسترسی دوربین/میکروفون داده نشد. / Camera/microphone permission denied.',
        );
      }
      options = value;
      if (_disposed) return;
      await initializeMedia();
      if (Platform.isAndroid && value.background) {
        _captureChannel.setMethodCallHandler((call) async {
          if (call.method == 'stopCapture') await stop();
        });
        _foregroundOwned = true;
        await _captureChannel.invokeMethod<bool>('start', {
          'camera': value.camera,
          'microphone': value.microphone,
        });
        if (_disposed) {
          await stop();
          return;
        }
      }
      final constraints = value.constraints;
      if (Platform.isWindows && value.camera && value.cameraId == null) {
        final inputs = (await Helper.cameras)
            .where(
              (device) =>
                  !device.label.toLowerCase().contains('localist camera'),
            )
            .toList();
        if (inputs.isEmpty) {
          throw StateError(
            'دوربین ورودی دیگری پیدا نشد؛ برای دریافت از گوشی، لینک را در بخش گیرنده وارد کنید. / '
            'No input camera found. To receive from your phone, use the Receive section.',
          );
        }
        final video = constraints['video'] as Map<String, dynamic>;
        video.remove('facingMode');
        video['optional'] = [
          {'sourceId': inputs.first.deviceId},
        ];
      }
      if (value.microphoneId != null && value.microphone) {
        await selectMicrophone(value.microphoneId!);
      }
      localStream = await navigator.mediaDevices.getUserMedia(constraints);
      activeCameraId =
          localStream?.getVideoTracks().firstOrNull?.getSettings()['deviceId']
              as String?;
      if (_disposed) {
        await stop();
        return;
      }
      await refreshCameraControls();
      // Preview must never play our own microphone through the local speakers.
      final html = await rootBundle.loadString('assets/live_capture.html');
      final server = CaptureSignalingServer(html: html, accept: _acceptViewer);
      await server.start(port: port);
      _server = server;
      if (_disposed) {
        await stop();
        return;
      }
      addresses = (await LanNetworkService.instance.routes())
          .map((r) => r.address)
          .toList();
      if (addresses.isEmpty) addresses = ['127.0.0.1'];
      status = 'waiting';
    } catch (e) {
      error = '$e';
      await stop();
      rethrow;
    } finally {
      busy = false;
      _changed();
    }
  }

  Future<void> _acceptViewer(WebSocket socket) async {
    final stream = localStream;
    if (stream == null) {
      await socket.close();
      return;
    }
    final peer = await createPeerConnection(_configuration);
    _peers[socket] = peer;
    final candidates = <RTCIceCandidate>[];
    peer.onIceCandidate = (candidate) {
      if (socket.readyState == WebSocket.open) {
        socket.add(jsonEncode({'candidate': candidate.toMap()}));
      }
    };
    peer.onConnectionState = (state) {
      status = state.name
          .replaceFirst('RTCPeerConnectionState', '')
          .toLowerCase();
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        unawaited(socket.close());
      }
      _changed();
    };
    Future<void> queue = Future.value();
    socket.listen(
      (message) {
        queue = queue
            .then((_) async {
              final data = decodeCaptureSignal(message);
              if (data['type'] == 'answer') {
                await peer.setRemoteDescription(
                  RTCSessionDescription(data['sdp'] as String, 'answer'),
                );
                for (final candidate in candidates) {
                  await peer.addCandidate(candidate);
                }
                candidates.clear();
              } else if (data['candidate'] is Map) {
                final candidate = _candidate(data['candidate'] as Map);
                if (await peer.getRemoteDescription() == null) {
                  candidates.add(candidate);
                } else {
                  await peer.addCandidate(candidate);
                }
              }
            })
            .catchError((Object _) {
              unawaited(socket.close(WebSocketStatus.invalidFramePayloadData));
            });
      },
      onDone: () {
        _peers.remove(socket);
        if (_peers.isEmpty && broadcasting) status = 'waiting';
        unawaited(peer.close());
        _changed();
      },
      onError: (Object _) {
        unawaited(socket.close());
      },
    );
    try {
      for (final track in stream.getTracks()) {
        await peer.addTrack(track, stream);
      }
      final offer = await peer.createOffer();
      await peer.setLocalDescription(offer);
      socket.add(jsonEncode({'type': 'offer', 'sdp': offer.sdp}));
      for (final sender in await peer.getSenders()) {
        if (sender.track?.kind != 'video') continue;
        final parameters = sender.parameters;
        for (final encoding in parameters.encodings ?? <RTCRtpEncoding>[]) {
          encoding.maxBitrate = options.bitrateKbps * 1000;
          encoding.maxFramerate = options.fps;
        }
        await sender.setParameters(parameters);
      }
      _changed();
    } catch (_) {
      await socket.close();
      rethrow;
    }
  }

  Future<void> connect(String link) async {
    if (_disposed || active || busy) return;
    final uri = Uri.tryParse(link.trim());
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        !RegExp(r'^[A-Za-z0-9_=-]{40,64}$').hasMatch(uri.fragment)) {
      throw const FormatException(
        'لینک کامل اتصال را وارد کنید. / Enter the complete connection link.',
      );
    }
    if (!FeatureActivityService.instance.reserve(
      this,
      LocalistFeature.capture,
    )) {
      throw StateError('Stop the active service first.');
    }
    busy = true;
    error = '';
    _changed();
    try {
      await initializeMedia();
      final socket = await WebSocket.connect(
        uri
            .replace(
              scheme: uri.scheme == 'https' ? 'wss' : 'ws',
              path: '/signal',
              fragment: '',
              queryParameters: {'key': uri.fragment},
            )
            .toString(),
      ).timeout(const Duration(seconds: 12));
      _receiver = socket;
      if (_disposed) {
        await stop();
        return;
      }
      final peer = await createPeerConnection(_configuration);
      _peers[socket] = peer;
      if (_disposed) {
        await stop();
        return;
      }
      peer.onTrack = (event) {
        if (event.streams.isNotEmpty) remoteStream = event.streams.first;
        if (event.track.kind == 'audio' && playbackMuted) {
          unawaited(Helper.setVolume(0, event.track));
        }
        _changed();
      };
      peer.onIceCandidate = (candidate) {
        if (socket.readyState == WebSocket.open) {
          socket.add(jsonEncode({'candidate': candidate.toMap()}));
        }
      };
      peer.onConnectionState = (state) {
        status = state.name
            .replaceFirst('RTCPeerConnectionState', '')
            .toLowerCase();
        _changed();
      };
      Future<void> queue = Future.value();
      socket.listen(
        (message) {
          queue = queue
              .then((_) async {
                final data = decodeCaptureSignal(message);
                if (data['type'] == 'offer') {
                  await peer.setRemoteDescription(
                    RTCSessionDescription(data['sdp'] as String, 'offer'),
                  );
                  for (final candidate in _pendingCandidates) {
                    await peer.addCandidate(candidate);
                  }
                  _pendingCandidates.clear();
                  final answer = await peer.createAnswer();
                  await peer.setLocalDescription(answer);
                  socket.add(jsonEncode({'type': 'answer', 'sdp': answer.sdp}));
                } else if (data['candidate'] is Map) {
                  final candidate = _candidate(data['candidate'] as Map);
                  if (await peer.getRemoteDescription() == null) {
                    if (_pendingCandidates.length >= 100) {
                      throw const FormatException('Too many ICE candidates');
                    }
                    _pendingCandidates.add(candidate);
                  } else {
                    await peer.addCandidate(candidate);
                  }
                }
              })
              .catchError((Object e) {
                error = '$e';
                unawaited(stop());
              });
        },
        onDone: () => unawaited(stop()),
        onError: (Object e) {
          error = '$e';
          unawaited(stop());
        },
      );
    } catch (e) {
      error = '$e';
      await stop();
      rethrow;
    } finally {
      busy = false;
      _changed();
    }
  }

  static RTCIceCandidate _candidate(Map map) => RTCIceCandidate(
    map['candidate'] as String?,
    map['sdpMid'] as String?,
    map['sdpMLineIndex'] as int?,
  );
  void muteMicrophone(bool mute) {
    microphoneMuted = mute;
    for (final track in localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = !mute;
    }
    _changed();
  }

  void pauseCamera(bool pause) {
    cameraPaused = pause;
    for (final track in localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = !pause;
    }
    _changed();
  }

  Future<void> selectMicrophone(String id) async {
    final inputs = await inputDevices();
    if (!inputs.any(
      (device) => device.kind == 'audioinput' && device.deviceId == id,
    )) {
      throw StateError(
        'ورودی میکروفون در دسترس نیست. / Microphone input is no longer available.',
      );
    }
    await Helper.selectAudioInput(id);
    options = options.copyWith(microphoneId: id);
    _changed();
  }

  Future<void> setPlaybackMuted(bool mute) async {
    for (final track
        in remoteStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      await Helper.setVolume(mute ? 0 : 1, track);
    }
    playbackMuted = mute;
    _changed();
  }

  Future<void> refreshCameraControls() async {
    maxZoom = zoom = 1;
    hasTorch = torch = false;
    final track = localStream?.getVideoTracks().firstOrNull;
    if (!Platform.isAndroid || track == null) return;
    try {
      final result =
          await _captureChannel.invokeMapMethod<String, dynamic>(
            'cameraCapabilities',
            {'cameraId': activeCameraId, 'rear': options.rearCamera},
          ) ??
          {};
      maxZoom = ((result['maxZoom'] as num?)?.toDouble() ?? 1).clamp(1, 100);
      hasTorch = result['torch'] == true;
    } catch (_) {
      /* Optional hardware controls never block capture. */
    }
    _changed();
  }

  Future<void> setZoom(double value) async {
    final track = localStream?.getVideoTracks().firstOrNull;
    if (track == null) return;
    final target = value.clamp(1, maxZoom);
    await Helper.setZoom(track, target.toDouble());
    zoom = target.toDouble();
    _changed();
  }

  Future<void> setTorch(bool enabled) async {
    final track = localStream?.getVideoTracks().firstOrNull;
    if (track == null || !hasTorch) return;
    await track.setTorch(enabled);
    torch = enabled;
    // Upstream torch rebuilds its Camera2 request; reapply the current crop.
    await Helper.setZoom(track, zoom);
    _changed();
  }

  Future<void> prepareBackgroundCapture() async {
    if (!broadcasting || !Platform.isAndroid) return;
    if (!_foregroundOwned) {
      _captureChannel.setMethodCallHandler((call) async {
        if (call.method == 'stopCapture') await stop();
      });
      _foregroundOwned = true;
      try {
        await _captureChannel.invokeMethod<bool>('start', {
          'camera': options.camera,
          'microphone': options.microphone,
        });
      } catch (_) {
        _foregroundOwned = false;
        _captureChannel.setMethodCallHandler(null);
        rethrow;
      }
      if (!broadcasting || _disposed) {
        await _captureChannel.invokeMethod<bool>('stop');
        _foregroundOwned = false;
        return;
      }
    }
    options = options.copyWith(background: true);
    _changed();
  }

  Future<void> continueWithScreenOff() async {
    await prepareBackgroundCapture();
    if (broadcasting && Platform.isAndroid) {
      await _captureChannel.invokeMethod('background');
    }
  }

  Future<void> switchCamera({String? cameraId}) async {
    final track = localStream?.getVideoTracks().firstOrNull;
    if (track != null) {
      if (torch) await setTorch(false);
      final cameras = (await inputDevices())
          .where((device) => device.kind == 'videoinput')
          .toList();
      final current = cameras.indexWhere(
        (device) => device.deviceId == activeCameraId,
      );
      final next =
          cameraId ??
          (cameras.isEmpty
              ? null
              : cameras[(current + 1) % cameras.length].deviceId);
      await Helper.switchCamera(track, next);
      activeCameraId = next;
      options = options.copyWith(cameraId: next, clearCameraId: next == null);
      await refreshCameraControls();
    }
  }

  Future<void>? _stopping;
  Future<void> stop() =>
      _stopping ??= _stop().whenComplete(() => _stopping = null);
  Future<void> _stop() async {
    final receiver = _receiver;
    _receiver = null;
    final server = _server;
    _server = null;
    final local = localStream;
    localStream = null;
    remoteStream = null;
    _changed();
    // Stop private media and its CPU lease before waiting for network peers.
    for (final track in local?.getTracks() ?? <MediaStreamTrack>[]) {
      await track.stop().catchError((Object _) {});
    }
    await local?.dispose().catchError((Object _) {});
    if (_foregroundOwned) {
      _foregroundOwned = false;
      _captureChannel.setMethodCallHandler(null);
      try {
        await _captureChannel.invokeMethod<bool>('stop');
      } catch (exception) {
        error = 'Could not stop the capture notification: $exception';
      }
    }
    for (final peer in _peers.values.toList()) {
      await peer.close().catchError((Object _) {});
    }
    _peers.clear();
    _pendingCandidates.clear();
    await server?.stop();
    await receiver
        ?.close()
        .timeout(const Duration(seconds: 2), onTimeout: () => null)
        .catchError((Object _) {});
    microphoneMuted = false;
    cameraPaused = false;
    playbackMuted = torch = hasTorch = false;
    zoom = maxZoom = 1;
    activeCameraId = null;
    status = '';
    FeatureActivityService.instance.setActive(
      this,
      LocalistFeature.capture,
      false,
    );
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(stop());
    super.dispose();
  }
}

Map<String, dynamic> decodeCaptureSignal(dynamic message) {
  if (message is! String || message.length > 131072) {
    throw const FormatException('Invalid signal.');
  }
  final data = jsonDecode(message);
  if (data is! Map<String, dynamic> ||
      (data['type'] != 'offer' &&
          data['type'] != 'answer' &&
          data['candidate'] is! Map) ||
      (data.containsKey('sdp') && data['sdp'] is! String)) {
    throw const FormatException('Invalid signal.');
  }
  return data;
}
