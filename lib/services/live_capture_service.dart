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
import 'capture_capabilities.dart';
import 'log_service.dart';

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
    this.receiverControls = true,
    this.orientation = 'landscape',
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
            if (cameraId == null)
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
        width < 2 ||
        width > 8192 ||
        height < 2 ||
        height > 8192 ||
        width.isOdd ||
        height.isOdd ||
        fps < 1 ||
        fps > 240 ||
        bitrateKbps < 1 ||
        bitrateKbps > 1000000) {
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
          final remoteHost =
              request.connectionInfo?.remoteAddress.address ?? '';
          final socket = await WebSocketTransformer.upgrade(request);
          clients.add(socket);
          clientHosts[socket] = remoteHost;
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

/// Capture signaling stays on the LAN, even if the OS/app has a web proxy.
/// A proxy accepting discovery but rejecting WebSocket upgrades can return
/// misleading 404/501 responses. Never send the pairing key through it.
Future<WebSocket> connectCaptureSocket(Uri uri) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8)
    ..findProxy = (_) => 'DIRECT';
  try {
    final socket = await WebSocket.connect(
      uri
          .replace(
            scheme: uri.scheme == 'https' ? 'wss' : 'ws',
            path: '/signal',
            fragment: '',
            queryParameters: {'key': uri.fragment},
          )
          .toString(),
      customClient: client,
    ).timeout(const Duration(seconds: 10));
    unawaited(
      socket.done
          .whenComplete(() => client.close(force: true))
          .catchError((Object _) {}),
    );
    return socket;
  } on WebSocketException catch (error) {
    client.close(force: true);
    throw WebSocketException(
      'اتصال محلی دوربین برقرار نشد؛ سرویس فرستنده و مسیر شبکه بررسی شود. / Local capture handshake failed.',
      error.httpStatusCode,
    );
  } catch (_) {
    client.close(force: true);
    rethrow;
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

  static Future<CaptureCapabilities> deviceCapabilities(
    String cameraId, {
    int width = 1280,
    int height = 720,
    int fps = 30,
  }) async {
    final args = {
      'cameraId': cameraId,
      'width': width,
      'height': height,
      'fps': fps,
    };
    final data = Platform.isWindows
        ? await const MethodChannel(
            'com.prs.localist.vpn',
          ).invokeMapMethod<dynamic, dynamic>(
            'getCaptureDeviceCapabilities',
            args,
          )
        : await _captureChannel.invokeMapMethod<dynamic, dynamic>(
            'cameraCapabilities',
            args,
          );
    return CaptureCapabilities.fromMap(data ?? {});
  }

  MediaStream? localStream, remoteStream;
  CaptureSignalingServer? _server;
  WebSocket? _receiver;
  Timer? _receiverWatchdog;
  final Map<WebSocket, RTCPeerConnection> _peers = {};
  final List<RTCIceCandidate> _pendingCandidates = [];
  List<String> addresses = [];
  LiveCaptureOptions options = const LiveCaptureOptions();
  bool busy = false, microphoneMuted = false, cameraPaused = false;
  bool playbackMuted = false, torch = false;
  double zoom = 1, maxZoom = 1;
  bool hasTorch = false;
  String? activeCameraId;
  CaptureCapabilities capabilities = const CaptureCapabilities();
  String _error = '', status = '', _lastLoggedState = '';
  String get error => _error;
  set error(String value) {
    if (value.isNotEmpty && value != _error) {
      LogService.instance.warning('Camera & Mic: ${redactCaptureError(value)}');
    }
    _error = value;
  }

  Map<String, dynamic> _remoteControls = {};
  List<MediaDeviceInfo> _controlMicrophones = [];
  final Map<int, Completer<void>> _controlRequests = {};
  int _controlSequence = 0, _captureGeneration = 0;
  Map<String, dynamic> get captureControlState => receiving
      ? Map<String, dynamic>.from(_remoteControls)
      : {
          'enabled': broadcasting && !busy,
          ...capabilities.toJson(),
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
  Future<List<Map<String, dynamic>>> connectionDiagnostics() async => [
    for (final peer in _peers.values.toList())
      for (final report in await peer.getStats())
        if (report.type == 'inbound-rtp')
          {
            'type': report.type,
            for (final key in [
              'kind',
              'mediaType',
              'bytesReceived',
              'packetsReceived',
              'framesDecoded',
              'frameWidth',
              'frameHeight',
            ])
              if (report.values[key] != null) key: report.values[key],
          },
  ];
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
      final state =
          'sending=$broadcasting receiving=$receiving status=$status viewers=$viewers';
      if (state != _lastLoggedState) {
        _lastLoggedState = state;
        LogService.instance.info('Camera & Mic: $state');
      }
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
    final stopping = _stopping;
    if (stopping != null) await stopping;
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
    final generation = ++_captureGeneration;
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
      value = value.copyWith(background: true, receiverControls: true);
      final inputs = await inputDevices();
      final cameras = inputs.where((d) => d.kind == 'videoinput').toList();
      final microphones = inputs.where((d) => d.kind == 'audioinput').toList();
      final cameraId =
          cameras
              .where((d) => d.deviceId == value.cameraId)
              .firstOrNull
              ?.deviceId ??
          cameras.firstOrNull?.deviceId;
      final microphoneId =
          microphones
              .where((d) => d.deviceId == value.microphoneId)
              .firstOrNull
              ?.deviceId ??
          microphones.firstOrNull?.deviceId;
      if (value.camera && cameraId == null ||
          value.microphone && microphoneId == null) {
        throw StateError(
          'ورودی انتخاب‌شده در دسترس نیست. / Selected input is unavailable.',
        );
      }
      value = value.copyWith(cameraId: cameraId, microphoneId: microphoneId);
      if (value.camera) {
        capabilities = await deviceCapabilities(
          cameraId!,
          width: value.width,
          height: value.height,
          fps: value.fps,
        );
        final mode = capabilities.choose(
          width: value.width,
          height: value.height,
        );
        if (mode != null) {
          value = value.copyWith(
            width: mode.width,
            height: mode.height,
            fps: value.fps.clamp(mode.minFps, mode.maxFps),
          );
          capabilities = await deviceCapabilities(
            cameraId,
            width: value.width,
            height: value.height,
            fps: value.fps,
          );
        }
        if (capabilities.hasBitrateRange) {
          value = value.copyWith(
            bitrateKbps: value.bitrateKbps.clamp(
              capabilities.minBitrate,
              capabilities.maxBitrate,
            ),
          );
        }
      }
      options = value;
      if (_disposed || generation != _captureGeneration) return;
      await initializeMedia();
      if (Platform.isAndroid && value.background) {
        _captureChannel.setMethodCallHandler((call) async {
          if (call.method == 'captureDiagnostics') {
            LogService.instance.info('${call.arguments}');
          }
          if (call.method == 'stopCapture') await stop();
          if (call.method == 'captureError') {
            error = '${call.arguments}';
            await stop();
          }
        });
        _foregroundOwned = true;
        await _captureChannel.invokeMethod<bool>('start', {
          'camera': value.camera,
          'microphone': value.microphone,
        });
        if (_disposed || generation != _captureGeneration) {
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
      if (_disposed || generation != _captureGeneration) {
        await stop();
        return;
      }
      activeCameraId =
          localStream?.getVideoTracks().firstOrNull?.getSettings()['deviceId']
              as String?;
      await setOrientation(value.orientation);
      if (_disposed) {
        await stop();
        return;
      }
      await refreshCameraControls();
      if (_disposed || generation != _captureGeneration) return;
      _controlMicrophones = (await inputDevices())
          .where((device) => device.kind == 'audioinput')
          .take(12)
          .toList();
      // Preview must never play our own microphone through the local speakers.
      final html = await rootBundle.loadString('assets/live_capture.html');
      if (_disposed || generation != _captureGeneration) return;
      final server = CaptureSignalingServer(html: html, accept: _acceptViewer);
      await server.start(port: port);
      if (_disposed || generation != _captureGeneration) {
        await server.stop();
        return;
      }
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
    var mediaConnected = false;
    final handshakeDeadline = Timer(const Duration(seconds: 20), () {
      if (_peers[socket] == peer && !mediaConnected) {
        LogService.instance.warning(
          'Camera sender: media handshake timed out; releasing viewer slot.',
        );
        unawaited(socket.close(WebSocketStatus.goingAway));
      }
    });
    final candidates = <RTCIceCandidate>[];
    peer.onIceCandidate = (candidate) {
      if (socket.readyState == WebSocket.open &&
          captureCandidateAllowed(candidate.candidate, preferredAddresses)) {
        socket.add(jsonEncode({'candidate': candidate.toMap()}));
      }
    };
    peer.onConnectionState = (state) {
      if (_peers[socket] != peer) return;
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        mediaConnected = true;
        handshakeDeadline.cancel();
      }
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
            .catchError((Object e) {
              LogService.instance.warning(
                'Camera sender signaling: ${redactCaptureError('$e')}',
              );
              unawaited(socket.close(WebSocketStatus.invalidFramePayloadData));
            });
      },
      onDone: () {
        handshakeDeadline.cancel();
        _peers.remove(socket);
        if (_peers.isEmpty && broadcasting) status = 'waiting';
        unawaited(peer.close());
        _changed();
      },
      onError: (Object e) {
        handshakeDeadline.cancel();
        LogService.instance.warning(
          'Camera sender socket: ${redactCaptureError('$e')}',
        );
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
      try {
        for (final sender in await peer.getSenders()) {
          if (sender.track?.kind != 'video') continue;
          final parameters = sender.parameters;
          for (final encoding in parameters.encodings ?? <RTCRtpEncoding>[]) {
            encoding.maxBitrate = options.bitrateKbps * 1000;
            encoding.maxFramerate = options.fps;
          }
          await sender.setParameters(parameters);
        }
      } catch (e) {
        // Some OEM encoders reject live rate controls. Keep negotiated media
        // flowing at the encoder's supported rate instead of dropping the peer.
        LogService.instance.warning(
          'Camera rate control unavailable: ${redactCaptureError('$e')}',
        );
      }
      _changed();
    } catch (e) {
      error = 'Camera sender negotiation: ${redactCaptureError('$e')}';
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
        'اطلاعات دستگاه فرستنده معتبر نیست. / Invalid sender discovery information.',
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
    final generation = ++_captureGeneration;
    _changed();
    try {
      await initializeMedia();
      final socket = await connectCaptureSocket(uri);
      if (_disposed || generation != _captureGeneration) {
        await socket.close();
        return;
      }
      _receiver = socket;
      if (_disposed) {
        await stop();
        return;
      }
      final peer = await createPeerConnection(_configuration);
      if (_disposed || generation != _captureGeneration) {
        await peer.close();
        return;
      }
      _peers[socket] = peer;
      final preferredAddresses = await _usbAddresses(uri.host);
      if (_disposed || generation != _captureGeneration) {
        if (_receiver == socket) await stop();
        return;
      }
      peer.onTrack = (event) {
        if (_receiver != socket) return;
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
        if (_receiver != socket) return;
        status = state.name
            .replaceFirst('RTCPeerConnectionState', '')
            .toLowerCase();
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _receiverWatchdog?.cancel();
        } else if (state ==
            RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          error = 'ارتباط رسانه برقرار نشد. / Media connection failed.';
          unawaited(stop());
        } else if (state ==
            RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          Timer(const Duration(seconds: 5), () {
            if (_receiver == socket && status == 'disconnected') {
              error = 'ارتباط رسانه قطع شد. / Media connection disconnected.';
              unawaited(stop());
            }
          });
        }
        _changed();
      };
      Future<void> queue = Future.value();
      _receiverWatchdog?.cancel();
      _receiverWatchdog = Timer(const Duration(seconds: 15), () {
        if (_receiver == socket && status != 'connected') {
          error = 'مهلت اتصال رسانه تمام شد. / Media connection timed out.';
          unawaited(stop());
        }
      });
      socket.listen(
        (message) {
          queue = queue
              .then((_) async {
                if (_receiver != socket) return;
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
                if (_receiver != socket) return;
                error = '$e';
                unawaited(stop());
              });
        },
        onDone: () {
          if (_receiver != socket) return;
          error = 'ارتباط با فرستنده قطع شد. / Sender disconnected.';
          unawaited(stop());
        },
        onError: (Object e) {
          if (_receiver != socket) return;
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
        'cameraId': activeCameraId ?? options.cameraId,
        'rear': options.rearCamera,
        'mode': value,
      });
    }
    options = options.copyWith(orientation: value);
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
    if (!broadcasting || busy) {
      throw StateError('Receiver controls are not enabled by the sender.');
    }
    busy = true;
    final generation = _captureGeneration;
    final previous = options;
    error = '';
    _changed();
    try {
      final width = command['width'] as int? ?? options.width;
      final requestedHeight =
          command['height'] as int? ??
          (command.containsKey('width') ? null : options.height);
      final mode = capabilities.modes
          .where(
            (m) =>
                m.width == width &&
                (requestedHeight == null || m.height == requestedHeight),
          )
          .firstOrNull;
      if ((command.containsKey('width') || command.containsKey('height')) &&
          capabilities.modes.isNotEmpty &&
          mode == null) {
        throw StateError(
          'این حالت توسط دوربین پشتیبانی نمی‌شود. / Camera mode is not supported.',
        );
      }
      final microphone = command['microphone'] as int? ?? -1;
      if (microphone >= _controlMicrophones.length) {
        throw StateError('The requested microphone is no longer available.');
      }
      var next = options.copyWith(
        width: width,
        height: requestedHeight ?? mode?.height ?? options.height,
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
      if (mode != null && (next.fps < mode.minFps || next.fps > mode.maxFps)) {
        throw StateError(
          'نرخ فریم توسط این حالت پشتیبانی نمی‌شود. / Unsupported frame rate for this mode.',
        );
      }
      final limits = options.camera && options.cameraId != null
          ? await deviceCapabilities(
              options.cameraId!,
              width: next.width,
              height: next.height,
              fps: next.fps,
            )
          : capabilities;
      if (limits.hasBitrateRange &&
          (next.bitrateKbps < limits.minBitrate ||
              next.bitrateKbps > limits.maxBitrate)) {
        if (!command.containsKey('bitrate')) {
          next = next.copyWith(
            bitrateKbps: next.bitrateKbps.clamp(
              limits.minBitrate,
              limits.maxBitrate,
            ),
          );
        } else {
          throw StateError(
            'بیت‌ریت خارج از محدودهٔ انکودر است. / Bitrate is outside encoder limits.',
          );
        }
      }
      final restart =
          next.width != options.width ||
          next.height != options.height ||
          next.fps != options.fps ||
          next.noiseSuppression != options.noiseSuppression ||
          next.echoCancellation != options.echoCancellation ||
          next.autoGain != options.autoGain;
      if (generation != _captureGeneration || !broadcasting || _disposed) {
        throw StateError('Capture stopped during configuration.');
      }
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
        options = applied.copyWith(receiverControls: true);
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
        options = next.copyWith(receiverControls: true);
      }
      capabilities = limits;
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
    if (options.cameraId != null) {
      try {
        capabilities = await deviceCapabilities(
          options.cameraId!,
          width: options.width,
          height: options.height,
          fps: options.fps,
        );
      } catch (_) {}
    }
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
        if (call.method == 'captureError') {
          error = '${call.arguments}';
          await stop();
        }
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
    if (busy || _stopping != null || !broadcasting) return;
    busy = true;
    final generation = _captureGeneration;
    _changed();
    try {
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
        if (next == null || next == activeCameraId) return;
        await Helper.switchCamera(track, next);
        if (_disposed || generation != _captureGeneration) return;
        activeCameraId = next;
        options = options.copyWith(cameraId: next);
        await setOrientation(options.orientation);
        await refreshCameraControls();
      }
    } finally {
      busy = false;
      _changed();
    }
  }

  Future<void>? _stopping;
  Future<void> stop() =>
      _stopping ??= _stop().whenComplete(() => _stopping = null);
  Future<void> _stop() async {
    ++_captureGeneration;
    _receiverWatchdog?.cancel();
    _receiverWatchdog = null;
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

String redactCaptureError(String value) => value
    .replaceAll(RegExp(r'#[A-Za-z0-9_=-]{32,}'), '#[REDACTED]')
    .replaceAll(RegExp(r'key=[A-Za-z0-9_=-]{32,}'), 'key=[REDACTED]');

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
    'height',
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
  for (final key in ['width', 'height', 'fps', 'bitrate', 'microphone']) {
    if (command.containsKey(key) && command[key] is! int) {
      throw const FormatException('Invalid capture number.');
    }
  }
  if ((command.containsKey('width') &&
          ((command['width'] as int) < 2 ||
              (command['width'] as int) > 8192 ||
              (command['width'] as int).isOdd)) ||
      (command.containsKey('height') &&
          ((command['height'] as int) < 2 ||
              (command['height'] as int) > 8192 ||
              (command['height'] as int).isOdd)) ||
      (command.containsKey('fps') &&
          ((command['fps'] as int) < 1 || (command['fps'] as int) > 240)) ||
      (command.containsKey('bitrate') &&
          ((command['bitrate'] as int) < 1 ||
              (command['bitrate'] as int) > 1000000)) ||
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
