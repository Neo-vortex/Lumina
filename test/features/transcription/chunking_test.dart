import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/features/transcription/data/whisper_service.dart';

void main() {
  test('long audio splits into 30 s chunks covering every sample', () {
    const rate = 16000;
    final samples = rate * 65; // 65 s
    final ranges = chunkRanges(samples, sampleRate: rate, chunk: const Duration(seconds: 30));
    expect(ranges, [(0, rate * 30), (rate * 30, rate * 60), (rate * 60, samples)]);
  });

  test('short audio is one chunk', () {
    expect(chunkRanges(100, sampleRate: 16000, chunk: const Duration(seconds: 30)), [(0, 100)]);
  });
}
