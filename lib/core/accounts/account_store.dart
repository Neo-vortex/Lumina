import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../custom_server/custom_server.dart';

/// One signed-in (or signing-in) account: Telegram or a custom server, with
/// its own TDLib folder and database key.
class Account {
  Account({
    required this.id,
    this.server,
    this.legacy = false,
    this.userId,
    this.name,
    this.phone,
    this.username,
  });

  /// Stable local id ("a1b2c3"); names the TDLib folder and the key.
  final String id;

  /// Its server's saved form (CustomServer.toJson); null for Telegram.
  Map<String, Object?>? server;

  /// Created before accounts existed: keeps the old folder and key names
  /// (tdlib/ for Telegram, tdlib-server-<id>/ for a custom server).
  final bool legacy;

  /// Filled once signed in (shown in the account switcher).
  int? userId;
  String? name;
  String? phone;
  String? username;

  bool get signedIn => userId != null;

  CustomServer? get customServer => CustomServer.fromJson(server);

  /// "Telegram" or the custom server's address.
  String get serverLabel => customServer?.address ?? 'Telegram';

  /// Where its TDLib data lives under the support directory.
  String dirName() => legacy
      ? (customServer == null ? 'tdlib' : 'tdlib-server-${customServer!.storageId}')
      : 'tdlib-acct-$id';

  /// The database-key scope (SecureStore) for this account.
  String? get keyScope => legacy ? customServer?.storageId : 'acct-$id';

  Map<String, Object?> toJson() => {
    'id': id,
    'server': server,
    'legacy': legacy,
    'user_id': userId,
    'name': name,
    'phone': phone,
    'username': username,
  };

  static Account fromJson(Map j) => Account(
    id: j['id'] as String,
    server: (j['server'] as Map?)?.cast<String, Object?>(),
    legacy: j['legacy'] == true,
    userId: (j['user_id'] as num?)?.toInt(),
    name: j['name'] as String?,
    phone: j['phone'] as String?,
    username: j['username'] as String?,
  );
}

/// The accounts on this phone and which one is active, in
/// `accounts.json` beside the TDLib folders. Only the active account runs a
/// TDLib client; switching rebuilds the app on another (AppRoot.reload).
///
/// The active account's server is mirrored into custom_server.json, which
/// the sign-in screen's server picker and session restore already write: a
/// fresh account takes whatever server it signs in to.
class AccountStore {
  AccountStore._(this._dir, this.accounts, this.activeId);

  /// The store loaded for the running app (set by prepareTdlib).
  static AccountStore? current;

  /// Restarts TDLib on the (newly) active account (AppRoot.reload).
  static Future<void> Function()? reloadApp;

  final String _dir;
  final List<Account> accounts;
  String activeId;

  static File _file(String dir) => File('$dir/accounts.json');

  Account get active => accounts.firstWhere((a) => a.id == activeId, orElse: () => accounts.first);

  List<Account> get others => [
    for (final a in accounts)
      if (a.id != activeId) a,
  ];

  static String _newId() {
    final r = Random.secure();
    return List.generate(8, (_) => 'abcdefghijklmnopqrstuvwxyz0123456789'[r.nextInt(36)]).join();
  }

  /// Loads the list, or builds it from what's on disk the first time
  /// (Telegram data and the current custom server become accounts).
  static Future<AccountStore> load(String supportDir) async {
    final f = _file(supportDir);
    if (await f.exists()) {
      try {
        final j = jsonDecode(await f.readAsString()) as Map;
        final list = [for (final a in j['accounts'] as List) Account.fromJson(a as Map)];
        if (list.isNotEmpty) return AccountStore._(supportDir, list, j['active'] as String? ?? list.first.id);
      } catch (_) {
        // Unreadable: rebuild from disk below.
      }
    }
    final current = CustomServer.load(supportDir);
    final list = <Account>[];
    final telegramData = Directory('$supportDir/tdlib/db').existsSync();
    if (telegramData || current == null) list.add(Account(id: _newId(), legacy: true));
    if (current != null) list.add(Account(id: _newId(), legacy: true, server: current.toJson()));
    final store = AccountStore._(supportDir, list, current == null ? list.first.id : list.last.id);
    await store.save();
    return store;
  }

  Future<void> save() async {
    final f = _file(_dir);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(
      jsonEncode({
        'active': activeId,
        'accounts': [for (final a in accounts) a.toJson()],
      }),
      flush: true,
    );
    await tmp.rename(f.path);
  }

  /// Makes [id] active and mirrors its server for the next TDLib client.
  Future<void> activate(String id) async {
    activeId = id;
    await CustomServer.save(_dir, active.customServer);
    await save();
  }

  /// A fresh account on Telegram (the sign-in screen can change its
  /// server), made active.
  Future<Account> addNew() async {
    final a = Account(id: _newId());
    accounts.add(a);
    await activate(a.id);
    return a;
  }

  /// The active account's server follows custom_server.json while it hasn't
  /// signed in yet (the sign-in screen's server picker writes that file).
  Future<void> syncPendingServer() async {
    final a = active;
    // Legacy accounts take their folder from the server, which is exactly
    // the old one-server-at-a-time behaviour.
    if (a.signedIn) return;
    final server = CustomServer.load(_dir)?.toJson();
    if (jsonEncode(server) == jsonEncode(a.server)) return;
    a.server = server;
    // A new account's folder doesn't depend on its server, and TDLib keeps
    // the DC list and auth keys it learnt in its database: without a clean
    // start, a switch to a custom server would still talk to Telegram (or
    // back), which rejects the number. Nothing is signed in here yet.
    if (!a.legacy) {
      final dir = Directory('$_dir/${a.dirName()}');
      if (await dir.exists()) await dir.delete(recursive: true).catchError((Object _) => dir);
    }
    await save();
  }

  /// Fills in who the active account is, once signed in.
  Future<void> updateActive({required int userId, String? name, String? phone, String? username}) async {
    final a = active;
    if (a.userId == userId && a.name == name && a.phone == phone && a.username == username) return;
    a
      ..userId = userId
      ..name = name
      ..phone = phone
      ..username = username;
    await save();
  }

  /// Forgets the active account (its data is already wiped) and activates
  /// another; returns it, or null when none is left (a fresh one is made).
  Future<Account?> removeActive() async {
    final gone = active;
    accounts.removeWhere((a) => a.id == gone.id);
    final dir = Directory('$_dir/${gone.dirName()}');
    if (await dir.exists()) await dir.delete(recursive: true).catchError((Object _) => dir);
    if (accounts.isEmpty) {
      await addNew();
      return null;
    }
    final next = accounts.firstWhere((a) => a.signedIn, orElse: () => accounts.first);
    await activate(next.id);
    return next;
  }

  /// Drops a not-yet-signed-in account (abandoned "Add account").
  Future<void> discard(String id) async {
    final a = accounts.where((x) => x.id == id).firstOrNull;
    if (a == null || a.signedIn || accounts.length < 2) return;
    accounts.remove(a);
    final dir = Directory('$_dir/${a.dirName()}');
    if (await dir.exists()) await dir.delete(recursive: true).catchError((Object _) => dir);
    await save();
  }
}
