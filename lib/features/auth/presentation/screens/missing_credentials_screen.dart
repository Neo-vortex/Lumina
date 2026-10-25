import 'package:flutter/material.dart';

import '../widgets/auth_scaffold.dart';

class MissingCredentialsScreen extends StatelessWidget {
  const MissingCredentialsScreen({super.key});

  @override
  Widget build(BuildContext context) => const AuthScaffold(
    title: 'API credentials missing',
    subtitle:
        'This build has no Telegram API id/hash. Get them at my.telegram.org and rebuild with\n'
        '--dart-define=TG_API_ID=… --dart-define=TG_API_HASH=…',
    children: [],
  );
}
