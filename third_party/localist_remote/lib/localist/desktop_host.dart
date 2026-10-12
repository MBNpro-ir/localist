import 'dart:convert';

import '../common.dart';
import '../consts.dart';
import '../utils/multi_window_manager.dart';
import '../utils/platform_channel.dart';
import 'package:window_size/window_size.dart' as window_size;

/// Main-window session callbacks without mounting the standalone home page.
/// Closing/reusing tabs and opening another monitor still need this handler
/// when Localist keeps the upstream main window hidden.
void registerLocalistDesktopHost() {
  rustDeskWinManager.setMethodHandler((call, fromWindowId) async {
    switch (call.method) {
      case kWindowEventShow:
        await rustDeskWinManager.registerActiveWindow(call.arguments['id']);
      case kWindowEventHide:
        await rustDeskWinManager.unregisterActiveWindow(call.arguments['id']);
      case kWindowRefreshCurrentUser:
        gFFI.userModel.refreshCurrentUser();
      case kWindowGetScreenList:
        return jsonEncode((await window_size.getScreenList())
            .map((screen) => {
                  'frame': {
                    'l': screen.frame.left,
                    't': screen.frame.top,
                    'r': screen.frame.right,
                    'b': screen.frame.bottom
                  },
                  'visibleFrame': {
                    'l': screen.visibleFrame.left,
                    't': screen.visibleFrame.top,
                    'r': screen.visibleFrame.right,
                    'b': screen.visibleFrame.bottom
                  },
                  'scaleFactor': screen.scaleFactor,
                })
            .toList());
      case kWindowConnect:
        await connectMainDesktop(call.arguments['id'],
            isFileTransfer: call.arguments['isFileTransfer'],
            isViewCamera: call.arguments['isViewCamera'],
            isTerminal: call.arguments['isTerminal'],
            isTcpTunneling: call.arguments['isTcpTunneling'],
            isRDP: call.arguments['isRDP'],
            password: call.arguments['password'],
            forceRelay: call.arguments['forceRelay'],
            connToken: call.arguments['connToken']);
      case kWindowBumpMouse:
        return RdPlatformChannel.instance
            .bumpMouse(dx: call.arguments['dx'], dy: call.arguments['dy']);
      case kWindowEventMoveTabToNewWindow:
        final args = (call.arguments as String).split(',');
        if (args.length != 4) return null;
        final windowId = int.tryParse(args[0]);
        final type =
            WindowType.values.where((t) => t.name == args[3]).firstOrNull;
        if (windowId != null && type != null) {
          await rustDeskWinManager.moveTabToNewWindow(
              windowId, args[1], args[2], type);
        }
      case kWindowEventOpenMonitorSession:
        final args = jsonDecode(call.arguments);
        await rustDeskWinManager.openMonitorSession(
            args['window_id'],
            args['peer_id'],
            args['display'],
            args['display_count'],
            parseParamScreenRect(args),
            args['window_type']);
      case kWindowEventRemoteWindowCoords:
        final windowId = int.tryParse(call.arguments);
        if (windowId != null) {
          return jsonEncode(
              await rustDeskWinManager.getOtherRemoteWindowCoords(windowId));
        }
      // The visible Localist window is owned by the primary app. Never reveal
      // the upstream blank home when a session asks to foreground its parent.
      case kWindowMainWindowOnTop:
      case kWindowActionRebuild:
        return null;
    }
  });
}
