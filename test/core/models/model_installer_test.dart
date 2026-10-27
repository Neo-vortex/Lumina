import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/models/bundled_models.dart';

class _Installed extends ModelInstaller {
  @override
  Future<String> pathFor(BundledModel model) async => '/models/${model.fileName}';

  @override
  Future<bool> isInstalled(BundledModel model) async => true;
}

class _Recording extends ModelInstaller {
  final ensured = <String>[];

  @override
  Future<String> ensure(BundledModel model) async {
    ensured.add(model.fileName);
    if (model == BundledModel.whisperBase) throw const NotEnoughSpace(2, 1);
    return '/models/${model.fileName}';
  }
}

void main() {
  test('preinstall extracts each model in turn and swallows failures', () async {
    final installer = _Recording();
    await installer.preinstall(const [BundledModel.whisperBase, BundledModel.actionModel]);
    expect(installer.ensured, [BundledModel.whisperBase.fileName, BundledModel.actionModel.fileName]);
  });

  test('a scheduled preinstall waits for its delay and dispose cancels it', () async {
    final installer = _Recording()
      ..schedulePreinstall(const [BundledModel.actionModel], delay: const Duration(milliseconds: 20));
    expect(installer.ensured, isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(installer.ensured, [BundledModel.actionModel.fileName]);

    final cancelled = _Recording()
      ..schedulePreinstall(const [BundledModel.actionModel], delay: const Duration(milliseconds: 20))
      ..dispose();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(cancelled.ensured, isEmpty);
  });

  test('ensure completes for an installed model (it used to wait on itself forever)', () async {
    final path = await _Installed().ensure(BundledModel.actionModel).timeout(const Duration(seconds: 2));
    expect(path, endsWith(BundledModel.actionModel.fileName));
  });

  test('a second ensure after the first finished starts fresh and completes too', () async {
    final installer = _Installed();
    await installer.ensure(BundledModel.actionModel).timeout(const Duration(seconds: 2));
    await installer.ensure(BundledModel.actionModel).timeout(const Duration(seconds: 2));
  });
}
