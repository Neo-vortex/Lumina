import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  static Future<AppPreferences> load() async {
    final prefs = AppPreferences(SharedPreferencesAsync());
    await prefs._loadAll();
    return prefs;
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

  bool get autoplayVideos => _bool('media.autoplayVideos', true);
  set autoplayVideos(bool v) => _set('media.autoplayVideos', v);

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
