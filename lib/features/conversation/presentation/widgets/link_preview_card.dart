import 'package:flutter/material.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../../core/telegram/display.dart';
import '../../../../core/telegram/link_opener.dart';
import '../../../../core/telegram/widgets/formatted_text_view.dart';
import '../../../../core/telegram/widgets/td_file_image.dart';
import '../screens/instant_view_screen.dart';

/// The picture a link preview carries, if any.
({td.File? file, td.Minithumbnail? mini, bool playable}) previewMedia(td.LinkPreviewType t) {
  td.File? best(td.Photo? p) =>
      p == null || p.sizes.isEmpty ? null : p.sizes.reduce((a, b) => a.width >= b.width ? a : b).photo;
  return switch (t) {
    td.LinkPreviewTypeArticle(:final photo) => (
      file: best(photo),
      mini: photo?.minithumbnail,
      playable: false,
    ),
    td.LinkPreviewTypeWebApp(:final photo) => (
      file: best(photo),
      mini: photo?.minithumbnail,
      playable: false,
    ),
    td.LinkPreviewTypePhoto(:final photo) ||
    td.LinkPreviewTypeApp(:final photo) => (file: best(photo), mini: photo.minithumbnail, playable: false),
    td.LinkPreviewTypeEmbeddedVideoPlayer(:final thumbnail) ||
    td.LinkPreviewTypeEmbeddedAnimationPlayer(
      :final thumbnail,
    ) => (file: best(thumbnail), mini: thumbnail?.minithumbnail, playable: true),
    td.LinkPreviewTypeVideo(:final video) => (
      file: video.thumbnail?.file,
      mini: video.minithumbnail,
      playable: true,
    ),
    td.LinkPreviewTypeAnimation(:final animation) => (
      file: animation.thumbnail?.file,
      mini: animation.minithumbnail,
      playable: true,
    ),
    td.LinkPreviewTypeChat(:final photo) || td.LinkPreviewTypeUser(:final photo) => (
      file: photo == null || photo.sizes.isEmpty ? null : photo.sizes.last.photo,
      mini: photo?.minithumbnail,
      playable: false,
    ),
    _ => (file: null, mini: null, playable: false),
  };
}

/// A link preview inside a bubble (or above the composer): accent bar,
/// site, title, description and picture, plus "Instant View" for articles
/// Telegram can show natively.
class LinkPreviewCard extends StatelessWidget {
  const LinkPreviewCard({
    super.key,
    required this.preview,
    required this.textColor,
    required this.accent,
    this.largeMedia,
    this.compact = false,
  });

  final td.LinkPreview preview;
  final Color textColor;
  final Color accent;

  /// Overrides [td.LinkPreview.showLargeMedia] (composer toggle).
  final bool? largeMedia;

  /// Composer: one-line title/description, no Instant View button.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = preview;
    final media = previewMedia(p.type);
    final large = (largeMedia ?? p.showLargeMedia) && media.file != null && !compact;
    final small = !large && media.file != null;
    Widget picture({double? size}) => ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            TdFileImage(file: media.file!, placeholderBytes: Display.minithumbnail(media.mini), priority: 6),
            if (media.playable)
              const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white70, size: 40)),
          ],
        ),
      ),
    );
    final texts = <Widget>[
      if (p.siteName.isNotEmpty)
        Text(
          p.siteName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: accent, fontWeight: FontWeight.w700, fontSize: 13.5),
        ),
      if (p.title.isNotEmpty)
        Text(
          p.title,
          maxLines: compact ? 1 : 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 14.5),
        ),
      if (p.description.text.isNotEmpty)
        FormattedTextView(
          p.description,
          maxLines: compact ? 1 : 5,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: textColor.withValues(alpha: 0.85), fontSize: 13.5, height: 1.3),
          linkColor: accent,
        ),
      if (p.author.isNotEmpty && !compact)
        Text(p.author, style: TextStyle(color: textColor.withValues(alpha: 0.6), fontSize: 12.5)),
    ];
    return Semantics(
      button: true,
      label: 'Link preview: ${[p.siteName, p.title].where((s) => s.isNotEmpty).join(', ')}',
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: compact ? null : () => openLink(context, p.url),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 6, 8, 8),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
            border: Border(left: BorderSide(color: accent, width: 3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            spacing: 2,
            children: [
              if (large && p.showMediaAboveDescription)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: AspectRatio(aspectRatio: 16 / 9, child: picture()),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      spacing: 2,
                      children: texts,
                    ),
                  ),
                  if (small) ...[const SizedBox(width: 8), picture(size: compact ? 40 : 56)],
                ],
              ),
              if (large && !p.showMediaAboveDescription)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: AspectRatio(aspectRatio: 16 / 9, child: picture()),
                ),
              if (p.instantViewVersion > 0 && !compact)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: accent,
                        side: BorderSide(color: accent.withValues(alpha: 0.5)),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () =>
                          Navigator.of(context).push(InstantViewScreen.route(p.url, title: p.siteName)),
                      icon: const Icon(Icons.bolt_rounded, size: 18),
                      label: const Text('Instant View'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
