import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';

import '../../../../core/theme/glow_colors.dart';

/// A folder invite as a glowing QR card.
class FolderQrScreen extends StatelessWidget {
  const FolderQrScreen({super.key, required this.url, required this.title, required this.color});

  final String url;
  final String title;
  final Color color;

  static Route<void> route({required String url, required String title, required Color color}) =>
      MaterialPageRoute(
        builder: (_) => FolderQrScreen(url: url, title: title, color: color),
      );

  Uint8List? _png() {
    final r = zx.encodeBarcode(
      contents: url,
      params: EncodeParams(
        format: Format.qrCode,
        width: 640,
        height: 640,
        margin: 2,
        eccLevel: EccLevel.medium,
      ),
    );
    if (!r.isValid || r.data == null) return null;
    return pngFromBytes(r.data!, r.width ?? 640, r.height ?? 640);
  }

  @override
  Widget build(BuildContext context) {
    final png = _png();
    return Scaffold(
      backgroundColor: GlowColors.backgroundDeep,
      appBar: AppBar(backgroundColor: Colors.transparent, title: Text(title)),
      body: Center(
        child: Container(
          margin: const EdgeInsets.all(32),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: glow(color, intensity: 1.2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (png == null)
                const Padding(padding: EdgeInsets.all(48), child: Text('Could not draw the QR code'))
              else
                Semantics(
                  label: 'QR code for $url',
                  child: Image.memory(png, width: 260, height: 260, filterQuality: FilterQuality.none),
                ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(url, style: const TextStyle(color: Colors.black54, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
