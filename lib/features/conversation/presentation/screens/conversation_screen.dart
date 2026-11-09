import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;
import 'package:super_sliver_list/super_sliver_list.dart';

import '../../../../core/widgets/lumina_glass.dart';
import '../../../../core/storage/app_preferences.dart';
import '../../../../core/tdlib/td_client.dart';
import '../../../../core/telegram/display.dart';
import '../../../../core/telegram/file_store.dart';
import '../../../../core/telegram/permissions.dart';
import '../../../../core/telegram/telegram_cache.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../../../core/theme/motion.dart';
import '../../../auth/bloc/auth_bloc.dart';
import '../../../auth/domain/auth_step.dart';
import '../../../chat_info/data/chat_info_repository.dart';
import '../../../chats/data/chats_repository.dart';
import '../../bloc/conversation_cubit.dart';
import '../../data/messages_repository.dart';
import '../widgets/composer.dart';
import 'scheduled_messages_screen.dart';
import '../widgets/formatting_controller.dart';
import '../widgets/conversation_extensions.dart';
import '../widgets/conversation_header.dart';
import '../widgets/forward_sheet.dart';
import '../widgets/message_bubble.dart';
import '../widgets/jump_to_date_sheet.dart';
import '../../../media_panel/presentation/media_panel.dart';
import '../widgets/reaction_panel.dart';
import '../widgets/message_menu.dart';
import '../widgets/message_details_sheet.dart';
import '../widgets/message_rows.dart';
import '../../../../core/tdlib/td_errors.dart';
import '../../../../core/widgets/delete_confirm.dart';
import '../../../../core/telegram/widgets/animated_sticker.dart';
import '../../../../core/gestures/swipe_actions.dart';
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

class _ConversationScreenState extends State<ConversationScreen> with WidgetsBindingObserver {
  /// The newest message the list showed, to notice new arrivals.
  int _newestShown = 0;

  /// The floating date while scrolling: the day at the top of the screen.
  DateTime? _stickyDay;
  bool _stickyShown = false;
  Timer? _stickyHide;

  void _updateSticky({required bool scrolling}) {
    final range = _list.isAttached ? _list.visibleRange : null;
    if (range == null) return;
    // The list is reversed: the highest visible index is the top row.
    DateTime? day;
    for (var i = range.$2 - _adsOffset; i >= range.$1 - _adsOffset && day == null; i--) {
      if (i < 0 || i >= _rows.length) continue;
      final date = switch (_rows[i]) {
        BubbleRow(:final primary) => primary.date,
        ServiceRow(:final message) => message.date,
        DayHeaderRow(day: final d) => d.millisecondsSinceEpoch ~/ 1000,
        _ => null,
      };
      if (date != null) {
        final t = DateTime.fromMillisecondsSinceEpoch(date * 1000);
        day = DateTime(t.year, t.month, t.day);
      }
    }
    final show = scrolling && day != null && _scroll.hasClients && _scroll.offset > 120;
    if (!show && !_stickyShown) {
      // The chip is hidden: keep its day current without rebuilding the
      // whole screen (header and composer) on every new message.
      _stickyDay = day;
    } else if (day != _stickyDay || show != _stickyShown && show) {
      setState(() {
        _stickyDay = day;
        if (show) _stickyShown = true;
      });
    }
    if (show) {
      _stickyHide?.cancel();
    } else if (!scrolling) {
      _stickyHide?.cancel();
      _stickyHide = Timer(const Duration(seconds: 1), () {
        if (mounted) setState(() => _stickyShown = false);
      });
    }
  }

  final _text = FormattingController();
  final _scroll = ScrollController();
  final _list = ListController();
  final _seenAtOpen = <int>{};
  var _initialised = false;
  var _showJump = false;
  List<MessageRow> _rows = const [];

  // buildRows is memoised on the message list.
  List<td.Message>? _rowsFrom;
  int? _rowsUnread;

  /// Bubbles that have already played their entrance (G1).
  final _animated = <int>{};

  void _updateRows(ConversationState state) {
    if (identical(state.messages, _rowsFrom) && state.firstUnreadId == _rowsUnread) return;
    _rowsFrom = state.messages;
    _rowsUnread = state.firstUnreadId;
    _rows = buildRows(state.messages, firstUnreadId: state.firstUnreadId);
    _indexOfKey = {for (var i = 0; i < _rows.length; i++) _rowKey(_rows[i]): i};
    _rowWidgets.removeWhere((k, _) => !_indexOfKey.containsKey(k));
  }

  /// Built bubbles with what they were built from. When nothing a bubble
  /// shows changed, the list gets the very same widget back and Flutter skips
  /// it entirely: state changes (a page of history, a read receipt, a
  /// reaction elsewhere) used to rebuild every visible bubble.
  final _rowWidgets = <Object, ({List<Object?> inputs, Widget widget})>{};

  /// Row key → index, so rows keep their state (images, animations) when a
  /// new message shifts every index.
  Map<Object, int> _indexOfKey = const {};

  Object _rowKey(MessageRow row) => switch (row) {
    DayHeaderRow(:final day) => 'd$day',
    UnreadDividerRow() => 'unread',
    ServiceRow(:final message) => message.id,
    BubbleRow() => _cubit.stableId(row.id),
  };

  /// Sponsored cards occupy the first list indices (bottom of the screen).
  var _adsOffset = 0;
  late final ConversationCubit _cubit = context.read<ConversationCubit>();

  /// Shows the list once it sits where it should (one frame after the jump,
  /// so the jump's layout has landed).
  void _reveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_placed) setState(() => _placed = true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _watchRoute();
  }

  @override
  void initState() {
    super.initState();
    final draft = _cubit.state.chat?.draftMessage;
    if (draft?.content case td.DraftMessageContentText(:final text)) _text.setFormatted(text);
    _cubit.restoreDraftReply(draft?.replyTo).ignore();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _cubit.saveDraft(_text.text, entities: _text.entities);
    WidgetsBinding.instance.removeObserver(this);
    _stickyHide?.cancel();
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

  /// Back in the app with the chat open: what's on screen is read now.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reportVisible();
  }

  void _reportVisible() {
    // Nothing is read while the app is in the background.
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    // Mid anchor scroll the screen shows rows the user passes over (at open,
    // the window's bottom); reading those would undercount the unread.
    if (_anchoring > 0 || !_list.isAttached) return;
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

  static const _anchorAlignment = 0.82;
  static const _anchorTopLine = Rect.fromLTWH(0, 0, 1, 24);

  /// Anchor scrolls in flight; the list reports what it shows once they land.
  var _anchoring = 0;

  // ---- Opening without a stutter -----------------------------------------
  // The list waits for the route's slide-in to finish (building a screenful
  // of bubbles mid-transition dropped frames), then jumps straight to the
  // first unread message while still invisible, and fades in in place.

  /// The open transition has finished (or there was none).
  var _routeSettled = false;

  /// The first anchor (first unread / focused message) has been applied.
  var _placed = false;

  /// An anchor that arrived before the list could take it.
  int? _pendingAnchor;

  /// The anchor serial already handed to [_scrollToAnchor].
  int? _appliedAnchor;

  Animation<double>? _routeAnimation;

  void _watchRoute() {
    if (_routeAnimation != null) return;
    final anim = ModalRoute.of(context)?.animation;
    _routeAnimation = anim;
    if (anim == null || anim.status == AnimationStatus.completed) {
      _routeSettled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _settleNow());
      return;
    }
    void done(AnimationStatus s) {
      if (s != AnimationStatus.completed) return;
      anim.removeStatusListener(done);
      if (!mounted) return;
      setState(() => _routeSettled = true);
      WidgetsBinding.instance.addPostFrameCallback((_) => _settleNow());
    }

    anim.addStatusListener(done);
  }

  /// The route is in place: apply what arrived meanwhile (an anchor to jump
  /// to, or just loaded messages to show).
  void _settleNow() {
    if (!mounted || _placed) return;
    final anchor = _cubit.state.anchor;
    final pending = _pendingAnchor;
    if (pending != null) {
      _pendingAnchor = null;
      _scrollToAnchor(pending);
    } else if (anchor != null && anchor.serial != _appliedAnchor) {
      _appliedAnchor = anchor.serial;
      _scrollToAnchor(anchor.messageId);
    } else if (!_cubit.state.initialLoading) {
      _reveal();
    }
  }

  void _scrollToAnchor(int messageId) {
    if (!_routeSettled) {
      _pendingAnchor = messageId;
      return;
    }
    // The first placement jumps (no scroll animation through every row in
    // between) while the list is still invisible.
    final first = !_placed;
    _anchoring++;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_list.isAttached) {
        _anchoring--;
        if (first) _reveal();
        return;
      }
      final index = _rows.indexWhere(
        (r) =>
            (r is BubbleRow && r.messages.any((m) => m.id == messageId)) ||
            (r is ServiceRow && r.message.id == messageId),
      );
      if (index < 0) {
        _anchoring--;
        if (first) _reveal();
        return;
      }
      // Reveal the message's first line near the top (the list is reversed,
      // so 1.0 is the top edge): centring the whole row put the start of a
      // tall message above the screen. The newest row just sits at the bottom.
      final newest = index == 0;
      // The newest row: the list's very end, which keeps the room left for
      // the floating composer (aligning the row to the edge hid it behind).
      if (newest && _scroll.hasClients) {
        if (first) {
          _scroll.jumpTo(0);
          _reveal();
        } else if (Motion.ambientEnabled(context)) {
          _scroll.animateTo(0, duration: Motion.screen, curve: Motion.move);
        } else {
          _scroll.jumpTo(0);
        }
        Future.delayed(const Duration(milliseconds: 500), () {
          _anchoring--;
          if (mounted) _reportVisible();
        });
        return;
      }
      final alignment = newest ? 0.0 : _anchorAlignment;
      final rect = newest ? null : _anchorTopLine;
      if (first) {
        _list.jumpToItem(
          index: index + _adsOffset,
          scrollController: _scroll,
          alignment: alignment,
          rect: rect,
        );
        _reveal();
      } else if (Motion.ambientEnabled(context)) {
        _list.animateToItem(
          index: index + _adsOffset,
          scrollController: _scroll,
          alignment: alignment,
          rect: rect,
          duration: (d) => Motion.screen,
          curve: (d) => Motion.move,
        );
      } else {
        _list.jumpToItem(
          index: index + _adsOffset,
          scrollController: _scroll,
          alignment: alignment,
          rect: rect,
        );
      }
      Future.delayed(const Duration(milliseconds: 500), () {
        _anchoring--;
        if (mounted) _reportVisible();
      });
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
        final chat = _cubit.state.chat;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Message scheduled'),
            action: chat == null
                ? null
                : SnackBarAction(
                    label: 'View',
                    onPressed: () => Navigator.of(context).push(ScheduledMessagesScreen.route(chat)),
                  ),
          ),
        );
      }
    }
  }

  /// Reacts, telling the user when it couldn't (not allowed here, offline).
  Future<void> _react(td.Message m, String emoji) async {
    final messenger = ScaffoldMessenger.of(context);
    // Fetch the effect while the chip glows, so it plays the moment TDLib
    // confirms.
    _prefetchEffect(emoji);
    try {
      if (!await _cubit.toggleReaction(m, emoji)) {
        messenger.showSnackBar(SnackBar(content: Text('$emoji isn\'t allowed as a reaction in this chat')));
      } else {
        HapticFeedback.lightImpact();
      }
    } on TdException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  void _prefetchEffect(String emoji) {
    final FileStore files;
    try {
      files = context.read<FileStore>();
    } on ProviderNotFoundException {
      return;
    }
    context.read<MessagesRepository>().emojiReaction(emoji).then((r) {
      if (r == null) return;
      for (final s in [r.effectAnimation, r.activateAnimation]) {
        if (!s.sticker.local.isDownloadingCompleted) files.download(s.sticker.id, priority: 24).ignore();
      }
    }).ignore();
  }

  /// Double tap: what Settings → Gestures says (a ❤️ reaction by default).
  Future<void> _onDoubleTap(td.Message m, td.Chat chat) async {
    final prefs = context.read<AppPreferences>();
    HapticFeedback.lightImpact();
    final messenger = ScaffoldMessenger.of(context);
    try {
      switch (prefs.doubleTap) {
        case MessageDoubleTap.react:
          await _react(m, prefs.doubleTapEmoji);
        case MessageDoubleTap.reply:
          _cubit.startReply(m);
        case MessageDoubleTap.forward:
          await showForwardSheet(context, fromChatId: m.chatId, messageIds: [m.id]);
        case MessageDoubleTap.copy:
          await copyMessageText(context, m);
        case MessageDoubleTap.select:
          _cubit.toggleSelected(m);
        case MessageDoubleTap.pin:
          await (m.isPinned ? _cubit.unpin(m) : _cubit.pin(m));
        case MessageDoubleTap.none:
          break;
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  /// Long-press starts (or extends) multi-select, like Telegram.
  void _onLongPress(td.Message m) {
    HapticFeedback.mediumImpact();
    _cubit.toggleSelected(m);
  }

  /// Tap: the focus menu with quick reactions, read status and actions.
  Future<void> _openMenu(td.Message m, td.Chat chat, {Rect? anchor, Widget? bubble}) async {
    if (_cubit.state.selecting) {
      _cubit.toggleSelected(m);
      return;
    }
    final extensions = ConversationExtensions.of(context);
    final repo = context.read<MessagesRepository>();
    final prefs = context.read<AppPreferences>();
    final properties = await _cubit.properties(m);
    if (!mounted) return;
    final private = chat.type is td.ChatTypePrivate;
    final result = await showMessageMenu(
      context,
      message: m,
      properties: properties,
      reactions: _cubit.reactionChoices(m),
      failedInChat: _cubit.retryableFailed.length,
      reactionCatalog: _TdReactionCatalog(repo, chat.id, m.id, Localizations.localeOf(context).languageCode),
      quickReactions: prefs.quickReactions,
      aiSuggestion: extensions.aiReaction(context, m),
      anchor: anchor,
      bubble: bubble,
      readStatus: m.isOutgoing && private ? repo.readStatus(chat.id, m.id) : null,
      // Keyed by emoji: an unkeyed FutureBuilder keeps the previous
      // future's data, so a slot that changed emoji drew the old one while
      // its tap sent the new one.
      reactionIcon: (emoji, size) => FutureBuilder<td.EmojiReaction?>(
        key: ValueKey('reaction-icon-$emoji'),
        future: repo.emojiReaction(emoji),
        builder: (context, snap) => snap.data == null
            ? Text(emoji, style: TextStyle(fontSize: size * 0.8, height: 1))
            // The select animation fills its frame; the center icon has wide
            // margins and drew the emoji at half the size asked for.
            : AnimatedSticker(sticker: snap.data!.selectAnimation, size: size),
      ),
      protectedContent: chat.hasProtectedContent,
      extras: extensions.menuEntries(m),
    );
    if (!mounted || result == null) return;
    if (result.reaction != null) {
      await _react(m, result.reaction!);
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      switch (result.action!) {
        case MessageAction.retry:
          await _cubit.retry(m);
        case MessageAction.retryAll:
          await _cubit.retryAllFailed();
        case MessageAction.reply:
          _cubit.startReply(m);
        case MessageAction.copy:
          await copyMessageText(context, m);
        case MessageAction.selectText:
          final quote = await showSelectText(context, m, canQuote: properties?.canBeReplied ?? true);
          if (quote != null) _cubit.startReply(m, quote: quote);
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
        case MessageAction.details:
          await showMessageDetails(
            context,
            m,
            readStatus: m.isOutgoing && chat.type is td.ChatTypePrivate
                ? context.read<MessagesRepository>().readStatus(chat.id, m.id)
                : null,
          );
        case MessageAction.copyLink:
          final link = await context.read<MessagesRepository>().link(m.chatId, m.id);
          await Clipboard.setData(ClipboardData(text: link));
          messenger.showSnackBar(const SnackBar(content: Text('Link copied')));
        case MessageAction.delete:
          await _confirmAndDelete([m.id], chat);
        case MessageAction.aiAction || MessageAction.transcribe:
          if (mounted) await extensions.onMenuAction(context, result.action!, m);
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  /// The date header's calendar: counts messages per day, then jumps to the day picked.
  Future<void> _openCalendar(DateTime day) async {
    final repo = context.read<MessagesRepository>();
    final chatId = _cubit.chatId;
    final id = await showJumpToDateSheet(
      context,
      initial: day,
      load: () => countDays((from) => repo.history(chatId, fromMessageId: from, limit: 100)),
    );
    if (id != null && mounted) await _cubit.jumpTo(id);
  }

  Future<void> _deleteSelected(td.Chat chat) => _confirmAndDelete(_cubit.state.selected.toList(), chat);

  /// Every delete confirms; "for everyone" is offered only when TDLib allows
  /// it for all of [ids].
  Future<void> _confirmAndDelete(List<int> ids, td.Chat chat) async {
    if (ids.isEmpty) return;
    final repo = context.read<MessagesRepository>();
    final cache = context.read<TelegramCache>();
    var canForAll = true;
    try {
      for (final id in ids) {
        final p = await repo.properties(chat.id, id);
        if (!p.canBeDeletedForAllUsers) canForAll = false;
      }
    } catch (_) {
      canForAll = false;
    }
    if (!mounted) return;
    final forAll = await confirmDeleteMessages(
      context,
      count: ids.length,
      canForEveryone: canForAll,
      otherName: cache.peerUser(chat)?.firstName,
    );
    if (forAll == null) return;
    await _cubit.delete(ids, forEveryone: forAll);
  }

  /// Where content starts below the floating header (set in build).
  double _headerInset = 0;

  /// The floating composer's height: the list keeps that much room at the
  /// bottom so the newest message stops just above it.
  double _composerHeight = 72;

  void _setComposerHeight(double h) {
    // An expanded emoji panel covers the messages; only its keyboard-height
    // part moves them up.
    h -= MediaPanel.expandedBy;
    if ((h - _composerHeight).abs() < 1 || !mounted) return;
    setState(() => _composerHeight = h);
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
      listenWhen: (a, b) =>
          (a.anchor?.serial != b.anchor?.serial && b.anchor != null) ||
          // Loaded without an anchor (no unread): just show the list.
          (a.initialLoading && !b.initialLoading && a.anchor?.serial == b.anchor?.serial),
      listener: (context, state) {
        final anchor = state.anchor;
        if (!_placed && _routeSettled && (anchor == null || anchor.serial == _appliedAnchor)) {
          _reveal();
          return;
        }
        if (anchor != null && anchor.serial != _appliedAnchor) {
          _appliedAnchor = anchor.serial;
          _scrollToAnchor(anchor.messageId);
        }
      },
      // The scaffold (header, pinned banner, composer) rebuilds only for what
      // it shows; the message list has its own builder.
      buildWhen: (a, b) =>
          !identical(a.chat, b.chat) ||
          a.revision != b.revision ||
          a.initialLoading != b.initialLoading ||
          a.selecting != b.selecting ||
          a.selected.length != b.selected.length ||
          a.pinned != b.pinned ||
          a.replyTo != b.replyTo ||
          a.replyQuote != b.replyQuote ||
          a.editing != b.editing,
      builder: (context, state) {
        final chat = state.chat ?? cache.chats[state.chatId];
        if (chat == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator(color: GlowColors.violet)),
          );
        }
        final isGroup =
            chat.type is td.ChatTypeBasicGroup ||
            (chat.type is td.ChatTypeSupergroup && !cache.isChannel(chat));
        final isChannel = cache.isChannel(chat);
        final canPost = cache.canPost(chat);
        // The floating header's bottom edge: the status bar plus its height
        // (the body extends behind it unless selecting).
        _headerInset = state.selecting ? 0 : MediaQuery.paddingOf(context).top + 66;

        return PopScope(
          canPop: !state.selecting,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _cubit.clearSelection();
          },
          // One shared backdrop copy for the header, pinned card and composer
          // glass: the copy, not the glass, is what costs while scrolling.
          child: BackdropGroup(
            child: Scaffold(
              resizeToAvoidBottomInset: true,
              // The glass header floats over the chat: messages scroll under it.
              extendBodyBehindAppBar: !state.selecting,
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
                      // One visible action (voice call) and a ⋮ menu, so the title and
                      // last seen keep their room.
                      actions: [
                        ...extensions.headerActions(context, chat),
                        _HeaderMenu(
                          entries: [
                            HeaderMenuEntry(Icons.search_rounded, 'Search in chat', () async {
                              final id = await Navigator.of(context).push<int>(ChatSearchScreen.route(chat));
                              if (id != null) await _cubit.jumpTo(id);
                            }),
                            ...extensions.headerMenu(context, chat),
                            if (chat.hasScheduledMessages)
                              HeaderMenuEntry(
                                Icons.schedule_send_rounded,
                                'Scheduled messages',
                                () => Navigator.of(context).push(ScheduledMessagesScreen.route(chat)),
                              ),
                          ],
                        ),
                      ],
                    ),
              body: extensions.backdrop(
                context,
                chat,
                // The list runs under the floating header and composer, so their
                // glass always has the chat moving behind it.
                Stack(
                  children: [
                    Stack(
                      children: [
                        Positioned.fill(child: _messageList(cache, isGroup, isChannel)),
                        if (state.pinned != null)
                          Positioned(
                            left: 0,
                            right: 0,
                            top: _headerInset,
                            child: PinnedBanner(
                              message: state.pinned!,
                              onTap: () => _cubit.jumpTo(state.pinned!.id),
                              onUnpin: cache.isAdmin(chat) || chat.type is td.ChatTypePrivate
                                  ? () => _cubit.unpin(state.pinned!)
                                  : null,
                            ),
                          ),
                      ],
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _MeasureHeight(
                        onHeight: _setComposerHeight,
                        child: canPost
                            ? ListenableBuilder(
                                listenable: extensions.composerListenable,
                                builder: (context, _) => Composer(
                                  controller: _text,
                                  replyTo: state.replyTo,
                                  replyQuote: state.replyQuote,
                                  editing: state.editing,
                                  onSend: _send,
                                  onCancelMode: () {
                                    if (state.editing != null) _text.clear();
                                    _cubit.cancelComposerMode();
                                  },
                                  onChanged: _cubit.composerChanged,
                                  onAttach: cache.canSendMedia(chat)
                                      ? () => extensions.onAttach(context, chat)
                                      : null,
                                  onVoice: cache.canSendVoice(chat)
                                      ? () => extensions.onVoice(context, chat, _text)
                                      : null,
                                  onVoiceStart: cache.canSendVoice(chat)
                                      ? () => extensions.onVoiceStart(context, chat)
                                      : null,
                                  onVoiceFinish: ({required bool send}) =>
                                      extensions.onVoiceFinish(context, chat, send: send),
                                  voiceRecording: extensions.voiceRecording(context, chat),
                                  onDictate: () => extensions.onDictate(context, chat, _text),
                                  onWritingTools: extensions.writingTools(context, _text),
                                  mediaPanel: extensions.mediaPanel(context, chat),
                                  recordingOverlay: extensions.recordingOverlay(context, chat),
                                  orbMode: extensions.orbMode(context, chat),
                                  loadPreview: _cubit.linkPreview,
                                  previewsOnSend: context.read<AppPreferences>().linkPreviewsOnSend,
                                ),
                              )
                            : _ReadOnlyBar(chat: chat, isChannel: isChannel),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _messageList(TelegramCache cache, bool isGroup, bool isChannel) =>
      BlocBuilder<ConversationCubit, ConversationState>(
        buildWhen: (a, b) =>
            !identical(a.messages, b.messages) ||
            !identical(a.chat, b.chat) ||
            !identical(a.sponsored, b.sponsored) ||
            a.revision != b.revision ||
            a.firstUnreadId != b.firstUnreadId ||
            a.highlightId != b.highlightId ||
            a.selected != b.selected ||
            a.hasOlder != b.hasOlder ||
            a.hasNewer != b.hasNewer ||
            a.initialLoading != b.initialLoading ||
            !identical(a.pendingReactions, b.pendingReactions) ||
            a.reactionBurst != b.reactionBurst,
        builder: (context, state) {
          final chat = state.chat ?? cache.chats[state.chatId]!;
          if (!_initialised && !state.initialLoading) {
            _initialised = true;
            _seenAtOpen.addAll(state.messages.map((m) => m.id));
            WidgetsBinding.instance.addPostFrameCallback((_) => _reportVisible());
          }
          _updateRows(state);
          _adsOffset = state.hasNewer ? 0 : state.sponsored.length;
          // A message that arrives while the chat is open (e.g. at the bottom,
          // not scrolling) is read as soon as it's drawn, so the sender sees it.
          final newest = state.messages.isEmpty ? 0 : state.messages.first.id;
          if (_initialised && newest != _newestShown) {
            _newestShown = newest;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _reportVisible();
            });
          }
          final empty = !state.initialLoading && _rows.isEmpty && !state.hasOlder
              ? ConversationExtensions.of(context).emptyChat(context, chat)
              : null;
          return Stack(
            children: [
              if (state.initialLoading)
                const Center(child: CircularProgressIndicator(color: GlowColors.violet))
              else if (empty != null)
                Center(
                  child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: empty),
                )
              else
                NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    // The glass drops to a plain blur while the list moves.
                    if (n is ScrollStartNotification) GlassMotion.set(true);
                    if (n is ScrollEndNotification) GlassMotion.set(false);
                    // Not while the open jump (or an anchor scroll) is landing:
                    // a page arriving mid-jump rebuilt and shifted the list.
                    if (_placed && _anchoring == 0) {
                      if (n.metrics.extentAfter < 800) _cubit.loadOlder();
                      if (n.metrics.extentBefore < 300 && state.hasNewer) _cubit.loadNewer();
                    }
                    if (n is ScrollEndNotification) _reportVisible();
                    if (n is ScrollUpdateNotification) _updateSticky(scrolling: true);
                    if (n is ScrollEndNotification) _updateSticky(scrolling: false);
                    return false;
                  },
                  child: !_routeSettled
                      ? const SizedBox.expand()
                      : AnimatedOpacity(
                          opacity: _placed ? 1 : 0,
                          duration: _placed ? const Duration(milliseconds: 160) : Duration.zero,
                          curve: Curves.easeOut,
                          child: SuperListView.builder(
                            reverse: true,
                            controller: _scroll,
                            listController: _list,
                            findChildIndexCallback: (key) {
                              if (key is! ValueKey) return null;
                              final i = _indexOfKey[key.value];
                              return i == null ? null : i + _adsOffset;
                            },
                            // Room for the floating header (and pinned banner) above the oldest row.
                            padding: EdgeInsets.only(
                              top: _headerInset + 8 + (state.pinned != null ? 60 : 0),
                              bottom: _composerHeight + 8,
                            ),
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
                ),
              // The day you're scrolling through, pinned at the top; fades a
              // second after scrolling stops. Tap for the calendar.
              if (_stickyDay case final day?)
                Positioned(
                  // Below the floating header and pinned card.
                  top: _headerInset + (state.pinned != null ? 60 : 0),
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    ignoring: !_stickyShown,
                    child: AnimatedOpacity(
                      opacity: _stickyShown ? 1 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: _DayHeader(day: day, onTap: () => _openCalendar(day)),
                    ),
                  ),
                ),
              if (_showJump || state.hasNewer)
                Positioned(
                  right: 16,
                  // Above the floating composer.
                  bottom: _composerHeight + 16,
                  child: _JumpButton(unread: chat.unreadCount, onTap: _cubit.jumpToLatest),
                ),
            ],
          );
        },
      );

  Widget _buildRow(MessageRow row, td.Chat chat, ConversationState state, bool isGroup, bool isChannel) {
    final prefs = context.read<AppPreferences>();
    return switch (row) {
      DayHeaderRow(:final day) => _DayHeader(
        key: ValueKey(_rowKey(row)),
        day: day,
        onTap: () => _openCalendar(day),
      ),
      UnreadDividerRow() => const _UnreadDivider(key: ValueKey('unread')),
      ServiceRow(:final message) => _ServiceBubble(key: ValueKey(message.id), message: message),
      BubbleRow() => _cachedBubble(row, chat, state, isGroup, isChannel, prefs),
    };
  }

  Widget _cachedBubble(
    BubbleRow row,
    td.Chat chat,
    ConversationState state,
    bool isGroup,
    bool isChannel,
    AppPreferences prefs,
  ) {
    final burst = state.reactionBurst;
    final inputs = <Object?>[
      for (final m in row.messages) identityHashCode(m),
      identityHashCode(chat),
      state.revision,
      isGroup,
      isChannel,
      _initialised,
      row.messages.any((m) => m.id == state.highlightId),
      row.messages.any((m) => state.selected.contains(m.id)),
      state.selecting,
      [
        for (final p in state.pendingReactions)
          if (p.startsWith('${row.primary.id}|')) p,
      ].join(','),
      burst != null && burst.messageId == row.primary.id ? burst.serial : null,
      prefs.messageSwipe(SwipeSide.left),
      prefs.messageSwipe(SwipeSide.right),
      prefs.swipeEmoji,
      prefs.doubleTap,
    ];
    final key = _rowKey(row);
    final hit = _rowWidgets[key];
    if (hit != null && listEquals(hit.inputs, inputs)) return hit.widget;
    final widget = _bubble(row, chat, state, isGroup, isChannel, prefs);
    _rowWidgets[key] = (inputs: inputs, widget: widget);
    return widget;
  }

  Widget _bubble(
    BubbleRow row,
    td.Chat chat,
    ConversationState state,
    bool isGroup,
    bool isChannel,
    AppPreferences prefs,
  ) {
    return MessageBubble(
      key: ValueKey(_cubit.stableId(row.id)),
      row: row,
      chat: chat,
      isGroup: isGroup,
      isChannel: isChannel,
      animateIn: _initialised && !_seenAtOpen.contains(row.id) && _animated.add(_cubit.stableId(row.id)),
      highlighted: row.messages.any((m) => m.id == state.highlightId),
      selected: row.messages.any((m) => state.selected.contains(m.id)),
      selecting: state.selecting,
      swipeLeft: prefs.messageSwipe(SwipeSide.left),
      swipeRight: prefs.messageSwipe(SwipeSide.right),
      swipeEmoji: prefs.swipeEmoji,
      onSwipe: (side) => switch (prefs.messageSwipe(side)) {
        MessageSwipe.reply => _cubit.startReply(row.primary),
        MessageSwipe.react => _react(row.primary, prefs.swipeEmoji),
        MessageSwipe.delete => _confirmAndDelete([for (final m in row.messages) m.id], chat),
        MessageSwipe.none => null,
      },
      onLongPress: () => _onLongPress(row.primary),
      onDoubleTap: prefs.doubleTap == MessageDoubleTap.none ? null : () => _onDoubleTap(row.primary, chat),
      onMenu: (rect) => _openMenu(
        row.primary,
        chat,
        anchor: rect,
        // The menu is its own route: hand the bubble the chat's cubit.
        bubble: BlocProvider.value(value: _cubit, child: _buildRow(row, chat, state, isGroup, isChannel)),
      ),
      onTap: () {
        if (state.selecting) _cubit.toggleSelected(row.primary);
      },
      onReplyQuoteTap: _cubit.jumpTo,
      pendingReactions: {
        for (final p in state.pendingReactions)
          if (p.startsWith('${row.primary.id}|')) p.substring(p.indexOf('|') + 1),
      },
      reactionBurst: switch (state.reactionBurst) {
        final b? when b.messageId == row.primary.id => (emoji: b.emoji, serial: b.serial),
        _ => null,
      },
      onReaction: (emoji) => _react(row.primary, emoji),
      onSwitchInline: (query) {
        final text = '$query ';
        _text.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
      },
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({super.key, required this.day, this.onTap});

  final DateTime day;

  /// Opens the calendar to jump to another day.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      button: onTap != null,
      hint: onTap != null ? 'Jump to a date' : null,
      child: Center(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              // Dark glass: readable over any wallpaper.
              color: Colors.black.withValues(alpha: 0.38),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Text(
              Display.dayHeader(day, DateTime.now()),
              style: const TextStyle(fontSize: 12, color: Color(0xFFD0D6DE), fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }
}

class _UnreadDivider extends StatelessWidget {
  const _UnreadDivider({super.key});

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
  const _ServiceBubble({super.key, required this.message});

  final td.Message message;

  @override
  Widget build(BuildContext context) {
    final text = Display.serviceText(context.read<TelegramCache>(), message) ?? '';
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 40),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.38),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: Color(0xFFD0D6DE)),
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

/// Shown instead of the composer where the account can't post: Subscribe /
/// Join when it isn't a member of a public supergroup or channel, Mute /
/// Unmute in a channel it follows, otherwise a line saying why.
class _ReadOnlyBar extends StatefulWidget {
  const _ReadOnlyBar({required this.chat, required this.isChannel});

  final td.Chat chat;
  final bool isChannel;

  @override
  State<_ReadOnlyBar> createState() => _ReadOnlyBarState();
}

class _ReadOnlyBarState extends State<_ReadOnlyBar> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = widget.chat;
    final cache = context.read<TelegramCache>();
    final member = cache.isMember(chat);
    final Widget child;
    Color? tint;
    if (!member && chat.type is td.ChatTypeSupergroup) {
      // The main action: violet-tinted glass.
      tint = GlowColors.violetDeep.withValues(alpha: 0.55);
      child = TextButton(
        style: TextButton.styleFrom(
          foregroundColor: GlowColors.text,
          minimumSize: const Size.fromHeight(48),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        onPressed: _busy ? null : () => _run(() => context.read<ChatInfoRepository>().join(chat)),
        child: Text(widget.isChannel ? 'Subscribe' : 'Join group'),
      );
    } else if (member && widget.isChannel) {
      final muted = cache.isMuted(chat);
      child = TextButton.icon(
        style: TextButton.styleFrom(
          foregroundColor: GlowColors.text,
          minimumSize: const Size.fromHeight(48),
          shape: const StadiumBorder(),
        ),
        onPressed: _busy ? null : () => _run(() => context.read<ChatsRepository>().setMuted(chat.id, !muted)),
        icon: Icon(muted ? Icons.notifications_off_rounded : Icons.notifications_rounded),
        label: Text(muted ? 'Unmute' : 'Mute'),
      );
    } else {
      final waiting = member && chat.type is td.ChatTypeSecret;
      final text = !member
          ? 'You are not a member'
          : waiting
          ? 'Waiting for the secret chat to start…'
          : 'Sending messages is restricted here';
      final accent = waiting ? GlowColors.cyan : GlowColors.textMuted;
      child = Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              waiting ? Icons.lock_rounded : (member ? Icons.block_rounded : Icons.person_off_rounded),
              size: 18,
              color: accent,
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(color: waiting ? GlowColors.text : GlowColors.textMuted, fontSize: 14),
              ),
            ),
            if (waiting) ...[
              const SizedBox(width: 12),
              const SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: GlowColors.cyan),
              ),
            ],
          ],
        ),
      );
    }
    // A floating glass pill over the chat, like the composer.
    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
          child: GlassGroup(
            shareBackdrop: true,
            child: GlassPill(radius: 24, tint: tint, child: child),
          ),
        ),
      ),
    );
  }
}

/// The reaction panel's data, straight from TDLib.
class _TdReactionCatalog implements ReactionCatalog {
  _TdReactionCatalog(this._repo, this._chatId, this._messageId, this._language);

  final MessagesRepository _repo;
  final int _chatId;
  final int _messageId;
  final String _language;

  @override
  Future<({List<String> recent, List<String> popular})> sections() =>
      _repo.reactionSections(_chatId, _messageId);

  @override
  Future<List<({String name, List<String> emojis})>> categories() => _repo.emojiCategories();

  @override
  Future<List<String>> search(String query) => _repo.searchEmojis(query, {'en', _language}.toList());
}

/// The chat header's ⋮ menu.
class _HeaderMenu extends StatelessWidget {
  const _HeaderMenu({required this.entries});
  final List<HeaderMenuEntry> entries;

  @override
  Widget build(BuildContext context) => PopupMenuButton<int>(
    tooltip: 'More',
    icon: const Icon(Icons.more_vert_rounded),
    color: GlowColors.surfaceHigh,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    onSelected: (i) => entries[i].onSelected(),
    itemBuilder: (context) => [
      for (var i = 0; i < entries.length; i++)
        PopupMenuItem<int>(
          value: i,
          child: Row(
            children: [
              Icon(entries[i].icon, size: 20, color: GlowColors.text),
              const SizedBox(width: 12),
              Text(entries[i].label),
            ],
          ),
        ),
    ],
  );
}

/// Reports its child's height after every layout that changes it.
class _MeasureHeight extends SingleChildRenderObjectWidget {
  const _MeasureHeight({required this.onHeight, required super.child});

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderMeasureHeight(onHeight);

  @override
  void updateRenderObject(BuildContext context, _RenderMeasureHeight renderObject) =>
      renderObject.onHeight = onHeight;
}

class _RenderMeasureHeight extends RenderProxyBox {
  _RenderMeasureHeight(this.onHeight);

  ValueChanged<double> onHeight;
  double? _last;

  @override
  void performLayout() {
    super.performLayout();
    final h = size.height;
    if (h != _last) {
      _last = h;
      WidgetsBinding.instance.addPostFrameCallback((_) => onHeight(h));
    }
  }
}
