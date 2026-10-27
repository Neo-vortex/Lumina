import 'package:flutter/foundation.dart';

import '../../../core/storage/app_preferences.dart';
import '../../auto_download/data/auto_download_service.dart';
import '../../auto_download/domain/auto_download_policy.dart';
import 'downloads_repository.dart';

/// Whether the phone is on Wi-Fi, and when that changes.
abstract interface class NetworkWatch {
  bool get onWifi;
  Listenable get changes;
}

/// [NetworkWatch] over auto-download's network tracking.
class AutoDownloadNetworkWatch implements NetworkWatch {
  AutoDownloadNetworkWatch(this._service);

  final AutoDownloadService _service;

  @override
  bool get onWifi => _service.network == NetworkKind.wifi;

  @override
  Listenable get changes => _service.changes;
}

/// Wi-Fi-only downloads: paused by Lumina off Wi-Fi ("Waiting for Wi-Fi"),
/// resumed on Wi-Fi. A pause the user made is never undone here.
class DownloadPolicy {
  DownloadPolicy({required DownloadsRepository repository, required this._prefs, required this.network})
    : _repo = repository;

  final DownloadsRepository _repo;
  final AppPreferences _prefs;
  final NetworkWatch network;
  final _waiting = <int>{};
  final _userPaused = <int>{};
  final _changes = _Changes();

  Listenable get changes => _changes;

  bool isWifiOnly(int fileId) => _prefs.downloadsWifiOnly.contains(fileId);

  bool isWaitingForWifi(int fileId) => _waiting.contains(fileId);

  Future<void> setWifiOnly(int fileId, bool on) async {
    final ids = _prefs.downloadsWifiOnly;
    on ? ids.add(fileId) : ids.remove(fileId);
    _prefs.setDownloadsWifiOnly(ids);
    _notify();
  }

  /// A new download takes the default from Settings.
  void onAdded(int fileId) {
    if (_prefs.downloadsWifiOnlyDefault && !isWifiOnly(fileId)) setWifiOnly(fileId, true);
  }

  void userPaused(int fileId, bool paused) {
    paused ? _userPaused.add(fileId) : _userPaused.remove(fileId);
    if (paused) _waiting.remove(fileId);
  }

  /// Pauses or resumes the Wi-Fi-only downloads among [activeFileIds] for
  /// the current network. Only files whose waiting state changes are touched.
  Future<void> apply(Iterable<int> activeFileIds) async {
    final flagged = _prefs.downloadsWifiOnly;
    for (final id in activeFileIds) {
      if (!flagged.contains(id) || _userPaused.contains(id)) continue;
      if (!network.onWifi && _waiting.add(id)) {
        await _repo.setPaused(id, true);
        _notify();
      } else if (network.onWifi && _waiting.remove(id)) {
        await _repo.setPaused(id, false);
        _notify();
      }
    }
  }

  void _notify() => _changes.ping();

  void dispose() => _changes.dispose();
}

class _Changes extends ChangeNotifier {
  void ping() => notifyListeners();
}
