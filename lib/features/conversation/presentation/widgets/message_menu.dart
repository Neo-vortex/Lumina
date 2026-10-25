import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:handy_tdlib_next/api.dart' as td;

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
  deleteForMe,
  deleteForAll,
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

/// Long-press menu: quick reactions on top, then the actions TDLib says the
/// message allows. Returns the chosen action, or the emoji as a reaction.
Future<({MessageAction? action, String? reaction})?> showMessageMenu(
  BuildContext context, {
  required td.Message message,
  required td.MessageProperties? properties,
  required Future<List<String>> reactions,
  required bool protectedContent,
  List<ExtraMenuEntry> extras = const [],
}) {
  Feedback.forLongPress(context);
  final p = properties;
  final hasText = _plainText(message) != null;
  final canSave = !protectedContent && (p?.canBeSaved ?? true);
  return showModalBottomSheet<({MessageAction? action, String? reaction})>(
    context: context,
    backgroundColor: GlowColors.surfaceHigh,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      Widget item(MessageAction action, IconData icon, String label, {Color? color}) => ListTile(
        leading: Icon(icon, color: color),
        title: Text(label, style: TextStyle(color: color)),
        onTap: () => Navigator.pop(context, (action: action, reaction: null)),
      );
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
          child: ListView(
            shrinkWrap: true,
            children: [
              FutureBuilder<List<String>>(
                future: reactions,
                builder: (context, snap) {
                  final list = snap.data ?? const [];
                  if (list.isEmpty) return const SizedBox.shrink();
                  return SizedBox(
                    height: 56,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: [
                        for (final emoji in list)
                          Semantics(
                            button: true,
                            label: 'React $emoji',
                            excludeSemantics: true,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(24),
                              onTap: () => Navigator.pop(context, (action: null, reaction: emoji)),
                              child: SizedBox(
                                width: 48,
                                child: Center(child: Text(emoji, style: const TextStyle(fontSize: 26))),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
              if (p?.canBeReplied ?? true) item(MessageAction.reply, Icons.reply_rounded, 'Reply'),
              if (hasText && canSave) item(MessageAction.copy, Icons.copy_rounded, 'Copy text'),
              if (hasText && canSave)
                item(MessageAction.selectText, Icons.text_fields_rounded, 'Select text'),
              if (p?.canBeEdited ?? false) item(MessageAction.edit, Icons.edit_rounded, 'Edit'),
              if ((p?.canBePinned ?? false) && !message.isPinned)
                item(MessageAction.pin, Icons.push_pin_rounded, 'Pin'),
              if ((p?.canBePinned ?? false) && message.isPinned)
                item(MessageAction.unpin, Icons.push_pin_outlined, 'Unpin'),
              if (p?.canBeForwarded ?? false) item(MessageAction.forward, Icons.forward_rounded, 'Forward'),
              if ((p?.canBeForwarded ?? false) && canSave)
                item(MessageAction.forwardHidden, Icons.visibility_off_rounded, 'Forward without sender'),
              for (final e in extras) item(e.action, e.icon, e.label, color: GlowColors.cyan),
              item(MessageAction.select, Icons.check_circle_outline_rounded, 'Select'),
              if (p?.canGetLink ?? false) item(MessageAction.copyLink, Icons.link_rounded, 'Copy link'),
              if (p?.canBeDeletedOnlyForSelf ?? false)
                item(
                  MessageAction.deleteForMe,
                  Icons.delete_outline_rounded,
                  'Delete for me',
                  color: GlowColors.coral,
                ),
              if (p?.canBeDeletedForAllUsers ?? false)
                item(
                  MessageAction.deleteForAll,
                  Icons.delete_forever_rounded,
                  'Delete for everyone',
                  color: GlowColors.coral,
                ),
            ],
          ),
        ),
      );
    },
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
