import 'dart:io';

import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../platform/system_channel.dart';
import '../storage/app_preferences.dart';

/// Short interface sounds. The send sound is Telegram for Android's own
/// (sound_out.wav from its GPL v2 source, assets/sounds/send.wav; see
/// assets/sounds/CREDITS.txt), silent whenever the phone is on silent or
/// vibrate or Settings → Send sound is off.
abstract final class UiSounds {
  static AudioPlayer? _send;
  static Future<void>? _loading;
  static DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  static Future<void> sent() async {
    if (!(AppPreferences.current?.sendSound ?? true)) return;
    // An album or a burst of sends plays once.
    final now = DateTime.now();
    if (now.difference(_last) < const Duration(milliseconds: 250)) return;
    _last = now;
    try {
      if (await const SystemChannel().ringerSilent()) return;
      final p = _send ??= AudioPlayer(handleInterruptions: false);
      await (_loading ??= _load(p, 'assets/sounds/send.wav'));
      await p.seek(Duration.zero);
      await p.play();
    } catch (_) {
      // No sound is never worth an error; try loading afresh next time.
      _loading = null;
    }
  }

  /// Not `setAsset`: just_audio copies an asset to a cache file named after
  /// its path and never rewrites it, so after an update that replaced the
  /// sound the phone kept playing the old one. The copy here is named after
  /// the bytes, so a new sound is always a new file.
  static Future<void> _load(AudioPlayer p, String asset) async {
    final bytes = (await rootBundle.load(asset)).buffer.asUint8List();
    var hash = 0;
    for (final b in bytes) {
      hash = (hash * 31 + b) & 0x7fffffff;
    }
    final dir = Directory('${(await getTemporaryDirectory()).path}/ui_sounds');
    final file = File('${dir.path}/${asset.split('/').last.split('.').first}_${bytes.length}_$hash.wav');
    if (!file.existsSync()) {
      await dir.create(recursive: true);
      // Older copies of the same sound go.
      for (final old in dir.listSync().whereType<File>()) {
        old.deleteSync();
      }
      await file.writeAsBytes(bytes, flush: true);
    }
    await p.setFilePath(file.path);
    // Telegram plays it at full volume.
    await p.setVolume(1.0);
  }
}
