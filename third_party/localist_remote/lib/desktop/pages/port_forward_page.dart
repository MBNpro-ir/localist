import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:get/get.dart';

const double _kColumn1Width = 30;
const double _kColumn4Width = 100;
const double _kRowHeight = 60;
const double _kTextLeftMargin = 20;

class _PortForward {
  int localPort;
  String remoteHost;
  int remotePort;

  _PortForward.fromJson(List<dynamic> json)
      : localPort = json[0] as int,
        remoteHost = json[1] as String,
        remotePort = json[2] as int;
}

class PortForwardPage extends StatefulWidget {
  PortForwardPage({
    Key? key,
    required this.id,
    required this.password,
    this.loginMethod = '',
    required this.tabController,
    required this.isRDP,
    required this.isSharedPassword,
    this.initialForward,
    this.forceRelay,
    this.connToken,
  }) : super(key: key);
  final String id;
  final String? password;
  final String loginMethod;
  final DesktopTabController tabController;
  final bool isRDP;
  final bool? forceRelay;
  final bool? isSharedPassword;
  final String? connToken;
  final Map<String, Object?>? initialForward;
  final SimpleWrapper<State<PortForwardPage>?> _lastState = SimpleWrapper(null);

  FFI get ffi => (_lastState.value! as _PortForwardPageState)._ffi;

  Future<void> applyInitialForward(Map<String, Object?> route) async {
    final state = _lastState.value;
    if (state is _PortForwardPageState) {
      await state.applyInitialForward(route);
    }
  }

  @override
  State<PortForwardPage> createState() {
    final state = _PortForwardPageState();
    _lastState.value = state;
    return state;
  }
}

class _PortForwardPageState extends State<PortForwardPage>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController localPortController = TextEditingController();
  final TextEditingController remoteHostController = TextEditingController();
  final TextEditingController remotePortController = TextEditingController();
  RxList<_PortForward> pfs = RxList.empty(growable: true);
  late FFI _ffi;

  @override
  void initState() {
    super.initState();
    _ffi = FFI(null);
    _ffi.start(widget.id,
        isPortForward: true,
        password: widget.password,
        loginMethod: widget.loginMethod,
        isSharedPassword: widget.isSharedPassword,
        forceRelay: widget.forceRelay,
        connToken: widget.connToken,
        isRdp: widget.isRDP);
    Get.put<FFI>(_ffi, tag: 'pf_${widget.id}');
    if (!widget.isRDP && widget.initialForward != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(applyInitialForward(widget.initialForward!));
      });
    }
    debugPrint("Port forward page init success with id ${widget.id}");
    // Call onSelected in post frame callback, since we cannot guarantee that the callback will not call setState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.tabController.onSelected?.call(widget.id);
    });
  }

  Future<void> applyInitialForward(Map<String, Object?> route) async {
    if (!mounted || widget.isRDP) return;
    final localPort = route['localPort'];
    final remoteHost = route['remoteHost'];
    final remotePort = route['remotePort'];
    if (localPort is! int || remoteHost is! String || remotePort is! int) {
      _showInitialForwardError('Invalid initial tunnel mapping.');
      return;
    }
    try {
      final peer = jsonDecode(bind.mainGetPeerSync(id: widget.id)) as Map;
      final routes = peer['port_forwards'] as List? ?? const [];
      List? existing;
      for (final candidate in routes.whereType<List>()) {
        if (candidate.length == 3 && candidate[0] == localPort) {
          existing = candidate;
          break;
        }
      }
      if (existing != null) {
        final existingHost = existing[1]?.toString().toLowerCase();
        if (!const {'127.0.0.1', 'localhost'}.contains(existingHost)) {
          throw StateError(
            'Local port $localPort already maps to another target. Remove that mapping before opening the Developer Agent tunnel.',
          );
        }
        if (existingHost != remoteHost.toLowerCase() ||
            existing[2] != remotePort) {
          await bind.sessionRemovePortForward(
            sessionId: _ffi.sessionId,
            localPort: localPort,
          );
          await bind.sessionAddPortForward(
            sessionId: _ffi.sessionId,
            localPort: localPort,
            remoteHost: remoteHost,
            remotePort: remotePort,
          );
        }
      } else {
        await bind.sessionAddPortForward(
          sessionId: _ffi.sessionId,
          localPort: localPort,
          remoteHost: remoteHost,
          remotePort: remotePort,
        );
      }
      refreshTunnelConfig();
    } catch (error) {
      _showInitialForwardError(error.toString());
    }
  }

  void _showInitialForwardError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  void dispose() {
    _ffi.close();
    _ffi.dialogManager.dismissAll();
    Get.delete<FFI>(tag: 'pf_${widget.id}');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: FutureBuilder(future: () async {
        if (!widget.isRDP) {
          refreshTunnelConfig();
        }
      }(), builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          return Container(
            decoration: BoxDecoration(
                border: Border.all(
                    width: 20,
                    color: Theme.of(context).scaffoldBackgroundColor)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                buildPrompt(context),
                Flexible(
                  child: Container(
                    decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.background,
                        border: Border.all(width: 1, color: MyTheme.border)),
                    child:
                        widget.isRDP ? buildRdp(context) : buildTunnel(context),
                  ),
                ),
              ],
            ),
          );
        }
        return const Offstage();
      }),
    );
  }

  buildPrompt(BuildContext context) {
    return Obx(() => Offstage(
          offstage: pfs.isEmpty && !widget.isRDP,
          child: Container(
              height: 45,
              color: const Color(0xFF007F00),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      translate('Listening ...'),
                      style: const TextStyle(fontSize: 16, color: Colors.white),
                    ),
                    Text(
                      translate('not_close_tcp_tip'),
                      style: const TextStyle(
                          fontSize: 10, color: Color(0xFFDDDDDD), height: 1.2),
                    )
                  ])).marginOnly(bottom: 8),
        ));
  }

  buildTunnel(BuildContext context) {
    text(String label) => Expanded(
        child: Text(translate(label)).marginOnly(left: _kTextLeftMargin));

    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: Theme.of(context).colorScheme,
      ),
      child: Obx(() => ListView.builder(
          controller: ScrollController(),
          itemCount: pfs.length + 2,
          itemBuilder: ((context, index) {
            if (index == 0) {
