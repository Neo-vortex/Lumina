import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:handy_tdlib_next/api.dart' as td;
import 'package:intl/intl.dart' show DateFormat, NumberFormat;

import '../../../../core/media/audio_playback.dart';
import '../../../../core/media/tdlib_stream_server.dart';
import '../../../../core/tdlib/td_client.dart';
import '../../../../core/telegram/display.dart';
import '../../../../core/telegram/file_store.dart';
import '../../../../core/telegram/link_opener.dart';
import '../../../../core/telegram/widgets/td_file_image.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../../media/presentation/widgets/video_player_view.dart';

/// Telegram's Instant View: an article rendered natively from TDLib page
/// blocks (no browser, no WebView). "Open in browser" uses [openLink].
class InstantViewScreen extends StatefulWidget {
  const InstantViewScreen({super.key, required this.url, this.title = ''});

  final String url;
  final String title;

  static Route<void> route(String url, {String title = ''}) => MaterialPageRoute(
    builder: (_) => InstantViewScreen(url: url, title: title),
  );

  @override
  State<InstantViewScreen> createState() => _InstantViewScreenState();
}

class _InstantViewScreenState extends State<InstantViewScreen> {
  td.WebPageInstantView? _page;
  String? _error;
  final _anchors = <String, GlobalKey>{};
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _load(full: false);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({required bool full}) async {
    try {
      final p = await context.read<TdClient>().invoke<td.WebPageInstantView>(
        td.GetWebPageInstantView(url: widget.url, forceFull: full),
      );
      if (!mounted) return;
      setState(() => _page = p);
      // TDLib may return a partial page first; fetch the rest.
      if (!p.isFull && !full) {
        _load(full: true);
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'This article can’t be shown here.');
    }
  }

  void _jump(String anchor) {
    final ctx = _anchors[anchor]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 350), alignment: 0.1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title.isEmpty ? 'Instant View' : widget.title),
        actions: [
          IconButton(
            tooltip: 'Open in browser',
            onPressed: () => openLink(context, widget.url),
            icon: const Icon(Icons.open_in_browser_rounded),
          ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!, style: const TextStyle(color: GlowColors.textMuted)),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => openLink(context, widget.url),
                    child: const Text('Open in browser'),
                  ),
                ],
              ),
            )
          : page == null
          ? const Center(child: CircularProgressIndicator(color: GlowColors.cyan))
          : Directionality(
              textDirection: page.isRtl ? TextDirection.rtl : TextDirection.ltr,
              child: SelectionArea(
                child: ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 48),
                  children: [
                    for (final b in page.pageBlocks) _Block(b, anchors: _anchors, onAnchor: _jump),
                    if (page.viewCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: Text(
                          '${NumberFormat.compact().format(page.viewCount)} views',
                          style: const TextStyle(color: GlowColors.textMuted, fontSize: 13),
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// One page block (recursively for lists, details, collages, posts…).
class _Block extends StatelessWidget {
  const _Block(this.block, {required this.anchors, required this.onAnchor});

  final td.PageBlock block;
  final Map<String, GlobalKey> anchors;
  final void Function(String) onAnchor;

  Widget _rich(td.RichText t, TextStyle style) => _RichTextView(t, style: style, onAnchor: onAnchor);

  Widget _children(List<td.PageBlock> blocks) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [for (final b in blocks) _Block(b, anchors: anchors, onAnchor: onAnchor)],
  );

  Widget _caption(td.PageBlockCaption c) {
    if (_isEmpty(c.text) && _isEmpty(c.credit)) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_isEmpty(c.text)) _rich(c.text, const TextStyle(color: GlowColors.textMuted, fontSize: 13.5)),
          if (!_isEmpty(c.credit))
            _rich(
              c.credit,
              const TextStyle(color: GlowColors.textMuted, fontSize: 12, fontStyle: FontStyle.italic),
            ),
        ],
      ),
    );
  }

  static bool _isEmpty(td.RichText t) => switch (t) {
    td.RichTextPlain(:final text) => text.isEmpty,
    td.RichTexts(:final texts) => texts.every(_isEmpty),
    _ => false,
  };

  static const _body = TextStyle(fontSize: 17, height: 1.55, color: GlowColors.text);

  @override
  Widget build(BuildContext context) {
    Widget pad(Widget w, {double v = 8}) => Padding(
      padding: EdgeInsets.symmetric(vertical: v),
      child: w,
    );
    final b = block;
    return switch (b) {
      td.PageBlockTitle(:final title) => pad(
        _rich(
          title,
          const TextStyle(fontSize: 27, fontWeight: FontWeight.w700, height: 1.25, color: GlowColors.text),
        ),
      ),
      td.PageBlockSubtitle(:final subtitle) => pad(
        _rich(subtitle, const TextStyle(fontSize: 19, color: GlowColors.textMuted, height: 1.35)),
        v: 4,
      ),
      td.PageBlockAuthorDate(:final author, :final publishDate) => pad(
        DefaultTextStyle(
          style: const TextStyle(color: GlowColors.textMuted, fontSize: 14),
          child: Wrap(
            spacing: 6,
            children: [
              if (!_isEmpty(author)) _rich(author, const TextStyle(color: GlowColors.cyan, fontSize: 14)),
              if (publishDate > 0)
                Text(
                  DateFormat.yMMMMd().format(DateTime.fromMillisecondsSinceEpoch(publishDate * 1000)),
                  style: const TextStyle(color: GlowColors.textMuted, fontSize: 14),
                ),
            ],
          ),
        ),
        v: 4,
      ),
      td.PageBlockHeader(:final header) => pad(
        _rich(header, const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: GlowColors.text)),
        v: 12,
      ),
      td.PageBlockSubheader(:final subheader) => pad(
        _rich(subheader, const TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: GlowColors.text)),
        v: 10,
      ),
      td.PageBlockKicker(:final kicker) => pad(
        _rich(
          kicker,
          const TextStyle(
            fontSize: 13,
            letterSpacing: 1.2,
            color: GlowColors.violet,
            fontWeight: FontWeight.w700,
          ),
        ),
        v: 4,
      ),
      td.PageBlockParagraph(:final text) => pad(_rich(text, _body)),
      td.PageBlockPreformatted(:final text) => pad(
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: GlowColors.surfaceHigh, borderRadius: BorderRadius.circular(10)),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: _rich(
              text,
              const TextStyle(fontFamily: 'monospace', fontSize: 14, height: 1.45, color: GlowColors.text),
            ),
          ),
        ),
      ),
      td.PageBlockFooter(:final footer) => pad(
        _rich(footer, const TextStyle(color: GlowColors.textMuted, fontSize: 14)),
      ),
      td.PageBlockDivider() => const Divider(height: 32, color: GlowColors.outline),
      td.PageBlockAnchor(:final name) => SizedBox(key: anchors.putIfAbsent(name, GlobalKey.new), height: 0),
      td.PageBlockList(:final items) => pad(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final it in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 26, child: Text(it.label.isEmpty ? '•' : it.label, style: _body)),
                    Expanded(child: _children(it.pageBlocks)),
                  ],
                ),
              ),
          ],
        ),
        v: 4,
      ),
      td.PageBlockBlockQuote(:final text, :final credit) => pad(
        Container(
          padding: const EdgeInsets.only(left: 14),
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: GlowColors.violet, width: 3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _rich(text, _body.copyWith(fontStyle: FontStyle.italic)),
              if (!_isEmpty(credit))
                _rich(credit, const TextStyle(color: GlowColors.textMuted, fontSize: 14)),
            ],
          ),
        ),
      ),
      td.PageBlockPullQuote(:final text, :final credit) => pad(
        Column(
          children: [
            _rich(
              text,
              const TextStyle(fontSize: 21, fontStyle: FontStyle.italic, height: 1.4, color: GlowColors.text),
            ),
            if (!_isEmpty(credit)) _rich(credit, const TextStyle(color: GlowColors.textMuted)),
          ],
        ),
        v: 14,
      ),
      td.PageBlockPhoto(:final photo, :final caption, :final url) => pad(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (photo != null && photo.sizes.isNotEmpty)
              GestureDetector(
                onTap: url.isEmpty ? null : () => openLink(context, url),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: AspectRatio(
                    aspectRatio: photo.sizes.last.height == 0
                        ? 16 / 9
                        : photo.sizes.last.width / photo.sizes.last.height,
                    child: TdFileImage(
                      file: photo.sizes.last.photo,
                      placeholderBytes: Display.minithumbnail(photo.minithumbnail),
                    ),
                  ),
                ),
              ),
            _caption(caption),
          ],
        ),
      ),
      td.PageBlockVideo(:final video, :final caption, :final needAutoplay, :final isLooped) => pad(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (video != null)
              _IvVideo(
                file: video.video,
                mime: video.mimeType,
                width: video.width,
                height: video.height,
                thumb: video.thumbnail?.file,
                mini: video.minithumbnail,
                autoplay: needAutoplay,
                loop: isLooped,
              ),
            _caption(caption),
          ],
        ),
      ),
      td.PageBlockAnimation(:final animation, :final caption) => pad(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (animation != null)
              _IvVideo(
                file: animation.animation,
                mime: animation.mimeType,
                width: animation.width,
                height: animation.height,
                thumb: animation.thumbnail?.file,
                mini: animation.minithumbnail,
                autoplay: true,
                loop: true,
              ),
            _caption(caption),
          ],
        ),
      ),
      td.PageBlockAudio(:final audio, :final caption) => pad(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (audio != null)
              _AudioTile(
                file: audio.audio,
                mime: audio.mimeType,
                title: [audio.performer, audio.title].where((s) => s.isNotEmpty).join(' — '),
                duration: audio.duration,
              ),
            _caption(caption),
          ],
        ),
      ),
      td.PageBlockVoiceNote(:final voiceNote, :final caption) => pad(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (voiceNote != null)
              _AudioTile(
                file: voiceNote.voice,
                mime: voiceNote.mimeType,
                title: 'Voice message',
                duration: voiceNote.duration,
              ),
            _caption(caption),
          ],
        ),
      ),
      td.PageBlockCover(:final cover) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _Block(cover, anchors: anchors, onAnchor: onAnchor),
      ),
      td.PageBlockCollage(:final pageBlocks, :final caption) ||
      td.PageBlockSlideshow(:final pageBlocks, :final caption) => pad(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 260,
              child: PageView(
                children: [for (final p in pageBlocks) _Block(p, anchors: anchors, onAnchor: onAnchor)],
              ),
            ),
            if (pageBlocks.length > 1)
              Text(
                '${pageBlocks.length} items · swipe',
                style: const TextStyle(color: GlowColors.textMuted, fontSize: 12),
              ),
            _caption(caption),
          ],
        ),
      ),
      td.PageBlockDetails(:final header, :final pageBlocks, :final isOpen) => Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: isOpen,
          tilePadding: EdgeInsets.zero,
          title: _rich(header, _body.copyWith(fontWeight: FontWeight.w600)),
          children: [_children(pageBlocks)],
        ),
      ),
      td.PageBlockTable(:final caption, :final cells, :final isBordered, :final isStriped) => pad(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!_isEmpty(caption)) _rich(caption, const TextStyle(color: GlowColors.textMuted)),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Table(
                defaultColumnWidth: const IntrinsicColumnWidth(),
                border: isBordered ? TableBorder.all(color: GlowColors.outline) : null,
                children: [
                  for (var r = 0; r < cells.length; r++)
                    TableRow(
                      decoration: isStriped && r.isOdd
                          ? const BoxDecoration(color: GlowColors.surface)
                          : null,
                      children: [
                        for (var c = 0; c < _width(cells); c++)
                          c < cells[r].length
                              ? Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: cells[r][c].text == null
                                      ? const SizedBox.shrink()
                                      : _rich(
                                          cells[r][c].text!,
                                          TextStyle(
                                            color: GlowColors.text,
                                            fontSize: 14,
                                            fontWeight: cells[r][c].isHeader
                                                ? FontWeight.w700
                                                : FontWeight.w400,
                                          ),
                                        ),
                                )
                              : const SizedBox.shrink(),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      td.PageBlockRelatedArticles(:final header, :final articles) => pad(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _rich(header, _body.copyWith(fontWeight: FontWeight.w700)),
            for (final a in articles)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(a.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: a.description.isEmpty
                    ? null
                    : Text(a.description, maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: a.photo == null || a.photo!.sizes.isEmpty
                    ? null
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox.square(
                          dimension: 52,
                          child: TdFileImage(file: a.photo!.sizes.first.photo),
                        ),
                      ),
                onTap: () => Navigator.of(context).pushReplacement(InstantViewScreen.route(a.url)),
              ),
          ],
        ),
      ),
      td.PageBlockChatLink(:final title, :final username) => pad(
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.campaign_rounded, color: GlowColors.cyan),
          title: Text(title),
          subtitle: Text('@$username'),
          onTap: () => openLink(context, 'https://t.me/$username'),
        ),
      ),
      td.PageBlockEmbeddedPost(:final author, :final date, :final pageBlocks, :final caption) => pad(
        Container(
          padding: const EdgeInsets.only(left: 12),
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: GlowColors.outlineStrong, width: 2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                [
                  author,
                  if (date > 0) DateFormat.yMMMd().format(DateTime.fromMillisecondsSinceEpoch(date * 1000)),
                ].join(' · '),
                style: const TextStyle(color: GlowColors.textMuted, fontWeight: FontWeight.w600),
              ),
              _children(pageBlocks),
              _caption(caption),
            ],
          ),
        ),
      ),
      td.PageBlockEmbedded(:final url, :final posterPhoto, :final caption) => pad(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Embedded HTML is not executed; show its poster and link out.
            InkWell(
              onTap: url.isEmpty ? null : () => openLink(context, url),
              child: Container(
                height: 160,
                decoration: BoxDecoration(
                  color: GlowColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (posterPhoto != null && posterPhoto.sizes.isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: TdFileImage(file: posterPhoto.sizes.last.photo),
                      ),
                    const Center(child: Icon(Icons.open_in_new_rounded, color: Colors.white70, size: 32)),
                  ],
                ),
              ),
            ),
            _caption(caption),
          ],
        ),
      ),
      td.PageBlockMap(:final location, :final caption) => pad(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton.icon(
              onPressed: () => openLink(
                context,
                'geo:${location.latitude},${location.longitude}?q=${location.latitude},${location.longitude}',
              ),
              icon: const Icon(Icons.map_rounded),
              label: const Text('Open map'),
            ),
            _caption(caption),
          ],
        ),
      ),
    };
  }

  static int _width(List<List<td.PageBlockTableCell>> cells) =>
      cells.fold(0, (m, r) => r.length > m ? r.length : m);
}

/// [td.RichText] as spans.
class _RichTextView extends StatefulWidget {
  const _RichTextView(this.text, {required this.style, required this.onAnchor});

  final td.RichText text;
  final TextStyle style;
  final void Function(String) onAnchor;

  @override
  State<_RichTextView> createState() => _RichTextViewState();
}

class _RichTextViewState extends State<_RichTextView> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  TapGestureRecognizer _tap(VoidCallback f) {
    final r = TapGestureRecognizer()..onTap = f;
    _recognizers.add(r);
    return r;
  }

  InlineSpan _span(td.RichText t, TextStyle s) {
    const link = TextStyle(color: GlowColors.cyan, decoration: TextDecoration.underline);
    return switch (t) {
      td.RichTextPlain(:final text) => TextSpan(text: text, style: s),
      td.RichTexts(:final texts) => TextSpan(children: [for (final x in texts) _span(x, s)]),
      td.RichTextBold(:final text) => _span(text, s.copyWith(fontWeight: FontWeight.w700)),
      td.RichTextItalic(:final text) => _span(text, s.copyWith(fontStyle: FontStyle.italic)),
      td.RichTextUnderline(:final text) => _span(text, s.copyWith(decoration: TextDecoration.underline)),
      td.RichTextStrikethrough(:final text) => _span(
        text,
        s.copyWith(decoration: TextDecoration.lineThrough),
      ),
      td.RichTextFixed(:final text) => _span(text, s.copyWith(fontFamily: 'monospace')),
      td.RichTextMarked(:final text) => _span(
        text,
        s.copyWith(backgroundColor: GlowColors.amber.withValues(alpha: 0.35)),
      ),
      td.RichTextSubscript(:final text) => _span(text, s.copyWith(fontSize: (s.fontSize ?? 16) * 0.7)),
      td.RichTextSuperscript(:final text) => WidgetSpan(
        alignment: PlaceholderAlignment.top,
        child: Text.rich(_span(text, s.copyWith(fontSize: (s.fontSize ?? 16) * 0.7))),
      ),
      td.RichTextUrl(:final text, :final url) => TextSpan(
        children: [_span(text, s.merge(link))],
        recognizer: _tap(() => openLink(context, url)),
      ),
      td.RichTextEmailAddress(:final text, :final emailAddress) => TextSpan(
        children: [_span(text, s.merge(link))],
        recognizer: _tap(() => openLink(context, 'mailto:$emailAddress')),
      ),
      td.RichTextPhoneNumber(:final text, :final phoneNumber) => TextSpan(
        children: [_span(text, s.merge(link))],
        recognizer: _tap(() => openLink(context, 'tel:$phoneNumber')),
      ),
      td.RichTextAnchorLink(:final text, :final anchorName) ||
      td.RichTextReference(:final text, :final anchorName) => TextSpan(
        children: [_span(text, s.merge(link))],
        recognizer: _tap(() => widget.onAnchor(anchorName)),
      ),
      td.RichTextAnchor() => const TextSpan(),
      td.RichTextIcon(:final document, :final width, :final height) => WidgetSpan(
        child: SizedBox(
          width: width.toDouble().clamp(8, 64),
          height: height.toDouble().clamp(8, 64),
          child: TdFileImage(file: document.document, fit: BoxFit.contain),
        ),
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
    return Text.rich(_span(widget.text, widget.style));
  }
}

class _IvVideo extends StatefulWidget {
  const _IvVideo({
    required this.file,
    required this.mime,
    required this.width,
    required this.height,
    required this.thumb,
    required this.mini,
    required this.autoplay,
    required this.loop,
  });

  final td.File file;
  final String mime;
  final int width;
  final int height;
  final td.File? thumb;
  final td.Minithumbnail? mini;
  final bool autoplay;
  final bool loop;

  @override
  State<_IvVideo> createState() => _IvVideoState();
}

class _IvVideoState extends State<_IvVideo> {
  ({String source, bool local})? _source;

  Future<void> _play() async {
    final f = context.read<FileStore>()[widget.file.id] ?? widget.file;
    if (f.local.isDownloadingCompleted && f.local.path.isNotEmpty) {
      setState(() => _source = (source: f.local.path, local: true));
      return;
    }
    final url = await context.read<TdStreamServer>().urlFor(
      f,
      mimeType: widget.mime.isEmpty ? 'video/mp4' : widget.mime,
    );
    if (mounted) setState(() => _source = (source: url.toString(), local: false));
  }

  @override
  Widget build(BuildContext context) {
    final ratio = widget.height == 0 ? 16 / 9 : widget.width / widget.height;
    final s = _source;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: AspectRatio(
        aspectRatio: ratio,
        child: s != null
            ? VideoPlayerView(source: s.source, isLocalFile: s.local, aspectRatio: ratio, loop: widget.loop)
            : GestureDetector(
                onTap: _play,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (widget.thumb != null)
                      TdFileImage(file: widget.thumb!, placeholderBytes: Display.minithumbnail(widget.mini))
                    else
                      const ColoredBox(color: GlowColors.surfaceHigh),
                    const Center(
                      child: Icon(Icons.play_circle_fill_rounded, size: 56, color: Colors.white70),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _AudioTile extends StatelessWidget {
  const _AudioTile({required this.file, required this.mime, required this.title, required this.duration});

  final td.File file;
  final String mime;
  final String title;
  final int duration;

  @override
  Widget build(BuildContext context) {
    final playback = context.read<AudioPlayback>();
    final key = 'iv:${file.id}';
    return ValueListenableBuilder(
      valueListenable: playback.state,
      builder: (context, s, _) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: IconButton.filled(
          style: IconButton.styleFrom(backgroundColor: GlowColors.violetDeep),
          onPressed: () => playback.toggle(key, file, mime: mime.isEmpty ? 'audio/mpeg' : mime),
          icon: Icon(s.isFor(key) && s.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
        ),
        title: Text(title.isEmpty ? 'Audio' : title),
        subtitle: Text(Display.duration(duration)),
      ),
    );
  }
}
