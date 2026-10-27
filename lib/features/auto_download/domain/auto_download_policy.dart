import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../core/telegram/auto_download_gate.dart';

export '../../../core/telegram/auto_download_gate.dart' show MediaKind;

/// The network the phone is on, as auto-download distinguishes it.
enum NetworkKind {
  mobile('Mobile'),
  wifi('Wi-Fi'),
  roaming('Roaming');

  const NetworkKind(this.label);
  final String label;
}

enum ChatKind {
  contacts('Contacts'),
  private('Private chats'),
  groups('Groups'),
  channels('Channels');

  const ChatKind(this.label);
  final String label;
}

enum AutoDownloadPreset {
  off('Off'),
  low('Low'),
  medium('Medium'),
  high('High'),
  custom('Custom');

  const AutoDownloadPreset(this.label);
  final String label;
}

const _kb = 1024, _mb = 1024 * 1024;

/// What is downloaded automatically on one network type: a media × chat
/// grid of toggles, size limits for videos and files, and whether the start
/// of larger videos is preloaded.
@immutable
class AutoDownloadPolicy {
  const AutoDownloadPolicy({
    required this.enabled,
    required this.maxVideoSize,
    required this.maxFileSize,
    required this.preloadLargeVideos,
  });

  final Set<(MediaKind, ChatKind)> enabled;
  final int maxVideoSize;
  final int maxFileSize;
  final bool preloadLargeVideos;

  /// The slider's snapping stops, 100 KB to 4 GB on a roughly log scale.
  static const sizeStops = [
    100 * _kb,
    250 * _kb,
    500 * _kb,
    1 * _mb,
    2 * _mb,
    5 * _mb,
    10 * _mb,
    20 * _mb,
    50 * _mb,
    100 * _mb,
    200 * _mb,
    500 * _mb,
    1024 * _mb,
    2048 * _mb,
    4096 * _mb,
  ];

  /// The stop nearest to [size] on the log scale.
  static int snap(int size) {
    double distance(int s) => (log(size.clamp(1, 1 << 40) / s)).abs();
    return sizeStops.reduce((a, b) => distance(b) < distance(a) ? b : a);
  }

  static Set<(MediaKind, ChatKind)> _cells(Iterable<MediaKind> media, Iterable<ChatKind> chats) => {
    for (final m in media)
      for (final c in chats) (m, c),
  };

  static AutoDownloadPolicy of(AutoDownloadPreset p) => switch (p) {
    AutoDownloadPreset.off || AutoDownloadPreset.custom => const AutoDownloadPolicy(
      enabled: {},
      maxVideoSize: 10 * _mb,
      maxFileSize: 1 * _mb,
      preloadLargeVideos: false,
    ),
    AutoDownloadPreset.low => AutoDownloadPolicy(
      enabled: {
        ..._cells([MediaKind.photos], ChatKind.values),
        ..._cells([MediaKind.voice, MediaKind.videoMessages], [ChatKind.contacts, ChatKind.private]),
      },
      maxVideoSize: 1 * _mb,
      maxFileSize: 1 * _mb,
      preloadLargeVideos: false,
    ),
    AutoDownloadPreset.medium => AutoDownloadPolicy(
      enabled: {
        ..._cells([
          MediaKind.photos,
          MediaKind.voice,
          MediaKind.videoMessages,
          MediaKind.gifs,
        ], ChatKind.values),
        ..._cells([MediaKind.videos], [ChatKind.contacts, ChatKind.private, ChatKind.groups]),
        ..._cells([MediaKind.files], [ChatKind.contacts, ChatKind.private]),
      },
      maxVideoSize: 10 * _mb,
      maxFileSize: 1 * _mb,
      preloadLargeVideos: false,
    ),
    AutoDownloadPreset.high => AutoDownloadPolicy(
      enabled: _cells(MediaKind.values, ChatKind.values),
      maxVideoSize: 100 * _mb,
      maxFileSize: 100 * _mb,
      preloadLargeVideos: true,
    ),
  };

  static AutoDownloadPolicy defaultFor(NetworkKind n) => of(switch (n) {
    NetworkKind.mobile => AutoDownloadPreset.medium,
    NetworkKind.wifi => AutoDownloadPreset.high,
    NetworkKind.roaming => AutoDownloadPreset.low,
  });

  /// The named preset this equals, else custom.
  AutoDownloadPreset get preset {
    for (final p in AutoDownloadPreset.values) {
      if (p != AutoDownloadPreset.custom && AutoDownloadPolicy.of(p) == this) return p;
    }
    // Off ignores the limits: an empty grid downloads nothing either way.
    return enabled.isEmpty ? AutoDownloadPreset.off : AutoDownloadPreset.custom;
  }

  bool isOn(MediaKind m, ChatKind c) => enabled.contains((m, c));

  /// Whether a file of [size] bytes of kind [m] in a chat of kind [c] is
  /// downloaded without asking.
  bool allows(MediaKind m, ChatKind c, {required int size}) {
    if (!isOn(m, c)) return false;
    return switch (m) {
      MediaKind.videos => size <= maxVideoSize,
      MediaKind.files => size <= maxFileSize,
      _ => true,
    };
  }

  bool anyOn(MediaKind m) => enabled.any((e) => e.$1 == m);

  AutoDownloadPolicy toggled(MediaKind m, ChatKind c) =>
      copyWith(enabled: isOn(m, c) ? ({...enabled}..remove((m, c))) : {...enabled, (m, c)});

  AutoDownloadPolicy copyWith({
    Set<(MediaKind, ChatKind)>? enabled,
    int? maxVideoSize,
    int? maxFileSize,
    bool? preloadLargeVideos,
  }) => AutoDownloadPolicy(
    enabled: enabled ?? this.enabled,
    maxVideoSize: maxVideoSize ?? this.maxVideoSize,
    maxFileSize: maxFileSize ?? this.maxFileSize,
    preloadLargeVideos: preloadLargeVideos ?? this.preloadLargeVideos,
  );

  String toJson() => jsonEncode({
    'on': [for (final (m, c) in enabled) '${m.name}.${c.name}'],
    'video': maxVideoSize,
    'file': maxFileSize,
    'preload': preloadLargeVideos,
  });

  static AutoDownloadPolicy? fromJson(String source) {
    try {
      final j = jsonDecode(source) as Map<String, Object?>;
      final on = <(MediaKind, ChatKind)>{};
      for (final cell in (j['on']! as List).cast<String>()) {
        final [m, c] = cell.split('.');
        final media = MediaKind.values.where((v) => v.name == m).firstOrNull;
        final chat = ChatKind.values.where((v) => v.name == c).firstOrNull;
        if (media != null && chat != null) on.add((media, chat));
      }
      return AutoDownloadPolicy(
        enabled: on,
        maxVideoSize: j['video']! as int,
        maxFileSize: j['file']! as int,
        preloadLargeVideos: j['preload']! as bool,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is AutoDownloadPolicy &&
      setEquals(other.enabled, enabled) &&
      other.maxVideoSize == maxVideoSize &&
      other.maxFileSize == maxFileSize &&
      other.preloadLargeVideos == preloadLargeVideos;

  @override
  int get hashCode =>
      Object.hash(Object.hashAllUnordered(enabled), maxVideoSize, maxFileSize, preloadLargeVideos);
}
