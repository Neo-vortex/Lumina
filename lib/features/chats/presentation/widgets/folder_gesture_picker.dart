import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../../core/telegram/display.dart';
import '../../../../core/telegram/telegram_cache.dart';
import '../../../../core/telegram/widgets/chat_avatar.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../../../core/theme/motion.dart';
import '../../domain/lens_entry.dart';
import 'folder_picker_layout.dart';
import 'folder_preview.dart';

/// Hold-and-swipe folder switcher: an overlay driven by the long-press
/// pointer that opened it ([move], [end], [cancel]). Folder names line the
/// thumb's edge and lean toward the finger; the highlighted folder's chats
/// preview on the other side; releasing switches.
class FolderGesturePicker {
  FolderGesturePicker._(this._finger);

  late final OverlayEntry _entry;
  final _view = GlobalKey<_PickerViewState>();

  /// Owned here, not by the view: moves that come before the overlay's
  /// first frame still count.
  final ValueNotifier<Offset> _finger;
  var _open = true;

  bool get isOpen => _open;

  static FolderGesturePicker open(
    BuildContext context, {
    required List<LensEntry> entries,
    required int current,
    required Color Function(LensEntry) colorOf,
    required Offset start,
    required ValueChanged<int> onPicked,
  }) {
    final cache = context.read<TelegramCache>();
    final picker = FolderGesturePicker._(ValueNotifier(start));
    picker._entry = OverlayEntry(
      builder: (_) => _PickerView(
        key: picker._view,
        finger: picker._finger,
        entries: entries,
        current: current,
        colorOf: colorOf,
        start: start,
        cache: cache,
        onDone: (index) {
          picker._close();
          if (index != null && index != current) onPicked(index);
        },
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(picker._entry);
    HapticFeedback.lightImpact();
    return picker;
  }

  void move(Offset globalPosition) {
    if (_open) _finger.value = globalPosition;
  }

  void end() => _view.currentState == null ? _close() : _view.currentState!.finish(cancelled: false);

  void cancel() => _view.currentState == null ? _close() : _view.currentState!.finish(cancelled: true);

  void _close() {
    if (!_open) return;
    _open = false;
    _entry.remove();
    _finger.dispose();
  }
}

class _PickerView extends StatefulWidget {
  const _PickerView({
    super.key,
    required this.finger,
    required this.entries,
    required this.current,
    required this.colorOf,
    required this.start,
    required this.cache,
    required this.onDone,
  });

  final ValueNotifier<Offset> finger;
  final List<LensEntry> entries;
  final int current;
  final Color Function(LensEntry) colorOf;
  final Offset start;
  final TelegramCache cache;
  final ValueChanged<int?> onDone;

  @override
  State<_PickerView> createState() => _PickerViewState();
}

class _PickerViewState extends State<_PickerView> with TickerProviderStateMixin {
  ValueNotifier<Offset> get _finger => widget.finger;

  /// Bumped when auto-scroll moves the list under a resting finger.
  final _scrolled = ValueNotifier<double>(0);
  late final AnimationController _appear = AnimationController(vsync: this, duration: Motion.standard)
    ..forward();
  late final Ticker _ticker = createTicker(_tick);
  FolderPickerLayout? _layout;
  late int? _highlight = widget.current;
  final _previews = <int, FolderPreview>{};
  Duration _last = Duration.zero;
  var _done = false;

  FolderPickerLayout get layout => _layout!;
  bool get _cancelled => layout.isCancel(_finger.value);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final size = MediaQuery.sizeOf(context);
    final fresh = FolderPickerLayout(
      screen: size,
      padding: MediaQuery.paddingOf(context),
      count: widget.entries.length,
      rightEdge: _layout?.rightEdge ?? FolderPickerLayout.rightEdgeFor(widget.start.dx, size.width),
      scroll: _layout?.scroll ?? 0,
    );
    if (_layout == null) {
      // Start with the current folder in view on long lists.
      final c = fresh.centerOf(widget.current);
      _layout = fresh.withScroll(c - size.height / 2);
      _ticker.start();
      _finger.addListener(_rehighlight);
      _rehighlight();
    } else {
      _layout = fresh;
    }
  }

  @override
  void dispose() {
    _finger.removeListener(_rehighlight);
    _ticker.dispose();
    _appear.dispose();
    _scrolled.dispose();
    super.dispose();
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    final v = layout.scrollVelocity(_finger.value.dy);
    if (v == 0 || dt <= 0) return;
    final next = layout.withScroll(layout.scroll + v * dt);
    if (next.scroll == layout.scroll) return;
    _layout = next;
    _scrolled.value = next.scroll;
    _rehighlight();
  }

  void _rehighlight() {
    if (_done) return;
    final i = _cancelled ? null : layout.indexAt(_finger.value.dy);
    if (i == _highlight) return;
    _highlight = i;
    if (i != null) HapticFeedback.selectionClick();
    setState(() {});
  }

  void finish({required bool cancelled}) {
    if (_done) return;
    _done = true;
    _ticker.stop();
    final pick = cancelled || _cancelled ? null : _highlight;
    if (pick != null && pick != widget.current) HapticFeedback.mediumImpact();
    widget.onDone(pick);
  }

  FolderPreview _preview(int i) => _previews[i] ??= FolderPreview.of(widget.cache, widget.entries[i].list);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final ambient = Motion.ambientEnabled(context);
    final cancelled = _cancelled;
    return Material(
      type: MaterialType.transparency,
      child: Semantics(
        label: 'Folder picker. Slide to a folder and release',
        liveRegion: true,
        child: FadeTransition(
          opacity: CurvedAnimation(parent: _appear, curve: Motion.enter),
          child: Stack(
            children: [
              const Positioned.fill(child: RepaintBoundary(child: _Backdrop())),
              Positioned.fill(
                child: AnimatedOpacity(
                  duration: Motion.micro,
                  opacity: cancelled ? 0.4 : 1,
                  child: ListenableBuilder(
                    listenable: Listenable.merge([_finger, _scrolled]),
                    builder: (context, _) => Stack(
                      children: [
                        for (var i = 0; i < widget.entries.length; i++)
                          _name(i, _finger.value, ambient, size),
                      ],
                    ),
                  ),
                ),
              ),
              if (!cancelled && _highlight != null) _previewCard(size),
              if (cancelled)
                const Center(
                  child: Text(
                    'Release to cancel',
                    style: TextStyle(color: GlowColors.textMuted, fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _name(int i, Offset finger, bool ambient, Size size) {
    final l = layout;
    final entry = widget.entries[i];
    final color = widget.colorOf(entry);
    final highlighted = i == _highlight && !_cancelled;
    final f = _cancelled
        ? 0.0
        : ambient
        ? l.focus(i, finger)
        : (highlighted ? 1.0 : 0.0);
    final right = l.rightEdge;
    final lean = f * 22 * (right ? -1 : 1);
    final unread = entry.unread.chats;
    final label = Row(
      mainAxisSize: MainAxisSize.min,
      textDirection: right ? TextDirection.rtl : TextDirection.ltr,
      children: [
        Flexible(
          child: AnimatedContainer(
            duration: Motion.micro,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: highlighted ? color.withValues(alpha: 0.22) : Colors.transparent,
              border: Border.all(color: highlighted ? color.withValues(alpha: 0.8) : Colors.transparent),
              boxShadow: highlighted ? glow(color, intensity: 0.8) : null,
            ),
            child: Text(
              entry.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Color.lerp(GlowColors.textMuted, GlowColors.text, f.clamp(0, 1)),
                fontSize: 17,
                fontWeight: highlighted ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
        if (unread > 0) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(10),
              boxShadow: glow(color, intensity: 0.3 + 0.5 * f),
            ),
            child: Text(
              '$unread',
              style: const TextStyle(color: GlowColors.onAccent, fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ],
    );
    final maxWidth = size.width * 0.42;
    return Positioned(
      top: l.centerOf(i) - FolderPickerLayout.slot / 2,
      height: FolderPickerLayout.slot,
      left: right ? null : 12,
      right: right ? 12 : null,
      width: maxWidth,
      child: Align(
        alignment: right ? Alignment.centerRight : Alignment.centerLeft,
        child: Transform.translate(
          offset: Offset(lean, 0),
          child: Transform.scale(
            scale: 1 + 0.35 * f,
            alignment: right ? Alignment.centerRight : Alignment.centerLeft,
            child: label,
          ),
        ),
      ),
    );
  }

  Widget _previewCard(Size size) {
    final i = _highlight!;
    final p = _preview(i);
    final entry = widget.entries[i];
    final color = widget.colorOf(entry);
    final width = size.width * 0.58;
    const height = 76.0 + 6 * 52;
    final padding = MediaQuery.paddingOf(context);
    final top = (layout.centerOf(i) - height / 2).clamp(
      padding.top + 8,
      size.height - padding.bottom - height - 8,
    );
    return AnimatedPositioned(
      duration: Motion.micro,
      curve: Motion.enter,
      top: top.toDouble(),
      left: layout.rightEdge ? 16 : null,
      right: layout.rightEdge ? null : 16,
      width: width,
      child: IgnorePointer(
        child: AnimatedSwitcher(
          duration: Motion.standard,
          child: Container(
            key: ValueKey(i),
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            decoration: BoxDecoration(
              color: GlowColors.surface.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: color.withValues(alpha: 0.45)),
              boxShadow: glow(color, intensity: 0.25),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.headline,
                  style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13),
                ),
                const SizedBox(height: 8),
                for (final c in p.chats) _PreviewRow(chat: c, cache: widget.cache, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The chat list blurred once, darker and blurrier toward the edges.
class _Backdrop extends StatelessWidget {
  const _Backdrop();

  @override
  Widget build(BuildContext context) => ClipRect(
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            radius: 0.9,
            colors: [
              GlowColors.background.withValues(alpha: 0.35),
              GlowColors.backgroundDeep.withValues(alpha: 0.92),
            ],
          ),
        ),
      ),
    ),
  );
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.chat, required this.cache, required this.color});

  final td.Chat chat;
  final TelegramCache cache;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = chat;
    final unread = c.unreadCount;
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          ChatAvatar(id: c.id, title: c.title, photo: c.photo, size: 36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: unread > 0 ? FontWeight.w700 : FontWeight.w500, fontSize: 14),
                ),
                Text(
                  Display.preview(cache, c.lastMessage),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: GlowColors.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          if (unread > 0)
            Container(
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
              child: Text(
                '$unread',
                style: const TextStyle(color: GlowColors.onAccent, fontSize: 11, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }
}
