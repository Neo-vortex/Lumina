import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../../core/telegram/display.dart';
import '../../../../core/telegram/telegram_cache.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../../../core/theme/motion.dart';
import '../../data/messages_repository.dart';
import 'formatting_controller.dart';
import 'link_preview_card.dart';
import '../../../../core/widgets/send_options_sheet.dart';
import 'send_orb.dart';

/// Message composer: reply/edit strip, attach button, multiline field and
/// the send orb. Voice recording and dictation are delegated through
/// callbacks so their features own the details.
class Composer extends StatefulWidget {
  const Composer({
    super.key,
    required this.controller,
    required this.replyTo,
    this.replyQuote,
    required this.editing,
    required this.onSend,
    required this.onCancelMode,
    required this.onChanged,
    this.onAttach,
    this.onVoice,
    this.onDictate,
    this.recordingOverlay,
    this.orbMode,
    this.loadPreview,
    this.previewsOnSend = true,
  });

  final TextEditingController controller;
  final td.Message? replyTo;

  /// The quoted passage of [replyTo], shown instead of its preview.
  final td.InputTextQuote? replyQuote;
  final td.Message? editing;

  /// [preview] says how to attach (or not) the link preview.
  final Future<void> Function(String text, SendOptions options, td.LinkPreviewOptions? preview) onSend;
  final VoidCallback onCancelMode;
  final ValueChanged<String> onChanged;
  final VoidCallback? onAttach;
  final VoidCallback? onVoice;
  final VoidCallback? onDictate;

  /// Replaces the text row while recording (waveform, timer).
  final Widget? recordingOverlay;

  /// Forces the orb mode (e.g. stop while recording, busy while dictating).
  final OrbMode? orbMode;

  /// Builds the preview Telegram will attach for a link in the text.
  final Future<td.LinkPreview?> Function(td.FormattedText text)? loadPreview;

  /// Settings → "Link previews when sending".
  final bool previewsOnSend;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  var _sending = false;

  // Link preview while composing.
  static final _linkish = RegExp(r'(https?://|www\.|t\.me/)\S+', caseSensitive: false);
  Timer? _previewTimer;
  String? _previewFor;
  td.LinkPreview? _preview;
  String? _dismissedUrl;
  bool? _large;
  var _above = false;

  static const _fullCharge = 160;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onText);
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    widget.controller.removeListener(_onText);
    super.dispose();
  }

  void _onText() {
    setState(() {});
    _schedulePreview();
  }

  void _schedulePreview() {
    final load = widget.loadPreview;
    final text = widget.controller.text;
    final link = _linkish.firstMatch(text)?.group(0);
    if (load == null || !widget.previewsOnSend || link == null) {
      _previewTimer?.cancel();
      if (_preview != null || _previewFor != null) {
        setState(() {
          _preview = null;
          _previewFor = null;
        });
      }
      return;
    }
    if (link == _previewFor) return;
    _previewTimer?.cancel();
    _previewTimer = Timer(const Duration(milliseconds: 600), () async {
      _previewFor = link;
      final c = widget.controller;
      final p = await load(
        c is FormattingController ? c.formatted : td.FormattedText(text: text, entities: const []),
      );
      if (!mounted || _previewFor != link) return;
      setState(() {
        _preview = p;
        _large = null;
      });
    });
  }

  /// What to tell TDLib about the preview for the text being sent.
  td.LinkPreviewOptions? _previewOptions() {
    final hasLink = _linkish.hasMatch(widget.controller.text);
    if (!hasLink) return null;
    final p = _preview;
    if (!widget.previewsOnSend || p == null || p.url == _dismissedUrl) {
      return const td.LinkPreviewOptions(
        isDisabled: true,
        url: '',
        forceSmallMedia: false,
        forceLargeMedia: false,
        showAboveText: false,
      );
    }
    return td.LinkPreviewOptions(
      isDisabled: false,
      url: p.url,
      forceSmallMedia: _large == false,
      forceLargeMedia: _large == true,
      showAboveText: _above,
    );
  }

  Future<void> _send([SendOptions options = const SendOptions()]) async {
    final text = widget.controller.text;
    if (text.trim().isEmpty || _sending) return;
    setState(() => _sending = true);
    await widget.onSend(text, options, _previewOptions());
    if (mounted) {
      setState(() {
        _sending = false;
        _preview = null;
        _previewFor = null;
        _dismissedUrl = null;
        _above = false;
      });
    }
  }

  Future<void> _sendOptions() async {
    final options = await showSendOptionsSheet(context);
    if (options != null && mounted) await _send(options);
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.controller.text;
    final hasText = text.trim().isNotEmpty;
    final mode = widget.orbMode ?? (_sending ? OrbMode.busy : (hasText ? OrbMode.send : OrbMode.mic));
    final contextMessage = widget.editing ?? widget.replyTo;

    return Material(
      color: GlowColors.background,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSize(
              duration: Motion.micro,
              curve: Motion.enter,
              child: contextMessage == null
                  ? const SizedBox(width: double.infinity)
                  : _ContextStrip(
                      message: contextMessage,
                      editing: widget.editing != null,
                      quote: widget.editing == null ? widget.replyQuote : null,
                      onCancel: widget.onCancelMode,
                    ),
            ),
            AnimatedSize(
              duration: Motion.micro,
              curve: Motion.enter,
              child: _preview == null || _preview!.url == _dismissedUrl || widget.recordingOverlay != null
                  ? const SizedBox(width: double.infinity)
                  : _PreviewStrip(
                      preview: _preview!,
                      large: _large ?? _preview!.showLargeMedia,
                      above: _above,
                      onToggleSize: _preview!.hasLargeMedia
                          ? () => setState(() => _large = !(_large ?? _preview!.showLargeMedia))
                          : null,
                      onToggleAbove: () => setState(() => _above = !_above),
                      onRemove: () => setState(() => _dismissedUrl = _preview!.url),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (widget.recordingOverlay == null && widget.onAttach != null)
                    IconButton(
                      tooltip: 'Attach',
                      onPressed: widget.onAttach,
                      icon: const Icon(Icons.add_circle_outline_rounded, color: GlowColors.cyan),
                    ),
                  Expanded(
                    child:
                        widget.recordingOverlay ??
                        Container(
                          constraints: const BoxConstraints(minHeight: 48),
                          decoration: BoxDecoration(
                            color: GlowColors.surface,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: GlowColors.outlineStrong),
                          ),
                          child: TextField(
                            controller: widget.controller,
                            onChanged: widget.onChanged,
                            minLines: 1,
                            maxLines: 6,
                            textCapitalization: TextCapitalization.sentences,
                            keyboardType: TextInputType.multiline,
                            contextMenuBuilder: (context, state) {
                              final c = widget.controller;
                              return AdaptiveTextSelectionToolbar.buttonItems(
                                anchors: state.contextMenuAnchors,
                                buttonItems: [
                                  ...state.contextMenuButtonItems,
                                  if (c is FormattingController)
                                    ...formattingMenuItems(context, c, hideToolbar: state.hideToolbar),
                                ],
                              );
                            },
                            decoration: InputDecoration(
                              hintText: widget.editing != null ? 'Edit message' : 'Message',
                              hintStyle: const TextStyle(color: GlowColors.textMuted),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                            ),
                          ),
                        ),
                  ),
                  const SizedBox(width: 8),
                  SendOrb(
                    mode: mode,
                    charge: hasText ? (text.length / _fullCharge).clamp(0.08, 1.0) : 0,
                    // A mode forced by an extension (recording) routes taps to it.
                    onTap: widget.orbMode != null
                        ? (widget.onVoice ?? () {})
                        : switch (mode) {
                            OrbMode.send => _send,
                            OrbMode.mic => widget.onVoice ?? () {},
                            OrbMode.stop => widget.onVoice ?? () {},
                            OrbMode.busy => () {},
                          },
                    onLongPress: hasText && widget.editing == null
                        ? _sendOptions
                        : (!hasText ? widget.onDictate : null),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewStrip extends StatelessWidget {
  const _PreviewStrip({
    required this.preview,
    required this.large,
    required this.above,
    required this.onToggleSize,
    required this.onToggleAbove,
    required this.onRemove,
  });

  final td.LinkPreview preview;
  final bool large;
  final bool above;
  final VoidCallback? onToggleSize;
  final VoidCallback onToggleAbove;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 6, 4, 0),
    child: Row(
      children: [
        Expanded(
          child: LinkPreviewCard(
            preview: preview,
            textColor: GlowColors.text,
            accent: GlowColors.cyan,
            largeMedia: large,
            compact: true,
          ),
        ),
        if (onToggleSize != null)
          IconButton(
            tooltip: large ? 'Smaller picture' : 'Larger picture',
            onPressed: onToggleSize,
            icon: Icon(large ? Icons.photo_size_select_small_rounded : Icons.photo_size_select_large_rounded),
          ),
        IconButton(
          tooltip: above ? 'Preview below text' : 'Preview above text',
          onPressed: onToggleAbove,
          icon: Icon(above ? Icons.vertical_align_bottom_rounded : Icons.vertical_align_top_rounded),
        ),
        IconButton(
          tooltip: 'Send without preview',
          onPressed: onRemove,
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    ),
  );
}

class _ContextStrip extends StatelessWidget {
  const _ContextStrip({required this.message, required this.editing, required this.onCancel, this.quote});

  final td.Message message;
  final bool editing;
  final td.InputTextQuote? quote;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final cache = context.read<TelegramCache>();
    final accent = editing ? GlowColors.amber : GlowColors.cyan;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
      child: Row(
        children: [
          Icon(
            editing
                ? Icons.edit_rounded
                : quote != null
                ? Icons.format_quote_rounded
                : Icons.reply_rounded,
            color: accent,
            size: 20,
          ),
          const SizedBox(width: 10),
          Container(width: 2, height: 32, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  editing
                      ? 'Editing'
                      : '${quote != null ? 'Quote' : 'Reply to'} ${message.isOutgoing ? 'yourself' : Display.senderName(cache, message.senderId)}',
                  style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w600),
                ),
                Text(
                  quote != null ? '“${quote!.text.text}”' : Display.preview(cache, message),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: GlowColors.textMuted),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: editing ? 'Cancel editing' : 'Cancel reply',
            onPressed: onCancel,
            icon: const Icon(Icons.close_rounded, color: GlowColors.textMuted),
          ),
        ],
      ),
    );
  }
}
