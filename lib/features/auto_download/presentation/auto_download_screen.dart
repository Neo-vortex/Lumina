import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/glow_colors.dart';
import '../../../core/theme/motion.dart';
import '../data/auto_download_service.dart';
import '../domain/auto_download_policy.dart';

/// "100 KB", "20 MB", "4 GB": the slider stops are round numbers.
String sizeLabel(int bytes) {
  const kb = 1024, mb = kb * 1024, gb = mb * 1024;
  if (bytes >= gb) return '${bytes ~/ gb} GB';
  if (bytes >= mb) return '${bytes ~/ mb} MB';
  return '${bytes ~/ kb} KB';
}

/// Settings → Data & storage → Auto-download: a tab per network type, then
/// presets, a media × chat grid of glowing toggles, size limits and video
/// preloading.
class AutoDownloadScreen extends StatefulWidget {
  const AutoDownloadScreen({super.key});

  static Route<void> route() => MaterialPageRoute(builder: (_) => const AutoDownloadScreen());

  @override
  State<AutoDownloadScreen> createState() => _AutoDownloadScreenState();
}

class _AutoDownloadScreenState extends State<AutoDownloadScreen> {
  late final AutoDownloadService _service = context.read<AutoDownloadService>();
  late NetworkKind _tab = _service.network;

  static const _chatIcons = {
    ChatKind.contacts: Icons.person_rounded,
    ChatKind.private: Icons.chat_bubble_rounded,
    ChatKind.groups: Icons.groups_rounded,
    ChatKind.channels: Icons.campaign_rounded,
  };

  static const _mediaIcons = {
    MediaKind.photos: Icons.photo_rounded,
    MediaKind.videos: Icons.movie_rounded,
    MediaKind.files: Icons.description_rounded,
    MediaKind.voice: Icons.mic_rounded,
    MediaKind.videoMessages: Icons.radio_button_checked_rounded,
    MediaKind.gifs: Icons.gif_box_rounded,
    MediaKind.music: Icons.music_note_rounded,
  };

  void _set(AutoDownloadPolicy p) => _service.setPolicy(_tab, p).ignore();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Auto-download')),
    body: ListenableBuilder(
      listenable: _service.changes,
      builder: (context, _) {
        final policy = _service.policy(_tab);
        final preset = policy.preset;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _NetworkTabs(
              selected: _tab,
              current: _service.network,
              onSelect: (n) => setState(() => _tab = n),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in AutoDownloadPreset.values)
                  if (p != AutoDownloadPreset.custom || preset == AutoDownloadPreset.custom)
                    ChoiceChip(
                      label: Text(p.label),
                      selected: preset == p,
                      selectedColor: GlowColors.violet.withValues(alpha: 0.3),
                      side: BorderSide(color: preset == p ? GlowColors.violet : GlowColors.outline),
                      onSelected: p == AutoDownloadPreset.custom
                          ? null
                          : (_) {
                              HapticFeedback.selectionClick();
                              _set(AutoDownloadPolicy.of(p));
                            },
                    ),
              ],
            ),
            const SizedBox(height: 18),
            _Card(
              child: Column(
                children: [
                  Row(
                    children: [
                      const Expanded(child: SizedBox()),
                      for (final c in ChatKind.values)
                        SizedBox(
                          width: 48,
                          child: Tooltip(
                            message: c.label,
                            child: Icon(_chatIcons[c], size: 18, color: GlowColors.textMuted),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  for (final m in MediaKind.values)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Icon(
                            _mediaIcons[m],
                            size: 20,
                            color: policy.anyOn(m) ? GlowColors.cyan : GlowColors.textMuted,
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: Text(m.label, style: const TextStyle(fontSize: 15))),
                          for (final c in ChatKind.values)
                            SizedBox(
                              width: 48,
                              child: Center(
                                child: _GlowToggle(
                                  label: '${m.label} in ${c.label}',
                                  on: policy.isOn(m, c),
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    _set(policy.toggled(m, c));
                                  },
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _Card(
              child: Column(
                children: [
                  _SizeLimit(
                    key: const ValueKey('video-limit'),
                    title: 'Videos',
                    value: policy.maxVideoSize,
                    enabled: policy.anyOn(MediaKind.videos),
                    onChanged: (v) => _set(policy.copyWith(maxVideoSize: v)),
                  ),
                  _SizeLimit(
                    key: const ValueKey('file-limit'),
                    title: 'Files',
                    value: policy.maxFileSize,
                    enabled: policy.anyOn(MediaKind.files),
                    onChanged: (v) => _set(policy.copyWith(maxFileSize: v)),
                  ),
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    activeThumbColor: GlowColors.cyan,
                    title: const Text('Preload larger videos'),
                    subtitle: const Text('Fetch the start of videos over the limit, so they play at once'),
                    value: policy.preloadLargeVideos,
                    onChanged: (v) => _set(policy.copyWith(preloadLargeVideos: v)),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );
}

class _NetworkTabs extends StatelessWidget {
  const _NetworkTabs({required this.selected, required this.current, required this.onSelect});

  final NetworkKind selected;
  final NetworkKind current;
  final ValueChanged<NetworkKind> onSelect;

  static const _icons = {
    NetworkKind.mobile: Icons.signal_cellular_alt_rounded,
    NetworkKind.wifi: Icons.wifi_rounded,
    NetworkKind.roaming: Icons.public_rounded,
  };

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: GlowColors.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: GlowColors.outline),
        ),
        child: Row(
          children: [
            for (final n in NetworkKind.values)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSelect(n),
                  child: AnimatedContainer(
                    duration: Motion.standard,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: n == selected
                          ? LinearGradient(
                              colors: [
                                GlowColors.violet.withValues(alpha: 0.45),
                                GlowColors.magenta.withValues(alpha: 0.3),
                              ],
                            )
                          : null,
                      boxShadow: n == selected ? glow(GlowColors.violet, intensity: 0.4) : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _icons[n],
                          size: 18,
                          color: n == selected ? GlowColors.text : GlowColors.textMuted,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            n.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: n == selected ? GlowColors.text : GlowColors.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: GlowColors.cyan,
              boxShadow: glow(GlowColors.cyan, intensity: 0.6),
            ),
          ),
          const SizedBox(width: 6),
          Text('Now on ${current.label}', style: const TextStyle(color: GlowColors.textMuted, fontSize: 12)),
        ],
      ),
    ],
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: GlowColors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: GlowColors.outline),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: const EdgeInsets.fromLTRB(14, 12, 6, 12), child: child),
  );
}

/// A round toggle that lights up when on.
class _GlowToggle extends StatelessWidget {
  const _GlowToggle({required this.label, required this.on, required this.onTap});

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    toggled: on,
    button: true,
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox.square(
        dimension: 44,
        child: Center(
          child: AnimatedContainer(
            duration: Motion.standard,
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: on ? const RadialGradient(colors: [GlowColors.cyan, GlowColors.teal]) : null,
              border: Border.all(color: on ? GlowColors.cyan : GlowColors.outlineStrong, width: 1.5),
              boxShadow: on ? glow(GlowColors.cyan, intensity: 0.45) : null,
            ),
            child: on ? const Icon(Icons.check_rounded, size: 16, color: GlowColors.onAccent) : null,
          ),
        ),
      ),
    ),
  );
}

/// A log-scale size limit, 100 KB to 4 GB, snapping to [AutoDownloadPolicy.sizeStops].
class _SizeLimit extends StatelessWidget {
  const _SizeLimit({
    super.key,
    required this.title,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String title;
  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    const stops = AutoDownloadPolicy.sizeStops;
    final index = stops.indexOf(AutoDownloadPolicy.snap(value));
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 4),
            child: Row(
              children: [
                Text(title, style: const TextStyle(fontSize: 15)),
                const Spacer(),
                Text(
                  'Up to ${sizeLabel(stops[index])}',
                  style: const TextStyle(color: GlowColors.cyan, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
          Slider(
            value: index.toDouble(),
            max: (stops.length - 1).toDouble(),
            divisions: stops.length - 1,
            activeColor: GlowColors.cyan,
            inactiveColor: GlowColors.outline,
            label: sizeLabel(stops[index]),
            onChanged: (v) {
              final next = stops[v.round()];
              if (next == stops[index]) return;
              HapticFeedback.selectionClick();
              onChanged(next);
            },
          ),
        ],
      ),
    );
  }
}
