import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../../core/telegram/display.dart';
import '../../../../core/telegram/telegram_cache.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../../../core/telegram/message_effects.dart';
import '../../../../core/widgets/lumina_glass.dart';
import '../../../../core/theme/motion.dart';
import '../../data/messages_repository.dart';
import 'composer_selection_menu.dart';
import 'formatting_controller.dart';
import 'link_preview_card.dart';
import '../../../../core/widgets/send_options_sheet.dart';
import 'send_orb.dart';
import 'voice_hold_orb.dart';

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
    this.onVoiceStart,
    this.onVoiceFinish,
    this.voiceRecording = false,
    this.onDictate,
    this.onWritingTools,
    this.mediaPanel,
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

  /// Hold-to-record voice messages (null: the mic only taps [onVoice]).
  final VoidCallback? onVoiceStart;
  final void Function({required bool send})? onVoiceFinish;

  /// A voice message is being recorded.
  final bool voiceRecording;
  final VoidCallback? onDictate;

  /// On-device writing help (rewrite, grammar, tone); shown once there's text.
  final VoidCallback? onWritingTools;

  /// The emoji/sticker/GIF panel, built at keyboard height in place of the
  /// keyboard; emoji go to the draft, stickers and GIFs send.
  final Widget Function(double height, ValueChanged<String> onEmoji, VoidCallback onSent)? mediaPanel;

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
  final _focus = FocusNode();
  var _panel = false;
  var _keyboardHeight = 300.0;

  void _togglePanel() {
    if (_panel) {
      setState(() => _panel = false);
      _focus.requestFocus();
    } else {
      setState(() => _panel = true);
      _focus.unfocus();
    }
  }

  void _insertEmoji(String e) {
    final c = widget.controller;
    final sel = c.selection.isValid ? c.selection : TextSelection.collapsed(offset: c.text.length);
    final text = c.text.replaceRange(sel.start, sel.end, e);
    c.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: sel.start + e.length),
    );
  }

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

  // Starting a reply (swipe or menu) or an edit opens the keyboard on the
  // message box, closing the emoji/sticker panel if it was up.
  @override
  void didUpdateWidget(Composer old) {
    super.didUpdateWidget(old);
    final replyStarted = widget.replyTo != null && widget.replyTo?.id != old.replyTo?.id;
    final editStarted = widget.editing != null && widget.editing?.id != old.editing?.id;
    if (replyStarted || editStarted) {
      if (_panel) setState(() => _panel = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    _focus.dispose();
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
      final p = await load(c is FormattingController ? c.formatted : td.FormattedText(text: text, entities: const []));
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
    final options = await showSendOptionsSheet(context, effects: () => MessageEffects.available(context));
    if (options != null && mounted) await _send(options);
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.controller.text;
    final hasText = text.trim().isNotEmpty;
    final mode = widget.orbMode ?? (_sending ? OrbMode.busy : (hasText ? OrbMode.send : OrbMode.mic));
    final contextMessage = widget.editing ?? widget.replyTo;
    // Remember the keyboard's height so the panel takes exactly its place.
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    if (inset > 120) _keyboardHeight = inset;

    // Back peels one layer at a time: the panel, then the reply or edit,
    // and only then leaves the chat.
    return PopScope(
      canPop: !_panel && contextMessage == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_panel) {
          setState(() => _panel = false);
        } else {
          widget.onCancelMode();
        }
      },
      // No band: glass pills float over the chat background.
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GlassGroup(
                shareBackdrop: true,
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
                          if (widget.recordingOverlay == null && widget.onAttach != null) ...[
                            GlassPill(
                              round: true,
                              child: SizedBox.square(
                                dimension: 48,
                                child: IconButton(
                                  tooltip: 'Attach',
                                  onPressed: widget.onAttach,
                                  icon: const Icon(Icons.add_rounded, color: GlowColors.text),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child:
                                widget.recordingOverlay ??
                                // Glass at rest; typing only firms up a quiet violet edge.
                                GlassPill(
                                  child: ListenableBuilder(
                                    listenable: _focus,
                                    builder: (context, child) => AnimatedContainer(
                                      duration: const Duration(milliseconds: 160),
                                      curve: Curves.easeOut,
                                      constraints: const BoxConstraints(minHeight: 48),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(24),
                                        border: Border.all(
                                          color: _focus.hasFocus
                                              ? GlowColors.violet.withValues(alpha: 0.38)
                                              : Colors.transparent,
                                        ),
                                      ),
                                      child: child,
                                    ),
                                    child: TextField(
                                      controller: widget.controller,
                                      focusNode: _focus,
                                      onTap: () {
                                        if (_panel) setState(() => _panel = false);
                                      },
                                      onChanged: widget.onChanged,
                                      minLines: 1,
                                      maxLines: 6,
                                      textCapitalization: TextCapitalization.sentences,
                                      keyboardType: TextInputType.multiline,
                                      contextMenuBuilder: (context, state) =>
                                          ComposerSelectionMenu(state: state, controller: widget.controller),
                                      decoration: InputDecoration(
                                        hintText: widget.editing != null ? 'Edit message' : 'Message',
                                        hintStyle: const TextStyle(color: GlowColors.textMuted),
                                        border: InputBorder.none,
                                        prefixIcon: widget.mediaPanel == null
                                            ? null
                                            : IconButton(
                                                tooltip: _panel ? 'Keyboard' : 'Emoji, stickers and GIFs',
                                                onPressed: _togglePanel,
                                                icon: Icon(
                                                  _panel ? Icons.keyboard_rounded : Icons.emoji_emotions_outlined,
                                                  color: GlowColors.textMuted,
                                                ),
                                              ),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                                        suffixIcon: !hasText && widget.onDictate != null && widget.onVoiceStart != null
                                            ? IconButton(
                                                tooltip: 'Dictate (speech to text)',
                                                onPressed: widget.onDictate,
                                                icon: const Icon(
                                                  Icons.keyboard_voice_outlined,
                                                  color: GlowColors.textMuted,
                                                  size: 22,
                                                ),
                                              )
                                            : hasText && widget.onWritingTools != null
                                            ? IconButton(
                                                tooltip: 'Writing help',
                                                onPressed: widget.onWritingTools,
                                                icon: const Icon(
                                                  Icons.auto_awesome_rounded,
                                                  color: GlowColors.magenta,
                                                  size: 20,
                                                ),
                                              )
                                            : null,
                                      ),
                                    ),
                                  ),
                                ),
                          ),
                          const SizedBox(width: 8),
                          if (widget.onVoiceStart != null &&
                              widget.onVoiceFinish != null &&
                              (widget.voiceRecording || (!hasText && widget.editing == null && widget.orbMode == null)))
                            VoiceHoldOrb(
                              recording: widget.voiceRecording,
                              onStart: widget.onVoiceStart!,
                              onFinish: widget.onVoiceFinish!,
                            )
                          else
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
              if (_panel && widget.mediaPanel != null)
                widget.mediaPanel!(_keyboardHeight, _insertEmoji, () => setState(() => _panel = false)),
            ],
          ),
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
        IconButton(tooltip: 'Send without preview', onPressed: onRemove, icon: const Icon(Icons.close_rounded)),
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
    // Reply: violet; editing: amber. A calm glass card: the accent is only
    // the thin bar and the label, no fill or glow.
    final accent = editing ? GlowColors.amber : GlowColors.violet;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      child: GlassPill(
        radius: 18,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 34,
                decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 10),
              Icon(
                editing
                    ? Icons.edit_rounded
                    : quote != null
                    ? Icons.format_quote_rounded
                    : Icons.reply_rounded,
                color: accent,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      editing
                          ? 'Editing'
                          : '${quote != null ? 'Quote' : 'Reply to'} ${message.isOutgoing ? 'yourself' : Display.senderName(cache, message.senderId)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Color.lerp(accent, Colors.white, 0.25),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      quote != null ? '“${quote!.text.text}”' : Display.preview(cache, message),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: GlowColors.text),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: editing ? 'Cancel editing' : 'Cancel reply',
                onPressed: onCancel,
                visualDensity: VisualDensity.compact,
                icon: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(shape: BoxShape.circle, color: GlowColors.text.withValues(alpha: 0.08)),
                  child: const Icon(Icons.close_rounded, size: 16, color: GlowColors.textMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
