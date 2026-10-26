import 'package:flutter/painting.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../core/storage/app_preferences.dart';

/// What to draw behind a chat's messages.
sealed class BackdropSpec {
  const BackdropSpec();
}

/// Lumina's own glowing backdrop (today's look).
final class BackdropGlow extends BackdropSpec {
  const BackdropGlow();
}

/// A wallpaper image: a TDLib file (Telegram's gallery or a chat's
/// background) or a local photo [path].
final class BackdropImage extends BackdropSpec {
  const BackdropImage({this.file, this.fileId, this.path});
  final td.File? file;

  /// A known TDLib file by id (the Settings default from the gallery).
  final int? fileId;
  final String? path;
}

/// One colour, a two-colour gradient or Telegram's freeform gradient.
final class BackdropFill extends BackdropSpec {
  const BackdropFill(this.colors, {this.angle = 0});
  final List<Color> colors;
  final int angle;
}

class ChatBackdrop {
  const ChatBackdrop(this.spec, {this.blur = 0, this.dim = 0});

  final BackdropSpec spec;

  /// Blur sigma in logical pixels (0 = sharp).
  final double blur;

  /// 0..1 black over the background so bubbles stay readable.
  final double dim;
}

Color _rgb(int c) => Color(0xFF000000 | c);

BackdropSpec? _fill(td.BackgroundFill f) => switch (f) {
  td.BackgroundFillSolid(:final color) => BackdropFill([_rgb(color)]),
  td.BackgroundFillGradient(:final topColor, :final bottomColor, :final rotationAngle) => BackdropFill([
    _rgb(topColor),
    _rgb(bottomColor),
  ], angle: rotationAngle),
  td.BackgroundFillFreeformGradient(:final colors) => BackdropFill([for (final c in colors) _rgb(c)]),
};

/// The backdrop for [chat]: its Telegram background if it has one,
/// otherwise the default from Settings (Lumina glow out of the box).
ChatBackdrop resolveBackdrop(td.Chat? chat, AppPreferences prefs) {
  final bg = chat?.background;
  if (bg != null) {
    final dim = (bg.darkThemeDimming / 100).clamp(0.0, 0.9);
    final spec = switch (bg.background.type) {
      td.BackgroundTypeWallpaper() when bg.background.document != null => BackdropImage(
        file: bg.background.document!.document,
      ),
      // Patterns draw as their fill; the pattern art isn't rendered yet.
      td.BackgroundTypePattern(:final fill) || td.BackgroundTypeFill(:final fill) => _fill(fill),
      _ => null,
    };
    if (spec != null) {
      final type = bg.background.type;
      final blurred = type is td.BackgroundTypeWallpaper && type.isBlurred;
      return ChatBackdrop(spec, blur: blurred ? 12 : 0, dim: dim);
    }
  }
  final spec = switch (prefs.backdropKind) {
    'photo' when prefs.backdropPath != null => BackdropImage(path: prefs.backdropPath),
    'telegram' when prefs.backdropFileId != null => BackdropImage(fileId: prefs.backdropFileId),
    'fill' => BackdropFill([for (final c in prefs.backdropColors) _rgb(c)]),
    _ => const BackdropGlow(),
  };
  return ChatBackdrop(spec, blur: prefs.backdropBlur, dim: prefs.backdropDim);
}
