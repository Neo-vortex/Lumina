import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../telegram/file_store.dart';

/// Streams TDLib files to media players over loopback HTTP with Range
/// support, so playback starts before the download finishes and seeking
/// fetches only the needed part.
///
/// Each Range request is served by asking TDLib for that byte range
/// (`downloadFile(offset:)`), then reading bytes from TDLib's partially
/// downloaded local file as `getFileDownloadedPrefixSize` reports them
/// available. Works for VLC (libVLC's own HTTP stack) and ExoPlayer /
/// just_audio (cleartext permitted for 127.0.0.1 only, see
/// network_security_config.xml).
///
/// Any app on the device can reach 127.0.0.1, so every URL carries a random
/// per-process token; requests without it get 403.
class TdStreamServer {
  TdStreamServer(this._files);

  final FileStore _files;
  HttpServer? _server;
  late final String _token = _randomToken();

  static const _chunk = 256 * 1024;

  Future<void> start() async {
    if (_server != null) return;
    final server = _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) => unawaited(_handle(request)));
  }

  /// URL a player can open for [file]. [mimeType] becomes Content-Type.
  Future<Uri> urlFor(td.File file, {String mimeType = 'application/octet-stream'}) async {
    await start();
    _files.remember(file);
    return Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: _server!.port,
      path: '/f/${file.id}',
      queryParameters: {'t': _token, 'm': mimeType},
    );
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      final segments = request.uri.pathSegments;
      final fileId = segments.length == 2 && segments[0] == 'f' ? int.tryParse(segments[1]) : null;
      if (request.uri.queryParameters['t'] != _token || fileId == null) {
        response.statusCode = HttpStatus.forbidden;
        return;
      }
      var file = _files[fileId] ?? await _files.refresh(fileId);
      final size = file.size != 0 ? file.size : file.expectedSize;
      final range = _parseRange(request.headers.value(HttpHeaders.rangeHeader), size);
      if (range == null) {
        response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$size');
        return;
      }
      final (start, end) = range; // inclusive end
      response.headers
        ..set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..set(HttpHeaders.contentTypeHeader, request.uri.queryParameters['m'] ?? 'application/octet-stream');
      if (size > 0) {
        response.statusCode = request.headers.value(HttpHeaders.rangeHeader) == null
            ? HttpStatus.ok
            : HttpStatus.partialContent;
        response.contentLength = end - start + 1;
        if (response.statusCode == HttpStatus.partialContent) {
          response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$size');
        }
      }
      if (request.method == 'HEAD') return;

      await _files.requestRange(fileId, start);
      file = _files[fileId]!;
      RandomAccessFile? raf;
      try {
        var offset = start;
        while (offset <= end) {
          final available = await _files.downloadedPrefix(fileId, offset);
          if (available <= 0) {
            final current = _files[fileId]!;
            if (current.local.isDownloadingCompleted) break; // past real EOF
            if (!current.local.isDownloadingActive) await _files.requestRange(fileId, offset);
            await _nextChange(fileId);
            continue;
          }
          final path = _files[fileId]!.local.path;
          raf ??= await File(path).open();
          final want = min(min(available, _chunk), end - offset + 1);
          await raf.setPosition(offset);
          final bytes = await raf.read(want);
          if (bytes.isEmpty) {
            await _nextChange(fileId);
            continue;
          }
          response.add(bytes);
          await response.flush();
          offset += bytes.length;
        }
      } finally {
        await raf?.close();
      }
    } on HttpException {
      // Player closed the connection (seek or stop); nothing to do.
    } on SocketException {
      // Same.
    } catch (e, st) {
      debugPrint('Stream server error: $e\n$st');
    } finally {
      try {
        await response.close();
      } catch (_) {}
    }
  }

  /// Waits for TDLib to report progress on [fileId] (or 1 s, whichever first).
  Future<void> _nextChange(int fileId) => _files
      .watch(fileId)
      .skip(_files[fileId] != null ? 1 : 0)
      .first
      .timeout(const Duration(seconds: 1), onTimeout: () => _files[fileId]!);

  /// Parses a single `bytes=a-b` range. Unknown size streams to the end.
  static (int, int)? _parseRange(String? header, int size) {
    final last = size > 0 ? size - 1 : 1 << 52;
    if (header == null) return (0, last);
    final match = RegExp(r'bytes=(\d*)-(\d*)').firstMatch(header);
    if (match == null) return (0, last);
    final a = match.group(1)!, b = match.group(2)!;
    if (a.isEmpty && b.isNotEmpty) {
      // Suffix range: last N bytes.
      if (size <= 0) return null;
      final n = int.parse(b);
      return (max(0, size - n), last);
    }
    final start = int.parse(a.isEmpty ? '0' : a);
    final end = b.isEmpty ? last : min(int.parse(b), last);
    if (size > 0 && start > last) return null;
    return (start, end);
  }

  @visibleForTesting
  static (int, int)? parseRangeForTest(String? header, int size) => _parseRange(header, size);

  static String _randomToken() {
    final random = Random.secure();
    return List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }
}
