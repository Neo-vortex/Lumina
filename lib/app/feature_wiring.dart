import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/media/ffmpeg_service.dart';
import '../features/media/data/media_sender.dart';
import 'app_conversation_extensions.dart';

import '../features/conversation/presentation/widgets/conversation_extensions.dart';
import '../features/home/presentation/widgets/compose_orb.dart';
import '../features/settings/presentation/screens/settings_screen.dart';

/// Cross-feature hooks: what each feature contributes to the conversation
/// screen, compose menu and settings. Kept in one place so features stay
/// independent of each other.
List<RepositoryProvider<Object>> featureProviders() => [
  RepositoryProvider<FfmpegService>(create: (_) => FfmpegService()..purgeTemp().ignore()),
  RepositoryProvider<MediaSender>(create: (c) => MediaSender(c.read<FfmpegService>())),
  RepositoryProvider<ConversationExtensions>(create: (_) => const AppConversationExtensions()),
  RepositoryProvider<ComposeActions>(create: (_) => const ComposeActions([])),
  RepositoryProvider<SettingsEntries>(create: (_) => SettingsEntries((_) => const [])),
];
