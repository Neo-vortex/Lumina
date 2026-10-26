import 'package:flutter/material.dart';

import '../theme/glow_colors.dart';
import 'glow_sheet.dart';

/// Every delete asks first. Returns null when cancelled, otherwise whether
/// to delete for the other side too ([alsoLabel], e.g. "Also delete for
/// Ada"); the toggle only shows when [alsoLabel] is given, and starts off.
Future<bool?> confirmDelete(
  BuildContext context, {
  required String title,
  String? message,
  String? alsoLabel,
  String confirmLabel = 'Delete',
}) async {
  var also = false;
  final ok = await showGlowConfirm(
    context,
    title: title,
    message: message,
    confirmLabel: confirmLabel,
    icon: Icons.delete_outline_rounded,
    destructive: true,
    body: alsoLabel == null
        ? null
        : (context) => StatefulBuilder(
            builder: (context, setState) => SwitchListTile(
              value: also,
              onChanged: (v) => setState(() => also = v),
              activeThumbColor: GlowColors.coral,
              title: Text(alsoLabel),
              contentPadding: EdgeInsets.zero,
            ),
          ),
  );
  return ok ? also : null;
}

/// The message-delete confirmation, with "for everyone" when Telegram
/// allows it. [otherName] names the peer in private chats.
Future<bool?> confirmDeleteMessages(
  BuildContext context, {
  required int count,
  required bool canForEveryone,
  String? otherName,
}) => confirmDelete(
  context,
  title: count == 1 ? 'Delete this message?' : 'Delete $count messages?',
  alsoLabel: canForEveryone
      ? (otherName == null ? 'Also delete for everyone' : 'Also delete for $otherName')
      : null,
);
