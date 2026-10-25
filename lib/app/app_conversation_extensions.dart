import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:handy_tdlib_next/api.dart' as td;

import '../core/media/ffmpeg_service.dart';
import '../features/auth/bloc/auth_bloc.dart';
import '../features/auth/domain/auth_step.dart';
import '../features/conversation/bloc/conversation_cubit.dart';
import '../features/conversation/data/messages_repository.dart';
import '../features/conversation/presentation/widgets/conversation_extensions.dart';
import '../features/media/presentation/screens/send_media_screen.dart';
import '../features/media/presentation/widgets/attach_sheet.dart';

/// The app's implementation of the conversation hooks: wires media,
/// voice, dictation, AI actions and chat info into the conversation screen.
class AppConversationExtensions extends ConversationExtensions {
  const AppConversationExtensions();

  @override
  void onAttach(BuildContext context, td.Chat chat) => _attach(context, chat);

  Future<void> _attach(BuildContext context, td.Chat chat) async {
    final cubit = context.read<ConversationCubit>();
    final messages = context.read<MessagesRepository>();
    final paths = await pickAttachments(context, context.read<FfmpegService>());
    if (paths.isEmpty || !context.mounted) return;
    final isBot = switch (context.read<AuthBloc>().state.step) {
      AuthReady(:final capabilities) => capabilities.isBot,
      _ => false,
    };
    final request = await SendMediaScreen.open(
      context,
      paths: paths,
      allowViewOnce: !isBot && chat.type is td.ChatTypePrivate,
      parseCaption: messages.parseMarkdown,
    );
    if (request == null) return;
    final error = request.asAlbum
        ? await cubit.sendAlbum(request.contents)
        : await _sendEach(cubit, request.contents);
    if (error != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  static Future<String?> _sendEach(ConversationCubit cubit, List<td.InputMessageContent> contents) async {
    for (final c in contents) {
      final error = await cubit.sendContent(c);
      if (error != null) return error;
    }
    return null;
  }
}
