import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/media/waveform.dart';

Uint8List wav(List<int> samples) {
  final data = ByteData(44 + samples.length * 2);
  void str(int o, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(o + i, s.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  data.setUint32(4, 36 + samples.length * 2, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, 16000, Endian.little);
  data.setUint32(28, 32000, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  str(36, 'data');
  data.setUint32(40, samples.length * 2, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    data.setInt16(44 + i * 2, samples[i], Endian.little);
  }
  return data.buffer.asUint8List();
}

void main() {
  test('5-bit packing round-trips', () {
    final values = List<int>.generate(100, (i) => (i * 7) % 32);
    final decoded = Waveform.decode(Waveform.encode(values));
    expect(decoded.take(100), values);
  });

  test('100 samples pack into 63 bytes', () {
    final encoded = Waveform.encode(List.filled(100, 31));
    expect(Waveform.decode(encoded).length, greaterThanOrEqualTo(100));
  });

  test('peaks from WAV: loudest bucket is 31, silence is 0', () {
    final samples = [...List.filled(500, 0), ...List.filled(500, 16000)];
    final peaks = Waveform.fromWav(wav(samples), count: 10);
    expect(peaks.first, 0);
    expect(peaks.last, 31);
  });

  test('resample keeps peaks', () {
    expect(Waveform.resample([0, 31, 0, 0, 10, 0], 3), [31, 0, 10]);
  });
}
