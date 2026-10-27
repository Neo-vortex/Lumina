import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Kinds of media auto-download distinguishes.
enum MediaKind {
  photos('Photos'),
  videos('Videos'),
  files('Files'),
  voice('Voice messages'),
  videoMessages('Video messages'),
  gifs('GIFs'),
  music('Music');

  const MediaKind(this.label);
  final String label;
}

/// Whether media may download without a tap (Settings → Data & storage →
/// Auto-download). Implemented by the auto-download feature.
abstract interface class AutoDownloadGate {
  bool allows({required int chatId, required MediaKind media, required int size});

  /// Fetch the start of videos too large to auto-download.
  bool get preloadLargeVideos;

  /// The app's gate, or one that allows everything (tests, previews).
  static AutoDownloadGate of(BuildContext context) {
    try {
      return context.read<AutoDownloadGate>();
    } on ProviderNotFoundException {
      return const _AllowAll();
    }
  }
}

class _AllowAll implements AutoDownloadGate {
  const _AllowAll();

  @override
  bool allows({required int chatId, required MediaKind media, required int size}) => true;

  @override
  bool get preloadLargeVideos => false;
}
