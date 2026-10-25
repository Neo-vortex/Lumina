import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/storage/app_preferences.dart';
import '../../../core/theme/glow_colors.dart';
import '../../settings/presentation/widgets/settings_section.dart';
import '../bloc/call_cubit.dart';
import '../data/call_engine.dart';

/// Settings → Calls: whether calls use the Phone app's own call screen
/// (Lumina's calling account) or Lumina's.
class CallSettings extends StatefulWidget {
  const CallSettings({super.key});

  @override
  State<CallSettings> createState() => _CallSettingsState();
}

class _CallSettingsState extends State<CallSettings> with WidgetsBindingObserver {
  bool? _accountEnabled;

  CallSystem? get _system {
    final engine = context.read<CallEngine>();
    return engine is CallSystem ? engine as CallSystem : null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Re-check after returning from the Phone app's settings.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final enabled = await _system?.callingAccountEnabled() ?? false;
    if (mounted) setState(() => _accountEnabled = enabled);
  }

  Future<void> _toggle(AppPreferences prefs, bool on) async {
    prefs.callsUseCallingAccount = on;
    await context.read<CallCubit>().refreshTelecom();
    await _check();
    if (!on || (_accountEnabled ?? false) || !mounted) return;
    final open = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GlowColors.surfaceHigh,
        title: const Text('Turn on Lumina in the Phone app'),
        content: const Text(
          'In the Phone app\'s calling accounts, switch on "Lumina". Calls then use the Phone app\'s '
          'call screen, and numbers you dial there with the Lumina account become Telegram calls.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Later')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Open settings')),
        ],
      ),
    );
    if (open ?? false) await _system?.openCallingAccounts();
  }

  @override
  Widget build(BuildContext context) {
    final prefs = context.read<AppPreferences>();
    return ListenableBuilder(
      listenable: prefs.changes,
      builder: (context, _) {
        final on = prefs.callsUseCallingAccount;
        return SettingsSection(
          title: 'Calls',
          children: [
            SwitchListTile(
              value: on,
              onChanged: (v) => _toggle(prefs, v),
              title: const Text('Use the Phone app for calls'),
              subtitle: Text(
                !on
                    ? 'Lumina\'s call screen. Bluetooth, car and call history work either way.'
                    : (_accountEnabled ?? false)
                    ? 'The Phone app shows calls and can dial Telegram contacts'
                    : 'Turn on "Lumina" in the Phone app\'s calling accounts',
              ),
            ),
            if (on)
              ListTile(
                leading: const Icon(Icons.settings_phone_rounded),
                title: const Text('Phone app calling accounts'),
                trailing: Icon(
                  (_accountEnabled ?? false) ? Icons.check_circle_rounded : Icons.open_in_new_rounded,
                  color: (_accountEnabled ?? false) ? GlowColors.cyan : GlowColors.textMuted,
                ),
                onTap: () => _system?.openCallingAccounts(),
              ),
          ],
        );
      },
    );
  }
}
