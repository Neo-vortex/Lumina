import 'package:flutter/material.dart';

import '../telegram/display.dart';
import '../theme/glow_colors.dart';
import '../widgets/glow_sheet.dart';
import 'account_store.dart';

/// Switch to another account (Telegram or a custom server) or add one.
/// Switching closes this account's client and starts the other's: a second
/// or two, no sign-in.
Future<void> showAccountSwitcher(BuildContext context) async {
  final store = AccountStore.current;
  if (store == null) return;
  final picked = await showGlowSheet<String>(
    context,
    title: 'Accounts',
    builder: (context) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final a in [store.active, ...store.others])
          ListTile(
            leading: _AccountAvatar(account: a, active: a.id == store.activeId),
            title: Text(a.name ?? (a.signedIn ? 'Account' : 'Not signed in yet')),
            subtitle: Text(
              [if (a.phone != null && a.phone!.isNotEmpty) '+${a.phone}', a.serverLabel].join(' · '),
              style: const TextStyle(color: GlowColors.textMuted),
            ),
            trailing: a.id == store.activeId
                ? const Icon(Icons.check_circle_rounded, color: GlowColors.cyan)
                : const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.pop(context, a.id),
          ),
        const Divider(height: 1),
        ListTile(
          leading: const CircleAvatar(
            backgroundColor: GlowColors.surfaceHigh,
            child: Icon(Icons.add_rounded, color: GlowColors.violet),
          ),
          title: const Text('Add account'),
          subtitle: const Text(
            'Another Telegram account or a custom server',
            style: TextStyle(color: GlowColors.textMuted),
          ),
          onTap: () => Navigator.pop(context, '+'),
        ),
        const SizedBox(height: 8),
      ],
    ),
  );
  if (picked == null || picked == store.activeId) return;
  if (picked == '+') {
    await store.addNew();
  } else {
    await store.activate(picked);
  }
  await AccountStore.reloadApp?.call();
}

/// "Back to …" from the sign-in screen of an account being added: drops it
/// and returns to [to].
Future<void> abandonNewAccount(Account to) async {
  final store = AccountStore.current;
  if (store == null) return;
  final pending = store.activeId;
  await store.activate(to.id);
  // Its folder goes only once its client is closed (the reload closes it).
  await AccountStore.reloadApp?.call();
  // The reload loaded a fresh store.
  await (AccountStore.current ?? store).discard(pending);
}

class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar({required this.account, required this.active});

  final Account account;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final accent = Display.accentFor(account.userId ?? account.id.hashCode);
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: [accent, accent.withValues(alpha: 0.55)]),
        border: active ? Border.all(color: GlowColors.cyan, width: 2) : null,
      ),
      alignment: Alignment.center,
      child: account.customServer != null && account.name == null
          ? const Icon(Icons.dns_rounded, color: GlowColors.onAccent, size: 20)
          : Text(
              Display.initials(account.name ?? '?'),
              style: const TextStyle(color: GlowColors.onAccent, fontWeight: FontWeight.w700),
            ),
    );
  }
}
