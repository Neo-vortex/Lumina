import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:handy_tdlib_next/api.dart' as td;
import 'package:super_sliver_list/super_sliver_list.dart';

import '../../../../core/storage/app_preferences.dart';
import '../../../../core/tdlib/td_client.dart';
import '../../../../core/telegram/display.dart';
import '../../../../core/telegram/permissions.dart';
import '../../../../core/telegram/telegram_cache.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../../../core/theme/motion.dart';
import '../../../../core/widgets/glow_background.dart';
import '../../../auth/bloc/auth_bloc.dart';
import '../../../auth/domain/auth_step.dart';
import '../../bloc/conversation_cubit.dart';
import '../../data/messages_repository.dart';
import '../widgets/composer.dart';
import '../widgets/formatting_controller.dart';
import '../widgets/conversation_extensions.dart';
import '../widgets/conversation_header.dart';
import '../widgets/forward_sheet.dart';
import '../widgets/message_bubble.dart';
import '../widgets/message_menu.dart';
import '../widgets/message_rows.dart';
import '../widgets/pinned_banner.dart';
import '../widgets/sponsored_card.dart';
import 'chat_search_screen.dart';

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({super.key});

  static Route<void> route(int chatId, {int? focusMessageId}) => MaterialPageRoute(
    builder: (context) => BlocProvider(
      create: (context) => ConversationCubit(
        chatId: chatId,
        repository: context.read<MessagesRepository>(),
        cache: context.read<TelegramCache>(),
        updates: context.read<TdClient>().updates,
        showSponsored: _showSponsored(context, chatId),
      )..start(focusMessageId: focusMessageId),
      child: const ConversationScreen(),
    ),
  );

  /// Channels show sponsored messages unless the account turned them off:
  /// officially (Premium) or with the local "Hide channel ads" preference.
  static bool _showSponsored(BuildContext context, int chatId) {
    final cache = context.read<TelegramCache>();
    final chat = cache.chats[chatId];
    if (chat == null || !cache.isChannel(chat)) return false;
    final step = context.read<AuthBloc>().state.step;
    if (step is AuthReady && step.capabilities.isBot) return false;
    return !context.read<AppPreferences>().hideSponsored;
  }

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final _text = FormattingController();
  final _scroll = ScrollController();
  final _list = ListController();
  final _seenAtOpen = <int>{};
  var _initialised = false;
  var _showJump = false;
  List<MessageRow> _rows = const [];

  /// Sponsored cards occupy the first list indices (bottom of the screen).
  var _adsOffset = 0;
  late final ConversationCubit _cubit = context.read<ConversationCubit>();

  @override
  void initState() {
    super.initState();
    final draft = _cubit.state.chat?.draftMessage?.inputMessageText;
    if (draft case td.InputMessageText(:final text)) _text.setFormatted(text);
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _cubit.saveDraft(_text.text, entities: _text.entities);
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _list.dispose();
    _text.dispose();
    super.dispose();
  }

  void _onScroll() {
    final show = _scroll.hasClients && _scroll.offset > 400;
    if (show != _showJump) setState(() => _showJump = show);
  }

  void _reportVisible() {
    if (!_list.isAttached) return;
    final range = _list.visibleRange;
    if (range == null) return;
    final ids = <int>[];
    for (var i = range.$1 - _adsOffset; i <= range.$2 - _adsOffset && i < _rows.length; i++) {
      if (i < 0) continue;
      final row = _rows[i];
      if (row is BubbleRow) {
        for (final m in row.messages) {
          if (!m.isOutgoing) ids.add(m.id);
        }
      } else if (row is ServiceRow) {
        ids.add(row.message.id);
      }
    }
    _cubit.visible(ids);
  }

  void _scrollToAnchor(int messageId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_list.isAttached) return;
      final index = _rows.indexWhere(
        (r) =>
            (r is BubbleRow && r.messages.any((m) => m.id == messageId)) ||
            (r is ServiceRow && r.message.id == messageId),
      );
      if (index < 0) return;
      if (Motion.ambientEnabled(context)) {
        _list.animateToItem(
          index: index + _adsOffset,
          scrollController: _scroll,
          alignment: 0.5,
          duration: (d) => Motion.screen,
          curve: (d) => Motion.move,
        );
      } else {
        _list.jumpToItem(index: index + _adsOffset, scrollController: _scroll, alignment: 0.5);
      }
      Future.delayed(const Duration(milliseconds: 500), _reportVisible);
    });
  }

  Future<void> _send(String text, SendOptions options, td.LinkPreviewOptions? preview) async {
    final error = await _cubit.send(text, entities: _text.entities, options: options, linkPreview: preview);
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    } else {
      _text.clear();
      _cubit.saveDraft('');
      if (options.scheduleAt != null || options.whenOnline) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Message scheduled')));
      }
    }
  }

  Future<void> _onLongPress(td.Message m, td.Chat chat) async {
    if (_cubit.state.selecting) {
      _cubit.toggleSelected(m);
      return;
    }
    final extensions = ConversationExtensions.of(context);
    final properties = await _cubit.properties(m);
    if (!mounted) return;
    final result = await showMessageMenu(
      context,
      message: m,
      properties: properties,
      reactions: _cubit.reactionChoices(m),
      protectedContent: chat.hasProtectedContent,
      extras: extensions.menuEntries(m),
    );
    if (!mounted || result == null) return;
    if (result.reaction != null) {
      await _cubit.toggleReaction(m, result.reaction!);
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      switch (result.action!) {
        case MessageAction.reply:
          _cubit.startReply(m);
        case MessageAction.copy:
          await copyMessageText(context, m);
        case MessageAction.selectText:
          await showSelectText(context, m);
        case MessageAction.edit:
          _cubit.startEdit(m);
          _text.setFormatted(messageText(m) ?? const td.FormattedText(text: '', entities: []));
        case MessageAction.pin:
          await _cubit.pin(m);
        case MessageAction.unpin:
          await _cubit.unpin(m);
        case MessageAction.forward:
          await showForwardSheet(context, fromChatId: m.chatId, messageIds: [m.id]);
        case MessageAction.forwardHidden:
          await showForwardSheet(
            context,
            fromChatId: m.chatId,
            messageIds: [m.id],
            hideSenderInitially: true,
          );
        case MessageAction.select:
          _cubit.toggleSelected(m);
        case MessageAction.copyLink:
          final link = await context.read<MessagesRepository>().link(m.chatId, m.id);
          await Clipboard.setData(ClipboardData(text: link));
          messenger.showSnackBar(const SnackBar(content: Text('Link copied')));
        case MessageAction.deleteForMe:
          await _cubit.delete([m.id], forEveryone: false);
        case MessageAction.deleteForAll:
          await _cubit.delete([m.id], forEveryone: true);
        case MessageAction.aiAction || MessageAction.transcribe:
          if (mounted) await extensions.onMenuAction(context, result.action!, m);
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _deleteSelected(td.Chat chat) async {
    final ids = _cubit.state.selected.toList();
    final forAll = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GlowColors.surfaceHigh,
        title: Text('Delete ${ids.length} message${ids.length == 1 ? '' : 's'}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          if (chat.canBeDeletedForAllUsers)
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('For everyone', style: TextStyle(color: GlowColors.coral)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('For me', style: TextStyle(color: GlowColors.coral)),
          ),
        ],
      ),
    );
    if (forAll == null) return;
    try {
      await _cubit.delete(ids, forEveryone: forAll);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cache = context.read<TelegramCache>();
    final isBot = context.select(
      (AuthBloc b) => switch (b.state.step) {
        AuthReady(:final capabilities) => capabilities.isBot,
        _ => false,
      },
    );
    final extensions = ConversationExtensions.of(context);

    return BlocConsumer<ConversationCubit, ConversationState>(
      listenWhen: (a, b) => a.anchor?.serial != b.anchor?.serial && b.anchor != null,
      listener: (context, state) => _scrollToAnchor(state.anchor!.messageId),
      builder: (context, state) {
        final chat = state.chat ?? cache.chats[state.chatId];
        if (chat == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator(color: GlowColors.violet)),
          );
        }
        if (!_initialised && !state.initialLoading) {
          _initialised = true;
          _seenAtOpen.addAll(state.messages.map((m) => m.id));
          WidgetsBinding.instance.addPostFrameCallback((_) => _reportVisible());
        }
        _rows = buildRows(state.messages, firstUnreadId: state.firstUnreadId);
        _adsOffset = state.hasNewer ? 0 : state.sponsored.length;
        final isGroup =
            chat.type is td.ChatTypeBasicGroup ||
            (chat.type is td.ChatTypeSupergroup && !cache.isChannel(chat));
        final isChannel = cache.isChannel(chat);
        final canPost = cache.canPost(chat);

        return PopScope(
          canPop: !state.selecting,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _cubit.clearSelection();
          },
          child: Scaffold(
            resizeToAvoidBottomInset: true,
            appBar: state.selecting
                ? _SelectionBar(
                    count: state.selected.length,
                    onClose: _cubit.clearSelection,
                    onForward: () => showForwardSheet(
                      context,
                      fromChatId: chat.id,
                      messageIds: (state.selected.toList()..sort()),
                    ).then((_) => _cubit.clearSelection()),
                    onDelete: () => _deleteSelected(chat),
                  )
                : ConversationHeader(
                    chat: chat,
                    showPresence: !isBot,
                    onTitleTap: () => extensions.openChatInfo(context, chat),
                    actions: [
                      IconButton(
                        tooltip: 'Search in chat',
                        icon: const Icon(Icons.search_rounded),
                        onPressed: () async {
                          final id = await Navigator.of(context).push<int>(ChatSearchScreen.route(chat));
                          if (id != null) await _cubit.jumpTo(id);
                        },
                      ),
                    ],
                  ),
            body: GlowBackground(
              child: Column(
                children: [
                  if (state.pinned != null)
                    PinnedBanner(
                      message: state.pinned!,
                      onTap: () => _cubit.jumpTo(state.pinned!.id),
                      onUnpin: cache.isAdmin(chat) || chat.type is td.ChatTypePrivate
                          ? () => _cubit.unpin(state.pinned!)
                          : null,
                    ),
                  Expanded(
                    child: Stack(
                      children: [
                        if (state.initialLoading)
                          const Center(child: CircularProgressIndicator(color: GlowColors.violet))
                        else
                          NotificationListener<ScrollNotification>(
                            onNotification: (n) {
                              if (n.metrics.extentAfter < 800) _cubit.loadOlder();
                              if (n.metrics.extentBefore < 300 && state.hasNewer) _cubit.loadNewer();
                              if (n is ScrollEndNotification) _reportVisible();
                              return false;
                            },
                            child: SuperListView.builder(
                              reverse: true,
                              controller: _scroll,
                              listController: _list,
                              padding: const EdgeInsets.only(top: 12, bottom: 8),
                              itemCount: _rows.length + (state.hasOlder ? 1 : 0) + _adsOffset,
                              itemBuilder: (context, i) {
                                final ads = _adsOffset;
                                if (i < ads) {
                                  final ad = state.sponsored[i];
                                  _cubit.sponsoredVisible(ad);
                                  return SponsoredCard(ad: ad, onOpen: () => _cubit.sponsoredClicked(ad));
                                }
                                i -= ads;
                                if (i >= _rows.length) {
                                  return const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Center(
                                      child: SizedBox.square(
                                        dimension: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: GlowColors.violet,
                                        ),
                                      ),
                                    ),
                                  );
                                }
                                return _buildRow(_rows[i], chat, state, isGroup, isChannel);
                              },
                            ),
                          ),
                        if (_showJump || state.hasNewer)
                          Positioned(
                            right: 16,
                            bottom: 16,
                            child: _JumpButton(unread: chat.unreadCount, onTap: _cubit.jumpToLatest),
                          ),
                      ],
                    ),
                  ),
                  if (canPost)
                    ListenableBuilder(
                      listenable: extensions.composerListenable,
                      builder: (context, _) => Composer(
                        controller: _text,
                        replyTo: state.replyTo,
                        editing: state.editing,
                        onSend: _send,
                        onCancelMode: () {
                          if (state.editing != null) _text.clear();
                          _cubit.cancelComposerMode();
                        },
                        onChanged: _cubit.composerChanged,
                        onAttach: cache.canSendMedia(chat) ? () => extensions.onAttach(context, chat) : null,
                        onVoice: cache.canSendVoice(chat)
                            ? () => extensions.onVoice(context, chat, _text)
                            : null,
                        onDictate: () => extensions.onDictate(context, chat, _text),
                        recordingOverlay: extensions.recordingOverlay(context, chat),
                        orbMode: extensions.orbMode(context, chat),
                        loadPreview: _cubit.linkPreview,
                        previewsOnSend: context.read<AppPreferences>().linkPreviewsOnSend,
                      ),
                    )
                  else
                    _ReadOnlyBar(chat: chat, isChannel: isChannel),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRow(MessageRow row, td.Chat chat, ConversationState state, bool isGroup, bool isChannel) {
    return switch (row) {
      DayHeaderRow(:final day) => _DayHeader(day: day),
      UnreadDividerRow() => const _UnreadDivider(),
      ServiceRow(:final message) => _ServiceBubble(message: message),
      BubbleRow() => MessageBubble(
        key: ValueKey(row.id),
        row: row,
        chat: chat,
        isGroup: isGroup,
        isChannel: isChannel,
        animateIn: _initialised && !_seenAtOpen.contains(row.id),
        highlighted: row.messages.any((m) => m.id == state.highlightId),
        selected: row.messages.any((m) => state.selected.contains(m.id)),
        selecting: state.selecting,
        onReply: () => _cubit.startReply(row.primary),
        onLongPress: () => _onLongPress(row.primary, chat),
        onTap: () {
          if (state.selecting) _cubit.toggleSelected(row.primary);
        },
        onReplyQuoteTap: _cubit.jumpTo,
        onReaction: (emoji) => _cubit.toggleReaction(row.primary, emoji),
      ),
    };
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: GlowColors.surfaceHigh.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            Display.dayHeader(day, DateTime.now()),
            style: const TextStyle(fontSize: 12, color: GlowColors.textMuted, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

class _UnreadDivider extends StatelessWidget {
  const _UnreadDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Container(height: 1, color: GlowColors.cyan.withValues(alpha: 0.4))),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'Unread messages',
              style: TextStyle(color: GlowColors.cyan, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Container(height: 1, color: GlowColors.cyan.withValues(alpha: 0.4))),
        ],
      ),
    );
  }
}

class _ServiceBubble extends StatelessWidget {
  const _ServiceBubble({required this.message});

  final td.Message message;

  @override
  Widget build(BuildContext context) {
    final text = Display.serviceText(context.read<TelegramCache>(), message) ?? '';
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 40),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: GlowColors.surfaceHigh.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: GlowColors.textMuted),
        ),
      ),
    );
  }
}

class _JumpButton extends StatelessWidget {
  const _JumpButton({required this.unread, required this.onTap});

  final int unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: unread > 0 ? 'Jump to latest, $unread unread' : 'Jump to latest',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: GlowColors.surfaceHigh,
                border: Border.all(color: GlowColors.outlineStrong),
                boxShadow: glow(GlowColors.violet, intensity: 0.4),
              ),
              child: const Icon(Icons.keyboard_arrow_down_rounded, color: GlowColors.text),
            ),
            if (unread > 0)
              Positioned(
                top: -6,
                right: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: GlowColors.teal, borderRadius: BorderRadius.circular(10)),
                  child: Text(
                    unread > 99 ? '99+' : '$unread',
                    style: const TextStyle(
                      color: GlowColors.onAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SelectionBar extends StatelessWidget implements PreferredSizeWidget {
  const _SelectionBar({
    required this.count,
    required this.onClose,
    required this.onForward,
    required this.onDelete,
  });

  final int count;
  final VoidCallback onClose;
  final VoidCallback onForward;
  final VoidCallback onDelete;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: GlowColors.surfaceHigh,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              IconButton(
                tooltip: 'Cancel selection',
                icon: const Icon(Icons.close_rounded),
                onPressed: onClose,
              ),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    '$count selected',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              IconButton(tooltip: 'Forward', icon: const Icon(Icons.forward_rounded), onPressed: onForward),
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline_rounded, color: GlowColors.coral),
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadOnlyBar extends StatelessWidget {
  const _ReadOnlyBar({required this.chat, required this.isChannel});

  final td.Chat chat;
  final bool isChannel;

  @override
  Widget build(BuildContext context) {
    final cache = context.read<TelegramCache>();
    final member = cache.isMember(chat);
    final text = !member
        ? (isChannel ? 'You are not subscribed' : 'You are not a member')
        : chat.type is td.ChatTypeSecret
        ? 'Waiting for the secret chat to start…'
        : isChannel
        ? 'Only admins can post here'
        : 'Sending messages is restricted here';
    return Material(
      color: GlowColors.background,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: GlowColors.textMuted),
          ),
        ),
      ),
    );
  }
}
