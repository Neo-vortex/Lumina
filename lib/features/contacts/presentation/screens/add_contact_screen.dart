import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/platform/system_channel.dart';
import '../../../../core/telegram/display.dart';
import '../../../../core/telegram/telegram_cache.dart';
import '../../../../core/telegram/widgets/chat_avatar.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../../../core/widgets/glow_button.dart';
import '../../../auth/presentation/widgets/country_phone_field.dart';
import '../../data/contacts_repository.dart';

/// "Add contact" wizard: 1. phone number, 2. name, 3. who that is on
/// Telegram (message them or see the profile), or an invite if nobody is.
class AddContactScreen extends StatefulWidget {
  const AddContactScreen({super.key, required this.onMessage, required this.onProfile});

  final void Function(BuildContext context, int userId) onMessage;
  final void Function(BuildContext context, int userId) onProfile;

  static Route<void> route({
    required void Function(BuildContext context, int userId) onMessage,
    required void Function(BuildContext context, int userId) onProfile,
  }) => MaterialPageRoute(
    builder: (_) => AddContactScreen(onMessage: onMessage, onProfile: onProfile),
  );

  @override
  State<AddContactScreen> createState() => _AddContactScreenState();
}

enum _Step { phone, name, result }

class _AddContactScreenState extends State<AddContactScreen> {
  final _phone = TextEditingController();
  final _first = TextEditingController();
  final _last = TextEditingController();
  var _step = _Step.phone;
  String? _phoneError;
  var _busy = false;
  PhoneLookup? _result;

  @override
  void dispose() {
    _phone.dispose();
    _first.dispose();
    _last.dispose();
    super.dispose();
  }

  String get _digits => _phone.text.replaceAll(RegExp(r'[^0-9]'), '');

  void _toName() {
    if (_digits.length < 7) {
      setState(() => _phoneError = 'Enter the full number with country code');
      return;
    }
    setState(() {
      _phoneError = null;
      _step = _Step.name;
    });
  }

  Future<void> _lookup() async {
    if (_first.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final r = await context.read<ContactsRepository>().addByPhone(
        '+$_digits',
        firstName: _first.text.trim(),
        lastName: _last.text.trim(),
      );
      if (mounted) {
        setState(() {
          _result = r;
          _step = _Step.result;
        });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _back() {
    switch (_step) {
      case _Step.phone:
        Navigator.pop(context);
      case _Step.name:
        setState(() => _step = _Step.phone);
      case _Step.result:
        setState(() {
          _step = _Step.phone;
          _result = null;
          _phone.clear();
          _first.clear();
          _last.clear();
        });
    }
  }

  String get _name => '${_first.text.trim()} ${_last.text.trim()}'.trim();

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _step == _Step.phone,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && !_busy) _back();
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('New contact'),
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: _busy ? null : _back),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Steps(current: _step.index),
              const SizedBox(height: 28),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  transitionBuilder: (child, a) => FadeTransition(
                    opacity: a,
                    child: SlideTransition(
                      position: Tween(begin: const Offset(0.08, 0), end: Offset.zero).animate(a),
                      child: child,
                    ),
                  ),
                  child: KeyedSubtree(key: ValueKey(_step), child: _body()),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _body() => switch (_step) {
    _Step.phone => _page(
      icon: Icons.dialpad_rounded,
      title: 'Phone number',
      text: 'Their mobile number, with the country code.',
      children: [
        CountryPhoneField(controller: _phone, errorText: _phoneError, onSubmitted: (_) => _toName()),
      ],
      action: GlowButton(label: 'Next', onPressed: _toName),
    ),
    _Step.name => _page(
      icon: Icons.badge_rounded,
      title: 'Name',
      text: 'How they appear in your chats and contacts. Only you see it.',
      children: [
        TextField(
          controller: _first,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'First name'),
        ),
        TextField(
          controller: _last,
          textCapitalization: TextCapitalization.words,
          onSubmitted: (_) => _lookup(),
          decoration: const InputDecoration(labelText: 'Last name (optional)'),
        ),
      ],
      action: GlowButton(
        label: _busy ? 'Looking them up…' : 'Add contact',
        onPressed: _busy || _first.text.trim().isEmpty ? null : _lookup,
      ),
    ),
    _Step.result => _resultPage(),
  };

  Widget _resultPage() {
    final r = _result;
    if (r is PhoneFound) {
      final user = context.read<TelegramCache>().users[r.userId];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: ChatAvatar.user(user, size: 96)),
          const SizedBox(height: 16),
          Text(
            Display.userName(user),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            '+$_digits · ${Display.status(user)}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: GlowColors.textMuted),
          ),
          const SizedBox(height: 12),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle_rounded, color: GlowColors.teal, size: 18),
              SizedBox(width: 6),
              Text('Added to your contacts', style: TextStyle(color: GlowColors.teal)),
            ],
          ),
          const Spacer(),
          GlowButton(label: 'Send a message', onPressed: () => widget.onMessage(context, r.userId)),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => widget.onProfile(context, r.userId),
            child: const Text('View profile'),
          ),
          TextButton(onPressed: _back, child: const Text('Add another')),
        ],
      );
    }
    return _page(
      icon: Icons.person_search_rounded,
      title: 'Not on Telegram yet',
      text: 'Nobody uses +$_digits on Telegram. Invite $_name, or keep the number in your phone.',
      children: const [],
      action: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlowButton(
            label: 'Invite',
            onPressed: () => const SystemChannel().shareText(
              'Hi! Let\'s chat on Telegram, it\'s fast and free: https://telegram.org/dl',
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => const SystemChannel().saveToPhoneContacts(name: _name, phone: '+$_digits'),
            child: const Text('Save to phone'),
          ),
          TextButton(onPressed: _back, child: const Text('Try another number')),
        ],
      ),
    );
  }

  Widget _page({
    required IconData icon,
    required String title,
    required String text,
    required List<Widget> children,
    required Widget action,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Icon(icon, size: 44, color: GlowColors.violet),
      const SizedBox(height: 12),
      Text(
        title,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 6),
      Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: GlowColors.textMuted),
      ),
      const SizedBox(height: 24),
      ...children,
      const Spacer(),
      action,
    ],
  );
}

/// Three dots joined by a line; done and current ones glow.
class _Steps extends StatelessWidget {
  const _Steps({required this.current});

  final int current;

  static const _labels = ['Number', 'Name', 'Done'];

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var i = 0; i < 3; i++) ...[
        if (i > 0)
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              height: 2,
              margin: const EdgeInsets.only(bottom: 18),
              color: i <= current ? GlowColors.violet : GlowColors.outline,
            ),
          ),
        Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: i <= current ? GlowColors.active : null,
                color: i <= current ? null : GlowColors.surfaceHigh,
                boxShadow: i == current
                    ? [BoxShadow(color: GlowColors.violet.withValues(alpha: 0.5), blurRadius: 12)]
                    : null,
              ),
              child: Center(
                child: i < current
                    ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                    : Text('${i + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _labels[i],
              style: TextStyle(fontSize: 11, color: i <= current ? GlowColors.text : GlowColors.textMuted),
            ),
          ],
        ),
      ],
    ],
  );
}
