import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:llamadart/llamadart.dart' show ComputeDevice;

import '../../../core/storage/app_preferences.dart';
import '../../../core/theme/glow_colors.dart';
import '../../settings/presentation/widgets/settings_section.dart';
import '../data/action_extractor.dart';

/// Settings → Media & voice → On-device AI: where the ✨ model runs.
class AiSettings extends StatelessWidget {
  const AiSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final prefs = context.read<AppPreferences>();
    final extractor = context.read<ActionExtractor>();
    final running = switch (extractor.device) {
      ComputeDevice.gpu => 'Running on the GPU (Vulkan)',
      ComputeDevice.cpu => 'Running on the CPU',
      _ => 'Loads on first use',
    };
    return ListenableBuilder(
      listenable: prefs.changes,
      builder: (context, _) => SettingsSection(
        title: 'On-device AI',
        children: [
          ListTile(
            leading: const Icon(Icons.auto_awesome_rounded, color: GlowColors.violet),
            title: const Text('SmolLM2 · actions and writing help'),
            subtitle: Text(running),
          ),
          SwitchListTile(
            activeThumbColor: GlowColors.cyan,
            title: const Text('Run AI on the CPU'),
            subtitle: const Text('Uses the GPU when it can. Turn on if ✨ results look wrong'),
            value: prefs.aiForceCpu,
            onChanged: (v) {
              prefs.aiForceCpu = v;
              // The next ✨ loads on the chosen device.
              extractor.unload();
            },
          ),
        ],
      ),
    );
  }
}
