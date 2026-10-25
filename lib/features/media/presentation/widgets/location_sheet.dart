import 'package:flutter/material.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../../core/platform/system_channel.dart';
import '../../../../core/theme/glow_colors.dart';
import 'attach_sheet.dart';

/// Live location periods Telegram accepts (seconds).
const liveLocationPeriods = [(900, '15 minutes'), (3600, '1 hour'), (28800, '8 hours')];

/// "Send my current location" or "Share live location for …".
Future<AttachPick?> showLocationSheet(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final where = const SystemChannel().currentLocation().catchError((_) => null);
  return showModalBottomSheet<AttachPick>(
    context: context,
    backgroundColor: GlowColors.surfaceHigh,
    showDragHandle: true,
    builder: (context) => FutureBuilder(
      future: where,
      builder: (context, snap) {
        final here = snap.data;
        final loading = snap.connectionState != ConnectionState.done;
        td.InputMessageContent content(int live) {
          final location = td.Location(
            latitude: here!.latitude,
            longitude: here.longitude,
            horizontalAccuracy: 0,
          );
          return live == 0
              ? td.InputMessageLocation(location: location)
              : td.InputMessageLiveLocation(
                  location: td.LiveLocation(
                    location: location,
                    livePeriod: live,
                    heading: 0,
                    proximityAlertRadius: 0,
                  ),
                );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: GlowColors.coral,
                    child: Icon(Icons.my_location_rounded, color: Colors.white),
                  ),
                  title: const Text('Send current location'),
                  subtitle: Text(
                    loading
                        ? 'Finding you…'
                        : here == null
                        ? 'Location unavailable. Check permission and location services.'
                        : here.name.isEmpty
                        ? '${here.latitude.toStringAsFixed(5)}, ${here.longitude.toStringAsFixed(5)}'
                        : here.name,
                  ),
                  trailing: loading
                      ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : null,
                  enabled: here != null,
                  onTap: () => Navigator.pop(context, ContentPick(content(0))),
                ),
                const Divider(color: GlowColors.outline),
                const ListTile(
                  leading: CircleAvatar(
                    backgroundColor: GlowColors.violetDeep,
                    child: Icon(Icons.share_location_rounded, color: Colors.white),
                  ),
                  title: Text('Share live location'),
                  subtitle: Text('Updates while Lumina is open. Stop any time from the message.'),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final (seconds, label) in liveLocationPeriods)
                      ActionChip(
                        label: Text(label),
                        onPressed: here == null
                            ? null
                            : () => Navigator.pop(
                                context,
                                ContentPick(content(seconds), liveLocationSeconds: seconds),
                              ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ),
  ).whenComplete(() {
    where.then((h) {
      if (h == null) messenger.hideCurrentSnackBar();
    });
  });
}
