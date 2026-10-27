import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/telegram/widgets/progressive_image.dart';
import 'package:lumina_tdlib/api.dart' as td;

void main() {
  final progressive = File('test/fixtures/progressive.jpg').readAsBytesSync();
  final baseline = File('test/fixtures/baseline.jpg').readAsBytesSync();

  test('tells progressive JPEGs from baseline ones by the first bytes', () {
    expect(isProgressiveJpeg(progressive.sublist(0, 2048)), isTrue);
    expect(isProgressiveJpeg(baseline.sublist(0, 2048)), isFalse);
    expect(isProgressiveJpeg(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47])), isFalse, reason: 'PNG');
    expect(isProgressiveJpeg(progressive.sublist(0, 20)), isNull, reason: 'not enough bytes yet');
  });

  test('decodes at checkpoints: enough new bytes and not too often', () {
    const plan = DecodePlan();
    expect(
      plan.due(prefix: 50, total: 1000, lastPrefix: 0, sinceLast: const Duration(seconds: 1)),
      isFalse,
      reason: 'too little for a first scan',
    );
    expect(plan.due(prefix: 200, total: 1000, lastPrefix: 0, sinceLast: const Duration(seconds: 1)), isTrue);
    expect(
      plan.due(prefix: 240, total: 1000, lastPrefix: 200, sinceLast: const Duration(seconds: 1)),
      isFalse,
      reason: 'only 4 % more',
    );
    expect(
      plan.due(prefix: 400, total: 1000, lastPrefix: 200, sinceLast: const Duration(milliseconds: 50)),
      isFalse,
      reason: 'throttled',
    );
    expect(
      plan.due(prefix: 400, total: 1000, lastPrefix: 200, sinceLast: const Duration(milliseconds: 300)),
      isTrue,
    );
    expect(
      plan.due(prefix: 1000, total: 1000, lastPrefix: 900, sinceLast: Duration.zero),
      isFalse,
      reason: 'complete: the full image takes over',
    );
  });

  test('the blur eases off continuously as bytes arrive and is gone at the end', () {
    final sigmas = [for (var p = 0.0; p <= 1.0001; p += 0.1) blurFor(p)];
    for (var i = 1; i < sigmas.length; i++) {
      expect(sigmas[i], lessThan(sigmas[i - 1]));
    }
    expect(blurFor(1), 0);
    expect(blurFor(0), greaterThan(4));
  });

  widgetTests();
}

td.File partial(String path, int prefix, int total) => td.File(
  id: 7,
  size: total,
  expectedSize: total,
  local: td.LocalFile(
    path: path,
    canBeDownloaded: true,
    canBeDeleted: false,
    isDownloadingActive: true,
    isDownloadingCompleted: false,
    downloadOffset: 0,
    downloadedPrefixSize: prefix,
    downloadedSize: prefix,
  ),
  remote: const td.RemoteFile(
    id: '',
    uniqueId: '',
    isUploadingActive: false,
    isUploadingCompleted: true,
    uploadedSize: 0,
  ),
);

Future<int> decodedLayers(WidgetTester tester, String fixture) async {
  final bytes = File('test/fixtures/$fixture.jpg').readAsBytesSync();
  final dir = Directory.systemTemp.createTempSync('lumina_prog');
  addTearDown(() => dir.deleteSync(recursive: true));
  final path = '${dir.path}/photo.jpg';
  File(path).writeAsBytesSync(bytes.sublist(0, (bytes.length * 0.6).round()));
  final key = GlobalKey();
  Widget at(int prefix) => Directionality(
    textDirection: TextDirection.ltr,
    child: SizedBox(
      width: 320,
      height: 240,
      child: ProgressivePlaceholder(
        key: key,
        file: partial(path, prefix, bytes.length),
        minithumbnail: null,
        fit: BoxFit.cover,
      ),
    ),
  );
  await tester.pumpWidget(at(0));
  await tester.runAsync(() async {
    await tester.pumpWidget(at((bytes.length * 0.6).round()));
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await tester.pump();
    }
  });
  await tester.pump(const Duration(milliseconds: 400));
  return tester.widgetList<RawImage>(find.byType(RawImage)).where((r) => r.image != null).length;
}

void widgetTests() {
  testWidgets('a progressive photo shows its downloaded prefix, decoded', (tester) async {
    expect(await decodedLayers(tester, 'progressive'), 1);
  });

  testWidgets('a baseline photo stays on the placeholder until complete', (tester) async {
    expect(await decodedLayers(tester, 'baseline'), 0);
  });
}
