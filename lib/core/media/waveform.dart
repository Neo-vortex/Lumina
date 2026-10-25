import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// Telegram voice-note waveforms: [samples] values of 0..31 packed as a
/// little-endian 5-bit stream (TDLib `bytes`, base64 in JSON).
abstract final class Waveform {
  static const samples = 100;
  static const maxValue = 31;

  static String encode(List<int> values) {
    final bits = values.length * 5;
    final out = Uint8List((bits + 7) ~/ 8);
    for (var i = 0; i < values.length; i++) {
      final v = values[i].clamp(0, maxValue);
      final offset = i * 5;
      final byte = offset >> 3, shift = offset & 7;
      out[byte] |= (v << shift) & 0xff;
      if (shift > 3 && byte + 1 < out.length) out[byte + 1] |= v >> (8 - shift);
    }
    return base64Encode(out);
  }

  static List<int> decode(String encoded) {
    if (encoded.isEmpty) return const [];
    final bytes = base64Decode(encoded);
    final count = bytes.length * 8 ~/ 5;
    return List<int>.generate(count, (i) {
      final offset = i * 5;
      final byte = offset >> 3, shift = offset & 7;
      var v = bytes[byte] >> shift;
      if (shift > 3 && byte + 1 < bytes.length) v |= bytes[byte + 1] << (8 - shift);
      return v & maxValue;
    });
  }

  /// Peak envelope of 16-bit little-endian mono PCM in a WAV file,
  /// normalised to 0..31 (loudest bucket = 31).
  static List<int> fromWav(Uint8List wav, {int count = samples}) {
    final dataStart = _dataOffset(wav);
    final pcm = ByteData.sublistView(wav, dataStart);
    final frames = pcm.lengthInBytes ~/ 2;
    if (frames == 0) return List.filled(count, 0);
    final per = math.max(1, frames ~/ count);
    final peaks = <double>[];
    for (var b = 0; b < count; b++) {
      var peak = 0;
      final start = b * per;
      if (start >= frames) {
        peaks.add(0);
        continue;
      }
      final end = math.min(frames, start + per);
      for (var i = start; i < end; i++) {
        final s = pcm.getInt16(i * 2, Endian.little).abs();
        if (s > peak) peak = s;
      }
      peaks.add(peak.toDouble());
    }
    return normalise(peaks);
  }

  /// Scales arbitrary levels (e.g. live amplitudes) to 0..31.
  static List<int> normalise(List<double> levels) {
    final top = levels.fold<double>(0, math.max);
    if (top <= 0) return List.filled(levels.length, 0);
    return [for (final l in levels) (l / top * maxValue).round()];
  }

  /// Resamples [values] to [count] buckets (max per bucket).
  static List<int> resample(List<int> values, int count) {
    if (values.isEmpty) return List.filled(count, 0);
    return List<int>.generate(count, (i) {
      final a = i * values.length ~/ count;
      final b = math.max(a + 1, (i + 1) * values.length ~/ count);
      return values.sublist(a, math.min(b, values.length)).fold(0, math.max);
    });
  }

  static int _dataOffset(Uint8List wav) {
    // Walk RIFF chunks to "data"; fall back to the canonical 44-byte header.
    if (wav.length < 12 || String.fromCharCodes(wav.sublist(0, 4)) != 'RIFF') return 0;
    var p = 12;
    final view = ByteData.sublistView(wav);
    while (p + 8 <= wav.length) {
      final id = String.fromCharCodes(wav.sublist(p, p + 4));
      final size = view.getUint32(p + 4, Endian.little);
      if (id == 'data') return p + 8;
      p += 8 + size + (size & 1);
    }
    return 44;
  }
}
