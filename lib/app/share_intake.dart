import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../core/media/ui_sounds.dart';
import '../core/telegram/permissions.dart';
import '../core/telegram/telegram_cache.dart';
import '../core/telegram/widgets/chat_avatar.dart';
import '../core/theme/glow_colors.dart';
import '../core/widgets/glow_sheet.dart';
import '../features/auth/bloc/auth_bloc.dart';
import '../features/auth/domain/auth_step.dart';
import '../features/conversation/data/messages_repository.dart';
import '../features/conversation/presentation/screens/conversation_screen.dart';
import '../features/media/presentation/screens/send_media_screen.dart';
import 'feature_wiring.dart' show appNavigatorKey;

typedef SharedFile = ({String path, String name, String mime});

/// Something shared to Lumina from Android's share sheet: once signed in,
/// pick the chat, then the chat opens with it. Text lands in the composer
/// (to edit before sending); photos, videos and files go through the usual
/// send screen (caption, album or files, quality).
Future<void> receiveShare(String text, List<SharedFile> files) async {
  final context = await _readyContext();
  if (context == null || !context.mounted) return;
  final chatId = await _pickChat(context, text, files);
  if (chatId == null || !context.mounted) return;
  final navigator = Navigator.of(context);
  final messages = context.read<MessagesRepository>();
  if (text.trim().isNotEmpty) {
    // The composer opens with it, ready to edit and send.
    await messages.saveDraft(chatId, text).catchError((Object _) {});
  }
  navigator.push(ConversationScreen.route(chatId)).ignore();
  if (files.isEmpty || !context.mounted) return;
  final cache = context.read<TelegramCache>();
  final media = files.every((f) => f.mime.startsWith('image/') || f.mime.startsWith('video/'));
  final request = await SendMediaScreen.open(
    context,
    paths: [for (final f in files) f.path],
    asFiles: !media,
    music: files.every((f) => f.mime.startsWith('audio/')),
    allowViewOnce: cache.chats[chatId]?.type is td.ChatTypePrivate,
    parseCaption: messages.parseMarkdown,
  );
  if (request == null) return;
  try {
    if (request.asAlbum) {
      await messages.sendAlbum(chatId, request.contents, options: request.options);
    } else {
      for (final c in request.contents) {
        await messages.sendContent(chatId, c, options: request.options);
      }
    }
    UiSounds.sent().ignore();
  } catch (e) {
    final c = appNavigatorKey.currentContext;
    if (c != null && c.mounted) {
      ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text("Couldn't send: $e")));
    }
  }
}

/// The app's navigator once it exists and the account is signed in (a share
/// can arrive while Lumina is still starting).
Future<BuildContext?> _readyContext() async {
  for (var i = 0; i < 100 && appNavigatorKey.currentContext == null; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  final context = appNavigatorKey.currentContext;
  if (context == null || !context.mounted) return null;
  final auth = context.read<AuthBloc>();
  if (auth.state.step is! AuthReady) {
    try {
      await auth.stream.firstWhere((s) => s.step is AuthReady).timeout(const Duration(minutes: 2));
    } catch (_) {
      return null;
    }
  }
  // Let the home screen settle under the sheet.
  await Future<void>.delayed(const Duration(milliseconds: 300));
  return appNavigatorKey.currentContext;
}

Future<int?> _pickChat(BuildContext context, String text, List<SharedFile> files) {
  final cache = context.read<TelegramCache>();
  final all = cache.chatsIn(const td.ChatListMain()).where((c) => cache.canPost(c)).toList();
  final what = [
    if (files.isNotEmpty)
      files.length == 1 ? files.first.name : '${files.length} files',
    if (text.trim().isNotEmpty) text.trim().replaceAll('\n', ' '),
  ].join(' · ');
  var query = '';
  return showGlowSheet<int>(
    context,
    title: 'Share to…',
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final q = query.toLowerCase();
        final chats = q.isEmpty ? all : all.where((c) => c.title.toLowerCase().contains(q)).toList();
        return SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.65,
          child: Column(
            children: [
              if (what.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    children: [
                      Icon(
                        files.isEmpty ? Icons.notes_rounded : Icons.attach_file_rounded,
                        size: 18,
                        color: GlowColors.textMuted,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          what,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: GlowColors.textMuted),
                        ),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search'),
                  onChanged: (v) => setState(() => query = v.trim()),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: chats.length,
                  itemBuilder: (context, i) => ListTile(
                    leading: ChatAvatar.chat(chats[i], size: 40),
                    title: Text(chats[i].title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => Navigator.pop(context, chats[i].id),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}
