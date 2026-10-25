import 'package:flutter/material.dart';

import '../../../../core/platform/system_channel.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../domain/story_decoration.dart';

const storyEmojis = [
  '😀', '😂', '🥹', '😍', '🥰', '😎', '🤩', '🥳', '😴', '🤯', '😭', '😡', //
  '❤️', '🔥', '✨', '🎉', '💯', '👏', '🙏', '👍', '👀', '💪', '🌈', '☀️', //
  '🌙', '⭐', '🌸', '🍕', '☕', '🍰', '🎂', '🎁', '🎵', '📸', '✈️', '🏖️', //
  '⚽', '🏆', '🐶', '🐱', '🦋', '🌊', '🏔️', '🌍', '💡', '📚', '💼', '🚀', //
];

/// Suggested reactions Telegram accepts for story tags.
const reactionEmojis = ['❤️', '👍', '👎', '🔥', '🥰', '👏', '😁', '🤔', '🤯', '😱', '🎉', '🤩', '😢', '💯'];

Future<String?> pickEmoji(
  BuildContext context, {
  List<String> emojis = storyEmojis,
  String title = 'Sticker',
}) => showModalBottomSheet<String>(
  context: context,
  showDragHandle: true,
  backgroundColor: GlowColors.surfaceHigh,
  builder: (context) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Flexible(
          child: GridView.count(
            shrinkWrap: true,
            crossAxisCount: 7,
            padding: const EdgeInsets.all(12),
            children: [
              for (final e in emojis)
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.pop(context, e),
                  child: Center(child: Text(e, style: const TextStyle(fontSize: 30))),
                ),
            ],
          ),
        ),
      ],
    ),
  ),
);

const _textColors = [
  Color(0xFFFFFFFF),
  Color(0xFF0D0F12),
  GlowColors.cyan,
  GlowColors.amber,
  GlowColors.coral,
  GlowColors.violet,
  GlowColors.magenta,
];

/// Creates or edits a text sticker; returns false when the user cleared it.
Future<bool?> editTextSticker(BuildContext context, TextSticker sticker) async {
  final controller = TextEditingController(text: sticker.text);
  var color = sticker.color;
  var pill = sticker.pill;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        backgroundColor: GlowColors.surfaceHigh,
        title: const Text('Text'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: controller, autofocus: true, maxLines: 3, minLines: 1),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              children: [
                for (final c in _textColors)
                  GestureDetector(
                    onTap: () => setState(() => color = c),
                    child: CircleAvatar(
                      radius: 15,
                      backgroundColor: c == color ? GlowColors.cyan : GlowColors.outline,
                      child: CircleAvatar(radius: 12, backgroundColor: c),
                    ),
                  ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: pill,
              onChanged: (v) => setState(() => pill = v),
              title: const Text('Background'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Done')),
        ],
      ),
    ),
  );
  final text = controller.text.trim();
  controller.dispose();
  if (ok != true) return null;
  if (text.isEmpty) return false;
  sticker
    ..text = text
    ..color = color
    ..pill = pill;
  return true;
}

Future<LinkTag?> askLink(BuildContext context) async {
  final controller = TextEditingController(text: 'https://');
  final url = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: GlowColors.surfaceHigh,
      title: const Text('Link'),
      content: TextField(controller: controller, autofocus: true, keyboardType: TextInputType.url),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Add')),
      ],
    ),
  );
  controller.dispose();
  if (url == null) return null;
  final normalized = url.contains('://') ? url : 'https://$url';
  final uri = Uri.tryParse(normalized);
  if (uri == null ||
      uri.host.isEmpty ||
      !(uri.scheme == 'https' || uri.scheme == 'http' || uri.scheme == 'tg')) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('That doesn’t look like a link')));
    }
    return null;
  }
  return LinkTag(normalized);
}

/// A location tag at the phone's position (name editable). Falls back to a
/// plain "📍 name" text sticker when no position is available.
Future<StoryDecoration?> askLocation(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  ({double latitude, double longitude, String name})? here;
  try {
    here = await const SystemChannel().currentLocation();
  } catch (_) {}
  if (!context.mounted) return null;
  final controller = TextEditingController(text: here?.name ?? '');
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: GlowColors.surfaceHigh,
      title: const Text('Location'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Place name'),
          ),
          const SizedBox(height: 8),
          Text(
            here == null
                ? 'Your position isn’t available, so this will be a label without a map pin.'
                : 'Viewers can open this place on a map.',
            style: const TextStyle(color: GlowColors.textMuted, fontSize: 13),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Add')),
      ],
    ),
  );
  controller.dispose();
  if (name == null) return null;
  if (name.isEmpty) {
    messenger.showSnackBar(const SnackBar(content: Text('Add a place name')));
    return null;
  }
  if (here == null) return TextSticker('📍 $name');
  return LocationTag(name, latitude: here.latitude, longitude: here.longitude);
}
