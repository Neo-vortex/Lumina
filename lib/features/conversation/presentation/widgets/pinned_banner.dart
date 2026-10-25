import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../../core/telegram/display.dart';
import '../../../../core/telegram/telegram_cache.dart';
import '../../../../core/theme/glow_colors.dart';

/// Pinned message banner (spec §6.2); tap jumps to the message.
class PinnedBanner extends StatelessWidget {
  const PinnedBanner({super.key, required this.message, required this.onTap, this.onUnpin});

  final td.Message message;
  final VoidCallback onTap;
  final VoidCallback? onUnpin;

  @override
  Widget build(BuildContext context) {
    final cache = context.read<TelegramCache>();
    return Material(
      color: GlowColors.surface,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: GlowColors.outline)),
          ),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 34,
                decoration: BoxDecoration(
                  color: GlowColors.violet,
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: glow(GlowColors.violet, intensity: 0.5),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Pinned message',
                      style: TextStyle(color: GlowColors.violet, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      Display.preview(cache, message),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
              if (onUnpin != null)
                IconButton(
                  tooltip: 'Unpin',
                  icon: const Icon(Icons.close_rounded, size: 18, color: GlowColors.textMuted),
                  onPressed: onUnpin,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
