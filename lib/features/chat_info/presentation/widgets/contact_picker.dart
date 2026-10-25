import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/telegram/display.dart';
import '../../../../core/telegram/telegram_cache.dart';
import '../../../../core/telegram/widgets/chat_avatar.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../data/chat_info_repository.dart';

/// Picks one or many users from contacts, search, or an @username.
class ContactPickerScreen extends StatefulWidget {
  const ContactPickerScreen({super.key, required this.title, this.multiple = false, this.actionLabel = 'Done'});

  final String title;
  final bool multiple;
  final String actionLabel;

  static Future<List<int>?> pick(
    BuildContext context, {
    required String title,
    bool multiple = false,
    String actionLabel = 'Done',
  }) => Navigator.of(context).push<List<int>>(
    MaterialPageRoute(
      builder: (_) => ContactPickerScreen(title: title, multiple: multiple, actionLabel: actionLabel),
    ),
  );

  @override
  State<ContactPickerScreen> createState() => _ContactPickerScreenState();
}

class _ContactPickerScreenState extends State<ContactPickerScreen> {
  late final _repo = context.read<ChatInfoRepository>();
  List<int> _ids = const [];
  final _selected = <int>{};
  Timer? _debounce;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load(String q) async {
    try {
      var ids = q.isEmpty ? await _repo.contacts() : await _repo.searchContacts(q);
      if (q.length >= 4 && ids.isEmpty) {
        final byName = await _repo.findUser(q);
        if (byName != null) ids = [byName];
      }
      if (mounted) setState(() => _ids = ids);
    } catch (_) {
      // Bots have no contacts.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cache = context.read<TelegramCache>();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: GlowColors.background,
        title: Text(widget.title),
        actions: [
          if (widget.multiple)
            TextButton(
              onPressed: _selected.isEmpty ? null : () => Navigator.pop(context, _selected.toList()),
              child: Text('${widget.actionLabel}${_selected.isEmpty ? '' : ' (${_selected.length})'}'),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Name or @username'),
              onChanged: (q) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 250), () => _load(q.trim()));
              },
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: ListView.builder(
              itemCount: _ids.length,
              itemBuilder: (context, i) {
                final u = cache.users[_ids[i]];
                final selected = _selected.contains(_ids[i]);
                return ListTile(
                  leading: ChatAvatar.user(u, size: 42),
                  title: Text(Display.userName(u)),
                  subtitle: Text(Display.status(u), style: const TextStyle(color: GlowColors.textMuted)),
                  trailing: widget.multiple
                      ? Icon(
                          selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                          color: selected ? GlowColors.violet : GlowColors.outlineStrong,
                        )
                      : null,
                  onTap: () {
                    if (!widget.multiple) {
                      Navigator.pop(context, [_ids[i]]);
                    } else {
                      setState(() => selected ? _selected.remove(_ids[i]) : _selected.add(_ids[i]));
                    }
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
