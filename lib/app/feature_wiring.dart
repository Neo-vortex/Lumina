import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/media/audio_playback.dart';
import '../core/media/ffmpeg_service.dart';
import '../core/media/tdlib_stream_server.dart';
import '../core/storage/app_preferences.dart';
import '../core/storage/secure_store.dart';
import '../core/search/message_search.dart';
import '../core/tdlib/td_client.dart';
import '../core/telegram/telegram_cache.dart';
import '../core/telegram/file_store.dart';
import '../core/models/bundled_models.dart';
import '../features/proxy/data/proxy_repository.dart';
import '../features/assistant/data/action_extractor.dart';
import '../features/auth/presentation/widgets/auth_scaffold.dart';
import '../features/proxy/presentation/screens/proxy_screen.dart';
import '../features/proxy/presentation/widgets/connection_settings.dart';
import '../features/search/data/message_indexer.dart';
import '../features/search/presentation/widgets/search_settings.dart';
import '../features/transcription/data/transcription_center.dart';
import '../features/transcription/data/whisper_service.dart';
import '../features/transcription/presentation/widgets/speech_settings.dart';
import '../features/voice/data/voice_recorder.dart';
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
  RepositoryProvider<AudioPlayback>(
    create: (c) => AudioPlayback(
      files: c.read<FileStore>(),
      stream: c.read<TdStreamServer>(),
      prefs: c.read<AppPreferences>(),
    ),
    dispose: (p) => p.dispose(),
  ),
  RepositoryProvider<VoiceRecorder>(
    create: (c) => VoiceRecorder(c.read<FfmpegService>()),
    dispose: (r) => r.dispose(),
  ),
  RepositoryProvider<ProxyRepository>(
    lazy: false,
    create: (c) => ProxyRepository(
      client: c.read<TdClient>(),
      prefs: c.read<AppPreferences>(),
      secure: c.read<SecureStore>(),
    ),
    dispose: (r) => r.dispose(),
  ),
  RepositoryProvider<AuthExtras>(
    create: (_) => AuthExtras(openProxy: (context) => Navigator.of(context).push(ProxyScreen.route())),
  ),
  RepositoryProvider<MessageIndexer>(
    lazy: false,
    create: (c) => MessageIndexer(
      client: c.read<TdClient>(),
      cache: c.read<TelegramCache>(),
      secure: c.read<SecureStore>(),
      prefs: c.read<AppPreferences>(),
    ),
    dispose: (i) => i.dispose(),
  ),
  RepositoryProvider<MessageSearch>(create: (c) => c.read<MessageIndexer>()),
  RepositoryProvider<ModelInstaller>(create: (_) => ModelInstaller()),
  RepositoryProvider<ActionExtractor>(
    create: (c) => ActionExtractor(c.read<ModelInstaller>()),
    dispose: (e) => e.unload(),
  ),
  RepositoryProvider<WhisperService>(
    create: (c) => WhisperService(ffmpeg: c.read<FfmpegService>(), models: c.read<ModelInstaller>()),
    dispose: (w) => w.dispose(),
  ),
  RepositoryProvider<TranscriptionCenter>(
    create: (c) => TranscriptionCenter(
      whisper: c.read<WhisperService>(),
      files: c.read<FileStore>(),
      prefs: c.read<AppPreferences>(),
    ),
  ),
  RepositoryProvider<ConversationExtensions>(
    create: (c) => AppConversationExtensions(
      recorder: c.read<VoiceRecorder>(),
      transcripts: c.read<TranscriptionCenter>(),
      prefs: c.read<AppPreferences>(),
    ),
  ),
  RepositoryProvider<ComposeActions>(create: (_) => const ComposeActions([])),
  RepositoryProvider<SettingsEntries>(
    create: (_) => SettingsEntries(
      (context) => [const ConnectionSettings(), const SearchSettings(), const SpeechSettings()],
    ),
  ),
];
