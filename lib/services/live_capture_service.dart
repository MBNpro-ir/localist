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
    this.receiverControls = false,
    this.orientation = 'auto',
  });
  final String orientation;
  final String? cameraId, microphoneId;
  final bool receiverControls;
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
        !['auto', 'portrait', 'landscape'].contains(orientation) ||
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
    bool? receiverControls,
    int? width,
    int? height,
    int? fps,
    int? bitrateKbps,
    bool? echoCancellation,
    bool? noiseSuppression,
    bool? autoGain,
    String? orientation,
  }) => LiveCaptureOptions(
    background: background ?? this.background,
    camera: camera,
    microphone: microphone,
    rearCamera: rearCamera,
    width: width ?? this.width,
    height: height ?? this.height,
    fps: fps ?? this.fps,
    bitrateKbps: bitrateKbps ?? this.bitrateKbps,
    echoCancellation: echoCancellation ?? this.echoCancellation,
    noiseSuppression: noiseSuppression ?? this.noiseSuppression,
    autoGain: autoGain ?? this.autoGain,
    receiverControls: receiverControls ?? this.receiverControls,
    cameraId: clearCameraId ? null : cameraId ?? this.cameraId,
    microphoneId: microphoneId ?? this.microphoneId,
    orientation: orientation ?? this.orientation,
  );
}

/// Local signaling only; WebRTC encrypts media with DTLS-SRTP. No public STUN,
/// TURN, accounts or external signaling server is used. Each run has a new key.
class CaptureSignalingServer {
  CaptureSignalingServer({
    required this.html,
    required this.accept,
    this.maxViewers = 4,
  });
  final String html;
  final Future<void> Function(WebSocket) accept;
  final int maxViewers;
  final Set<WebSocket> clients = {};
  final Map<WebSocket, String> clientHosts = {};
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
          clientHosts[socket] =
              request.connectionInfo?.remoteAddress.address ?? '';
          socket.pingInterval = const Duration(seconds: 15);
          unawaited(
            socket.done
                .whenComplete(() {
                  clients.remove(socket);
                  clientHosts.remove(socket);
                })
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
    clientHosts.clear();
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
  Map<String, dynamic> _remoteControls = {};
  List<MediaDeviceInfo> _controlMicrophones = [];
  final Map<int, Completer<void>> _controlRequests = {};
  int _controlSequence = 0, _captureGeneration = 0;
  Map<String, dynamic> get captureControlState => receiving
      ? Map<String, dynamic>.from(_remoteControls)
      : {
          'enabled': broadcasting && options.receiverControls && !busy,
          'width': options.width,
          'height': options.height,
          'fps': options.fps,
          'bitrate': options.bitrateKbps,
          'zoom': (zoom * 100).round(),
          'maxZoom': (maxZoom * 100).round(),
          'noise': options.noiseSuppression,
          'echo': options.echoCancellation,
          'gain': options.autoGain,
          'torch': torch,
          'torchAvailable': hasTorch,
          'message': error,
          for (var i = 0; i < _controlMicrophones.length && i < 12; i++)
            'microphone$i': _controlMicrophones[i].label,
        };
  bool get broadcasting => _server != null;
  bool get receiving => _receiver != null;
  bool get active => broadcasting || receiving;
  int get viewers => _peers.length;
  int get signalingPort => _server?.port ?? 0;
  String get signalingKey => _server?.token ?? '';
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
    if (!_disposed) {
      notifyListeners();
      if (broadcasting) {
        final message = jsonEncode({
          'type': 'control-state',
          'state': captureControlState,
        });
        for (final socket in _peers.keys.toList()) {
          if (socket.readyState == WebSocket.open) socket.add(message);
        }
      }
    }
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
            'دوربین ورودی پیدا نشد؛ فرستندهٔ گوشی را روشن کنید تا خودکار دریافت شود. / '
            'No input camera found. Start sharing on your phone for automatic reception.',
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
      await setOrientation(value.orientation);
      activeCameraId =
          localStream?.getVideoTracks().firstOrNull?.getSettings()['deviceId']
              as String?;
      if (_disposed) {
        await stop();
        return;
      }
      await refreshCameraControls();
      _controlMicrophones = (await inputDevices())
          .where((device) => device.kind == 'audioinput')
          .take(12)
          .toList();
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
    final preferredAddresses = await _usbAddresses(
      _server?.clientHosts[socket] ?? '',
    );
    _peers[socket] = peer;
    final candidates = <RTCIceCandidate>[];
    peer.onIceCandidate = (candidate) {
      if (socket.readyState == WebSocket.open &&
          captureCandidateAllowed(candidate.candidate, preferredAddresses)) {
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
              } else if (data['type'] == 'control') {
                final id = data['id'];
                try {
                  await requestCaptureControl(
                    Map<String, dynamic>.from(data['command'] as Map),
                  );
                  if (socket.readyState == WebSocket.open) {
                    socket.add(
                      jsonEncode({'type': 'control-result', 'id': id}),
                    );
                  }
                } catch (error) {
                  if (socket.readyState == WebSocket.open) {
                    socket.add(
                      jsonEncode({
                        'type': 'control-result',
                        'id': id,
                        'error': '$error',
                      }),
                    );
                  }
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
      final preferredAddresses = await _usbAddresses(uri.host);
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
        if (socket.readyState == WebSocket.open &&
            captureCandidateAllowed(candidate.candidate, preferredAddresses)) {
          socket.add(jsonEncode({'candidate': candidate.toMap()}));
        }
      };
      peer.onConnectionState = (state) {
        status = state.name
            .replaceFirst('RTCPeerConnectionState', '')
            .toLowerCase();
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          unawaited(stop());
        } else if (state ==
            RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          Timer(const Duration(seconds: 5), () {
            if (_receiver == socket && status == 'disconnected') {
              unawaited(stop());
            }
          });
        }
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
                } else if (data['type'] == 'control-state') {
                  _remoteControls = Map<String, dynamic>.from(
                    data['state'] as Map,
                  );
                  _changed();
                } else if (data['type'] == 'control-result') {
                  final pending = _controlRequests.remove(data['id']);
                  if (data['error'] is String) {
                    pending?.completeError(StateError(data['error'] as String));
                  } else {
                    pending?.complete();
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
  static Future<Set<String>> _usbAddresses(String remoteHost) async {
    final routes = await LanNetworkService.instance.routes();
    final usb = routes.where(
      (route) => route.capturePriority == 0 && route.contains(remoteHost),
    );
    return usb.map((route) => route.address).toSet();
  }

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
    if (playbackMuted == mute) return;
    for (final track
        in remoteStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      await Helper.setVolume(mute ? 0 : 1, track);
    }
    playbackMuted = mute;
    _changed();
  }

  Future<void> setOrientation(String value) async {
    if (!['auto', 'portrait', 'landscape'].contains(value)) {
      throw const FormatException('Invalid camera orientation.');
    }
    if (Platform.isAndroid) {
      await _captureChannel.invokeMethod('orientation', {
        'track': localStream?.getVideoTracks().firstOrNull?.id,
        'mode': value,
      });
    }
    options = options.copyWith(orientation: value);
    _changed();
  }

  void allowReceiverControls(bool allow) {
    options = options.copyWith(receiverControls: allow);
    _changed();
  }

  Future<void> requestCaptureControl(Map<String, dynamic> command) async {
    validateCaptureControl(command);
    if (receiving) {
      if (_remoteControls['enabled'] != true || _controlRequests.isNotEmpty) {
        throw StateError('Sender controls are unavailable or busy.');
      }
      final id = ++_controlSequence;
      final pending = Completer<void>();
      _controlRequests[id] = pending;
      _receiver!.add(
        jsonEncode({'type': 'control', 'id': id, 'command': command}),
      );
      try {
        await pending.future.timeout(const Duration(seconds: 15));
      } finally {
        _controlRequests.remove(id);
      }
      return;
    }
    if (!broadcasting || !options.receiverControls || busy) {
      throw StateError('Receiver controls are not enabled by the sender.');
    }
    final width = command['width'] as int? ?? options.width;
    final microphone = command['microphone'] as int? ?? -1;
    if (microphone >= _controlMicrophones.length) {
      throw StateError('The requested microphone is no longer available.');
    }
    final next = options.copyWith(
      width: width,
      height: switch (width) {
        320 => 240,
        640 => 480,
        1280 => 720,
        _ => 1080,
      },
      fps: command['fps'] as int?,
      bitrateKbps: command['bitrate'] as int?,
      noiseSuppression: command['noise'] as bool?,
      echoCancellation: command['echo'] as bool?,
      autoGain: command['gain'] as bool?,
      microphoneId: microphone >= 0
          ? _controlMicrophones[microphone].deviceId
          : null,
    );
    next.validate();
    final restart =
        next.width != options.width ||
        next.fps != options.fps ||
        next.noiseSuppression != options.noiseSuppression ||
        next.echoCancellation != options.echoCancellation ||
        next.autoGain != options.autoGain;
    busy = true;
    final generation = _captureGeneration;
    final previous = options;
    error = '';
    _changed();
    try {
      if (restart) {
        final old = localStream;
        for (final track in old?.getTracks() ?? <MediaStreamTrack>[]) {
          await track.stop();
        }
        await old?.dispose();
        localStream = null;
        Future<MediaStream> acquire(LiveCaptureOptions value) async {
          final selected = value.microphoneId;
          if (selected != null && value.microphone) {
            await Helper.selectAudioInput(selected);
          }
          return navigator.mediaDevices.getUserMedia(value.constraints);
        }

        MediaStream stream;
        var applied = next;
        try {
          stream = await acquire(next);
        } catch (_) {
          applied = previous;
          stream = await acquire(previous);
        }
        if (generation != _captureGeneration || !broadcasting || _disposed) {
          for (final track in stream.getTracks()) {
            await track.stop();
          }
          await stream.dispose();
          throw StateError('Capture stopped during configuration.');
        }
        localStream = stream;
        await setOrientation(applied.orientation);
        for (final peer in _peers.values.toList()) {
          for (final sender in await peer.getSenders()) {
            final replacement = stream
                .getTracks()
                .where((track) => track.kind == sender.track?.kind)
                .firstOrNull;
            if (replacement != null) await sender.replaceTrack(replacement);
          }
        }
        // A sender may revoke permission while native capture is restarting.
        // Never restore the older permission value from an accepted request.
        options = applied.copyWith(receiverControls: options.receiverControls);
        muteMicrophone(microphoneMuted);
        pauseCamera(cameraPaused);
        activeCameraId =
            stream.getVideoTracks().firstOrNull?.getSettings()['deviceId']
                as String?;
        await refreshCameraControls();
        if (applied == previous) {
          throw StateError(
            'Requested mode was unavailable; previous capture restored.',
          );
        }
      } else {
        if (microphone >= 0) {
          await selectMicrophone(_controlMicrophones[microphone].deviceId);
        }
        options = next.copyWith(receiverControls: options.receiverControls);
      }
      for (final peer in _peers.values.toList()) {
        for (final sender in await peer.getSenders()) {
          if (sender.track?.kind != 'video') continue;
          final parameters = sender.parameters;
          for (final encoding in parameters.encodings ?? <RTCRtpEncoding>[]) {
            encoding.maxBitrate = options.bitrateKbps * 1000;
            encoding.maxFramerate = options.fps;
          }
          await sender.setParameters(parameters);
        }
      }
      if (command['zoom'] is num) {
        await setZoom((command['zoom'] as num).toDouble());
      }
      if (command['torch'] is bool && hasTorch) {
        await setTorch(command['torch'] as bool);
      }
    } catch (exception) {
      error = '$exception';
      if (localStream == null && generation == _captureGeneration) await stop();
      rethrow;
    } finally {
      busy = false;
      _changed();
    }
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
      await setOrientation(options.orientation);
      await refreshCameraControls();
    }
  }

  Future<void>? _stopping;
  Future<void> stop() =>
      _stopping ??= _stop().whenComplete(() => _stopping = null);
  Future<void> _stop() async {
    ++_captureGeneration;
    for (final pending in _controlRequests.values) {
      pending.completeError(StateError('Capture disconnected.'));
    }
    _controlRequests.clear();
    _remoteControls = {};
    final receiver = _receiver;
    _receiver = null;
    final server = _server;
    _server = null;
    final local = localStream;
    if (Platform.isAndroid && local != null) {
      await _captureChannel
          .invokeMethod('orientation', {'mode': 'auto'})
          .catchError((Object _) {});
    }
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

bool captureCandidateAllowed(
  String? candidate,
  Set<String> preferredAddresses,
) {
  if (preferredAddresses.isEmpty || candidate == null || candidate.isEmpty) {
    return true;
  }
  final fields = candidate.trim().split(RegExp(r'\s+'));
  return fields.length > 4 && preferredAddresses.contains(fields[4]);
}

Map<String, dynamic> decodeCaptureSignal(dynamic message) {
  if (message is! String || message.length > 131072) {
    throw const FormatException('Invalid signal.');
  }
  final data = jsonDecode(message);
  if (data is! Map<String, dynamic> ||
      (data['type'] != 'offer' &&
          data['type'] != 'answer' &&
          data['candidate'] is! Map &&
          data['type'] != 'control' &&
          data['type'] != 'control-state' &&
          data['type'] != 'control-result') ||
      (data.containsKey('sdp') && data['sdp'] is! String)) {
    throw const FormatException('Invalid signal.');
  }
  if (data['type'] == 'control') {
    if (data['id'] is! int || data['command'] is! Map<String, dynamic>) {
      throw const FormatException('Invalid control request.');
    }
    validateCaptureControl(data['command'] as Map<String, dynamic>);
  }
  if (data['type'] == 'control-state' &&
      data['state'] is! Map<String, dynamic>) {
    throw const FormatException('Invalid control state.');
  }
  if (data['type'] == 'control-result' &&
      (data['id'] is! int ||
          (data['error'] != null && data['error'] is! String))) {
    throw const FormatException('Invalid control result.');
  }
  return data;
}

void validateCaptureControl(Map<String, dynamic> command) {
  const keys = {
    'width',
    'fps',
    'bitrate',
    'zoom',
    'noise',
    'echo',
    'gain',
    'torch',
    'microphone',
  };
  if (command.isEmpty || command.keys.any((key) => !keys.contains(key))) {
    throw const FormatException('Unsupported capture control.');
  }
  for (final key in ['noise', 'echo', 'gain', 'torch']) {
    if (command.containsKey(key) && command[key] is! bool) {
      throw const FormatException('Invalid capture switch.');
    }
  }
  for (final key in ['width', 'fps', 'bitrate', 'microphone']) {
    if (command.containsKey(key) && command[key] is! int) {
      throw const FormatException('Invalid capture number.');
    }
  }
  if ((command.containsKey('width') &&
          ![320, 640, 1280, 1920].contains(command['width'])) ||
      (command.containsKey('fps') &&
          ![10, 15, 24, 30, 60].contains(command['fps'])) ||
      (command.containsKey('bitrate') &&
          ((command['bitrate'] as int) < 250 ||
              (command['bitrate'] as int) > 12000)) ||
      (command.containsKey('microphone') &&
          ((command['microphone'] as int) < -1 ||
              (command['microphone'] as int) >= 12)) ||
      (command.containsKey('zoom') &&
          (command['zoom'] is! num ||
              !(command['zoom'] as num).isFinite ||
              (command['zoom'] as num) < 1 ||
              (command['zoom'] as num) > 100))) {
    throw const FormatException('Capture control is out of range.');
  }
}
