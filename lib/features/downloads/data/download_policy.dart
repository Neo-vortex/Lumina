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
/// resumed on Wi-Fi. Only downloads Lumina paused itself are resumed (they
/// are remembered across restarts); anything already paused when Lumina
/// looks (the user, Pause all) is left alone.
class DownloadPolicy {
  DownloadPolicy({required DownloadsRepository repository, required this._prefs, required this.network})
    : _repo = repository;

  final DownloadsRepository _repo;
  final AppPreferences _prefs;
  final NetworkWatch network;
  final _changes = _Changes();

  Listenable get changes => _changes;

  bool isWifiOnly(int fileId) => _prefs.downloadsWifiOnly.contains(fileId);

  bool isWaitingForWifi(int fileId) => _prefs.downloadsWaiting.contains(fileId);

  Future<void> setWifiOnly(int fileId, bool on) async {
    final ids = _prefs.downloadsWifiOnly;
    on ? ids.add(fileId) : ids.remove(fileId);
    _prefs.setDownloadsWifiOnly(ids);
    if (!on) _setWaiting(fileId, false);
    _notify();
  }

  /// A new download takes the default from Settings.
  void onAdded(int fileId) {
    if (_prefs.downloadsWifiOnlyDefault && !isWifiOnly(fileId)) setWifiOnly(fileId, true);
  }

  /// The user paused a waiting download: it now stays paused on Wi-Fi too.
  void userPaused(int fileId) {
    _setWaiting(fileId, false);
    _notify();
  }

  /// The user resumed a Wi-Fi-only download by hand: it may use mobile data.
  Future<void> userResumed(int fileId) async {
    if (isWifiOnly(fileId)) await setWifiOnly(fileId, false);
  }

  void _setWaiting(int fileId, bool waiting) {
    final ids = _prefs.downloadsWaiting;
    if (waiting ? ids.add(fileId) : ids.remove(fileId)) _prefs.setDownloadsWaiting(ids);
  }

  /// Pauses or resumes the Wi-Fi-only downloads among [active] (with
  /// TDLib's paused state) for the current network.
  Future<void> apply(Iterable<({int id, bool paused})> active) async {
    final flagged = _prefs.downloadsWifiOnly;
    final waiting = _prefs.downloadsWaiting;
    for (final d in active) {
      if (!network.onWifi) {
        if (flagged.contains(d.id) && !d.paused && !waiting.contains(d.id)) {
          _setWaiting(d.id, true);
          await _repo.setPaused(d.id, true);
          _notify();
        }
      } else if (waiting.contains(d.id)) {
        _setWaiting(d.id, false);
        await _repo.setPaused(d.id, false);
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
