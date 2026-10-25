import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/glow_colors.dart';
import '../story_message_opener.dart';

/// Interactive story areas over the 9:16 media: reaction bubbles and
/// weather (drawn here, as Telegram apps do), and tappable links, places,
/// venues and reposted messages (drawn into the media by the poster).
class StoryAreasLayer extends StatelessWidget {
  const StoryAreasLayer({super.key, required this.story, required this.onReact, this.onBusy});

  final td.Story story;
  final void Function(String? emoji) onReact;

  /// Pauses the story while a confirmation is open.
  final void Function(bool busy)? onBusy;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final frame = c.biggest;
      final chosen = switch (story.chosenReactionType) {
        td.ReactionTypeEmoji(:final emoji) => emoji,
        _ => null,
      };
      return Stack(
        children: [
          for (final a in story.areas)
            if (_child(context, a, chosen) case final child?)
              Positioned.fromRect(
                rect: Rect.fromCenter(
                  center: Offset(
                    a.position.xPercentage / 100 * frame.width,
                    a.position.yPercentage / 100 * frame.height,
                  ),
                  width: a.position.widthPercentage / 100 * frame.width,
                  height: a.position.heightPercentage / 100 * frame.height,
                ),
                child: Transform.rotate(angle: a.position.rotationAngle * math.pi / 180, child: child),
              ),
        ],
      );
    },
  );

  Widget? _child(BuildContext context, td.StoryArea a, String? chosen) {
    switch (a.type) {
      case td.StoryAreaTypeSuggestedReaction(:final reactionType, :final totalCount, :final isDark):
        final emoji = switch (reactionType) {
          td.ReactionTypeEmoji(:final emoji) => emoji,
          _ => null,
        };
        if (emoji == null) return null;
        final selected = chosen == emoji;
        return Semantics(
          button: true,
          label: 'React $emoji',
          child: GestureDetector(
            onTap: () => onReact(selected ? null : emoji),
            child: LayoutBuilder(
              builder: (context, c) => Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark ? const Color(0xE61C2027) : const Color(0xF2FFFFFF),
                  border: selected ? Border.all(color: GlowColors.violet, width: 3) : null,
                  boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 8)],
                ),
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(emoji, style: TextStyle(fontSize: c.maxHeight * 0.42)),
                    if (totalCount > 0)
                      Text(
                        '$totalCount',
                        style: TextStyle(
                          fontSize: c.maxHeight * 0.14,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      case td.StoryAreaTypeWeather(:final temperature, :final emoji, :final backgroundColor):
        return LayoutBuilder(
          builder: (context, c) => Container(
            decoration: BoxDecoration(
              color: Color(0xFF000000 | backgroundColor),
              borderRadius: BorderRadius.circular(c.maxHeight / 2),
            ),
            alignment: Alignment.center,
            child: FittedBox(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('$emoji ${temperature.round()}°C', style: const TextStyle(color: Colors.white)),
              ),
            ),
          ),
        );
      case td.StoryAreaTypeLink(:final url):
        return _Tap(label: 'Open link', onTap: () => _confirmOpen(context, url, Uri.tryParse(url)));
      case td.StoryAreaTypeUpgradedGift(:final giftName):
        final url = 'https://t.me/nft/$giftName';
        return _Tap(label: 'Open gift', onTap: () => _confirmOpen(context, url, Uri.tryParse(url)));
      case td.StoryAreaTypeLocation(:final location, :final address):
        final name = [
          address?.street,
          address?.city,
        ].whereType<String>().where((s) => s.isNotEmpty).join(', ');
        return _Tap(
          label: 'Open place',
          onTap: () => _confirmOpen(context, name.isEmpty ? 'Location' : name, _geo(location, name)),
        );
      case td.StoryAreaTypeVenue(:final venue):
        return _Tap(
          label: 'Open ${venue.title}',
          onTap: () => _confirmOpen(context, venue.title, _geo(venue.location, venue.title)),
        );
      case td.StoryAreaTypeMessage(:final chatId, :final messageId):
        final StoryMessageOpener opener;
        try {
          opener = context.read<StoryMessageOpener>();
        } on ProviderNotFoundException {
          return null;
        }
        return _Tap(
          label: 'Open message',
          onTap: () async {
            // Paused while the chat is open; resumes on return.
            onBusy?.call(true);
            await opener.open(context, chatId, messageId);
            onBusy?.call(false);
          },
        );
    }
  }

  static Uri _geo(td.Location l, String label) => Uri.parse(
    'geo:${l.latitude},${l.longitude}?q=${l.latitude},${l.longitude}(${Uri.encodeComponent(label)})',
  );

  Future<void> _confirmOpen(BuildContext context, String label, Uri? uri) async {
    if (uri == null) return;
    onBusy?.call(true);
    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: GlowColors.surfaceHigh,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListTile(
          leading: Icon(
            uri.scheme == 'geo' ? Icons.place_rounded : Icons.open_in_new_rounded,
            color: GlowColors.cyan,
          ),
          title: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: uri.scheme == 'geo' ? const Text('Open in maps') : Text(uri.host),
          trailing: FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Open')),
        ),
      ),
    );
    onBusy?.call(false);
    if (ok == true) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// Invisible hit target over something the poster drew into the media;
/// a faint outline appears while pressed.
class _Tap extends StatefulWidget {
  const _Tap({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_Tap> createState() => _TapState();
}

class _TapState extends State<_Tap> {
  var _down = false;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: widget.label,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: _down ? Border.all(color: Colors.white70, width: 2) : null,
          color: _down ? Colors.white10 : null,
        ),
      ),
    ),
  );
}
