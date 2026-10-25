import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/media/ffmpeg_service.dart';
import '../../../../core/telegram/display.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../data/video_presets.dart';

/// Choose how to send a video: simple presets (original / two smaller /
/// compatible) or full control over codec, size, bitrate, fps and audio.
Future<VideoPreset?> showVideoConvertSheet(
  BuildContext context, {
  required MediaProbe probe,
  required Set<String> encoders,
  VideoPreset? current,
}) {
  return showModalBottomSheet<VideoPreset>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: GlowColors.surfaceHigh,
    builder: (context) => _ConvertSheet(probe: probe, encoders: encoders, current: current),
  );
}

class _ConvertSheet extends StatefulWidget {
  const _ConvertSheet({required this.probe, required this.encoders, this.current});

  final MediaProbe probe;
  final Set<String> encoders;
  final VideoPreset? current;

  @override
  State<_ConvertSheet> createState() => _ConvertSheetState();
}

class _ConvertSheetState extends State<_ConvertSheet> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 2, vsync: this);
  late final List<VideoPreset> _simple = simplePresets(widget.probe);
  late String _selected = widget.current?.id ?? 'original';

  // Advanced state.
  late final List<VideoCodec> _codecs = [
    for (final c in VideoCodec.values)
      if (widget.encoders.isEmpty || widget.encoders.contains(c.encoder)) c,
  ];
  late VideoCodec _codec = _codecs.isNotEmpty ? _codecs.first : VideoCodec.mpeg4;
  late final List<int> _sizes = resolutionChoices(widget.probe);
  late int _short = _sizes.isEmpty
      ? widget.probe.shortSide
      : _sizes.firstWhere((s) => s <= 720, orElse: () => _sizes.last);
  late double _kbps = recommendedKbps(_short, codec: _codec).toDouble();
  int? _fps = 30;
  AudioChoice _audio = AudioChoice.aac128;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  VideoPreset get _advanced => VideoPreset(
    id: 'custom',
    title: 'Custom · ${_short}p ${_codec.name.toUpperCase()}',
    description: '${_kbps.round()} kbps',
    codec: _codec,
    shortSide: _short,
    videoKbps: _kbps.round(),
    audio: _audio,
    fps: _fps,
  );

  @override
  Widget build(BuildContext context) {
    final p = widget.probe;
    final double maxKbps = math.max(
      2000.0,
      math.min(20000.0, p.bitrate > 0 ? p.bitrate / 1000 * 1.2 : 12000.0),
    );
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.78,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                '${p.videoCodec?.toUpperCase() ?? '?'} · ${p.width}×${p.height} · '
                '${Display.duration(p.duration.inSeconds)} · ${Display.fileSize(p.sizeBytes)}',
                style: const TextStyle(color: GlowColors.textMuted),
              ),
            ),
            TabBar(
              controller: _tabs,
              indicatorColor: GlowColors.violet,
              labelColor: GlowColors.text,
              tabs: const [
                Tab(text: 'Simple'),
                Tab(text: 'Advanced'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  RadioGroup<String>(
                    groupValue: _selected,
                    onChanged: (v) => setState(() => _selected = v!),
                    child: ListView(
                      children: [
                        for (final preset in _simple)
                          RadioListTile<String>(
                            value: preset.id,
                            title: Text(preset.title),
                            subtitle: Text(preset.description),
                            secondary: Text(
                              '${preset.isOriginal ? '' : '≈ '}${Display.fileSize(preset.estimateBytes(p))}',
                              style: TextStyle(
                                color: preset.id == 'compatible' ? GlowColors.cyan : GlowColors.text,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        if (needsCompatibility(p))
                          const Padding(
                            padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
                            child: Text(
                              'This video uses a codec many mid-range and older phones cannot play. '
                              '“Compatible” re-encodes it to H.264.',
                              style: TextStyle(color: GlowColors.textMuted, fontSize: 13),
                            ),
                          ),
                      ],
                    ),
                  ),
                  ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    children: [
                      const _Label('Codec'),
                      RadioGroup<VideoCodec>(
                        groupValue: _codec,
                        onChanged: (v) => setState(() {
                          _codec = v!;
                          _kbps = recommendedKbps(_short, codec: _codec).toDouble().clamp(200.0, maxKbps);
                        }),
                        child: Column(
                          children: [
                            for (final c in _codecs)
                              RadioListTile<VideoCodec>(value: c, title: Text(c.label), dense: true),
                          ],
                        ),
                      ),
                      const _Label('Resolution (short side)'),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final s in _sizes)
                            ChoiceChip(
                              label: Text('${s}p'),
                              selected: _short == s,
                              selectedColor: GlowColors.violetDeep,
                              onSelected: (_) => setState(() {
                                _short = s;
                                _kbps = recommendedKbps(s, codec: _codec).toDouble().clamp(200.0, maxKbps);
                              }),
                            ),
                        ],
                      ),
                      _Label('Video bitrate · ${_kbps.round()} kbps'),
                      Slider(
                        value: _kbps.clamp(200.0, maxKbps),
                        min: 200,
                        max: maxKbps,
                        onChanged: (v) => setState(() => _kbps = v),
                      ),
                      const _Label('Frame rate'),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final f in const [null, 60, 30, 24])
                            ChoiceChip(
                              label: Text(f == null ? 'Original' : '$f fps'),
                              selected: _fps == f,
                              selectedColor: GlowColors.violetDeep,
                              onSelected: (_) => setState(() => _fps = f),
                            ),
                        ],
                      ),
                      if (p.hasAudio) ...[
                        const _Label('Audio'),
                        DropdownButton<AudioChoice>(
                          value: _audio,
                          isExpanded: true,
                          dropdownColor: GlowColors.surfaceHigh,
                          items: [
                            for (final a in AudioChoice.values)
                              if (_codec != VideoCodec.vp9 || a.encoder != 'aac')
                                DropdownMenuItem(value: a, child: Text(a.label)),
                          ],
                          onChanged: (a) => setState(() => _audio = a!),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Text(
                        'Estimated size ≈ ${Display.fileSize(_advanced.estimateBytes(p))}',
                        style: const TextStyle(fontWeight: FontWeight.w600, color: GlowColors.cyan),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: GlowColors.violetDeep,
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: () {
                  final preset = _tabs.index == 1 ? _advanced : _simple.firstWhere((x) => x.id == _selected);
                  Navigator.pop(context, preset);
                },
                child: const Text('Use this'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 6, left: 4),
    child: Text(
      text,
      style: const TextStyle(color: GlowColors.violet, fontWeight: FontWeight.w600),
    ),
  );
}
