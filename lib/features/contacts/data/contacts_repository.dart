import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../core/tdlib/td_client.dart';
import '../../../core/telegram/telegram_cache.dart';

/// What adding someone by phone number found.
sealed class PhoneLookup {
  const PhoneLookup();
}

/// They're on Telegram and now in your contacts.
final class PhoneFound extends PhoneLookup {
  const PhoneFound(this.userId);
  final int userId;
}

/// Nobody on Telegram uses that number (yet).
final class PhoneNotOnTelegram extends PhoneLookup {
  const PhoneNotOnTelegram();
}

/// Your Telegram contacts: the list (kept fresh as people are added,
/// renamed or removed anywhere in the app) and every contact action.
class ContactsRepository extends ChangeNotifier {
  ContactsRepository({required TdClient client, required TelegramCache cache})
    : _client = client,
      _cache = cache {
    _subscription = client.updates.listen(_apply);
  }

  final TdClient _client;
  final TelegramCache _cache;
  late final StreamSubscription<td.Update> _subscription;

  List<int>? _ids;
  var _loading = false;

  /// Contact user ids, A→Z; null until first [load].
  List<int>? get ids => _ids;

  void _apply(td.Update u) {
    // Adding, renaming or removing a contact flips User.isContact or changes
    // the name: refresh when it concerns the list.
    if (u case td.UpdateUser(:final user)) {
      final listed = _ids?.contains(user.id) ?? false;
      if (user.isContact != listed) {
        load().ignore();
      } else if (listed) {
        _sort();
        notifyListeners();
      }
    }
  }

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    try {
      _ids = (await _client.invoke<td.Users>(const td.GetContacts())).userIds;
      _sort();
      notifyListeners();
    } on Object {
      // Bots have no contacts.
      _ids ??= const [];
      notifyListeners();
    } finally {
      _loading = false;
    }
  }

  void _sort() {
    final ids = _ids;
    if (ids == null) return;
    String key(int id) {
      final u = _cache.users[id];
      return '${u?.firstName ?? ''} ${u?.lastName ?? ''}'.trim().toLowerCase();
    }

    _ids = [...ids]..sort((a, b) => key(a).compareTo(key(b)));
  }

  Future<List<int>> search(String query) async =>
      (await _client.invoke<td.Users>(td.SearchContacts(query: query, limit: 100))).userIds;

  /// A public @username, for adding people who aren't contacts yet.
  Future<int?> findUsername(String username) async {
    try {
      final chat = await _client.invoke<td.Chat>(
        td.SearchPublicChat(username: username.replaceFirst('@', '')),
      );
      return switch (chat.type) {
        td.ChatTypePrivate(:final userId) => userId,
        _ => null,
      };
    } on Object {
      return null;
    }
  }

  /// Adds [userId] or renames them. Works without a phone number (their
  /// number may be hidden): Telegram keeps the contact by account.
  /// [sharePhone] lets them see your number too.
  Future<void> save(
    int userId, {
    required String firstName,
    String lastName = '',
    bool sharePhone = false,
  }) async {
    final user = _cache.users[userId];
    await _client.invoke<td.Ok>(
      td.AddContact(
        userId: userId,
        contact: td.ImportedContact(
          phoneNumber: user?.phoneNumber ?? '',
          firstName: firstName,
          lastName: lastName,
        ),
        sharePhoneNumber: sharePhone,
      ),
    );
    await load();
  }

  /// Adds whoever uses [phone] on Telegram, saved as [firstName] [lastName].
  Future<PhoneLookup> addByPhone(String phone, {required String firstName, String lastName = ''}) async {
    final r = await _client.invoke<td.ImportedContacts>(
      td.ImportContacts(
        contacts: [td.ImportedContact(phoneNumber: phone, firstName: firstName, lastName: lastName)],
      ),
    );
    final id = r.userIds.isEmpty ? 0 : r.userIds.first;
    if (id == 0) return const PhoneNotOnTelegram();
    await load();
    return PhoneFound(id);
  }

  Future<void> delete(Iterable<int> userIds) async {
    await _client.invoke<td.Ok>(td.RemoveContacts(userIds: userIds.toList()));
    _ids = [
      for (final id in _ids ?? const <int>[])
        if (!userIds.contains(id)) id,
    ];
    notifyListeners();
  }

  /// Sends [userId] as a contact card into [chatId]; recipients can open or
  /// add them even when the phone number is hidden.
  Future<void> shareTo(int chatId, int userId) {
    final user = _cache.users[userId];
    return _client.invoke<td.Message>(
      td.SendMessage(
        chatId: chatId,
        inputMessageContent: td.InputMessageContact(
          contact: td.Contact(
            phoneNumber: user?.phoneNumber ?? '',
            firstName: user?.firstName ?? '',
            lastName: user?.lastName ?? '',
            vcard: '',
            userId: userId,
          ),
        ),
      ),
    );
  }

  /// t.me link for [userId] (by username) or the in-app tg:// link.
  String linkOf(int userId) {
    final name = _cache.users[userId]?.usernames?.activeUsernames.firstOrNull;
    return name == null || name.isEmpty ? 'tg://user?id=$userId' : 'https://t.me/$name';
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
