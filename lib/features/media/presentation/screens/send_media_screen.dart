import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../../core/media/ffmpeg_service.dart';
import '../../../../core/telegram/display.dart';
import '../../../../core/telegram/send_options.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../../../core/widgets/glow_background.dart';
import '../../../../core/widgets/send_options_sheet.dart';
import '../../data/media_sender.dart';
import '../widgets/video_convert_sheet.dart';

/// What the review screen hands back to the conversation.
class MediaSendRequest {
  const MediaSendRequest(this.contents, {required this.asAlbum, this.options = const SendOptions()});
  final List<td.InputMessageContent> contents;
  final bool asAlbum;

  /// Silent / scheduled / when-online, from long-pressing send.
  final SendOptions options;
}

/// Review picked media before sending: caption, spoiler, view-once,
/// send-as-file, and per-video conversion (simple or advanced).
class SendMediaScreen extends StatefulWidget {
  const SendMediaScreen({
    super.key,
    required this.items,
    required this.allowViewOnce,
    required this.parseCaption,
    this.initialAsFile = false,
  });

  final List<PickedMedia> items;

  /// Starts with "Send as file" on (File tile, or "Original quality").
  final bool initialAsFile;

  /// View-once exists only in private chats (and not for bots).
  final bool allowViewOnce;
  final Future<td.FormattedText> Function(String text) parseCaption;

  static Future<MediaSendRequest?> open(
    BuildContext context, {
    required List<String> paths,
    required bool allowViewOnce,
    required Future<td.FormattedText> Function(String) parseCaption,
    bool asFiles = false,
    bool music = false,
  }) async {
    final sender = context.read<MediaSender>();
    final items = await Future.wait(paths.map((p) => sender.inspect(p, music: music)));
    if (!context.mounted) return null;
    return Navigator.of(context).push<MediaSendRequest>(
      MaterialPageRoute(
        builder: (_) => SendMediaScreen(
          items: items,
          allowViewOnce: allowViewOnce,
          parseCaption: parseCaption,
          // Music goes out as tracks; the picker marks it as files only so
          // nothing gets recompressed.
          initialAsFile: asFiles && !music,
        ),
      ),
    );
  }

  @override
  State<SendMediaScreen> createState() => _SendMediaScreenState();
}

class _SendMediaScreenState extends State<SendMediaScreen> {
  final _caption = TextEditingController();
  late var _asFile = widget.initialAsFile;
  var _spoiler = false;
  var _viewOnce = false;
  var _working = false;
  double? _progress;
  String? _status;
  FfmpegCancelToken? _cancel;

  @override
  void dispose() {
    _caption.dispose();
    _cancel?.cancel();
    super.dispose();
  }

  Future<void> _convert(PickedMedia m) async {
    final probe = m.probe;
    if (probe == null) return;
    final encoders = await context.read<MediaSender>().ffmpeg.encoders();
    if (!mounted) return;
    final preset = await showVideoConvertSheet(context, probe: probe, encoders: encoders, current: m.preset);
    if (preset != null) setState(() => m.preset = preset);
  }

  Future<void> _sendWithOptions() async {
    final options = await showSendOptionsSheet(context);
    if (options != null && mounted) await _send(options);
  }

  Future<void> _send([SendOptions options = const SendOptions()]) async {
    final sender = context.read<MediaSender>();
    setState(() => _working = true);
    try {
      final videos = widget.items
          .where((m) => m.kind == MediaKind.video && !(m.preset?.isOriginal ?? true))
          .toList();
      for (var i = 0; i < widget.items.length; i++) {
        final m = widget.items[i];
        if (!_asFile && videos.contains(m)) {
          setState(() {
            _status = 'Converting video ${videos.indexOf(m) + 1} of ${videos.length}…';
            _progress = 0;
          });
          _cancel = FfmpegCancelToken();
          final out = await sender.prepare(
            m,
            cancel: _cancel,
            onProgress: (p) {
              if (mounted) setState(() => _progress = p);
            },
          );
          if (out == null) {
            if (_cancel?.isCancelled ?? false) return;
            throw StateError('Could not convert ${m.name}');
          }
        } else {
          m.sendPath = m.path;
        }
      }
      setState(() {
        _status = 'Preparing…';
        _progress = null;
      });
      final caption = _caption.text.trim().isEmpty ? null : await widget.parseCaption(_caption.text.trim());
      final contents = <td.InputMessageContent>[];
      for (var i = 0; i < widget.items.length; i++) {
        contents.add(
          await sender.build(
            widget.items[i],
            caption: i == 0 ? caption : null,
            asFile: _asFile,
            spoiler: _spoiler,
            viewOnce: _viewOnce,
          ),
        );
      }
      final album = contents.length > 1 && !_viewOnce;
      if (mounted) Navigator.pop(context, MediaSendRequest(contents, asAlbum: album, options: options));
    } catch (e) {
      if (mounted) {
        setState(() {
          _working = false;
          _status = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final single = widget.items.length == 1;
    final hasMedia = widget.items.any((m) => m.kind != MediaKind.file);
    final visual = widget.items.any((m) => m.kind == MediaKind.photo || m.kind == MediaKind.video);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: GlowColors.background,
        title: Text(single ? 'Send ${widget.items.first.kind.name}' : 'Send ${widget.items.length} items'),
      ),
      body: GlowBackground(
        child: Column(
          children: [
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: single ? 1 : 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: single ? 0.9 : 1,
                ),
                itemCount: widget.items.length,
                itemBuilder: (context, i) =>
                    _Tile(media: widget.items[i], onConvert: () => _convert(widget.items[i])),
              ),
            ),
            if (_status != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  children: [
                    Semantics(liveRegion: true, child: Text(_status!)),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(value: _progress, color: GlowColors.violet),
                    TextButton(
                      onPressed: () {
                        _cancel?.cancel();
                        setState(() {
                          _working = false;
                          _status = null;
                        });
                      },
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ),
            Material(
              color: GlowColors.surface,
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hasMedia)
                      Wrap(
                        spacing: 8,
                        children: [
                          FilterChip(
                            label: const Text('Send as file'),
                            selected: _asFile,
                            onSelected: _working ? null : (v) => setState(() => _asFile = v),
                          ),
                          if (visual)
                            FilterChip(
                              label: const Text('Spoiler'),
                              selected: _spoiler,
                              onSelected: _working || _asFile ? null : (v) => setState(() => _spoiler = v),
                            ),
                          if (widget.allowViewOnce && single && visual)
                            FilterChip(
                              label: const Text('View once'),
                              selected: _viewOnce,
                              onSelected: _working || _asFile ? null : (v) => setState(() => _viewOnce = v),
                            ),
                        ],
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _caption,
                              minLines: 1,
                              maxLines: 4,
                              enabled: !_working,
                              decoration: const InputDecoration(
                                hintText: 'Add a caption',
                                border: InputBorder.none,
                              ),
                            ),
                          ),
                          // Long-press: silent / schedule / when online, as
                          // in the composer.
                          GestureDetector(
                            onLongPress: _working ? null : _sendWithOptions,
                            child: IconButton.filled(
                              tooltip: 'Send (hold for options)',
                              style: IconButton.styleFrom(
                                backgroundColor: GlowColors.violetDeep,
                                minimumSize: const Size(52, 52),
                              ),
                              onPressed: _working ? null : _send,
                              icon: const Icon(Icons.arrow_upward_rounded),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.media, required this.onConvert});

  final PickedMedia media;
  final VoidCallback onConvert;

  @override
  Widget build(BuildContext context) {
    final probe = media.probe;
    final preset = media.preset;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: GlowColors.surfaceHigh),
          if (media.kind == MediaKind.photo)
            Image.file(File(media.path), fit: BoxFit.cover, cacheWidth: 800)
          else if (media.kind == MediaKind.video)
            const Center(child: Icon(Icons.movie_rounded, size: 48, color: GlowColors.textMuted))
          else if (media.kind == MediaKind.audio)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.music_note_rounded, size: 42, color: GlowColors.cyan),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    child: Text(trackTitle(media), textAlign: TextAlign.center, maxLines: 2),
                  ),
                  if (media.probe?.performer case final p?)
                    Text(p, style: const TextStyle(color: GlowColors.textMuted, fontSize: 12)),
                  if (media.probe case final p?)
                    Text(
                      Display.duration(p.duration.inSeconds),
                      style: const TextStyle(color: GlowColors.textMuted, fontSize: 12),
                    ),
                ],
              ),
            )
          else
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.insert_drive_file_rounded, size: 42, color: GlowColors.amber),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(media.name, textAlign: TextAlign.center, maxLines: 2),
                  ),
                ],
              ),
            ),
          if (media.kind == MediaKind.video && probe != null)
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Material(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: onConvert,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.tune_rounded, size: 18, color: GlowColors.cyan),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            preset == null || preset.isOriginal
                                ? 'Original · ${Display.fileSize(probe.sizeBytes)}'
                                : '${preset.title} · ≈${Display.fileSize(preset.estimateBytes(probe))}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        Text(
                          Display.duration(probe.duration.inSeconds),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
