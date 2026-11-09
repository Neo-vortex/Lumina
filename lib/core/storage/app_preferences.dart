import '../widgets/lumina_glass.dart' show GlassMode;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../gestures/swipe_actions.dart';

/// How the chat-list title switches folders.
enum FolderPickerStyle { gesture, classic }

/// Which encoding of a Telegram video to fetch and play. Telegram keeps
/// lower-resolution copies beside the upload (a 35 MB clip may have a 6 MB
/// 480p one): [low] takes the smallest, [auto] the best up to 720p, and
/// [original] the upload itself.
enum VideoQuality { auto, original, low }

/// Non-secret user preferences, persisted with shared_preferences. Listen to
/// [changes] to react immediately.
class AppPreferences {
  AppPreferences(this._prefs);

  /// For tests.
  AppPreferences.inMemory() : _prefs = null;

  final SharedPreferencesAsync? _prefs;
  final _values = <String, Object>{};
  final _changes = ValueNotifier<int>(0);

  /// Fires after any preference changes.
  Listenable get changes => _changes;

  /// The app's instance once loaded, for code without a BuildContext (e.g.
  /// which video file a message stands for).
  static AppPreferences? current;

  static Future<AppPreferences> load() async {
    final prefs = AppPreferences(SharedPreferencesAsync());
    await prefs._loadAll();
    return current = prefs;
  }

  Future<void> _loadAll() async {
    final all = await _prefs?.getAll() ?? const {};
    for (final e in all.entries) {
      if (e.value != null) _values[e.key] = e.value!;
    }
  }

  bool _bool(String key, bool fallback) => _values[key] as bool? ?? fallback;
  double _double(String key, double fallback) => (_values[key] as num?)?.toDouble() ?? fallback;
  String? _string(String key) => _values[key] as String?;

  Future<void> _remove(String key) async {
    _values.remove(key);
    _changes.value++;
    await _prefs?.remove(key);
  }

  Future<void> _set(String key, Object value) async {
    _values[key] = value;
    _changes.value++;
    switch (value) {
      case bool v:
        await _prefs?.setBool(key, v);
      case double v:
        await _prefs?.setDouble(key, v);
      case int v:
        await _prefs?.setInt(key, v);
      case String v:
        await _prefs?.setString(key, v);
    }
  }

  // ---- Downloads ------------------------------------------------------------

  /// New downloads wait for Wi-Fi.
  bool get downloadsWifiOnlyDefault => _bool('downloads.wifiOnly', false);
  set downloadsWifiOnlyDefault(bool v) => _set('downloads.wifiOnly', v);

  /// Files (TDLib ids) that download on Wi-Fi only.
  Set<int> get downloadsWifiOnly => {
    for (final s in (_string('downloads.wifiOnlyFiles') ?? '').split(' ')) ?int.tryParse(s),
  };
  void setDownloadsWifiOnly(Set<int> ids) => _set('downloads.wifiOnlyFiles', ids.join(' '));

  /// Wi-Fi-only downloads Lumina paused off Wi-Fi (resumed on Wi-Fi).
  Set<int> get downloadsWaiting => {
    for (final s in (_string('downloads.waiting') ?? '').split(' ')) ?int.tryParse(s),
  };
  void setDownloadsWaiting(Set<int> ids) => _set('downloads.waiting', ids.join(' '));

  // ---- Folder picker --------------------------------------------------------

  /// Hold-and-swipe picker (default) or the classic drop-down list.
  FolderPickerStyle get folderPicker =>
      _enum(FolderPickerStyle.values, 'chats.folderPicker') ?? FolderPickerStyle.gesture;
  set folderPicker(FolderPickerStyle v) => _set('chats.folderPicker', v.name);

  // ---- On-device AI -------------------------------------------------------

  /// Keep the ✨ model on the CPU even when the GPU works.
  bool get aiForceCpu => _bool('ai.forceCpu', false);
  set aiForceCpu(bool v) => _set('ai.forceCpu', v);

  // ---- Auto-download -------------------------------------------------------

  /// One network type's auto-download policy, as JSON (see
  /// `AutoDownloadPolicy`); null until the user changes it.
  String? autoDownloadPolicy(String network) => _string('autoDownload.$network');
  void setAutoDownloadPolicy(String network, String json) => _set('autoDownload.$network', json);

  // ---- Swipe gestures -----------------------------------------------------

  MessageSwipe messageSwipe(SwipeSide side) =>
      _enum(MessageSwipe.values, 'swipe.message.${side.name}') ??
      (side == SwipeSide.left ? MessageSwipe.reply : MessageSwipe.react);
  void setMessageSwipe(SwipeSide side, MessageSwipe v) => _set('swipe.message.${side.name}', v.name);

  ChatSwipe chatSwipe(SwipeSide side) =>
      _enum(ChatSwipe.values, 'swipe.chat.${side.name}') ??
      (side == SwipeSide.left ? ChatSwipe.archive : ChatSwipe.pin);
  void setChatSwipe(SwipeSide side, ChatSwipe v) => _set('swipe.chat.${side.name}', v.name);

  /// The reaction a "React" message swipe sends.
  /// Double-tapping a message: react with [doubleTapEmoji] by default.
  MessageDoubleTap get doubleTap =>
      _enum(MessageDoubleTap.values, 'doubleTap.message') ?? MessageDoubleTap.react;
  set doubleTap(MessageDoubleTap v) => _set('doubleTap.message', v.name);

  /// Any emoji (the chat must allow it as a reaction).
  String get doubleTapEmoji => _string('doubleTap.emoji') ?? '❤️';
  set doubleTapEmoji(String v) => _set('doubleTap.emoji', v);

  String get swipeEmoji => _string('swipe.emoji') ?? '❤️';
  set swipeEmoji(String v) => _set('swipe.emoji', v);

  /// The reactions shown first when tapping a message (4–5).
  List<String> get quickReactions =>
      _string('reactions.quick')?.split(' ').where((e) => e.isNotEmpty).toList() ??
      const ['❤️', '👍', '🔥', '😂', '😮'];
  set quickReactions(List<String> v) => _set('reactions.quick', v.take(5).join(' '));

  /// Emoji picked in the media panel, most recent first.
  List<String> get recentEmoji =>
      _string('emoji.recent')?.split(' ').where((e) => e.isNotEmpty).toList() ?? const [];
  set recentEmoji(List<String> v) => _set('emoji.recent', v.join(' '));

  /// The on-device model suggests a reaction when you tap a message.
  bool get aiReactionSuggestion => _bool('reactions.ai', true);
  set aiReactionSuggestion(bool v) => _set('reactions.ai', v);

  /// Map thumbnails (from Telegram) on location messages.
  bool get mapPreviews => _bool('maps.previews', true);
  set mapPreviews(bool v) => _set('maps.previews', v);

  /// Which app opens a location: 'ask' (the system chooser), 'google' or 'osm'.
  String get mapApp => _string('maps.app') ?? 'ask';
  set mapApp(String v) => _set('maps.app', v);

  /// Default chat background: 'glow' (Lumina), 'photo', 'telegram' (a
  /// gallery wallpaper) or 'fill'.
  String get backdropKind => _string('backdrop.kind') ?? 'glow';
  set backdropKind(String v) => _set('backdrop.kind', v);

  /// Local photo for the 'photo' default.
  String? get backdropPath => _string('backdrop.path');
  set backdropPath(String? v) => v == null ? _remove('backdrop.path') : _set('backdrop.path', v);

  /// TDLib file id of a gallery wallpaper for the 'telegram' default.
  int? get backdropFileId => (_values['backdrop.fileId'] as num?)?.toInt();
  set backdropFileId(int? v) => v == null ? _remove('backdrop.fileId') : _set('backdrop.fileId', v);

  /// RGB colours (0xRRGGBB) for the 'fill' default.
  List<int> get backdropColors =>
      _string('backdrop.colors')?.split(',').map(int.parse).toList() ?? const [0x1B1F3B, 0x0E1220];
  set backdropColors(List<int> v) => _set('backdrop.colors', v.join(','));

  double get backdropBlur => _double('backdrop.blur', 0);
  set backdropBlur(double v) => _set('backdrop.blur', v.clamp(0.0, 30.0));

  double get backdropDim => _double('backdrop.dim', 0.35);
  set backdropDim(double v) => _set('backdrop.dim', v.clamp(0.0, 0.9));

  /// Chat list background: 'aurora' (drifting glow), 'plain', 'photo',
  /// 'telegram' (a gallery wallpaper) or 'fill'.
  String get listBackdropKind => _string('listBackdrop.kind') ?? 'aurora';
  set listBackdropKind(String v) => _set('listBackdrop.kind', v);

  String? get listBackdropPath => _string('listBackdrop.path');
  set listBackdropPath(String? v) => v == null ? _remove('listBackdrop.path') : _set('listBackdrop.path', v);

  int? get listBackdropFileId => (_values['listBackdrop.fileId'] as num?)?.toInt();
  set listBackdropFileId(int? v) =>
      v == null ? _remove('listBackdrop.fileId') : _set('listBackdrop.fileId', v);

  List<int> get listBackdropColors =>
      _string('listBackdrop.colors')?.split(',').map(int.parse).toList() ?? const [0x1B1F3B, 0x0E1220];
  set listBackdropColors(List<int> v) => _set('listBackdrop.colors', v.join(','));

  double get listBackdropBlur => _double('listBackdrop.blur', 8);
  set listBackdropBlur(double v) => _set('listBackdrop.blur', v.clamp(0.0, 30.0));

  /// Photos sit under chat rows, so they start well dimmed.
  double get listBackdropDim => _double('listBackdrop.dim', 0.55);
  set listBackdropDim(double v) => _set('listBackdrop.dim', v.clamp(0.0, 0.9));

  /// Let the aurora drift (a slow, low-frame-rate loop).
  bool get listAuroraDrift => _bool('listBackdrop.drift', true);
  set listAuroraDrift(bool v) => _set('listBackdrop.drift', v);

  /// Glass in the chat header and composer: full (liquid glass), light (a
  /// plain blur) or off (solid, the smoothest scrolling).
  GlassMode get glassMode => _enum(GlassMode.values, 'ui.glass') ?? GlassMode.light;
  set glassMode(GlassMode v) => _set('ui.glass', v.name);

  /// Text size across the app: 0.85 … 1.4 times the system size.
  double get textScale => _double('ui.textScale', 1.0);
  set textScale(double v) => _set('ui.textScale', v.clamp(0.85, 1.4));

  /// Play animated emoji, reactions and custom emoji; off shows them static.
  bool get animatedEmoji => _bool('emoji.animated', true);
  set animatedEmoji(bool v) => _set('emoji.animated', v);

  T? _enum<T extends Enum>(List<T> values, String key) {
    final name = _string(key);
    for (final v in values) {
      if (v.name == name) return v;
    }
    return null;
  }

  // ---- Privacy ("ghost mode", user request) -------------------------------

  /// Don't send read receipts automatically; messages are marked read only
  /// via "Mark as read".
  bool get hideReadReceipts => _bool('privacy.hideReadReceipts', false);
  set hideReadReceipts(bool v) => _set('privacy.hideReadReceipts', v);

  /// Don't broadcast typing / recording actions.
  bool get hideTyping => _bool('privacy.hideTyping', false);
  set hideTyping(bool v) => _set('privacy.hideTyping', v);

  /// Don't report the app as online while it is in the foreground.
  bool get appearOffline => _bool('privacy.appearOffline', false);
  set appearOffline(bool v) => _set('privacy.appearOffline', v);

  /// Don't mark stories as viewed when opening them.
  bool get hideStoryViews => _bool('privacy.hideStoryViews', false);
  set hideStoryViews(bool v) => _set('privacy.hideStoryViews', v);

  /// Ghost mode: every privacy switch at once (user request).
  bool get ghostMode => hideReadReceipts && hideTyping && appearOffline && hideStoryViews;
  set ghostMode(bool v) {
    hideReadReceipts = v;
    hideTyping = v;
    appearOffline = v;
    hideStoryViews = v;
  }

  // ---- Channels --------------------------------------------------------------

  /// Hide sponsored messages in channels for non-Premium accounts. Telegram's
  /// API terms require clients to show them, so this is opt-in and labelled.
  bool get hideSponsored => _bool('channels.hideSponsored', false);
  set hideSponsored(bool v) => _set('channels.hideSponsored', v);

  // ---- Stories ---------------------------------------------------------------

  /// Hide stories everywhere (most-voted suggestion on bugs.telegram.org).
  bool get hideStories => _bool('stories.hidden', false);
  set hideStories(bool v) => _set('stories.hidden', v);

  // ---- Media -----------------------------------------------------------------

  /// Voice/audio playback speed, 0.5–4.0×.
  double get playbackSpeed => _double('media.playbackSpeed', 1.0);
  set playbackSpeed(double v) => _set('media.playbackSpeed', v.clamp(0.5, 4.0));

  /// Downloaded videos start playing (muted) in the chat once scrolling
  /// settles on them. Off by default: they wait for their play button.
  bool get autoplayVideos => _bool('media.autoplayInline', false);
  set autoplayVideos(bool v) => _set('media.autoplayInline', v);

  /// A soft sound when a message goes out (not on silent or vibrate).
  bool get sendSound => _bool('media.sendSound', true);
  set sendSound(bool v) => _set('media.sendSound', v);

  /// The quality videos download and play in by default.
  VideoQuality get videoQuality => _enum(VideoQuality.values, 'media.videoQuality') ?? VideoQuality.low;
  set videoQuality(VideoQuality v) => _set('media.videoQuality', v.name);

  // ---- Dictation (Whisper) ---------------------------------------------------

  /// Send a dictated message automatically once transcribed (opt-in, §8.2).
  bool get dictationAutoSend => _bool('dictation.autoSend', false);
  set dictationAutoSend(bool v) => _set('dictation.autoSend', v);

  /// Whisper language hint ("auto" or ISO code).
  String get whisperLanguage => _string('dictation.language') ?? 'auto';
  set whisperLanguage(String v) => _set('dictation.language', v);

  // ---- Search ----------------------------------------------------------------

  /// Keep an on-device full-text index of message text (user request).
  bool get searchIndexEnabled => _bool('search.enabled', true);
  set searchIndexEnabled(bool v) => _set('search.enabled', v);

  /// Also index older history in the background, not just new messages.
  bool get searchBackfill => _bool('search.backfill', true);
  set searchBackfill(bool v) => _set('search.backfill', v);

  // ---- Proxy -----------------------------------------------------------------

  /// Saved proxies (JSON, secrets excluded; they live in SecureStore).
  String get proxiesJson => _string('proxy.list') ?? '[]';
  set proxiesJson(String v) => _set('proxy.list', v);

  // ---- Misc ------------------------------------------------------------------

  // ---- Attach hub ------------------------------------------------------------

  /// Last "Original quality" choice in the attach hub.
  bool get attachAsFiles => _bool('attach.asFiles', false);
  set attachAsFiles(bool v) => _set('attach.asFiles', v);

  /// JSON {tile: count}, for ordering tiles by use.
  String get attachUsage => _string('attach.usage') ?? '{}';
  set attachUsage(String v) => _set('attach.usage', v);

  /// Calls show in the Phone app's own in-call screen through Lumina's
  /// calling account (owner item 21). Off: Lumina's call screen, with
  /// Telecom still knowing about the call.
  bool get callsUseCallingAccount => _bool('calls.callingAccount', false);
  set callsUseCallingAccount(bool v) => _set('calls.callingAccount', v);

  /// Route calls through the active proxy when it is SOCKS5 (as official
  /// Telegram's "Use proxy for calls"). Off by default.
  bool get callsUseProxy => _bool('calls.useProxy', false);
  set callsUseProxy(bool v) => _set('calls.useProxy', v);

  /// Hide the channel an MTProto proxy promotes at the top of the chat list.
  bool get hideProxySponsor => _bool('proxy.hideSponsor', false);
  set hideProxySponsor(bool v) => _set('proxy.hideSponsor', v);

  /// Folder glow colours chosen on this device (JSON: folder id → colour id),
  /// for accounts whose folder colours Telegram doesn't sync (non-Premium).
  String get folderColorsJson => _string('folders.colors') ?? '{}';
  set folderColorsJson(String v) => _set('folders.colors', v);

  /// Active outgoing live locations (JSON), resumed after process death.
  String get liveLocations => _string('live.shares') ?? '[]';
  set liveLocations(String v) => _set('live.shares', v);

  // ---- Links -----------------------------------------------------------------

  /// Attach a link preview when sending a message with a link.
  bool get linkPreviewsOnSend => _bool('links.previewOnSend', true);
  set linkPreviewsOnSend(bool v) => _set('links.previewOnSend', v);

  /// Show link preview cards (and Instant View) in received messages.
  bool get showLinkPreviews => _bool('links.showPreviews', true);
  set showLinkPreviews(bool v) => _set('links.showPreviews', v);

  /// Open web links in the browser app instead of a Chromium Custom Tab.
  bool get openLinksExternally => _bool('links.external', false);
  set openLinksExternally(bool v) => _set('links.external', v);

  /// Delete cached media not opened for this many days; 0 keeps forever.
  int get keepMediaDays => _values['storage.keepMediaDays'] as int? ?? 0;
  set keepMediaDays(int v) => _set('storage.keepMediaDays', v);

  bool get batteryPromptShown => _bool('system.batteryPromptShown', false);
  set batteryPromptShown(bool v) => _set('system.batteryPromptShown', v);
}
