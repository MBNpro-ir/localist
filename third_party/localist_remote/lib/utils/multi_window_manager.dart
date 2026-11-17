import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/main.dart';
import 'package:flutter_hbb/models/input_model.dart';

/// must keep the order
// ignore: constant_identifier_names
enum WindowType {
  Main,
  RemoteDesktop,
  FileTransfer,
  ViewCamera,
  PortForward,
  Terminal,
  Unknown
}

extension Index on int {
  WindowType get windowType {
    switch (this) {
      case 0:
        return WindowType.Main;
      case 1:
        return WindowType.RemoteDesktop;
      case 2:
        return WindowType.FileTransfer;
      case 3:
        return WindowType.ViewCamera;
      case 4:
        return WindowType.PortForward;
      case 5:
        return WindowType.Terminal;
      default:
        return WindowType.Unknown;
    }
  }
}

class MultiWindowCallResult {
  int windowId;
  dynamic result;

  MultiWindowCallResult(this.windowId, this.result);
}

/// Window Manager
/// mainly use it in `Main Window`
/// use it in sub window is not recommended
class RustDeskMultiWindowManager {
  RustDeskMultiWindowManager._();

  static final instance = RustDeskMultiWindowManager._();

  final Set<int> _inactiveWindows = {};
  final Set<int> _activeWindows = {};
  final List<AsyncCallback> _windowActiveCallbacks = List.empty(growable: true);
  final List<int> _remoteDesktopWindows = List.empty(growable: true);
  final List<int> _fileTransferWindows = List.empty(growable: true);
  final List<int> _viewCameraWindows = List.empty(growable: true);
  final List<int> _portForwardWindows = List.empty(growable: true);
  final List<int> _terminalWindows = List.empty(growable: true);

  moveTabToNewWindow(int windowId, String peerId, String sessionId,
      WindowType windowType) async {
    var params = {
      'type': windowType.index,
      'id': peerId,
      'tab_window_id': windowId,
      'session_id': sessionId,
    };
    if (windowType == WindowType.RemoteDesktop) {
      await _newSession(
        false,
        WindowType.RemoteDesktop,
        kWindowEventNewRemoteDesktop,
        peerId,
        _remoteDesktopWindows,
        jsonEncode(params),
      );
    } else if (windowType == WindowType.ViewCamera) {
      await _newSession(
        false,
        WindowType.ViewCamera,
        kWindowEventNewViewCamera,
        peerId,
        _viewCameraWindows,
        jsonEncode(params),
      );
    }
  }

  // This function must be called in the main window thread.
  // Because the _remoteDesktopWindows is managed in that thread.
  openMonitorSession(int windowId, String peerId, int display, int displayCount,
      Rect? screenRect, int windowType) async {
    final isCamera = windowType == WindowType.ViewCamera.index;
    final windowIDs = isCamera ? _viewCameraWindows : _remoteDesktopWindows;
    if (windowIDs.length > 1) {
      for (final windowId in windowIDs) {
        if (await DesktopMultiWindow.invokeMethod(
            windowId,
            kWindowEventActiveDisplaySession,
            jsonEncode({
              'id': peerId,
              'display': display,
            }))) {
          return;
        }
      }
    }

    final displays = display == kAllDisplayValue
        ? List.generate(displayCount, (index) => index)
        : [display];
    var params = {
      'type': windowType,
      'id': peerId,
      'tab_window_id': windowId,
      'display': display,
      'displays': displays,
    };
    if (screenRect != null) {
      params['screen_rect'] = {
        'l': screenRect.left,
        't': screenRect.top,
        'r': screenRect.right,
        'b': screenRect.bottom,
      };
    }
    await _newSession(
      false,
      windowType.windowType,
      isCamera ? kWindowEventNewViewCamera : kWindowEventNewRemoteDesktop,
      peerId,
      windowIDs,
      jsonEncode(params),
      screenRect: screenRect,
    );
  }

  Future<int> newSessionWindow(
    WindowType type,
    String remoteId,
    String msg,
    List<int> windows,
    bool withScreenRect,
  ) async {
    final windowController = await DesktopMultiWindow.createWindow(msg);
    if (isWindows) {
      windowController.setInitBackgroundColor(Colors.black);
    }
    final windowId = windowController.windowId;
    if (!withScreenRect) {
      windowController
        ..setFrame(const Offset(0, 0) &
            Size(1280 + windowId * 20, 720 + windowId * 20))
        ..center()
        ..setTitle(getWindowNameWithId(
          remoteId,
          overrideType: type,
        ));
    } else {
      windowController.setTitle(getWindowNameWithId(
        remoteId,
        overrideType: type,
      ));
    }
    if (isMacOS) {
      Future.microtask(() => windowController.show());
    }
    registerActiveWindow(windowId);
    windows.add(windowId);
    return windowId;
  }

  Future<MultiWindowCallResult> _newSession(
    bool openInTabs,
    WindowType type,
    String methodName,
    String remoteId,
    List<int> windows,
    String msg, {
    Rect? screenRect,
  }) async {
    if (openInTabs) {
      if (windows.isEmpty) {
        final windowId = await newSessionWindow(
            type, remoteId, msg, windows, screenRect != null);
        return MultiWindowCallResult(windowId, null);
      } else {
        return call(type, methodName, msg);
      }
    } else {
      if (_inactiveWindows.isNotEmpty) {
        for (final windowId in windows) {
          if (_inactiveWindows.contains(windowId)) {
            if (screenRect == null) {
              await restoreWindowPosition(type,
                  windowId: windowId, peerId: remoteId);
            }
            await DesktopMultiWindow.invokeMethod(windowId, methodName, msg);
            if (methodName != kWindowEventNewRemoteDesktop) {
              WindowController.fromWindowId(windowId).show();
            }
            registerActiveWindow(windowId);
            return MultiWindowCallResult(windowId, null);
          }
        }
      }
      final windowId = await newSessionWindow(
          type, remoteId, msg, windows, screenRect != null);
      return MultiWindowCallResult(windowId, null);
    }
  }

  Future<MultiWindowCallResult> newSession(
    WindowType type,
    String methodName,
    String remoteId,
    List<int> windows, {
    String? password,
    String loginMethod = '',
    bool? forceRelay,
    String? switchUuid,
    bool? isRDP,
    bool? isSharedPassword,
    String? connToken,
    Map<String, Object?>? initialForward,
  }) async {
    var params = {
      "type": type.index,
      "id": remoteId,
      "password": password,
      "forceRelay": forceRelay
    };
    if (switchUuid != null) {
      params['switch_uuid'] = switchUuid;
    }
    if (isRDP != null) {
      params['isRDP'] = isRDP;
    }
    if (initialForward != null) {
      params['initialForward'] = initialForward;
    }
    if (isSharedPassword != null) {
      params['isSharedPassword'] = isSharedPassword;
    }
    if (connToken != null) {
      params['connToken'] = connToken;
    }
    if (loginMethod.isNotEmpty) {
      params['loginMethod'] = loginMethod;
    }
    final msg = jsonEncode(params);

    // separate window for file transfer is not supported
    bool openInTabs = type != WindowType.RemoteDesktop ||
        mainGetLocalBoolOptionSync(kOptionOpenNewConnInTabs);

    if (windows.length > 1 || !openInTabs) {
      for (final windowId in windows) {
        if (await DesktopMultiWindow.invokeMethod(
            windowId, kWindowEventActiveSession, remoteId)) {
          return MultiWindowCallResult(windowId, null);
        }
      }
    }

    return _newSession(openInTabs, type, methodName, remoteId, windows, msg);
  }

  Future<MultiWindowCallResult> newRemoteDesktop(
    Stri