import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/models/bundled_models.dart';

class _Installed extends ModelInstaller {
  @override
  Future<String> pathFor(BundledModel model) async => '/models/${model.fileName}';

  @override
  Future<bool> isInstalled(BundledModel model) async => true;
}

void main() {
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
