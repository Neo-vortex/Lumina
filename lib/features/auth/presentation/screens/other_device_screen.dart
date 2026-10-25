import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/glow_colors.dart';
import '../../../../core/widgets/glow_button.dart';
import '../../domain/auth_step.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/start_over_button.dart';

/// QR / other-device confirmation. The app never requests QR login itself,
/// but TDLib can still land here, so the link is shown instead of a dead end.
class OtherDeviceScreen extends StatelessWidget {
  const OtherDeviceScreen({super.key, required this.step});

  final AuthWaitOtherDevice step;

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Confirm on another device',
      subtitle: 'Open this link on a device where you are already signed in.',
      children: [
        SelectableText(
          step.link,
          textAlign: TextAlign.center,
          style: const TextStyle(color: GlowColors.cyan),
        ),
        const SizedBox(height: 20),
        GlowButton(
          label: 'Copy link',
          onPressed: () => Clipboard.setData(ClipboardData(text: step.link)),
        ),
        const SizedBox(height: 12),
        const StartOverButton(),
      ],
    );
  }
}
