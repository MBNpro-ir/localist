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
  static RustdeskImpl? _api;

  static Future<RustdeskImpl> get() async {
    await LocalistRemoteRuntime.ensureStarted();
    if (Platform.isAndroid) return bind;
    final existing = _api;
    if (existing != null) return existing;
    // Keep the failed future too. flutter_rust_bridge registers one
    // RustdeskPlatform per Dart process; retrying after a partial FFI failure
    // would construct a second platform and throw the misleading singleton
    // RPC exception shown in the Remote Control page.
    final initializing = _initializing ??= _initialize();
    final api = await initializing;
    _api ??= api;
    return api;
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
