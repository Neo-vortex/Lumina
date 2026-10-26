import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/theme/glow_colors.dart';
import 'package:lumina/features/folders/presentation/folder_palette.dart';

void main() {
  test('Telegram colour ids map to glow colours; blue folds into cyan', () {
    expect(FolderPalette.colorOf(0, position: 0), GlowColors.coral);
    expect(FolderPalette.colorOf(1, position: 0), GlowColors.amber);
    expect(FolderPalette.colorOf(2, position: 0), GlowColors.violet);
    expect(FolderPalette.colorOf(3, position: 0), GlowColors.teal);
    expect(FolderPalette.colorOf(4, position: 0), GlowColors.cyan);
    expect(FolderPalette.colorOf(5, position: 0), GlowColors.cyan);
    expect(FolderPalette.colorOf(6, position: 0), GlowColors.magenta);
  });

  test('no colour: picked by position, cycling the palette', () {
    final n = FolderPalette.choices.length;
    expect(FolderPalette.colorOf(-1, position: 0), FolderPalette.choices[0].color);
    expect(FolderPalette.colorOf(-1, position: n + 1), FolderPalette.choices[1].color);
  });

  test('icons: known names map, unknown falls back to a folder', () {
    expect(FolderPalette.iconOf('Work'), Icons.work_rounded);
    expect(FolderPalette.iconOf('Nope'), Icons.folder_rounded);
    expect(FolderPalette.iconOf(null), Icons.folder_rounded);
  });
}
