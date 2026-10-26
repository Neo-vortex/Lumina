import 'package:flutter/services.dart';

/// Dart side of MainActivity's "dev.lumina/system" channel.
class SystemChannel {
  const SystemChannel();

  static const _ch = MethodChannel('dev.lumina/system');

  /// Streams a bundled asset to [dest] (no full copy in memory). Bytes copied.
  Future<int> copyAsset(String asset, String dest) async =>
      (await _ch.invokeMethod<int>('copyAsset', {'asset': asset, 'dest': dest})) ?? 0;

  Future<int> freeSpace(String path) async => (await _ch.invokeMethod<int>('freeSpace', {'path': path})) ?? 0;

  /// Coarse device location with a best-effort place name, or null when
  /// the user declines or no fix is available.
  Future<({double latitude, double longitude, String name})?> currentLocation() async {
    final r = await _ch.invokeMapMethod<String, Object?>('currentLocation');
    if (r == null) return null;
    return (
      latitude: r['latitude']! as double,
      longitude: r['longitude']! as double,
      name: (r['name'] ?? '') as String,
    );
  }

  /// A fresh precise-if-allowed fix without geocoding, for live locations.
  /// Never prompts; null without permission or a fix.
  Future<({double latitude, double longitude, double accuracy})?> currentPosition() async {
    final r = await _ch.invokeMapMethod<String, Object?>('currentPosition');
    if (r == null) return null;
    return (
      latitude: r['latitude']! as double,
      longitude: r['longitude']! as double,
      accuracy: (r['accuracy'] as num?)?.toDouble() ?? 0,
    );
  }

  /// Starts the live-location foreground service. With [ask], first asks for
  /// precise location and notifications. False without location access.
  Future<bool> liveLocationStart({bool ask = true}) async =>
      (await _ch.invokeMethod<bool>('liveLocationStart', {'ask': ask})) ?? false;

  Future<void> liveLocationStop() => _ch.invokeMethod<void>('liveLocationStop');

  /// The system share sheet for plain text.
  Future<bool> shareText(String text) async =>
      (await _ch.invokeMethod<bool>('shareText', {'text': text})) ?? false;

  /// Android's "Open by default" page for Lumina (t.me links).
  Future<bool> openLinkSettings() async => (await _ch.invokeMethod<bool>('openLinkSettings')) ?? false;

  Future<int> totalRam() async => (await _ch.invokeMethod<int>('totalRam')) ?? 0;

  Future<bool> isIgnoringBatteryOptimizations() async =>
      (await _ch.invokeMethod<bool>('isIgnoringBatteryOptimizations')) ?? false;

  Future<bool> openBatterySettings() async => (await _ch.invokeMethod<bool>('openBatterySettings')) ?? false;

  Future<bool> insertCalendarEvent({
    required String title,
    required DateTime begin,
    required DateTime end,
    String? description,
    String? location,
    bool allDay = false,
    bool reminder = false,
  }) async =>
      (await _ch.invokeMethod<bool>('insertCalendarEvent', {
        'title': title,
        'begin': begin.millisecondsSinceEpoch,
        'end': end.millisecondsSinceEpoch,
        'description': description,
        'location': location,
        'allDay': allDay,
        'reminder': reminder,
      })) ??
      false;

  Future<bool> setAlarm({required int hour, required int minutes, String? message}) async =>
      (await _ch.invokeMethod<bool>('setAlarm', {'hour': hour, 'minutes': minutes, 'message': message})) ??
      false;

  Future<bool> setTimer({required int seconds, String? message}) async =>
      (await _ch.invokeMethod<bool>('setTimer', {'seconds': seconds, 'message': message})) ?? false;

  Future<bool> createNote({required String title, required String text}) async =>
      (await _ch.invokeMethod<bool>('createNote', {'title': title, 'text': text})) ?? false;
}
