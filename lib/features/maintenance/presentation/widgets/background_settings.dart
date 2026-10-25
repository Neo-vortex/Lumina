import 'package:flutter/material.dart';

import '../../../../core/platform/system_channel.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../../settings/presentation/widgets/settings_section.dart';

/// Settings → Background: whether Android lets Lumina keep its connection.
class BackgroundSettings extends StatefulWidget {
  const BackgroundSettings({super.key});

  @override
  State<BackgroundSettings> createState() => _BackgroundSettingsState();
}

class _BackgroundSettingsState extends State<BackgroundSettings> with WidgetsBindingObserver {
  bool? _unrestricted;

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

  // Re-check after returning from the system settings page.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    try {
      final v = await const SystemChannel().isIgnoringBatteryOptimizations();
      if (mounted) setState(() => _unrestricted = v);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final ok = _unrestricted;
    if (ok == null) return const SizedBox.shrink();
    return SettingsSection(
      title: 'Background',
      children: [
        ListTile(
          leading: Icon(
            ok ? Icons.battery_charging_full_rounded : Icons.battery_alert_rounded,
            color: ok ? GlowColors.cyan : GlowColors.amber,
          ),
          title: Text(ok ? 'Unrestricted battery use' : 'Battery optimisation is on'),
          subtitle: Text(
            ok
                ? 'Lumina can stay connected in the background.'
                : 'Android may pause Lumina in the background, delaying new messages.',
          ),
          trailing: ok
              ? null
              : TextButton(
                  onPressed: () => const SystemChannel().openBatterySettings(),
                  child: const Text('Allow'),
                ),
        ),
      ],
    );
  }
}

/// One-time explanation shown after the first sign-in when Android is
/// optimising Lumina's battery use. Returns without UI otherwise.
Future<void> maybeShowBatteryPrompt(
  BuildContext context, {
  required bool alreadyShown,
  required VoidCallback markShown,
}) async {
  if (alreadyShown) return;
  const system = SystemChannel();
  bool ignoring;
  try {
    ignoring = await system.isIgnoringBatteryOptimizations();
  } catch (_) {
    return;
  }
  markShown();
  if (ignoring || !context.mounted) return;
  final allow = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: GlowColors.surfaceHigh,
      icon: const Icon(Icons.battery_alert_rounded, color: GlowColors.amber),
      title: const Text('Stay connected?'),
      content: const Text(
        'Android saves battery by pausing apps in the background, which can delay your messages. '
        'You can let Lumina run unrestricted. You can change this later in Settings → Background.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Allow')),
      ],
    ),
  );
  if (allow == true) await system.openBatterySettings();
}
