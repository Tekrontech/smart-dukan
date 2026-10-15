import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../l10n/l10n.dart';

/// Opens the camera and returns the first barcode / IMEI read (spec 5.3).
Future<String?> scanCode(BuildContext context) =>
    Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const _ScannerPage(), fullscreenDialog: true));

class _ScannerPage extends StatefulWidget {
  const _ScannerPage();

  @override
  State<_ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<_ScannerPage> {
  final _controller = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(l.scanTitle),
        actions: [
          IconButton(onPressed: () => _controller.toggleTorch(), icon: const Icon(Icons.flashlight_on_outlined)),
        ],
      ),
      body: MobileScanner(
        controller: _controller,
        errorBuilder: (context, error) => Center(
          child: Text(l.cameraUnavailable, style: const TextStyle(color: Colors.white)),
        ),
        onDetect: (capture) {
          if (_done) return;
          final value = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
          if (value == null || value.isEmpty) return;
          _done = true;
          HapticFeedback.selectionClick();
          Navigator.of(context).pop(value.trim());
        },
      ),
    );
  }
}
