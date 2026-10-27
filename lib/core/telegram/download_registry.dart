import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

/// Where large downloads are recorded (Downloads screen). Content widgets
/// call [track] when they start a download they know the message of.
abstract interface class DownloadRegistry {
  void track(td.File file, td.Message message);

  static DownloadRegistry of(BuildContext context) {
    try {
      return context.read<DownloadRegistry>();
    } on ProviderNotFoundException {
      return const _None();
    }
  }
}

class _None implements DownloadRegistry {
  const _None();

  @override
  void track(td.File file, td.Message message) {}
}
