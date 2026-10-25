import 'package:flutter/material.dart';
import 'package:handy_tdlib_next/api.dart' as td;

import '../../../../core/theme/glow_colors.dart';

/// Group permissions + slow mode editor (spec §6.2).
Future<({td.ChatPermissions permissions, int slowMode})?> showPermissionsSheet(
  BuildContext context, {
  required td.ChatPermissions permissions,
  required int slowMode,
  required bool supportsSlowMode,
}) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  backgroundColor: GlowColors.surfaceHigh,
  builder: (_) =>
      _PermissionsSheet(initial: permissions, slowMode: slowMode, supportsSlowMode: supportsSlowMode),
);

class _PermissionsSheet extends StatefulWidget {
  const _PermissionsSheet({required this.initial, required this.slowMode, required this.supportsSlowMode});

  final td.ChatPermissions initial;
  final int slowMode;
  final bool supportsSlowMode;

  @override
  State<_PermissionsSheet> createState() => _PermissionsSheetState();
}

class _PermissionsSheetState extends State<_PermissionsSheet> {
  late var p = widget.initial;
  late var slow = widget.slowMode;

  static const _delays = [0, 10, 30, 60, 300, 900, 3600];

  @override
  Widget build(BuildContext context) {
    Widget sw(String label, bool value, td.ChatPermissions Function(bool) set) => SwitchListTile(
      dense: true,
      title: Text(label),
      value: value,
      onChanged: (v) => setState(() => p = set(v)),
    );
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.8,
        child: Column(
          children: [
            const Text('Members can', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            Expanded(
              child: ListView(
                children: [
                  sw('Send messages', p.canSendBasicMessages, (v) => p.copyWith(canSendBasicMessages: v)),
                  sw('Send photos', p.canSendPhotos, (v) => p.copyWith(canSendPhotos: v)),
                  sw('Send videos', p.canSendVideos, (v) => p.copyWith(canSendVideos: v)),
                  sw('Send files', p.canSendDocuments, (v) => p.copyWith(canSendDocuments: v)),
                  sw('Send music', p.canSendAudios, (v) => p.copyWith(canSendAudios: v)),
                  sw('Send voice messages', p.canSendVoiceNotes, (v) => p.copyWith(canSendVoiceNotes: v)),
                  sw('Send video messages', p.canSendVideoNotes, (v) => p.copyWith(canSendVideoNotes: v)),
                  sw(
                    'Send stickers & GIFs',
                    p.canSendOtherMessages,
                    (v) => p.copyWith(canSendOtherMessages: v),
                  ),
                  sw('Send polls', p.canSendPolls, (v) => p.copyWith(canSendPolls: v)),
                  sw('Add link previews', p.canAddLinkPreviews, (v) => p.copyWith(canAddLinkPreviews: v)),
                  sw('Add members', p.canInviteUsers, (v) => p.copyWith(canInviteUsers: v)),
                  sw('Pin messages', p.canPinMessages, (v) => p.copyWith(canPinMessages: v)),
                  sw('Change group info', p.canChangeInfo, (v) => p.copyWith(canChangeInfo: v)),
                  if (widget.supportsSlowMode) ...[
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                      child: Text(
                        'Slow mode',
                        style: TextStyle(color: GlowColors.violet, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final d in _delays)
                          ChoiceChip(
                            label: Text(
                              d == 0 ? 'Off' : (d < 60 ? '${d}s' : (d < 3600 ? '${d ~/ 60}m' : '1h')),
                            ),
                            selected: slow == d,
                            selectedColor: GlowColors.violetDeep,
                            onSelected: (_) => setState(() => slow = d),
                          ),
                      ],
                    ),
                  ] else
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Slow mode needs a supergroup. Telegram upgrades groups automatically when you change advanced settings.',
                        style: TextStyle(color: GlowColors.textMuted, fontSize: 13),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: GlowColors.violetDeep,
                  minimumSize: const Size.fromHeight(50),
                ),
                onPressed: () => Navigator.pop(context, (permissions: p, slowMode: slow)),
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
