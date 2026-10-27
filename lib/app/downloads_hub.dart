import 'dart:async';

import 'package:lumina_tdlib/api.dart' as td;
import 'package:open_filex/open_filex.dart';

import '../core/tdlib/td_client.dart';
import '../features/downloads/bloc/downloads_cubit.dart';
import '../features/downloads/data/download_notifier.dart';
import '../features/downloads/data/download_policy.dart';

/// Ties the Downloads list to the app: loads it once TDLib is logged in
/// (also when it already was), and keeps Wi-Fi-only downloads in step with
/// the network and with new downloads.
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
          _start();
        case td.UpdateFileAddedToDownloads(:final fileDownload):
          policy.onAdded(fileDownload.fileId);
        default:
          break;
      }
    });
    // Ready may have come before this hub existed.
    _checkReady(client);
    // Re-check whenever the set of active downloads or their pause state
    // changes (a new download, a resume), not on every progress tick.
    _list = cubit.stream.listen((s) {
      final key = s.activeStates.map((d) => '${d.id}${d.paused ? 'p' : ''}').join(',');
      if (key == _lastKey) return;
      _lastKey = key;
      _apply();
    });
    policy.network.changes.addListener(_apply);
  }

  final DownloadsCubit cubit;
  final DownloadPolicy policy;
  late final StreamSubscription<td.Update> _auth;
  late final StreamSubscription<DownloadsState> _list;
  late final DownloadNotifier _notifier;
  String? _lastKey;
  var _started = false;

  Future<void> _checkReady(TdClient client) async {
    try {
      final s = await client.invoke<td.AuthorizationState>(const td.GetAuthorizationState());
      if (s is td.AuthorizationStateReady) _start();
    } catch (_) {
      // Not running yet: the Ready update will come.
    }
  }

  void _start() {
    if (_started) return;
    _started = true;
    cubit.start().ignore();
  }

  void _apply() => policy.apply(cubit.state.activeStates).ignore();

  void dispose() {
    _notifier.dispose();
    _auth.cancel();
    _list.cancel();
    policy.network.changes.removeListener(_apply);
    policy.dispose();
  }
}
