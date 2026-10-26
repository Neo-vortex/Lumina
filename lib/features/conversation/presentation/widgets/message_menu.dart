import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../../core/telegram/widgets/formatted_text_view.dart';
import '../../../../core/theme/glow_colors.dart';

enum MessageAction {
  reply,
  copy,
  selectText,
  edit,
  pin,
  unpin,
  forward,
  forwardHidden,
  select,
  copyLink,
  details,
  delete,
  aiAction,
  transcribe,
}

/// Extra entries other features add (AI action, transcription).
class ExtraMenuEntry {
  const ExtraMenuEntry(this.action, this.icon, this.label);
  final MessageAction action;
  final IconData icon;
  final String label;
}

/// Tap menu, focus style: the chat dims, the tapped bubble ([bubble], drawn
/// where it was, [anchor]) lifts into focus with a pill of [quickReactions]
/// above it (a chevron opens every reaction) and a glass action list below,
/// headed by [readStatus] when known. Returns the chosen action, or the
/// emoji as a reaction.
Future<({MessageAction? action, String? reaction})?> showMessageMenu(
  BuildContext context, {
  required td.Message message,
  required td.MessageProperties? properties,
  required Future<List<String>> reactions,
  required bool protectedContent,
  List<String> quickReactions = const [],
  Rect? anchor,
  Widget? bubble,
  Future<String?>? readStatus,
  Widget Function(String emoji, double size)? reactionIcon,
  List<ExtraMenuEntry> extras = const [],
}) {
  HapticFeedback.selectionClick();
  final p = properties;
  final hasText = _plainText(message) != null;
  final canSave = !protectedContent && (p?.canBeSaved ?? true);
  final items = <(MessageAction, IconData, String, Color?)>[
    if (p?.canBeReplied ?? true) (MessageAction.reply, Icons.reply_rounded, 'Reply', null),
    if (hasText && canSave) (MessageAction.copy, Icons.copy_rounded, 'Copy', null),
    if (hasText && canSave) (MessageAction.selectText, Icons.text_fields_rounded, 'Select text', null),
    if (p?.canBeEdited ?? false) (MessageAction.edit, Icons.edit_rounded, 'Edit', null),
    if ((p?.canBePinned ?? false) && !message.isPinned)
      (MessageAction.pin, Icons.push_pin_rounded, 'Pin', null),
    if ((p?.canBePinned ?? false) && message.isPinned)
      (MessageAction.unpin, Icons.push_pin_outlined, 'Unpin', null),
    if (p?.canBeForwarded ?? false) (MessageAction.forward, Icons.forward_rounded, 'Forward', null),
    if ((p?.canBeForwarded ?? false) && canSave)
      (MessageAction.forwardHidden, Icons.visibility_off_rounded, 'Forward quietly', null),
    for (final e in extras) (e.action, e.icon, e.label, GlowColors.cyan),
    (MessageAction.select, Icons.check_circle_outline_rounded, 'Select', null),
    if (p?.canGetLink ?? false) (MessageAction.copyLink, Icons.link_rounded, 'Copy link', null),
    (MessageAction.details, Icons.info_outline_rounded, 'Details', null),
    // One entry; the confirmation offers "for everyone" when allowed.
    if ((p?.canBeDeletedOnlyForSelf ?? false) || (p?.canBeDeletedForAllUsers ?? false) || p == null)
      (MessageAction.delete, Icons.delete_outline_rounded, 'Delete', GlowColors.coral),
  ];
  return Navigator.of(context).push(
    PageRouteBuilder<({MessageAction? action, String? reaction})>(
      opaque: false,
      // Leave focus where it is: taking it closed the keyboard, the chat
      // re-laid out, and the menu no longer matched the bubble's place.
      requestFocus: false,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (context, animation, _) => _FocusMenu(
        animation: animation,
        anchor: anchor,
        bubble: bubble,
        reactions: reactions,
        quick: quickReactions,
        readStatus: readStatus,
        reactionIcon: reactionIcon,
        items: items,
      ),
    ),
  );
}

class _FocusMenu extends StatefulWidget {
  const _FocusMenu({
    required this.animation,
    required this.anchor,
    required this.bubble,
    required this.reactions,
    required this.quick,
    required this.readStatus,
    required this.reactionIcon,
    required this.items,
  });

  final Animation<double> animation;
  final Rect? anchor;
  final Widget? bubble;
  final Future<List<String>> reactions;
  final List<String> quick;
  final Future<String?>? readStatus;
  final Widget Function(String emoji, double size)? reactionIcon;
  final List<(MessageAction, IconData, String, Color?)> items;

  @override
  State<_FocusMenu> createState() => _FocusMenuState();
}

class _FocusMenuState extends State<_FocusMenu> {
  var _allReactions = false;

  void _react(String e) => Navigator.pop(context, (action: null, reaction: e));

  Widget _emoji(String e, double size) =>
      widget.reactionIcon?.call(e, size) ?? Text(e, style: TextStyle(fontSize: size * 0.8, height: 1));

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screen = media.size;
    final anchor = widget.anchor ?? Rect.fromLTWH(16, screen.height * 0.35, screen.width - 32, 48);
    const pillH = 60.0;
    final rows = (widget.items.length / 2).ceil();
    final listH = rows * 48.0 + 52;
    final bubbleH = anchor.height.clamp(40.0, screen.height * 0.35);
    // Keep the bubble where it was when everything fits; otherwise slide the
    // whole group just enough to stay on screen.
    final top = (anchor.top - pillH).clamp(
      media.padding.top + 8,
      (screen.height - media.padding.bottom - 8 - pillH - bubbleH - 8 - listH).clamp(
        media.padding.top + 8,
        double.infinity,
      ),
    );
    final curve = CurvedAnimation(parent: widget.animation, curve: Curves.easeOutCubic);
    // Material: without it the lifted bubble's text fell back to Flutter's
    // yellow-underlined "no Material" style.
    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.pop(context),
        child: Stack(
          children: [
            // The chat softly blurred behind the menu (only while it's open).
            Positioned.fill(
              child: AnimatedBuilder(
                animation: curve,
                builder: (context, _) => BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 6 * curve.value, sigmaY: 6 * curve.value),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            Positioned(
              top: top,
              left: 12,
              right: 12,
              child: GestureDetector(
                onTap: () {},
                child: FadeTransition(
                  opacity: curve,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _reactionPill(),
                      const SizedBox(height: 8),
                      if (widget.bubble != null)
                        Align(
                          alignment: anchor.center.dx > screen.width / 2
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxHeight: bubbleH + 24, maxWidth: anchor.width + 24),
                            child: ScaleTransition(
                              scale: Tween(begin: 0.96, end: 1.0).animate(curve),
                              // Long bubbles are clipped to the space left, not overflowed.
                              child: SingleChildScrollView(
                                physics: const NeverScrollableScrollPhysics(),
                                child: IgnorePointer(child: widget.bubble),
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      _actions(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reactionPill() => FutureBuilder<List<String>>(
    future: widget.reactions,
    builder: (context, snap) {
      final available = snap.data ?? const [];
      if (snap.hasData && available.isEmpty) return const SizedBox(height: 0);
      // Your picks first (when the chat allows them), then fill to five.
      // Compared without the emoji variation selector: the chat's heart is
      // a plain ❤ while pickers give ❤️; the chat's form is shown.
      String plain(String e) => e.replaceAll('\uFE0F', '');
      final picks = [
        for (final e in widget.quick)
          if (available.isEmpty) e else ?available.where((a) => plain(a) == plain(e)).firstOrNull,
      ];
      final quick = [...picks, ...available.where((a) => !picks.contains(a))].take(5).toList();
      return Material(
        color: GlowColors.surfaceHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(color: GlowColors.violet.withValues(alpha: 0.45)),
        ),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: _allReactions
              ? Padding(
                  padding: const EdgeInsets.all(10),
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final e in available)
                        _ReactionButton(emoji: e, icon: _emoji(e, 34), onTap: _react),
                    ],
                  ),
                )
              : SizedBox(
                  height: 60,
                  child: Row(
                    key: const ValueKey('quick-reactions'),
                    children: [
                      const SizedBox(width: 6),
                      for (final e in quick)
                        Expanded(
                          child: _ReactionButton(emoji: e, icon: _emoji(e, 38), onTap: _react),
                        ),
                      IconButton(
                        tooltip: 'More reactions',
                        icon: const Icon(Icons.expand_more_rounded, color: GlowColors.textMuted),
                        onPressed: available.length > quick.length
                            ? () => setState(() => _allReactions = true)
                            : null,
                      ),
                    ],
                  ),
                ),
        ),
      );
    },
  );

  Widget _actions() => Material(
    color: GlowColors.surfaceHigh.withValues(alpha: 0.97),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(22),
      side: const BorderSide(color: GlowColors.outline),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.readStatus != null)
          FutureBuilder<String?>(
            future: widget.readStatus,
            builder: (context, snap) => snap.data == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Row(
                      children: [
                        const Icon(Icons.done_all_rounded, size: 18, color: GlowColors.cyan),
                        const SizedBox(width: 8),
                        Text(snap.data!, style: const TextStyle(color: GlowColors.textMuted, fontSize: 13)),
                      ],
                    ),
                  ),
          ),
        Padding(
          padding: const EdgeInsets.all(4),
          child: LayoutBuilder(
            builder: (context, c) => Wrap(
              children: [
                for (final (action, icon, label, color) in widget.items)
                  SizedBox(
                    width: c.maxWidth / 2,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => Navigator.pop(context, (action: action, reaction: null)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        child: Row(
                          children: [
                            Icon(icon, size: 20, color: color ?? GlowColors.text),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                label,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: color),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _ReactionButton extends StatelessWidget {
  const _ReactionButton({required this.emoji, required this.icon, required this.onTap});

  final String emoji;
  final Widget icon;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'React $emoji',
    excludeSemantics: true,
    child: InkResponse(
      radius: 26,
      onTap: () => onTap(emoji),
      child: SizedBox(height: 48, width: 48, child: Center(child: icon)),
    ),
  );
}

td.FormattedText? _plainText(td.Message m) => switch (m.content) {
  td.MessageText(:final text) => text,
  td.MessagePhoto(:final caption) ||
  td.MessageVideo(:final caption) ||
  td.MessageDocument(:final caption) => caption.text.isEmpty ? null : caption,
  td.MessageAudio(:final caption) ||
  td.MessageAnimation(:final caption) ||
  td.MessageVoiceNote(:final caption) => caption.text.isEmpty ? null : caption,
  _ => null,
};

/// The text of a message (or its caption), if any.
td.FormattedText? messageText(td.Message m) => _plainText(m);

Future<void> copyMessageText(BuildContext context, td.Message m) async {
  final text = _plainText(m);
  if (text == null) return;
  await Clipboard.setData(ClipboardData(text: text.text));
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
  }
}

/// The quote for [selected] text inside [message], or null when the
/// selection can't be found in it. Only the entity types TDLib allows in
/// quotes are kept (and must be), clipped to the quoted range. [maxLength]
/// is TDLib's default `message_reply_quote_length_max`.
td.InputTextQuote? quoteFromSelection(td.FormattedText message, String selected, {int maxLength = 1024}) {
  final trimmed = selected.trim();
  if (trimmed.isEmpty) return null;
  final start = message.text.indexOf(trimmed);
  if (start < 0) return null;
  final end = start + (trimmed.length > maxLength ? maxLength : trimmed.length);
  final entities = <td.TextEntity>[
    for (final e in message.entities)
      if (e.type
          case td.TextEntityTypeBold() ||
              td.TextEntityTypeItalic() ||
              td.TextEntityTypeUnderline() ||
              td.TextEntityTypeStrikethrough() ||
              td.TextEntityTypeSpoiler() ||
              td.TextEntityTypeCustomEmoji()
          when e.offset < end && e.offset + e.length > start)
        td.TextEntity(
          offset: (e.offset < start ? start : e.offset) - start,
          length:
              ((e.offset + e.length > end ? end : e.offset + e.length) -
              (e.offset < start ? start : e.offset)),
          type: e.type,
        ),
  ];
  return td.InputTextQuote(
    text: td.FormattedText(text: message.text.substring(start, end), entities: entities),
    richTexts: const [],
    position: start,
  );
}

/// Free text selection inside one message (user request). With
/// [canQuote], a "Quote" button returns the selected passage to reply with.
Future<td.InputTextQuote?> showSelectText(BuildContext context, td.Message m, {bool canQuote = false}) {
  final text = _plainText(m);
  if (text == null) return Future.value();
  var selected = '';
  return showModalBottomSheet<td.InputTextQuote>(
    context: context,
    backgroundColor: GlowColors.surfaceHigh,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: StatefulBuilder(
          builder: (context, setState) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  child: SelectionArea(
                    onSelectionChanged: canQuote
                        ? (c) {
                            final next = c?.plainText ?? '';
                            if (next.trim().isEmpty != selected.trim().isEmpty) {
                              setState(() => selected = next);
                            } else {
                              selected = next;
                            }
                          }
                        : null,
                    child: FormattedTextView(text, style: const TextStyle(fontSize: 17, height: 1.45)),
                  ),
                ),
              ),
              if (canQuote) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: selected.trim().isEmpty
                        ? null
                        : () {
                            final quote = quoteFromSelection(text, selected);
                            if (quote == null) {
                              ScaffoldMessenger.of(
                                context,
                              ).showSnackBar(const SnackBar(content: Text("Couldn't quote that selection")));
                              return;
                            }
                            Navigator.pop(context, quote);
                          },
                    icon: const Icon(Icons.format_quote_rounded),
                    label: const Text('Quote'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
