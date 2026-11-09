import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import '../storage/app_preferences.dart';
import '../theme/glow_colors.dart';
import 'chat_scrolling.dart';

/// How much glass the chat chrome draws (Settings → Appearance): light glass
/// (one blur, the default), real liquid glass always, real glass only while
/// the chat is still (light while scrolling), or solid surfaces.
enum GlassMode { light, full, adaptive, off }

/// Perf builds only (--dart-define=LUMINA_GLASS=off|light|full): forces a mode.
const _forcedGlass = String.fromEnvironment('LUMINA_GLASS');

GlassMode glassModeOf(BuildContext context) {
  if (_forcedGlass.isNotEmpty) return GlassMode.values.byName(_forcedGlass);
  try {
    return context.read<AppPreferences>().glassMode;
  } on ProviderNotFoundException {
    return GlassMode.full;
  }
}

/// Solid stand-in when glass is off.
Widget _solid(Widget child, double radius) => DecoratedBox(
  decoration: BoxDecoration(
    color: GlowColors.surfaceHigh.withValues(alpha: 0.97),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
  ),
  child: child,
);

/// Lit glass, after Apple's materials: what's behind is blurred *and* made
/// more vivid (vibrancy), under a faint tint; a rim catches light from the
/// top left and a soft sheen runs along the top edge. The light-weight glass
/// (one blur pass), for cards and for [GlassMode.light].
class LuminaGlass extends StatelessWidget {
  const LuminaGlass({
    super.key,
    required this.child,
    this.radius = 24,
    this.blur = 22,
    this.tint = GlowColors.surface,
    this.tintOpacity = 0.42,
    this.padding,
    this.shadow = true,
    this.grouped = false,
  });

  final Widget child;
  final double radius;
  final double blur;
  final Color tint;
  final double tintOpacity;
  final EdgeInsetsGeometry? padding;

  /// A soft drop shadow lifting the pill off the background.
  final bool shadow;

  /// Share one backdrop copy with the other glass under the nearest
  /// [BackdropGroup] (the backdrop copy is the expensive part).
  final bool grouped;

  /// Saturation 1.6 with a slight lift: colours behind glow through instead
  /// of turning grey (what a plain blur does).
  static final ui.ImageFilter _vibrancy = const ColorFilter.matrix(<double>[
    1.39, -0.36, -0.04, 0, 6, //
    -0.11, 1.24, -0.04, 0, 6, //
    -0.11, -0.36, 1.46, 0, 6, //
    0, 0, 0, 1, 0, //
  ]);

  @override
  Widget build(BuildContext context) {
    final content = padding == null ? child : Padding(padding: padding!, child: child);
    if (glassModeOf(context) == GlassMode.off) return _solid(content, radius);
    final r = BorderRadius.circular(radius);
    final reduceTransparency = MediaQuery.highContrastOf(context);
    final filter = reduceTransparency
        ? ui.ImageFilter.blur(sigmaX: 0, sigmaY: 0)
        : ui.ImageFilter.compose(
            outer: _vibrancy,
            inner: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          );
    final glass = CustomPaint(
      foregroundPainter: _RimPainter(radius),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: r,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.alphaBlend(
                Colors.white.withValues(alpha: 0.07),
                tint,
              ).withValues(alpha: reduceTransparency ? 0.96 : tintOpacity),
              tint.withValues(alpha: reduceTransparency ? 0.96 : tintOpacity + 0.08),
            ],
          ),
        ),
        child: content,
      ),
    );
    final clipped = ClipRRect(
      borderRadius: r,
      child: grouped && BackdropGroup.of(context) != null
          ? BackdropFilter.grouped(filter: filter, child: glass)
          : BackdropFilter(filter: filter, child: glass),
    );
    if (!shadow) return clipped;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.28), blurRadius: 18, offset: const Offset(0, 6)),
        ],
      ),
      child: clipped,
    );
  }
}

/// The lit edge: bright where light hits (top left), fading round the far
/// side, plus a sheen just inside the top.
class _RimPainter extends CustomPainter {
  const _RimPainter(this.radius);

  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect.deflate(0.5), Radius.circular(radius));
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.34),
            Colors.white.withValues(alpha: 0.06),
            Colors.white.withValues(alpha: 0.03),
            Colors.white.withValues(alpha: 0.14),
          ],
          stops: const [0, 0.35, 0.7, 1],
        ).createShader(rect),
    );
    // Sheen: light just inside the top edge, following the pill's own outline
    // all the way into its rounded ends (an inset band stopped short of them
    // and read as glass cut off at both ends).
    final inner = RRect.fromRectAndRadius(rect.deflate(1.5), Radius.circular(radius));
    canvas.drawRRect(
      inner,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white.withValues(alpha: 0.09), Colors.white.withValues(alpha: 0)],
          stops: const [0, 0.45],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_RimPainter old) => old.radius != radius;
}

/// One glass surface for a row of [GlassPill]s (the conversation header,
/// the composer). In [GlassMode.full], liquid glass: the backdrop is sampled
/// once for all its pills (with [shareBackdrop], once for the whole screen's
/// [BackdropGroup]); each pill stays a separate shape. Light mode is a plain
/// blur per pill; off draws solid pills.
class GlassGroup extends StatelessWidget {
  const GlassGroup({super.key, required this.child, this.tint = 0.35, this.shareBackdrop = false});

  final Widget child;

  /// Reuse the screen's [BackdropGroup] copy. Only for glass that nothing
  /// else paints between (shared members don't see what's drawn in between).
  final bool shareBackdrop;

  /// iOS's Liquid Glass slider: 0 clear … 1 tinted (more legible text).
  final double tint;

  @override
  Widget build(BuildContext context) {
    final mode = glassModeOf(context);
    final scoped = _GlassScope(mode: mode, child: child);
    if (mode != GlassMode.full && mode != GlassMode.adaptive) return scoped;
    return LiquidGlassLayer(
      fake: const bool.fromEnvironment('LUMINA_GLASS_FAKE'),
      settings: LiquidGlassSettings.ios27Regular(brightness: Brightness.dark, tintAmount: tint),
      defaultAppearance: LiquidGlassAppearance.ios27Regular(brightness: Brightness.dark),
      useBackdropGroup: shareBackdrop && BackdropGroup.of(context) != null,
      // Separate shapes, no blend group: each pill keeps its own outline.
      child: scoped,
    );
  }
}

class _GlassScope extends InheritedWidget {
  const _GlassScope({required this.mode, required super.child});

  final GlassMode mode;

  @override
  bool updateShouldNotify(_GlassScope old) => old.mode != mode;
}

/// Content is scrolling under the chat's glass. Liquid glass costs a lot per
/// frame (measured: 5–30 missed frames / 2 s scrolling vs 0–3 for one plain
/// blur), and nothing is redrawn while the screen is still, so pills draw
/// liquid glass at rest and the cheap blur while this is true.
abstract final class GlassMotion {
  static ValueNotifier<bool> get scrolling => ChatScrolling.moving;
  static void set(bool moving) => ChatScrolling.set(moving);
}

/// A pill (or circle, with [round]) of glass inside a [GlassGroup]. No
/// shadows: each one costs a pass while the chat scrolls under it. The glass
/// is a background behind [child], so switching liquid ↔ blur while
/// scrolling never remounts the child (the composer's text field keeps
/// focus).
class GlassPill extends StatelessWidget {
  const GlassPill({super.key, required this.child, this.round = false, this.radius = 24, this.tint});

  final Widget child;
  final bool round;
  final double radius;

  /// Colours the glass itself (e.g. a faint accent); null keeps it neutral.
  final Color? tint;

  Color get _tintColor => tint == null ? GlowColors.surface : Color.alphaBlend(tint!, GlowColors.surface);

  @override
  Widget build(BuildContext context) {
    final mode = context.dependOnInheritedWidgetOfExactType<_GlassScope>()?.mode ?? GlassMode.off;
    final r = round ? 999.0 : radius;
    final liquid = LiquidGlass(
      shape: round ? const LiquidOval() : LiquidRoundedSuperellipse(borderRadius: radius),
      appearance: tint == null
          ? null
          : LiquidGlassAppearance.ios27Regular(brightness: Brightness.dark, tint: tint!),
      child: const SizedBox.expand(),
    );
    final Widget background = switch (mode) {
      GlassMode.full => liquid,
      GlassMode.adaptive => ValueListenableBuilder<bool>(
        valueListenable: GlassMotion.scrolling,
        builder: (context, moving, _) => moving
            ? LuminaGlass(
                radius: r,
                shadow: false,
                grouped: true,
                blur: 16,
                tint: _tintColor,
                child: const SizedBox.expand(),
              )
            : LiquidGlass(
                shape: round ? const LiquidOval() : LiquidRoundedSuperellipse(borderRadius: radius),
                appearance: tint == null
                    ? null
                    : LiquidGlassAppearance.ios27Regular(brightness: Brightness.dark, tint: tint!),
                child: const SizedBox.expand(),
              ),
      ),
      GlassMode.light => LuminaGlass(
        radius: r,
        shadow: false,
        grouped: true,
        blur: 16,
        tint: _tintColor,
        child: const SizedBox.expand(),
      ),
      GlassMode.off => _solid(const SizedBox.expand(), r),
    };
    return Stack(
      children: [
        Positioned.fill(child: background),
        child,
      ],
    );
  }
}
