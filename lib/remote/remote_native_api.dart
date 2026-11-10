import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:path_provider/path_provider.dart';

import 'embedded_remote_app.dart';
import '../services/log_service.dart';

/// Configuration IPC only. Session rendering stays in the bundled engine.
class RemoteNativeApi {
  static Future<RustdeskImpl>? _initializing;
  static RustdeskImpl? _api;
  static Future<RustdeskImpl>? _constructing;
  static bool _initialized = false;

  static Future<RustdeskImpl> get() async {
    LogService.instance.debug(
      'Remote native API requested platform=${Platform.operatingSystem} initialized=$_initialized',
    );
    await LocalistRemoteRuntime.ensureStarted();
    if (Platform.isAndroid) {
      LogService.instance.debug('Remote native API using Android binding');
      return bind;
    }
    final existing = _api;
    if (_initialized && existing != null) {
      LogService.instance.debug('Remote native API using initialized binding');
      return existing;
    }
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
    LogService.instance.debug('Remote native API initialization started');
    final api = await (_constructing ??= _construct());
    _api = api;
    LogService.instance.debug(
      'Remote native API bridge constructed; starting native initialization',
    );
    await api.mainInit(
      appDir: (await getApplicationDocumentsDirectory()).path,
      customClientConfig: '',
    );
    await api.mainCheckConnectStatus();
    LogService.instance.debug(
      'Remote native API waiting for IPC options synchronization',
    );
    final deadline = DateTime.now().add(const Duration(seconds: 12));
    var polls = 0;
    while (!await api.optionSynced()) {
      polls++;
      if (DateTime.now().isAfter(deadline)) {
        LogService.instance.debug(
          'Remote native API IPC synchronization timed out polls=$polls',
        );
        throw TimeoutException('Remote settings IPC did not become ready.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    _initialized = true;
    LogService.instance.debug(
      'Remote native API initialization completed polls=$polls',
    );
    return api;
  }

  static Future<RustdeskImpl> _construct() async {
    LogService.instance.debug('Remote native API opening bundled DLL');
    final library = DynamicLibrary.open(
      '${File(Platform.resolvedExecutable).parent.path}\\librustdesk.dll',
    );
    final api = RustdeskImpl(library);
    LogService.instance.debug('Remote native API DLL bridge created');
    return api;
  }
}
