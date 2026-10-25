import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:handy_tdlib_next/api.dart' as td;

import 'message_menu.dart';
import 'send_orb.dart';

/// Hooks other features plug into the conversation screen (attachments,
/// voice, dictation, AI actions, chat info) so this feature does not depend
/// on them. The app's composition root provides the implementation.
class ConversationExtensions {
  const ConversationExtensions();

  static ConversationExtensions of(BuildContext context) {
    try {
      return context.read<ConversationExtensions>();
    } on ProviderNotFoundException {
      return const ConversationExtensions();
    }
  }

  /// Changes that should rebuild the composer (recording started, …).
  Listenable get composerListenable => const _NeverChanges();

  List<ExtraMenuEntry> menuEntries(td.Message message) => const [];

  Future<void> onMenuAction(BuildContext context, MessageAction action, td.Message message) async {}

  void openChatInfo(BuildContext context, td.Chat chat) {}

  void onAttach(BuildContext context, td.Chat chat) {}

  void onVoice(BuildContext context, td.Chat chat, TextEditingController text) {}

  void onDictate(BuildContext context, td.Chat chat, TextEditingController text) {}

  Widget? recordingOverlay(BuildContext context, td.Chat chat) => null;

  OrbMode? orbMode(BuildContext context, td.Chat chat) => null;

  /// Extra UI under a voice message (e.g. "Transcribe" and the transcript).
  Widget? voiceAccessory(BuildContext context, td.Message message) => null;
}

class _NeverChanges implements Listenable {
  const _NeverChanges();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
