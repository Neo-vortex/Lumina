import 'package:flutter/services.dart';

/// Dart side of MainActivity's "dev.lumina/system" channel.
class SystemChannel {
  const SystemChannel();

  static const _ch = MethodChannel('dev.lumina/system');

  /// Streams a bundled asset to [dest] (no full copy in memory). Bytes copied.
  Future<int> copyAsset(String asset, String dest) async =>
      (await _ch.invokeMethod<int>('copyAsset', {'asset': asset, 'dest': dest})) ?? 0;

  Future<int> freeSpace(String path) async => (await _ch.invokeMethod<int>('freeSpace', {'path': path})) ?? 0;

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
