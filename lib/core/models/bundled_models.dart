import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../platform/system_channel.dart';

/// A model file shipped inside the APK (Git LFS in the repo).
class BundledModel {
  const BundledModel({required this.asset, required this.fileName, required this.bytes});

  final String asset;
  final String fileName;

  /// Exact size, used to detect a missing or truncated extraction.
  final int bytes;

  static const whisperBase = BundledModel(
    asset: 'assets/models/ggml-base-q5_1.bin',
    fileName: 'ggml-base-q5_1.bin',
    bytes: 59707625,
  );

  static const functionGemma = BundledModel(
    asset: 'assets/models/functiongemma-270m-it-Q4_0.gguf',
    fileName: 'functiongemma-270m-it-Q4_0.gguf',
    bytes: 241587424,
  );
}

class NotEnoughSpace implements Exception {
  const NotEnoughSpace(this.needed, this.free);
  final int needed;
  final int free;

  @override
  String toString() =>
      'Not enough free space: ${(needed / 1e6).round()} MB needed, ${(free / 1e6).round()} MB free';
}

/// Extracts bundled models to app-private storage once (native libraries
/// need a real file path), with a free-space check.
class ModelInstaller {
  ModelInstaller([this._system = const SystemChannel()]);

  final SystemChannel _system;
  final _inFlight = <String, Future<String>>{};

  Future<String> pathFor(BundledModel model) async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}/models/${model.fileName}';
  }

  Future<bool> isInstalled(BundledModel model) async {
    final f = File(await pathFor(model));
    return await f.exists() && await f.length() == model.bytes;
  }

  /// Path of the extracted model, extracting it first if needed.
  Future<String> ensure(BundledModel model) =>
      _inFlight[model.fileName] ??= _ensure(model).whenComplete(() => _inFlight.remove(model.fileName));

  Future<String> _ensure(BundledModel model) async {
    final path = await pathFor(model);
    if (await isInstalled(model)) return path;
    final dir = Directory(File(path).parent.path)..createSync(recursive: true);
    final free = await _system.freeSpace(dir.path);
    // Leave headroom for TDLib's database and media.
    final needed = model.bytes + 50 * 1024 * 1024;
    if (free > 0 && free < needed) throw NotEnoughSpace(needed, free);
    final copied = await _system.copyAsset(model.asset, path);
    if (copied != model.bytes) {
      await File(path).delete().catchError((_) => File(path));
      throw StateError('Model extraction incomplete ($copied of ${model.bytes} bytes)');
    }
    return path;
  }

  Future<void> remove(BundledModel model) async {
    final f = File(await pathFor(model));
    if (await f.exists()) await f.delete();
  }
}
