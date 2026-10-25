import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lumina_tdlib/api.dart' as td;
import 'package:intl/intl.dart';

import '../theme/glow_colors.dart';
import 'telegram_cache.dart';

/// Human-facing text for TDLib entities, shared by every feature.
abstract final class Display {
  static String userName(td.User? user) {
    if (user == null) return 'Unknown';
    if (user.type is td.UserTypeDeleted) return 'Deleted account';
    final name = [user.firstName, user.lastName].where((s) => s.isNotEmpty).join(' ');
    return name.isEmpty ? 'Unknown' : name;
  }

  static String senderName(TelegramCache cache, td.MessageSender sender) => switch (sender) {
    td.MessageSenderUser(:final userId) => userName(cache.users[userId]),
    td.MessageSenderChat(:final chatId) => cache.chats[chatId]?.title ?? 'Chat',
  };

  static int senderId(td.MessageSender sender) => switch (sender) {
    td.MessageSenderUser(:final userId) => userId,
    td.MessageSenderChat(:final chatId) => chatId,
  };

  static String initials(String title) {
    final parts = title.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    final first = parts.first.characters.first;
    final second = parts.length > 1 ? parts[1].characters.first : '';
    return (first + second).toUpperCase();
  }

  /// Stable accent per id, from the app palette (not Telegram's).
  static Color accentFor(int id) {
    const palette = [
      GlowColors.cyan,
      GlowColors.violet,
      GlowColors.amber,
      GlowColors.coral,
      GlowColors.teal,
      GlowColors.magenta,
    ];
    return palette[id.abs() % palette.length];
  }

  static Uint8List? minithumbnail(td.Minithumbnail? m) => m == null ? null : base64Decode(m.data);

  /// "online", "last seen 14:02", "last seen recently"…
  static String status(td.User? user, {DateTime? now}) {
    if (user == null) return '';
    if (user.type is td.UserTypeBot) return 'bot';
    now ??= DateTime.now();
    return switch (user.status) {
      td.UserStatusOnline() => 'online',
      td.UserStatusOffline(:final wasOnline) => 'last seen ${relativeTime(_date(wasOnline), now)}',
      td.UserStatusRecently() => 'last seen recently',
      td.UserStatusLastWeek() => 'last seen within a week',
      td.UserStatusLastMonth() => 'last seen within a month',
      _ => 'last seen a long time ago',
    };
  }

  static DateTime _date(int unixSeconds) => DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);

  static DateTime messageDate(td.Message m) => _date(m.date);

  static String relativeTime(DateTime t, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    final diff = today.difference(day).inDays;
    final time = DateFormat.Hm().format(t);
    if (diff == 0) return 'at $time';
    if (diff == 1) return 'yesterday at $time';
    return 'on ${DateFormat.MMMd().format(t)}';
  }

  /// Time shown in chat list rows: time today, weekday this week, else date.
  static String listTime(DateTime t, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(DateTime(t.year, t.month, t.day)).inDays;
    if (diff == 0) return DateFormat.Hm().format(t);
    if (diff < 7) return DateFormat.E().format(t);
    if (t.year == now.year) return DateFormat.MMMd().format(t);
    return DateFormat.yMd().format(t);
  }

  /// Date header in a conversation: "Today", "Yesterday", "March 3".
  static String dayHeader(DateTime t, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(DateTime(t.year, t.month, t.day)).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (t.year == now.year) return DateFormat.MMMMd().format(t);
    return DateFormat.yMMMMd().format(t);
  }

  static String duration(int seconds) {
    final d = Duration(seconds: seconds);
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '${d.inMinutes}:$s';
  }

  static String fileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }

  /// One-line summary of a message for chat list rows, replies and banners.
  static String preview(TelegramCache cache, td.Message? m) {
    if (m == null) return '';
    String withCaption(String label, td.FormattedText caption) =>
        caption.text.isEmpty ? label : '$label · ${caption.text}';
    return switch (m.content) {
      td.MessageText(:final text) => text.text,
      td.MessagePhoto(:final caption) => withCaption('Photo', caption),
      td.MessageVideo(:final caption) => withCaption('Video', caption),
      td.MessageAnimation(:final caption) => withCaption('GIF', caption),
      td.MessageDocument(:final document, :final caption) => withCaption(document.fileName, caption),
      td.MessageAudio(:final audio, :final caption) => withCaption(
        audio.title.isEmpty ? audio.fileName : audio.title,
        caption,
      ),
      td.MessageVoiceNote(:final voiceNote) => 'Voice message · ${duration(voiceNote.duration)}',
      td.MessageVideoNote(:final videoNote) => 'Video message · ${duration(videoNote.duration)}',
      td.MessageSticker(:final sticker) => '${sticker.emoji} Sticker',
      td.MessageAnimatedEmoji(:final emoji) => emoji,
      td.MessageDice(:final emoji) => emoji,
      td.MessagePoll() => 'Poll',
      td.MessageContact(:final contact) => 'Contact · ${contact.firstName} ${contact.lastName}'.trim(),
      td.MessageLocation() => 'Location',
      td.MessageLiveLocation() => 'Live location',
      td.MessageVenue() => 'Venue',
      td.MessageCall(:final isVideo) => isVideo ? 'Video call' : 'Call',
      td.MessageExpiredPhoto() => 'Photo expired',
      td.MessageExpiredVideo() => 'Video expired',
      td.MessageExpiredVoiceNote() => 'Voice message expired',
      td.MessageExpiredVideoNote() => 'Video message expired',
      _ => serviceText(cache, m) ?? 'Unsupported message',
    };
  }

  /// Text for service messages ("Ada joined the group"), or null if [m] is
  /// a regular message.
  static String? serviceText(TelegramCache cache, td.Message m) {
    final who = senderName(cache, m.senderId);
    return switch (m.content) {
      td.MessageBasicGroupChatCreate(:final title) => '$who created the group "$title"',
      td.MessageSupergroupChatCreate(:final title) =>
        cache.chats[m.chatId] != null && cache.isChannel(cache.chats[m.chatId]!)
            ? 'Channel "$title" created'
            : '$who created the group "$title"',
      td.MessageChatChangeTitle(:final title) => '$who changed the title to "$title"',
      td.MessageChatChangePhoto() => '$who changed the photo',
      td.MessageChatDeletePhoto() => '$who removed the photo',
      td.MessageChatAddMembers(:final memberUserIds) =>
        memberUserIds.length == 1 &&
                m.senderId is td.MessageSenderUser &&
                (m.senderId as td.MessageSenderUser).userId == memberUserIds.first
            ? '$who joined'
            : '$who added ${memberUserIds.map((id) => userName(cache.users[id])).join(', ')}',
      td.MessageChatJoinByLink() => '$who joined via invite link',
      td.MessageChatJoinByRequest() => '$who was accepted',
      td.MessageChatDeleteMember(:final userId) =>
        m.senderId is td.MessageSenderUser && (m.senderId as td.MessageSenderUser).userId == userId
            ? '$who left'
            : '$who removed ${userName(cache.users[userId])}',
      td.MessagePinMessage() => '$who pinned a message',
      td.MessageScreenshotTaken() => '$who took a screenshot',
      td.MessageChatUpgradeTo() || td.MessageChatUpgradeFrom() => 'Group upgraded to supergroup',
      td.MessageChatSetMessageAutoDeleteTime(:final messageAutoDeleteTime) =>
        messageAutoDeleteTime == 0 ? '$who disabled auto-delete' : '$who set messages to auto-delete',
      td.MessageContactRegistered() => '$who joined Telegram',
      td.MessageCustomServiceAction(:final text) => text,
      td.MessageVideoChatStarted() => 'Video chat started',
      td.MessageVideoChatEnded() => 'Video chat ended',
      td.MessageGameScore(:final score) => '$who scored $score',
      _ => null,
    };
  }

  static bool isService(td.Message m) => switch (m.content) {
    td.MessageText() || td.MessagePhoto() || td.MessageVideo() || td.MessageAnimation() => false,
    td.MessageDocument() || td.MessageAudio() || td.MessageVoiceNote() || td.MessageVideoNote() => false,
    td.MessageSticker() || td.MessageAnimatedEmoji() || td.MessageDice() || td.MessagePoll() => false,
    td.MessageContact() || td.MessageLocation() || td.MessageLiveLocation() => false,
    td.MessageVenue() || td.MessageCall() => false,
    td.MessageExpiredPhoto() || td.MessageExpiredVideo() => false,
    td.MessageExpiredVoiceNote() || td.MessageExpiredVideoNote() => false,
    td.MessageUnsupported() || td.MessageGame() || td.MessageInvoice() || td.MessageStory() => false,
    td.MessagePaidMedia() => false,
    _ => true,
  };
}
