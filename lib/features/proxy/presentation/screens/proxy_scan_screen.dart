import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';

import '../../../../core/theme/glow_colors.dart';
import '../../data/proxy_config.dart';

/// Camera QR scanner (zxing-cpp, no Google services) that returns the proxy
/// links found in the first code holding any. The gallery button scans a
/// screenshot instead.
class ProxyScanScreen extends StatefulWidget {
  const ProxyScanScreen({super.key});

  static Future<List<ProxyConfig>?> scan(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProxyScanScreen()));

  @override
  State<ProxyScanScreen> createState() => _ProxyScanScreenState();
}

class _ProxyScanScreenState extends State<ProxyScanScreen> {
  var _done = false;
  String? _lastRejected;

  void _onScan(Code code) {
    final text = code.text;
    if (_done || !code.isValid || text == null) return;
    final found = ProxyConfig.parseLinks(text);
    if (found.isNotEmpty) {
      _done = true;
      Navigator.of(context).pop(found);
      return;
    }
    // The camera keeps seeing the same code; say so once.
    if (text != _lastRejected) {
      _lastRejected = text;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('That QR code has no proxy link')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: GlowColors.text,
        title: const Text('Scan proxy QR code'),
      ),
      body: ReaderWidget(
        codeFormat: Format.qrCode,
        tryHarder: true,
        tryInverted: true,
        showToggleCamera: false,
        scanDelay: const Duration(milliseconds: 300),
        scanDelaySuccess: const Duration(milliseconds: 300),
        cropPercent: 0.7,
        actionButtonsBackgroundColor: GlowColors.surfaceHigh,
        onScan: _onScan,
        onScanFailure: (_) {},
      ),
    );
  }
}
