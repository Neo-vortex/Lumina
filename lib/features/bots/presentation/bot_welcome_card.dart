import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../core/tdlib/td_errors.dart';
import '../../../core/telegram/widgets/chat_avatar.dart';
import '../../../core/telegram/widgets/looping_gif.dart';
import '../../../core/telegram/widgets/td_file_image.dart';
import '../../../core/theme/glow_colors.dart';
import '../../../core/theme/motion.dart';
import '../../../core/widgets/glow_button.dart';
import '../data/bot_start_links.dart';
import '../data/bots_repository.dart';

/// A new bot chat: the bot's photo or clip, what it says about itself and
/// a big Start (with a pending `t.me/bot?start=…` parameter, if any).
class BotWelcomeCard extends StatefulWidget {
  const BotWelcomeCard({super.key, required this.botUserId, required this.chatId, required this.title});

  final int botUserId;
  final int chatId;
  final String title;

  @override
  State<BotWelcomeCard> createState() => _BotWelcomeCardState();
}

class _BotWelcomeCardState extends State<BotWelcomeCard> {
  td.BotInfo? _info;
  var _sending = false;

  @override
  void initState() {
    super.initState();
    context.read<BotsRepository>().info(widget.botUserId).then((i) {
      if (mounted) setState(() => _info = i);
    });
  }

  Future<void> _start() async {
    if (_sending) return;
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final links = context.read<BotStartLinks>();
    try {
      await context.read<BotsRepository>().start(
        botUserId: widget.botUserId,
        chatId: widget.chatId,
        parameter: links.peek(widget.chatId) ?? '',
      );
      // Only a /start that went out uses up the link's parameter.
      links.take(widget.chatId);
    } on TdException catch (e) {
      if (mounted) setState(() => _sending = false);
      messenger?.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Widget? _media(td.BotInfo info) {
    if (info.animation case final a?) {
      return LoopingGif(file: a.animation, thumbnail: a.thumbnail?.file, minithumbnail: a.minithumbnail);
    }
    if (info.photo case final p? when p.sizes.isNotEmpty) {
      return TdFileImage(file: p.sizes.last.photo, semanticLabel: 'Bot picture');
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    final media = info == null ? null : _media(info);
    final description = info?.description ?? '';
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: GlowColors.surface.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: GlowColors.violet.withValues(alpha: 0.45)),
          boxShadow: glow(GlowColors.violet, intensity: 0.3),
        ),
        child: AnimatedSize(
          duration: Motion.standard,
          curve: Motion.enter,
          alignment: Alignment.topCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (media != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: AspectRatio(aspectRatio: 16 / 9, child: media),
                )
              else
                ChatAvatar(id: widget.chatId, title: widget.title, size: 72, glowIntensity: 0.6),
              const SizedBox(height: 14),
              Text(
                widget.title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              if (description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  description,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, color: GlowColors.text, height: 1.4),
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: GlowButton(label: 'Start', busy: _sending, onPressed: _sending ? null : _start),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
