import 'package:flutter/material.dart';
import 'package:lumina_tdlib/api.dart' as td;
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/telegram/widgets/formatted_text_view.dart';
import '../../../../core/theme/glow_colors.dart';

/// A channel's sponsored message, clearly labelled as an ad.
class SponsoredCard extends StatelessWidget {
  const SponsoredCard({super.key, required this.ad, required this.onOpen});

  final td.SponsoredMessage ad;
  final Future<void> Function() onOpen;

  Future<void> _open() async {
    await onOpen().catchError((_) {});
    final uri = Uri.tryParse(ad.sponsor.url);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final text = switch (ad.content) {
      td.MessageText(:final text) => text,
      td.MessagePhoto(:final caption) || td.MessageVideo(:final caption) => caption,
      _ => const td.FormattedText(text: '', entities: []),
    };
    return Semantics(
      container: true,
      label: 'Sponsored message from ${ad.title}',
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 48, 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: GlowColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: GlowColors.amber.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    ad.title,
                    style: const TextStyle(fontWeight: FontWeight.w600, color: GlowColors.amber),
                  ),
                ),
                Text(
                  ad.isRecommended ? 'Recommended' : 'Ad',
                  style: const TextStyle(fontSize: 11, color: GlowColors.textMuted),
                ),
              ],
            ),
            if (text.text.isNotEmpty) ...[
              const SizedBox(height: 6),
              FormattedTextView(text, style: const TextStyle(fontSize: 14.5, height: 1.35)),
            ],
            if (ad.sponsor.info.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(ad.sponsor.info, style: const TextStyle(fontSize: 11, color: GlowColors.textMuted)),
            ],
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _open,
                style: OutlinedButton.styleFrom(
                  foregroundColor: GlowColors.amber,
                  side: const BorderSide(color: GlowColors.amber),
                  minimumSize: const Size.fromHeight(44),
                ),
                child: Text(ad.buttonText.isEmpty ? 'Open' : ad.buttonText),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
