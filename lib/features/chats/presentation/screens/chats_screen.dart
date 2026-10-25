import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:handy_tdlib_next/api.dart' as td;

import '../../../../core/telegram/telegram_cache.dart';
import '../../../../core/telegram/widgets/connection_status.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../../../core/widgets/luminous_refresh.dart';
import '../../../auth/bloc/auth_bloc.dart';
import '../../../auth/domain/auth_step.dart';
import '../../../conversation/presentation/screens/conversation_screen.dart';
import '../../../home/presentation/widgets/bot_limitations_card.dart';
import '../../bloc/chat_list_cubit.dart';
import '../../data/chats_repository.dart';
import '../widgets/chat_actions_sheet.dart';
import '../widgets/timeline_chat_row.dart';

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  final _search = TextEditingController();
  var _searching = false;
  var _botNoticeDismissed = false;
  List<td.Chat>? _results;
  Timer? _debounce;

  @override
  void dispose() {
    _search.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onQuery(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      final results = await context.read<ChatsRepository>().search(q);
      if (mounted && _search.text == q) setState(() => _results = results);
    });
  }

  void _open(td.Chat chat) {
    Navigator.of(context).push(ConversationScreen.route(chat.id));
  }

  @override
  Widget build(BuildContext context) {
    final caps = context.select(
      (AuthBloc b) => switch (b.state.step) {
        AuthReady(:final capabilities) => capabilities,
        _ => null,
      },
    );
    final isBot = caps?.isBot ?? false;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: _searching
                        ? TextField(
                            controller: _search,
                            autofocus: true,
                            onChanged: _onQuery,
                            decoration: const InputDecoration(
                              hintText: 'Search chats and people',
                              border: InputBorder.none,
                            ),
                          )
                        : const Align(
                            alignment: Alignment.centerLeft,
                            child: ConnectionAwareTitle(title: 'Chats'),
                          ),
                  ),
                  IconButton(
                    tooltip: _searching ? 'Close search' : 'Search',
                    icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
                    onPressed: () => setState(() {
                      _searching = !_searching;
                      _search.clear();
                      _results = null;
                    }),
                  ),
                ],
              ),
            ),
            if (isBot && !_botNoticeDismissed)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Dismissible(
                  key: const ValueKey('bot-limits'),
                  onDismissed: (_) => setState(() => _botNoticeDismissed = true),
                  child: BotLimitationsCard(caps!.limitations),
                ),
              ),
            Expanded(
              child: _results != null
                  ? _ResultsList(results: _results!, onOpen: _open)
                  : BlocBuilder<ChatListCubit, ChatListState>(
                      builder: (context, state) {
                        if (state.chats.isEmpty) {
                          return Center(
                            child: state.loading
                                ? const CircularProgressIndicator(color: GlowColors.violet)
                                : Padding(
                                    padding: const EdgeInsets.all(32),
                                    child: Text(
                                      isBot
                                          ? 'No chats yet. Chats appear here when someone messages your bot.'
                                          : 'No chats yet. Tap the orb to start one.',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(color: GlowColors.textMuted),
                                    ),
                                  ),
                          );
                        }
                        return LuminousRefresh(
                          onRefresh: context.read<ChatListCubit>().refresh,
                          child: NotificationListener<ScrollNotification>(
                            onNotification: (n) {
                              if (n.metrics.extentAfter < 600) context.read<ChatListCubit>().loadMore();
                              return false;
                            },
                            child: ListView.builder(
                              padding: const EdgeInsets.only(bottom: 120),
                              itemCount: state.chats.length,
                              itemBuilder: (context, i) {
                                final chat = state.chats[i];
                                return TimelineChatRow(
                                  key: ValueKey(chat.id),
                                  chat: chat,
                                  isFirst: i == 0,
                                  isLast: i == state.chats.length - 1,
                                  showPresence: !isBot,
                                  onTap: () => _open(chat),
                                  onLongPress: () => showChatActions(context, chat),
                                );
                              },
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultsList extends StatelessWidget {
  const _ResultsList({required this.results, required this.onOpen});

  final List<td.Chat> results;
  final void Function(td.Chat) onOpen;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return const Center(
        child: Text('Nothing found', style: TextStyle(color: GlowColors.textMuted)),
      );
    }
    final cache = context.read<TelegramCache>();
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, i) {
        final chat = cache.chats[results[i].id] ?? results[i];
        return TimelineChatRow(
          chat: chat,
          isFirst: i == 0,
          isLast: i == results.length - 1,
          onTap: () => onOpen(chat),
        );
      },
    );
  }
}
