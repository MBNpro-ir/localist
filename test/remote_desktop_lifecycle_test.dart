import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/localist/desktop_host.dart';
import 'package:flutter_hbb/utils/multi_window_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'hidden host handles session hide/show without revealing standalone home',
    () async {
      const codec = StandardMethodCodec();
      final outgoing = <MethodCall>[];
      const windows = MethodChannel('mixin.one/flutter_multi_window');
      const manager = MethodChannel('window_manager');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      for (final channel in [windows, manager]) {
        messenger.setMockMethodCallHandler(channel, (call) async {
          outgoing.add(call);
          return null;
        });
      }
      registerLocalistDesktopHost();
      Future<void> receive(String method, dynamic arguments) async {
        final done = Completer<void>();
        ServicesBinding.instance.channelBuffers.push(
          'mixin.one/flutter_multi_window_channel',
          codec.encodeMethodCall(
            MethodCall(method, {'fromWindowId': 77, 'arguments': arguments}),
          ),
          (response) {
            try {
              codec.decodeEnvelope(response!);
              done.complete();
            } catch (error, stack) {
              done.completeError(error, stack);
            }
          },
        );
        await done.future;
      }

      try {
        await receive(kWindowEventShow, {'id': 77});
        expect(rustDeskWinManager.getActiveWindows(), contains(77));
        await receive(kWindowEventHide, {'id': 77});
        expect(rustDeskWinManager.getActiveWindows(), isNot(contains(77)));
        await receive(kWindowEventShow, {'id': 77});
        expect(rustDeskWinManager.getActiveWindows(), contains(77));
        await receive(kWindowMainWindowOnTop, null);
        await receive(kWindowActionRebuild, null);
        expect(outgoing, isEmpty);
      } finally {
        await rustDeskWinManager.unregisterActiveWindow(77);
        rustDeskWinManager.setMethodHandler(null);
        for (final channel in [windows, manager]) {
          messenger.setMockMethodCallHandler(channel, null);
        }
      }
    },
  );
}
