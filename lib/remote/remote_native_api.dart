import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:path_provider/path_provider.dart';

import 'embedded_remote_app.dart';

/// Configuration IPC only. Session rendering stays in the bundled engine.
class RemoteNativeApi {
  static Future<RustdeskImpl>? _initializing;

  static Future<RustdeskImpl> get() async {
    await LocalistRemoteRuntime.ensureStarted();
    if (Platform.isAndroid) return bind;
    return _initializing ??= _initialize().catchError((Object error) {
      _initializing = null;
      throw error;
    });
  }

  static Future<RustdeskImpl> _initialize() async {
    final library = DynamicLibrary.open(
      '${File(Platform.resolvedExecutable).parent.path}\\librustdesk.dll',
    );
    final api = RustdeskImpl(library);
    await api.mainInit(
      appDir: (await getApplicationDocumentsDirectory()).path,
      customClientConfig: '',
    );
    await api.mainCheckConnectStatus();
    final deadline = DateTime.now().add(const Duration(seconds: 12));
    while (!await api.optionSynced()) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('Remote settings IPC did not become ready.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return api;
  }
}
