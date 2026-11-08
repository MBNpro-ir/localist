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
  });
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
          }
        : false,
    'audio': microphone
        ? {
            'echoCancellation': echoCancellation,
            'noiseSuppression': noiseSuppression,
            'autoGainControl': autoGain,
            'sampleRate': 48000,
            'channelCount': 1,
          }
        : false,
  };
  void validate() {
    if ((!camera && !microphone) ||
        ![640, 1280, 1920].contains(width) ||
        ![480, 720, 1080].contains(height) ||
        ![15, 24, 30, 60].contains(fps) ||
        bitrateKbps < 250 ||
        bitrateKbps > 12000) {
      throw const FormatException('Invalid capture settings.');
    }
  }
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
    for (final client in clients.toList()) {
      await client.close();
    }
    clients.clear();
    await _server?.close(force: true);
    _server = null;
    token = '';
  }
}

class LiveCaptureService extends ChangeNotifier {
  MediaStream? localStream, remoteStream;
  CaptureSignalingServer? _server;
  WebSocket? _receiver;
  final Map<WebSocket, RTCPeerConnection> _peers = {};
  final List<RTCIceCandidate> _pendingCandidates = [];
  List<String> addresses = [];
  LiveCaptureOptions options = const LiveCaptureOptions();
  bool busy = false, microphoneMuted = false, cameraPaused = false;
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
      localStream = await navigator.mediaDevices.getUserMedia(
        value.constraints,
      );
      if (_disposed) {
        await stop();
        return;
      }
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

  Future<void> switchCamera() async {
    final track = localStream?.getVideoTracks().firstOrNull;
    if (track != null) await Helper.switchCamera(track);
  }

  Future<void>? _stopping;
  Future<void> stop() =>
      _stopping ??= _stop().whenComplete(() => _stopping = null);
  Future<void> _stop() async {
    final receiver = _receiver;
    _receiver = null;
    await receiver?.close();
    final server = _server;
    _server = null;
    await server?.stop();
    for (final peer in _peers.values.toList()) {
      await peer.close();
    }
    _peers.clear();
    _pendingCandidates.clear();
    final local = localStream;
    localStream = null;
    remoteStream = null;
    for (final track in local?.getTracks() ?? <MediaStreamTrack>[]) {
      await track.stop();
    }
    await local?.dispose();
    if (_foregroundOwned) {
      _foregroundOwned = false;
      _captureChannel.setMethodCallHandler(null);
      try {
        await _captureChannel.invokeMethod<bool>('stop');
      } catch (exception) {
        error = 'Could not stop the capture notification: $exception';
      }
    }
    microphoneMuted = false;
    cameraPaused = false;
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
