import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:handy_tdlib_next/api.dart' as td;

import '../../../core/tdlib/td_client.dart';
import '../../../core/telegram/display.dart';
import '../../../core/telegram/telegram_cache.dart';

/// Where notifications go (Android, or a fake in tests).
abstract interface class NotificationSink {
  Future<void> show(Map<String, Object?> notification);
  Future<void> cancel(int id);
  Future<void> cancelAll();

  /// reply {chatId, groupId, text}, read {chatId, groupId}, open {chatId}.
  Stream<Map<Object?, Object?>> get actions;
}

/// "dev.lumina/notifications" (MessageNotifications.kt).
class ChannelNotificationSink implements NotificationSink {
  static const _methods = MethodChannel('dev.lumina/notifications');
  static const _events = EventChannel('dev.lumina/notifications/events');

  Future<void> _call(String method, [Object? args]) async {
    try {
      await _methods.invokeMethod<void>(method, args);
    } on MissingPluginException {
      // Tests / platforms without the channel.
    }
  }

  @override
  Future<void> show(Map<String, Object?> notification) => _call('show', notification);

  @override
  Future<void> cancel(int id) => _call('cancel', id);

  @override
  Future<void> cancelAll() => _call('cancelAll');

  @override
  late final Stream<Map<Object?, Object?>> actions = _events
      .receiveBroadcastStream()
      .cast<Map<Object?, Object?>>();

  /// connected, saver or off (Settings → Background).
  static Future<String> backgroundMode() async {
    try {
      return await _methods.invokeMethod<String>('backgroundMode') ?? 'connected';
    } on MissingPluginException {
      return 'connected';
    }
  }

  static Future<void> setBackgroundMode(String mode) async {
    try {
      await _methods.invokeMethod<void>('setBackgroundMode', mode);
    } on MissingPluginException {
      // Tests.
    }
  }
}

/// Message notifications from TDLib's notification API (so they're grouped,
/// updated and cleared exactly as on official clients), shown through the
/// [NotificationSink]. Nothing is posted while Lumina is in the foreground.
/// Reply and Mark as read work from the notification, also after a cold
/// start (the background worker boots the engine).
class NotificationCenter with WidgetsBindingObserver {
  NotificationCenter({
    required this._client,
    required this._cache,
    required this._sink,
    this._openChat,
    this._foreground,
  }) {
    _subs = [_client.updates.listen(_onUpdate), _sink.actions.listen(_onAction, onError: (_) {})];
    if (_foreground == null) {
      WidgetsBinding.instance.addObserver(this);
      _resumed = WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    }
  }

  final TdClient _client;
  final TelegramCache _cache;
  final NotificationSink _sink;
  final void Function(int chatId)? _openChat;
  final bool Function()? _foreground;
  late final List<StreamSubscription<Object?>> _subs;
  var _resumed = false;

  /// TDLib group id → its chat and current notifications (oldest first).
  final _groups = <int, ({int chatId, td.NotificationGroupType type, List<td.Notification> items})>{};

  bool get _inForeground => _foreground?.call() ?? _resumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
  }

  void _onUpdate(td.Update u) {
    switch (u) {
      case td.UpdateAuthorizationState(authorizationState: td.AuthorizationStateReady()):
        // TDLib keeps no notification groups unless asked to.
        _option('notification_group_count_max', 25);
        _option('notification_group_size_max', 10);
      case td.UpdateAuthorizationState(authorizationState: td.AuthorizationStateClosed()):
        _groups.clear();
        _sink.cancelAll().ignore();
      case td.UpdateActiveNotifications(:final groups):
        for (final g in groups) {
          _groups[g.id] = (chatId: g.chatId, type: g.type, items: [...g.notifications]);
        }
      case td.UpdateNotificationGroup(
        :final notificationGroupId,
        :final type,
        :final chatId,
        :final addedNotifications,
        :final removedNotificationIds,
      ):
        final items = [...?_groups[notificationGroupId]?.items]
          ..removeWhere((n) => removedNotificationIds.contains(n.id))
          ..addAll(addedNotifications);
        if (items.isEmpty) {
          _groups.remove(notificationGroupId);
          _sink.cancel(notificationGroupId).ignore();
          return;
        }
        _groups[notificationGroupId] = (chatId: chatId, type: type, items: items);
        if (addedNotifications.isNotEmpty) {
          _post(notificationGroupId, alert: addedNotifications.any((n) => !n.isSilent));
        } else if (removedNotificationIds.isNotEmpty) {
          _post(notificationGroupId, alert: false);
        }
      case td.UpdateNotification(:final notificationGroupId, :final notification):
        final g = _groups[notificationGroupId];
        if (g == null) return;
        final i = g.items.indexWhere((n) => n.id == notification.id);
        if (i >= 0) g.items[i] = notification;
        _post(notificationGroupId, alert: false);
      default:
    }
  }

  void _option(String name, int value) => _client
      .invoke<td.Ok>(
        td.SetOption(
          name: name,
          value: td.OptionValueInteger(value: value),
        ),
      )
      .ignore();

  void _post(int groupId, {required bool alert}) {
    final g = _groups[groupId];
    if (g == null || _inForeground) return;
    if (g.type is td.NotificationGroupTypeCalls) return; // Calls ring on their own.
    final payload = notificationPayload(groupId, g.chatId, g.items, _cache, alert: alert);
    if (payload != null) _sink.show(payload).ignore();
  }

  Future<void> _onAction(Map<Object?, Object?> a) async {
    final chatId = (a['chatId'] as num?)?.toInt();
    if (chatId == null) return;
    switch (a['type']) {
      case 'reply':
        final text = a['text'] as String? ?? '';
        if (text.trim().isEmpty) return;
        await _client.invoke<td.Message>(
          td.SendMessage(
            chatId: chatId,
            messageThreadId: 0,
            inputMessageContent: td.InputMessageText(
              text: td.FormattedText(text: text.trim(), entities: const []),
              clearDraft: false,
            ),
          ),
        );
        await _markRead(chatId, (a['groupId'] as num?)?.toInt());
      case 'read':
        await _markRead(chatId, (a['groupId'] as num?)?.toInt());
      case 'open':
        _openChat?.call(chatId);
    }
  }

  /// Marks what the notification showed as read (the newest message is
  /// enough; TDLib marks everything before it).
  Future<void> _markRead(int chatId, int? groupId) async {
    var newest = 0;
    for (final n in _groups[groupId]?.items ?? const <td.Notification>[]) {
      if (n.type case td.NotificationTypeNewMessage(:final message) when message.id > newest) {
        newest = message.id;
      }
    }
    if (newest == 0) {
      try {
        final chat = await _client.invoke<td.Chat>(td.GetChat(chatId: chatId));
        newest = chat.lastMessage?.id ?? 0;
      } catch (_) {
        return;
      }
    }
    if (newest == 0) return;
    try {
      await _client.invoke<td.Ok>(td.ViewMessages(chatId: chatId, messageIds: [newest], forceRead: true));
    } catch (_) {}
  }

  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    if (_foreground == null) WidgetsBinding.instance.removeObserver(this);
  }
}

/// What MessageNotifications.kt shows for one TDLib group, or null when it
/// has no message to show.
Map<String, Object?>? notificationPayload(
  int groupId,
  int chatId,
  List<td.Notification> items,
  TelegramCache cache, {
  required bool alert,
}) {
  final chat = cache.chats[chatId];
  final messages = <Map<String, Object?>>[];
  var silent = true;
  for (final n in items) {
    if (n.type case td.NotificationTypeNewMessage(:final message, :final showPreview)) {
      messages.add({
        'sender': message.isOutgoing ? 'You' : Display.senderName(cache, message.senderId),
        'text': showPreview ? Display.preview(cache, message) : 'New message',
        'date': message.date * 1000,
        'outgoing': message.isOutgoing,
      });
      if (!n.isSilent) silent = false;
    }
  }
  if (messages.isEmpty) return null;
  final type = chat?.type;
  final isGroup = type is td.ChatTypeBasicGroup || (type is td.ChatTypeSupergroup && !type.isChannel);
  return {
    'id': groupId,
    'chatId': chatId,
    'title': chat?.title ?? 'Lumina',
    'isGroup': isGroup,
    'silent': silent,
    'alert': alert,
    'messages': messages,
  };
}
