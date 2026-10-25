import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/models/bundled_models.dart';
import '../../../../core/storage/app_preferences.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../../settings/presentation/widgets/settings_section.dart';

/// Settings → Speech: offline Whisper model status, dictation language and
/// auto-send.
class SpeechSettings extends StatelessWidget {
  const SpeechSettings({super.key});

  static const _languages = {
    'auto': 'Detect automatically',
    'en': 'English',
    'es': 'Español',
    'de': 'Deutsch',
    'fr': 'Français',
    'it': 'Italiano',
    'pt': 'Português',
    'ru': 'Русский',
    'uk': 'Українська',
    'tr': 'Türkçe',
    'fa': 'فارسی',
    'ar': 'العربية',
    'hi': 'हिन्दी',
    'zh': '中文',
    'ja': '日本語',
    'ko': '한국어',
  };

  @override
  Widget build(BuildContext context) {
    final prefs = context.read<AppPreferences>();
    final models = context.read<ModelInstaller>();
    return SettingsSection(
      title: 'Speech',
      children: [
        FutureBuilder<bool>(
          future: models.isInstalled(BundledModel.whisperBase),
          builder: (context, snap) => ListTile(
            leading: const Icon(Icons.graphic_eq_rounded, color: GlowColors.cyan),
            title: const Text('Offline speech model'),
            subtitle: Text(
              snap.data == true
                  ? 'Whisper base · ready · works without internet'
                  : 'Whisper base · bundled, unpacked on first use (60 MB)',
            ),
          ),
        ),
        ListTile(
          title: const Text('Dictation language'),
          trailing: DropdownButton<String>(
            value: _languages.containsKey(prefs.whisperLanguage) ? prefs.whisperLanguage : 'auto',
            dropdownColor: GlowColors.surfaceHigh,
            underline: const SizedBox.shrink(),
            items: [for (final e in _languages.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => prefs.whisperLanguage = v ?? 'auto',
          ),
        ),
        SwitchListTile(
          value: prefs.dictationAutoSend,
          onChanged: (v) => prefs.dictationAutoSend = v,
          title: const Text('Send dictated messages automatically'),
          subtitle: const Text('Long-press the empty send orb to dictate'),
        ),
      ],
    );
  }
}
