import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../core/platform/system_channel.dart';
import '../../../core/telegram/display.dart';
import '../../../core/telegram/telegram_cache.dart';
import '../../../core/telegram/widgets/animated_sticker.dart';
import '../../../core/telegram/widgets/chat_avatar.dart';
import '../../../core/telegram/widgets/td_file_image.dart';
import '../../../core/theme/glow_colors.dart';
import '../../../core/widgets/delete_confirm.dart';
import '../../../core/widgets/glow_button.dart';
import '../../../core/widgets/glow_sheet.dart';
import '../../chats/data/chats_repository.dart';
import '../data/user_profile_repository.dart';
import 'profile_photo_viewer.dart';

typedef CallFn = void Function(int userId, {required bool video});

/// A user's full profile: photo gallery header, action orbs (message, mute,
/// call, video, more), an info card with everything TDLib offers, their
/// posts, and tabs of shared media, files, links, music, voice, GIFs,
/// gifts and groups in common. "More" holds secret chat, edit, share
/// (Android share or QR), block and delete; destructive ones confirm.
class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({
    super.key,
    required this.userId,
    required this.onMessage,
    required this.onCall,
    this.onOpenChat,
    this.onShowQr,
    this.botSection,
  });

  final int userId;
  final ValueChanged<int> onMessage;
  final CallFn onCall;

  /// Opens a chat by id (groups in common, a new secret chat).
  final ValueChanged<int>? onOpenChat;

  /// A bot's own section (about, commands, privacy policy), built by the
  /// bots feature; shown only for bots.
  final Widget Function(BuildContext context, td.User user, td.UserFullInfo full)? botSection;

  /// Shows a QR code for a link.
  final void Function(String url, String title)? onShowQr;

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  late final _repo = context.read<UserProfileRepository>();
  late final _cache = context.read<TelegramCache>();
  td.UserFullInfo? _full;
  final _gallery = GlobalKey<_GalleryState>();
  var _pulled = false;
  List<td.ChatPhoto> _photos = const [];
  List<td.Story> _posts = const [];

  td.User? get _user => _cache.users[widget.userId];
  bool get _blocked => _full?.blockList != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final full = await _repo.fullInfo(widget.userId);
      if (mounted) setState(() => _full = full);
    } catch (_) {}
    try {
      final photos = await _repo.photos(widget.userId);
      if (mounted) setState(() => _photos = photos);
    } catch (_) {}
    try {
      final posts = await _repo.posts(widget.userId);
      if (mounted) setState(() => _posts = posts);
    } catch (_) {}
  }

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _copy(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) _snack('$label copied');
  }

  String get _username => _user?.usernames?.activeUsernames.firstOrNull ?? '';
  String get _link => _username.isNotEmpty ? 'https://t.me/$_username' : 'tg://user?id=${widget.userId}';

  Future<void> _toggleMute() async {
    final chat = _cache.chats[widget.userId];
    if (chat == null) return;
    await context.read<ChatsRepository>().setMuted(chat.id, !_cache.isMuted(chat));
    if (mounted) setState(() {});
  }

  Future<void> _more() async {
    final user = _user;
    if (user == null) return;
    final action = await showGlowSheet<String>(
      context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (id, icon, label, color) in [
            ('secret', Icons.lock_rounded, 'Start secret chat', GlowColors.teal),
            ('edit', Icons.edit_rounded, user.isContact ? 'Edit contact' : 'Add to contacts', null),
            ('share', Icons.share_rounded, 'Share contact', null),
            ('qr', Icons.qr_code_2_rounded, 'Show QR code', null),
            (
              'block',
              _blocked ? Icons.lock_open_rounded : Icons.block_rounded,
              _blocked ? 'Unblock' : 'Block',
              GlowColors.coral,
            ),
            if (user.isContact) ('delete', Icons.person_remove_rounded, 'Delete contact', GlowColors.coral),
          ])
            ListTile(
              leading: Icon(icon, color: color),
              title: Text(label, style: TextStyle(color: color)),
              onTap: () => Navigator.pop(context, id),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
    if (!mounted || action == null) return;
    try {
      switch (action) {
        case 'secret':
          final chat = await _repo.startSecretChat(user.id);
          widget.onOpenChat?.call(chat.id);
        case 'edit':
          await _editContact(user);
        case 'share':
          final phone = user.phoneNumber.isEmpty ? '' : '\n+${user.phoneNumber}';
          await const SystemChannel().shareText('${Display.userName(user)}$phone\n$_link');
        case 'qr':
          widget.onShowQr?.call(_link, Display.userName(user));
        case 'block':
          if (!_blocked) {
            final ok = await showGlowConfirm(
              context,
              title: 'Block ${Display.userName(user)}?',
              message: 'They won\'t be able to message or call you.',
              confirmLabel: 'Block',
              icon: Icons.block_rounded,
              destructive: true,
            );
            if (!ok) return;
          }
          await _repo.setBlocked(user.id, !_blocked);
          await _load();
        case 'delete':
          final ok = await confirmDelete(context, title: 'Delete ${Display.userName(user)} from contacts?');
          if (ok == null) return;
          await _repo.deleteContact(user.id);
          if (mounted) setState(() {});
      }
    } catch (e) {
      if (mounted) _snack('$e');
    }
  }

  Future<void> _editContact(td.User user) async {
    final first = TextEditingController(text: user.firstName);
    final last = TextEditingController(text: user.lastName);
    final save = await showGlowSheet<bool>(
      context,
      title: user.isContact ? 'Edit contact' : 'Add to contacts',
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: first,
              decoration: const InputDecoration(labelText: 'First name'),
            ),
            TextField(
              controller: last,
              decoration: const InputDecoration(labelText: 'Last name'),
            ),
            const SizedBox(height: 16),
            GlowButton(label: 'Save', onPressed: () => Navigator.pop(context, true)),
          ],
        ),
      ),
    );
    if (save == true && first.text.trim().isNotEmpty) {
      await _repo.saveContact(user, firstName: first.text.trim(), lastName: last.text.trim());
      if (mounted) setState(() {});
    }
    first.dispose();
    last.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    if (user == null) return const Scaffold(body: Center(child: Text('Unknown user')));
    final name = Display.userName(user);
    final chat = _cache.chats[user.id];
    final muted = chat != null && _cache.isMuted(chat);
    final canCall = _full?.canBeCalled ?? true;
    return DefaultTabController(
      length: ProfileTab.values.length,
      child: Scaffold(
        // Pulling down at the top opens the photos full screen.
        body: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n is OverscrollNotification &&
                n.overscroll < -12 &&
                n.metrics.extentBefore == 0 &&
                !_pulled) {
              _pulled = true;
              _gallery.currentState?.open();
            }
            if (n is ScrollEndNotification) _pulled = false;
            return false;
          },
          child: NestedScrollView(
            headerSliverBuilder: (context, _) => [
              SliverAppBar(pinned: true, title: Text(name)),
              // Not in the app bar's flexible space: its layers there swallowed
              // the gallery's swipes and taps.
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 320,
                  child: _Gallery(key: _gallery, user: user, photos: _photos, personal: _full?.personalPhoto),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (user.isPremium)
                            const Padding(
                              padding: EdgeInsets.only(left: 6),
                              child: Icon(Icons.auto_awesome_rounded, color: GlowColors.violet, size: 18),
                            ),
                          if (user.verificationStatus?.isVerified ?? false)
                            const Padding(
                              padding: EdgeInsets.only(left: 6),
                              child: Icon(Icons.verified_rounded, color: GlowColors.cyan, size: 18),
                            ),
                        ],
                      ),
                      Text(
                        _blocked ? 'Blocked' : Display.status(user),
                        style: TextStyle(color: _blocked ? GlowColors.coral : GlowColors.textMuted),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _Orb(
                            icon: Icons.chat_bubble_rounded,
                            label: 'Message',
                            onTap: () => widget.onMessage(user.id),
                          ),
                          _Orb(
                            icon: muted ? Icons.notifications_off_rounded : Icons.notifications_rounded,
                            label: muted ? 'Unmute' : 'Mute',
                            onTap: chat == null ? null : _toggleMute,
                          ),
                          _Orb(
                            icon: Icons.call_rounded,
                            label: 'Voice call',
                            onTap: canCall ? () => widget.onCall(user.id, video: false) : null,
                          ),
                          _Orb(
                            icon: Icons.videocam_rounded,
                            label: 'Video call',
                            onTap: canCall && (_full?.supportsVideoCalls ?? true)
                                ? () => widget.onCall(user.id, video: true)
                                : null,
                          ),
                          _Orb(icon: Icons.more_horiz_rounded, label: 'More', onTap: _more),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _InfoCard(
                        children: [
                          if (user.phoneNumber.isNotEmpty)
                            _InfoRow(
                              icon: Icons.phone_rounded,
                              value: '+${user.phoneNumber}',
                              label: 'Mobile',
                              onTap: () => _copy('Phone', '+${user.phoneNumber}'),
                            ),
                          if (_username.isNotEmpty)
                            _InfoRow(
                              icon: Icons.alternate_email_rounded,
                              value: '@$_username',
                              label: 'Username',
                              onTap: () => _copy('Username', '@$_username'),
                              trailing: widget.onShowQr == null
                                  ? null
                                  : IconButton(
                                      tooltip: 'QR code',
                                      icon: const Icon(Icons.qr_code_2_rounded),
                                      onPressed: () => widget.onShowQr!(_link, name),
                                    ),
                            ),
                          _InfoRow(
                            icon: Icons.tag_rounded,
                            value: '${user.id}',
                            label: 'User ID',
                            onTap: () => _copy('User ID', '${user.id}'),
                          ),
                          if (_full?.bio case final bio? when bio.text.isNotEmpty)
                            _InfoRow(icon: Icons.info_outline_rounded, value: bio.text, label: 'Bio'),
                          if (_full?.birthdate case final b?)
                            _InfoRow(
                              icon: Icons.cake_rounded,
                              value: '${b.day}/${b.month}${b.year == 0 ? '' : '/${b.year}'}',
                              label: 'Birthday',
                            ),
                          if (_full?.businessInfo?.location case final loc? when loc.address.isNotEmpty)
                            _InfoRow(icon: Icons.place_rounded, value: loc.address, label: 'Location'),
                        ],
                      ),
                      if (widget.botSection case final section?
                          when user.type is td.UserTypeBot && _full?.botInfo != null) ...[
                        const SizedBox(height: 16),
                        section(context, user, _full!),
                      ],
                      if (_posts.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        const Text(
                          'POSTS',
                          style: TextStyle(
                            color: GlowColors.violet,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 96,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [for (final s in _posts) _PostThumb(story: s)],
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
              SliverPersistentHeader(pinned: true, delegate: _TabsHeader()),
            ],
            body: TabBarView(
              children: [
                for (final tab in ProfileTab.values)
                  _TabBody(userId: user.id, tab: tab, onOpenChat: widget.onOpenChat),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Gallery extends StatefulWidget {
  const _Gallery({super.key, required this.user, required this.photos, this.personal});

  final td.User user;
  final List<td.ChatPhoto> photos;

  /// The photo you set for this contact; shown first, like Telegram.
  final td.ChatPhoto? personal;

  @override
  State<_Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<_Gallery> {
  var _page = 0;
  final _pages = PageController();

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  List<td.ChatPhoto> get _all {
    final personal = widget.personal;
    return [?personal, ...widget.photos.where((p) => p.id != personal?.id)];
  }

  /// Full screen, starting at the photo on show.
  void open() {
    final photos = _all;
    if (photos.isEmpty) return;
    Navigator.of(context).push(ProfilePhotoViewer.route(photos, _page.clamp(0, photos.length - 1)));
  }

  void _go(int delta, int count) {
    final next = (_page + delta).clamp(0, count - 1);
    if (next != _page) {
      _pages.animateToPage(next, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final personal = widget.personal;
    final photos = [?personal, ...widget.photos.where((p) => p.id != personal?.id)];
    if (photos.isEmpty) {
      return Center(child: ChatAvatar.user(widget.user, size: 120));
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        // Swipe, or tap the left/right side, like Telegram.
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) =>
              _go(d.localPosition.dx > MediaQuery.sizeOf(context).width / 2 ? 1 : -1, photos.length),
          child: PageView.builder(
            controller: _pages,
            itemCount: photos.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, i) {
              final sizes = photos[i].sizes;
              final mine = personal != null && i == 0;
              return Semantics(
                label: 'Profile photo ${i + 1} of ${photos.length}${mine ? ', set by you' : ''}',
                image: true,
                excludeSemantics: true,
                child: sizes.isEmpty
                    ? ChatAvatar.user(widget.user, size: 120)
                    : TdFileImage(
                        file: sizes.last.photo,
                        placeholderBytes: Display.minithumbnail(photos[i].minithumbnail),
                      ),
              );
            },
          ),
        ),
        // The contrast scrim must not take touches, or swipes never reach
        // the photos.
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x66000000), Color(0x00000000), Color(0x99000000)],
              ),
            ),
          ),
        ),
        // The photo you set for a contact isn't their real profile photo.
        if (personal != null && _page == 0)
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: GlowColors.violet.withValues(alpha: 0.6)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.visibility_rounded, size: 14, color: GlowColors.violet),
                      SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Set by you · only you see this photo',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (photos.length > 1)
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < photos.length; i++)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _page ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == _page ? Colors.white : Colors.white54,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Orb extends StatelessWidget {
  const _Orb({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = onTap == null ? GlowColors.textMuted : GlowColors.violet;
    return Tooltip(
      message: label,
      child: InkResponse(
        onTap: onTap,
        radius: 32,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.15),
                border: Border.all(color: color.withValues(alpha: 0.6)),
                boxShadow: onTap == null ? null : glow(color, intensity: 0.4),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(height: 6),
            Text(switch (label) {
              'Voice call' => 'Call',
              'Video call' => 'Video',
              _ => label,
            }, style: TextStyle(color: color, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
    color: GlowColors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: const BorderSide(color: GlowColors.outline),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(children: children),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.value, required this.label, this.onTap, this.trailing});

  final IconData icon;
  final String value;
  final String label;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: GlowColors.cyan),
    title: Text(value),
    subtitle: Text(label, style: const TextStyle(color: GlowColors.textMuted, fontSize: 12)),
    trailing:
        trailing ??
        (onTap == null ? null : const Icon(Icons.copy_rounded, size: 18, color: GlowColors.textMuted)),
    onTap: onTap,
  );
}

class _PostThumb extends StatelessWidget {
  const _PostThumb({required this.story});

  final td.Story story;

  @override
  Widget build(BuildContext context) {
    final (file, mini) = switch (story.content) {
      td.StoryContentPhoto(:final photo) => (photo.sizes.firstOrNull?.photo, photo.minithumbnail),
      td.StoryContentVideo(:final video) => (video.thumbnail?.file, video.minithumbnail),
      _ => (null, null),
    };
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: 64,
          height: 96,
          child: file == null
              ? const ColoredBox(color: GlowColors.surfaceHigh)
              : TdFileImage(file: file, placeholderBytes: Display.minithumbnail(mini)),
        ),
      ),
    );
  }
}

class _TabsHeader extends SliverPersistentHeaderDelegate {
  @override
  double get minExtent => 48;
  @override
  double get maxExtent => 48;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => Material(
    color: GlowColors.background,
    child: TabBar(
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      indicatorColor: GlowColors.violet,
      labelColor: GlowColors.violet,
      unselectedLabelColor: GlowColors.textMuted,
      tabs: [for (final t in ProfileTab.values) Tab(text: t.label)],
    ),
  );

  @override
  bool shouldRebuild(_TabsHeader oldDelegate) => false;
}

/// One tab, loaded when first shown.
class _TabBody extends StatefulWidget {
  const _TabBody({required this.userId, required this.tab, this.onOpenChat});

  final int userId;
  final ProfileTab tab;
  final ValueChanged<int>? onOpenChat;

  @override
  State<_TabBody> createState() => _TabBodyState();
}

class _TabBodyState extends State<_TabBody> with AutomaticKeepAliveClientMixin {
  late final Future<List<Object>> _items = _load();

  @override
  bool get wantKeepAlive => true;

  Future<List<Object>> _load() async {
    final repo = context.read<UserProfileRepository>();
    return switch (widget.tab) {
      ProfileTab.gifts => await repo.gifts(widget.userId),
      ProfileTab.groups => await repo.groupsInCommon(widget.userId),
      _ => await repo.shared(widget.userId, widget.tab),
    };
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<List<Object>>(
      future: _items,
      builder: (context, snap) {
        if (snap.hasError) return _empty('Couldn\'t load ${widget.tab.label.toLowerCase()}');
        if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: GlowColors.violet));
        final items = snap.data!;
        if (items.isEmpty) return _empty('No ${widget.tab.label.toLowerCase()} yet');
        return switch (widget.tab) {
          ProfileTab.media || ProfileTab.gifs => GridView.builder(
            padding: const EdgeInsets.all(2),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
            ),
            itemCount: items.length,
            itemBuilder: (context, i) => _MediaCell(message: items[i] as td.Message),
          ),
          ProfileTab.gifts => GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3),
            itemCount: items.length,
            itemBuilder: (context, i) => _GiftCell(gift: items[i] as td.ReceivedGift),
          ),
          ProfileTab.groups => ListView(
            children: [
              for (final id in items.cast<int>())
                if (context.read<TelegramCache>().chats[id] case final chat?)
                  ListTile(
                    leading: ChatAvatar.chat(chat, size: 40),
                    title: Text(chat.title),
                    onTap: widget.onOpenChat == null ? null : () => widget.onOpenChat!(id),
                  ),
            ],
          ),
          _ => ListView(
            children: [for (final m in items.cast<td.Message>()) _MessageRow(message: m, tab: widget.tab)],
          ),
        };
      },
    );
  }

  Widget _empty(String text) => Center(
    child: Text(text, style: const TextStyle(color: GlowColors.textMuted)),
  );
}

class _MediaCell extends StatelessWidget {
  const _MediaCell({required this.message});

  final td.Message message;

  @override
  Widget build(BuildContext context) {
    final (file, mini, video) = switch (message.content) {
      td.MessagePhoto(:final photo) => (photo.sizes.firstOrNull?.photo, photo.minithumbnail, false),
      td.MessageVideo(:final video) => (video.thumbnail?.file, video.minithumbnail, true),
      td.MessageAnimation(:final animation) => (animation.thumbnail?.file, animation.minithumbnail, true),
      _ => (null, null, false),
    };
    return Stack(
      fit: StackFit.expand,
      children: [
        if (file != null)
          TdFileImage(file: file, placeholderBytes: Display.minithumbnail(mini))
        else
          const ColoredBox(color: GlowColors.surfaceHigh),
        if (video) const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white70)),
      ],
    );
  }
}

class _GiftCell extends StatelessWidget {
  const _GiftCell({required this.gift});

  final td.ReceivedGift gift;

  @override
  Widget build(BuildContext context) {
    final sticker = switch (gift.gift) {
      td.SentGiftRegular(:final gift) => gift.sticker,
      td.SentGiftUpgraded(:final gift) => gift.model.sticker,
    };
    return Center(child: AnimatedSticker(sticker: sticker, size: 72));
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({required this.message, required this.tab});

  final td.Message message;
  final ProfileTab tab;

  @override
  Widget build(BuildContext context) {
    final cache = context.read<TelegramCache>();
    final (icon, title) = switch (message.content) {
      td.MessageDocument(:final document) => (Icons.insert_drive_file_rounded, document.fileName),
      td.MessageAudio(:final audio) => (
        Icons.music_note_rounded,
        audio.title.isEmpty ? audio.fileName : '${audio.performer} – ${audio.title}',
      ),
      td.MessageVoiceNote() => (Icons.mic_rounded, 'Voice message'),
      td.MessageVideoNote() => (Icons.radio_button_checked_rounded, 'Video message'),
      _ => (Icons.link_rounded, Display.preview(cache, message)),
    };
    return ListTile(
      leading: Icon(icon, color: GlowColors.cyan),
      title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        Display.relativeTime(DateTime.fromMillisecondsSinceEpoch(message.date * 1000), DateTime.now()),
        style: const TextStyle(color: GlowColors.textMuted, fontSize: 12),
      ),
    );
  }
}
