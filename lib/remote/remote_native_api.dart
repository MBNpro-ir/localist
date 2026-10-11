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
  static Future<RustdeskImpl>? _constructing;
  static bool _initialized = false;

  static Future<RustdeskImpl> get() async {
    await LocalistRemoteRuntime.ensureStarted();
    if (Platform.isAndroid) return bind;
    final existing = _api;
    if (_initialized && existing != null) return existing;
    // Retry IPC stages on the same bridge. Construction (including a failure)
    // is retained because flutter_rust_bridge allows only one platform object.
    final initializing = _initializing ??= _initialize().whenComplete(
      () => _initializing = null,
    );
    final api = await initializing;
    _api ??= api;
    return api;
  }

  static Future<RustdeskImpl> _initialize() async {
    final api = await (_constructing ??= _construct());
    _api = api;
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
    _initialized = true;
    return api;
  }

  static Future<RustdeskImpl> _construct() async {
    final library = DynamicLibrary.open(
      '${File(Platform.resolvedExecutable).parent.path}\\librustdesk.dll',
    );
    return RustdeskImpl(library);
  }
}
