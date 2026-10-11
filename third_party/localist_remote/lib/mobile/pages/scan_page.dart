import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../common.dart';
import '../widgets/dialog.dart';

class ScanPage extends StatefulWidget {
  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final controller = MobileScannerController(formats: [BarcodeFormat.qrCode]);
  bool processing = false;

  Future<void> read(BarcodeCapture capture) async {
    if (processing) return;
    final value = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
    if (value == null) return;
    processing = true;
    await controller.stop();
    if (value.startsWith('config=')) {
      try {
        final config = ServerConfig.decode(value.substring(7));
        showServerSettingsWithValue(config, gFFI.dialogManager, null);
      } catch (_) { showToast('Invalid QR code'); }
    } else {
      handleUriLink(uriString: value);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scan QR'), actions: [
      IconButton(icon: const Icon(Icons.image), onPressed: () async {
        final file = await ImagePicker().pickImage(source: ImageSource.gallery);
        if (file != null) {
          final capture = await controller.analyzeImage(file.path);
          if (capture != null) await read(capture);
        }
      }),
      IconButton(icon: const Icon(Icons.flash_on), onPressed: controller.toggleTorch),
      IconButton(icon: const Icon(Icons.switch_camera), onPressed: controller.switchCamera),
    ]), body: MobileScanner(controller: controller, onDetect: (c) => unawaited(read(c))));

  @override
  void dispose() { unawaited(controller.dispose()); super.dispose(); }
}
