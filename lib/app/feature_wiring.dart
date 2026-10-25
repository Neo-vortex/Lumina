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
import '../features/media/data/live_location_service.dart';
import '../features/media/data/media_sender.dart';
import 'app_conversation_extensions.dart';
import 'app_story_wiring.dart';
import '../features/maintenance/data/storage_repository.dart';
import '../features/maintenance/presentation/widgets/background_settings.dart';
import '../features/maintenance/presentation/widgets/storage_settings.dart';
import '../features/chats/presentation/widgets/chat_row_extensions.dart';
import '../features/stories/data/stories_repository.dart';
import '../features/stories/data/saved_stories_store.dart';
import '../features/stories/presentation/story_message_opener.dart';
import '../features/chat_info/presentation/chat_info_extensions.dart';
import '../features/chat_info/data/chat_info_repository.dart';
import '../features/chat_info/presentation/compose_flows.dart';
import '../features/conversation/presentation/screens/conversation_screen.dart';

import 'package:flutter/material.dart' show Icons;

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
  RepositoryProvider<StoryMessageOpener>(
    create: (_) => StoryMessageOpener(
      (context, chatId, messageId) =>
          Navigator.of(context).push(ConversationScreen.route(chatId, focusMessageId: messageId)),
    ),
  ),
  RepositoryProvider<ComposeFlows>(
    create: (_) =>
        ComposeFlows((context, chatId) => Navigator.of(context).push(ConversationScreen.route(chatId))),
  ),
  // Not lazy: shares saved before the process died resume at launch.
  RepositoryProvider<LiveLocationService>(
    lazy: false,
    create: (c) => LiveLocationService(client: c.read<TdClient>(), prefs: c.read<AppPreferences>()),
    dispose: (s) => s.dispose(),
  ),
  RepositoryProvider<ConversationExtensions>(
    create: (c) => AppConversationExtensions(
      recorder: c.read<VoiceRecorder>(),
      transcripts: c.read<TranscriptionCenter>(),
      prefs: c.read<AppPreferences>(),
      flows: c.read<ComposeFlows>(),
      liveLocations: c.read<LiveLocationService>(),
    ),
  ),
  RepositoryProvider<ChatInfoRepository>(
    create: (c) => ChatInfoRepository(client: c.read<TdClient>(), cache: c.read<TelegramCache>()),
  ),
  RepositoryProvider<StorageRepository>(
    create: (c) => StorageRepository(
      client: c.read<TdClient>(),
      prefs: c.read<AppPreferences>(),
      ffmpeg: c.read<FfmpegService>(),
    ),
  ),
  RepositoryProvider<StoriesRepository>(
    lazy: false,
    create: (c) => StoriesRepository(
      client: c.read<TdClient>(),
      prefs: c.read<AppPreferences>(),
      ffmpeg: c.read<FfmpegService>(),
    ),
    dispose: (r) => r.dispose(),
  ),
  RepositoryProvider<SavedStoriesStore>(
    lazy: false,
    create: (c) => SavedStoriesStore(
      client: c.read<TdClient>(),
      stories: c.read<StoriesRepository>(),
      cache: c.read<TelegramCache>(),
      files: c.read<FileStore>(),
      ffmpeg: c.read<FfmpegService>(),
    ),
    dispose: (s) => s.dispose(),
  ),
  RepositoryProvider<ChatInfoExtensions>(
    create: (c) => AppChatInfoExtensions(prefs: c.read<AppPreferences>()),
  ),
  RepositoryProvider<ChatRowExtensions>(
    create: (c) =>
        AppChatRowExtensions(stories: c.read<StoriesRepository>(), prefs: c.read<AppPreferences>()),
  ),
  RepositoryProvider<ComposeActions>(create: (c) => _composeActions(c.read<ComposeFlows>())),
  RepositoryProvider<SettingsEntries>(
    create: (_) => SettingsEntries(
      (context) => [
        const ConnectionSettings(),
        const StorageSettings(),
        const SearchSettings(),
        const SpeechSettings(),
        const BackgroundSettings(),
      ],
    ),
  ),
];

ComposeActions _composeActions(ComposeFlows flows) => ComposeActions([
  ComposeAction(icon: Icons.edit_rounded, label: 'New message', onSelected: flows.newMessage),
  ComposeAction(icon: Icons.group_add_rounded, label: 'New group', onSelected: flows.newGroup),
  ComposeAction(icon: Icons.campaign_rounded, label: 'New channel', onSelected: flows.newChannel),
  ComposeAction(icon: Icons.lock_rounded, label: 'Secret chat', onSelected: flows.newSecretChat),
  const ComposeAction(
    icon: Icons.blur_on_rounded,
    label: 'Glimpses',
    onSelected: openGlimpses,
    visible: storiesVisible,
  ),
  const ComposeAction(
    icon: Icons.add_a_photo_rounded,
    label: 'Post story',
    onSelected: postStoryAsMe,
    visible: storiesVisible,
  ),
]);
