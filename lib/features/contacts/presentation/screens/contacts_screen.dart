import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../../core/telegram/display.dart';
import '../../../../core/telegram/profile_opener.dart';
import '../../../../core/telegram/telegram_cache.dart';
import '../../../../core/telegram/widgets/chat_avatar.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../../chat_info/data/chat_info_repository.dart';
import '../../../conversation/presentation/screens/conversation_screen.dart';
import '../../data/contacts_repository.dart';
import '../widgets/contact_sheets.dart';
import 'add_contact_screen.dart';

/// The Contacts tab: everyone you saved, A→Z with letter headers and who's
/// online on top; search by name, number or @username (people who aren't
/// contacts yet can be added from the results); add by phone number.
class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  late final ContactsRepository _repo = context.read<ContactsRepository>();
  final _query = TextEditingController();
  Timer? _debounce;
  List<int>? _results;

  @override
  void initState() {
    super.initState();
    _repo.load().ignore();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _search(String q) {
    _debounce?.cancel();
    q = q.trim();
    if (q.isEmpty) {
      setState(() => _results = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      var ids = await _repo.search(q).catchError((Object _) => <int>[]);
      // Not a contact yet? An exact @username still finds them.
      if (q.replaceFirst('@', '').length >= 4) {
        final found = await _repo.findUsername(q);
        if (found != null && !ids.contains(found)) ids = [...ids, found];
      }
      if (mounted && _query.text.trim() == q) setState(() => _results = ids);
    });
  }

  Future<void> _message(BuildContext context, int userId) async {
    final nav = Navigator.of(context);
    try {
      final chat = await context.read<ChatInfoRepository>().privateChat(userId);
      await nav.push(ConversationScreen.route(chat.id));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  void _profile(BuildContext context, int userId) =>
      ProfileOpener.maybeOf(context)?.openUser(context, userId).ignore();

  void _add() => Navigator.of(context).push(AddContactScreen.route(onMessage: _message, onProfile: _profile));

  @override
  Widget build(BuildContext context) {
    final cache = context.read<TelegramCache>();
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: _repo,
          builder: (context, _) {
            final all = _repo.ids;
            final results = _results;
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: ShaderMask(
                            blendMode: BlendMode.srcIn,
                            shaderCallback: (b) =>
                                const LinearGradient(colors: [GlowColors.violet, GlowColors.cyan])
                                    .createShader(b),
                            child: const Text(
                              'Contacts',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        if (all != null)
                          Text('${all.length}', style: const TextStyle(color: GlowColors.textMuted)),
                        IconButton(
                          tooltip: 'Add contact',
                          onPressed: _add,
                          icon: const Icon(Icons.person_add_alt_1_rounded, color: GlowColors.cyan),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: TextField(
                      controller: _query,
                      onChanged: _search,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search_rounded),
                        hintText: 'Name, number or @username',
                        filled: true,
                        fillColor: GlowColors.surface.withValues(alpha: 0.7),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        suffixIcon: _query.text.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close_rounded),
                                onPressed: () {
                                  _query.clear();
                                  _search('');
                                },
                              ),
                      ),
                    ),
                  ),
                ),
                if (results == null) ...[
                  SliverToBoxAdapter(
                    child: _ActionTile(
                      icon: Icons.dialpad_rounded,
                      title: 'Add by phone number',
                      subtitle: 'Find someone on Telegram by their number',
                      onTap: _add,
                    ),
                  ),
                  if (all == null)
                    const SliverToBoxAdapter(child: LinearProgressIndicator(minHeight: 2))
                  else if (all.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Text(
                          'No contacts yet.\nAdd people by number, or from their profile.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: GlowColors.textMuted),
                        ),
                      ),
                    )
                  else
                    ..._grouped(cache, all),
                ] else if (results.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text('Nobody found', style: TextStyle(color: GlowColors.textMuted)),
                    ),
                  )
                else
                  SliverList.builder(
                    itemCount: results.length,
                    itemBuilder: (context, i) => _row(cache, results[i]),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 120)),
              ],
            );
          },
        ),
      ),
    );
  }

  /// "Online now", then A, B, C… sections.
  List<Widget> _grouped(TelegramCache cache, List<int> ids) {
    final online = [
      for (final id in ids)
        if (cache.users[id]?.status is td.UserStatusOnline) id,
    ];
    final sections = <String, List<int>>{};
    for (final id in ids) {
      final name = Display.userName(cache.users[id]).trim();
      final letter = name.isEmpty ? '#' : name.characters.first.toUpperCase();
      sections.putIfAbsent(RegExp(r'\p{L}', unicode: true).hasMatch(letter) ? letter : '#', () => []).add(id);
    }
    return [
      if (online.isNotEmpty) ...[
        const _Header('Online now', color: GlowColors.cyan),
        SliverList.builder(itemCount: online.length, itemBuilder: (context, i) => _row(cache, online[i])),
      ],
      for (final MapEntry(key: letter, value: list) in sections.entries) ...[
        _Header(letter),
        SliverList.builder(itemCount: list.length, itemBuilder: (context, i) => _row(cache, list[i])),
      ],
    ];
  }

  Widget _row(TelegramCache cache, int id) {
    final u = cache.users[id];
    final contact = u?.isContact ?? false;
    final online = u?.status is td.UserStatusOnline;
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 16, right: 8),
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          ChatAvatar.user(u, size: 46),
          if (online)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: GlowColors.cyan,
                  border: Border.all(color: GlowColors.background, width: 2),
                ),
              ),
            ),
        ],
      ),
      title: Text(Display.userName(u), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        Display.status(u),
        style: TextStyle(color: online ? GlowColors.cyan : GlowColors.textMuted, fontSize: 13),
      ),
      trailing: contact
          ? IconButton(
              tooltip: 'Message',
              icon: const Icon(Icons.chat_bubble_outline_rounded, color: GlowColors.violet),
              onPressed: () => _message(context, id),
            )
          : TextButton.icon(
              onPressed: () => showContactEditor(context, id),
              icon: const Icon(Icons.person_add_rounded, size: 18),
              label: const Text('Add'),
            ),
      onTap: () => _profile(context, id),
      onLongPress: () => showContactActions(
        context,
        id,
        onMessage: () => _message(context, id),
        onProfile: () => _profile(context, id),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text, {this.color = GlowColors.violet});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.1),
      ),
    ),
  );
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Container(
      width: 46,
      height: 46,
      decoration: const BoxDecoration(shape: BoxShape.circle, gradient: GlowColors.active),
      child: Icon(icon, color: Colors.white),
    ),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
    subtitle: Text(subtitle, style: const TextStyle(color: GlowColors.textMuted, fontSize: 13)),
    onTap: onTap,
  );
}
