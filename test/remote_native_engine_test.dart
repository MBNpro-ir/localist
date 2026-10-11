import 'dart:ffi';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/generated_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'bundled native engine answers through the generated FFI bridge',
    () async {
      final library = DynamicLibrary.open(
        '${Directory.current.path}/third_party/localist_remote/windows/runtime/librustdesk.dll',
      );
      final api = RustdeskImpl(library);
      expect(
        await api.mainGetVersion().timeout(const Duration(seconds: 10)),
        '1.5.0',
      );
      expect(api.translate(name: 'Connect', locale: 'en'), 'Connect');
      expect(api.translate(name: 'Connect', locale: 'fa'), isNotEmpty);
      expect(api.mainGetAppNameSync(), 'LocalistRemote');
    },
    skip: !Platform.isWindows,
  );
}
