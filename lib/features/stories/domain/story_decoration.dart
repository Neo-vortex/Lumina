import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/painting.dart';
import 'package:lumina_tdlib/api.dart' as td;

/// Something placed on a story in the editor. Positions are fractions of the
/// 9:16 frame, so the same decoration renders identically in the editor,
/// in the burned-in overlay and as a tappable area for viewers.
sealed class StoryDecoration {
  StoryDecoration({this.center = const Offset(0.5, 0.45), this.scale = 1, this.rotation = 0});

  Offset center;
  double scale;

  /// Radians, clockwise.
  double rotation;

  /// Drawn into the media (emoji, text, link and location pills).
  /// Reaction tags are drawn by each viewer's app instead.
  bool get burned => true;

  /// The interactive area Telegram should attach, if any.
  td.InputStoryAreaType? get areaType => null;
}

class EmojiSticker extends StoryDecoration {
  EmojiSticker(this.emoji, {super.center, super.scale, super.rotation});
  final String emoji;
}

class TextSticker extends StoryDecoration {
  TextSticker(
    this.text, {
    this.color = const Color(0xFFFFFFFF),
    this.pill = true,
    super.center,
    super.scale,
    super.rotation,
  });
  String text;
  Color color;

  /// Text on a translucent rounded background, for legibility.
  bool pill;
}

/// A suggested reaction bubble; viewers tap it to react.
class ReactionTag extends StoryDecoration {
  ReactionTag(
    this.emoji, {
    this.dark = false,
    this.flipped = false,
    super.center,
    super.scale,
    super.rotation,
  });
  final String emoji;
  bool dark;
  bool flipped;

  @override
  bool get burned => false;

  @override
  td.InputStoryAreaType get areaType => td.InputStoryAreaTypeSuggestedReaction(
    reactionType: td.ReactionTypeEmoji(emoji: emoji),
    isDark: dark,
    isFlipped: flipped,
  );
}

class LinkTag extends StoryDecoration {
  LinkTag(this.url, {super.center, super.scale, super.rotation});
  final String url;

  String get label {
    final host = Uri.tryParse(url)?.host ?? '';
    return host.isEmpty ? url : host.replaceFirst(RegExp(r'^www\.'), '');
  }

  @override
  td.InputStoryAreaType get areaType => td.InputStoryAreaTypeLink(url: url);
}

class LocationTag extends StoryDecoration {
  LocationTag(
    this.name, {
    required this.latitude,
    required this.longitude,
    super.center,
    super.scale,
    super.rotation,
  });
  final String name;
  final double latitude;
  final double longitude;

  @override
  td.InputStoryAreaType get areaType => td.InputStoryAreaTypeLocation(
    location: td.Location(latitude: latitude, longitude: longitude, horizontalAccuracy: 0),
    address: td.LocationAddress(countryCode: '', state: '', city: name, street: ''),
  );
}

/// Measures and paints decorations. Sizes are relative to the frame height
/// so a 1080×1920 overlay and a phone-sized preview match exactly.
abstract final class DecorationPainter {
  static double _unit(Size frame) => frame.height / 1920;

  static TextPainter _text(
    String text,
    double fontSize,
    Color color, {
    FontWeight weight = FontWeight.w600,
  }) => TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(color: color, fontSize: fontSize, fontWeight: weight, height: 1.15),
    ),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
  )..layout(maxWidth: 1e6);

  static ({String text, Color fg, Color? bg, double font, String? icon}) _style(
    StoryDecoration d,
    Size frame,
  ) {
    final u = _unit(frame) * d.scale;
    return switch (d) {
      EmojiSticker(:final emoji) => (
        text: emoji,
        fg: const Color(0xFFFFFFFF),
        bg: null,
        font: 150 * u,
        icon: null,
      ),
      TextSticker(:final text, :final color, :final pill) => (
        text: text,
        fg: color,
        bg: pill ? const Color(0x99000000) : null,
        font: 64 * u,
        icon: null,
      ),
      ReactionTag(:final emoji, :final dark) => (
        text: emoji,
        fg: const Color(0xFFFFFFFF),
        bg: dark ? const Color(0xE61C2027) : const Color(0xF2FFFFFF),
        font: 110 * u,
        icon: null,
      ),
      LinkTag(:final label) => (
        text: label,
        fg: const Color(0xFF0D0F12),
        bg: const Color(0xF2FFFFFF),
        font: 52 * u,
        icon: '🔗 ',
      ),
      LocationTag(:final name) => (
        text: name,
        fg: const Color(0xFF0D0F12),
        bg: const Color(0xF2FFFFFF),
        font: 52 * u,
        icon: '📍 ',
      ),
    };
  }

  /// Unrotated size of [d] on [frame].
  static Size sizeOf(StoryDecoration d, Size frame) {
    final st = _style(d, frame);
    final tp = _text('${st.icon ?? ''}${st.text}', st.font, st.fg);
    final pad = st.bg == null ? 0.0 : st.font * 0.45;
    if (d is ReactionTag) {
      final side = math.max(tp.width, tp.height) + pad * 2;
      return Size(side, side);
    }
    return Size(tp.width + pad * 2, tp.height + pad * 1.2);
  }

  static Rect boundsOf(StoryDecoration d, Size frame) {
    final size = sizeOf(d, frame);
    final c = Offset(d.center.dx * frame.width, d.center.dy * frame.height);
    return Rect.fromCenter(center: c, width: size.width, height: size.height);
  }

  static void paint(Canvas canvas, Size frame, StoryDecoration d) {
    final st = _style(d, frame);
    final size = sizeOf(d, frame);
    final c = Offset(d.center.dx * frame.width, d.center.dy * frame.height);
    canvas
      ..save()
      ..translate(c.dx, c.dy)
      ..rotate(d.rotation);
    final rect = Rect.fromCenter(center: Offset.zero, width: size.width, height: size.height);
    final bg = st.bg;
    if (bg != null) {
      if (d is ReactionTag) {
        canvas.drawOval(rect.inflate(2), Paint()..color = const Color(0x33000000));
        canvas.drawOval(rect, Paint()..color = bg);
      } else {
        canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(st.font * 0.5)), Paint()..color = bg);
      }
    }
    final tp = _text('${st.icon ?? ''}${st.text}', st.font, st.fg);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  /// The Telegram area for [d], or null when it is purely visual.
  static td.InputStoryArea? areaOf(StoryDecoration d) {
    final type = d.areaType;
    if (type == null) return null;
    const frame = Size(1080, 1920);
    final size = sizeOf(d, frame);
    return td.InputStoryArea(
      position: positionOf(d.center, size, frame, d.rotation, rounded: d is! ReactionTag),
      type: type,
    );
  }

  static td.AreaPosition positionOf(
    Offset center,
    Size size,
    Size frame,
    double rotation, {
    bool rounded = true,
  }) => td.AreaPosition(
    xPercentage: center.dx * 100,
    yPercentage: center.dy * 100,
    widthPercentage: size.width / frame.width * 100,
    heightPercentage: size.height / frame.height * 100,
    rotationAngle: (rotation * 180 / math.pi) % 360,
    // Percent of the media width.
    cornerRadiusPercentage: rounded ? size.height / 2 / frame.width * 100 : 0,
  );
}

/// Renders the burned-in decorations to a transparent PNG of [frame] size.
Future<Uint8List?> renderOverlay(List<StoryDecoration> decorations, Size frame) async {
  final burned = decorations.where((d) => d.burned).toList();
  if (burned.isEmpty) return null;
  final recorder = PictureRecorder();
  final canvas = Canvas(recorder, Offset.zero & frame);
  for (final d in burned) {
    DecorationPainter.paint(canvas, frame, d);
  }
  final image = await recorder.endRecording().toImage(frame.width.round(), frame.height.round());
  final data = await image.toByteData(format: ImageByteFormat.png);
  image.dispose();
  return data?.buffer.asUint8List();
}
