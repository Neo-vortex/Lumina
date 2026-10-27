import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/models/bundled_models.dart';
import 'package:lumina/features/assistant/data/action_extractor.dart';
import 'package:llamadart/llamadart.dart';

class _Installed extends ModelInstaller {
  @override
  Future<String> ensure(BundledModel model) async => '/models/${model.fileName}';
}

final _ctx = AssistantContext(
  userName: 'Me',
  username: 'me',
  senderName: 'Ada',
  messageTime: DateTime(2026, 10, 26),
  now: DateTime(2026, 10, 26),
);

void main() {
  test('a model load that hangs times out instead of spinning, and the next try loads afresh', () async {
    var loads = 0;
    final stages = <ExtractStage>[];
    final extractor = ActionExtractor(
      _Installed(),
      loadEngine: (_, _) {
        loads++;
        return Completer<Never>().future; // never finishes
      },
      loadTimeout: const Duration(milliseconds: 50),
    );

    await expectLater(
      extractor.extract('lunch at 1', _ctx, onStage: stages.add),
      throwsA(isA<TimeoutException>()),
    );
    expect(stages, [ExtractStage.preparing, ExtractStage.loading]);

    await expectLater(extractor.extract('lunch at 1', _ctx), throwsA(isA<TimeoutException>()));
    // Each try: the GPU, then the CPU fallback.
    expect(loads, 4, reason: 'a failed load must not stay cached');
  });

  test('loads on the GPU, falls back to the CPU when that fails, and can be forced to the CPU', () async {
    final tried = <ComputeDevice>[];
    Future<LlamaEngine> load(String _, ComputeDevice d) async {
      tried.add(d);
      // Stop after the device choice: no real engine in unit tests.
      throw d == ComputeDevice.gpu ? LlamaUnsupportedException('no Vulkan') : StateError('cpu');
    }

    final extractor = ActionExtractor(_Installed(), loadEngine: load);
    await expectLater(extractor.extract('x', _ctx), throwsStateError);
    expect(tried, [ComputeDevice.gpu, ComputeDevice.cpu]);

    tried.clear();
    final cpuOnly = ActionExtractor(_Installed(), loadEngine: load, forceCpu: () => true);
    await expectLater(cpuOnly.extract('x', _ctx), throwsStateError);
    expect(tried, [ComputeDevice.cpu]);
  });
}
