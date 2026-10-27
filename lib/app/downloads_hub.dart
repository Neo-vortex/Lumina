import 'dart:async';

import 'package:lumina_tdlib/api.dart' as td;
import 'package:open_filex/open_filex.dart';

import '../core/tdlib/td_client.dart';
import '../features/downloads/bloc/downloads_cubit.dart';
import '../features/downloads/data/download_notifier.dart';
import '../features/downloads/data/download_policy.dart';

/// Ties the Downloads list to the app: loads it once TDLib is logged in and
/// keeps Wi-Fi-only downloads in step with the network.
class DownloadsHub {
  DownloadsHub({
    required TdClient client,
    required this.cubit,
    required this.policy,
    DownloadsChannel? channel,
  }) {
    _notifier = DownloadNotifier(
      cubit: cubit,
      channel: channel ?? MethodDownloadsChannel(),
      screenVisible: () => cubit.screenVisible,
      openFile: (path) => OpenFilex.open(path).ignore(),
    );
    _auth = client.updates.listen((u) {
      switch (u) {
        case td.UpdateAuthorizationState(authorizationState: td.AuthorizationStateReady()):
          cubit.start().then((_) => _apply()).ignore();
        case td.UpdateFileAddedToDownloads(:final fileDownload):
          policy.onAdded(fileDownload.fileId);
          _apply();
        default:
          break;
      }
    });
    policy.network.changes.addListener(_apply);
  }

  final DownloadsCubit cubit;
  final DownloadPolicy policy;
  late final StreamSubscription<td.Update> _auth;
  late final DownloadNotifier _notifier;

  void _apply() => policy.apply(cubit.state.active.map((i) => i.fileId)).ignore();

  void dispose() {
    _notifier.dispose();
    _auth.cancel();
    policy.network.changes.removeListener(_apply);
    policy.dispose();
  }
}
