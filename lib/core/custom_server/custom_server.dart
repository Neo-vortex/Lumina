import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';

/// A self-hosted, Telegram-compatible (MTProto) server. Lumina's patched
/// TDLib reads it from the environment at startup (tool/tdlib-patches):
/// LUMINA_SERVER=host:port serves every DC and LUMINA_SERVER_RSA (PEM) is the
/// only trusted key. Each server gets its own TDLib database.
class CustomServer {
  const CustomServer({required this.host, required this.port, required this.rsaPem});

  final String host;
  final int port;
  final String rsaPem;

  /// host:port as TDLib takes it (IPv6 in brackets).
  String get address => host.contains(':') ? '[$host]:$port' : '$host:$port';

  RsaPublicKey get key => RsaPublicKey.parse(rsaPem);

  /// Folder name for this server's TDLib data: stable per address + key.
  String get storageId =>
      sha256.convert(utf8.encode('$address\n${key.fingerprintHex}')).toString().substring(0, 16);

  Map<String, Object> toJson() => {'host': host, 'port': port, 'rsa': rsaPem};

  static CustomServer? fromJson(Object? json) {
    if (json is! Map) return null;
    final host = json['host'], port = json['port'], rsa = json['rsa'];
    if (host is! String || port is! int || rsa is! String) return null;
    return CustomServer(host: host, port: port, rsaPem: rsa);
  }

  // ---- Persistence (read before TDLib starts) ---------------------------------

  static File _file(String supportDir) => File('$supportDir/custom_server.json');

  static CustomServer? load(String supportDir) {
    try {
      final f = _file(supportDir);
      if (!f.existsSync()) return null;
      return fromJson(jsonDecode(f.readAsStringSync()));
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(String supportDir, CustomServer? server) async {
    final f = _file(supportDir);
    if (server == null) {
      if (await f.exists()) await f.delete();
    } else {
      await f.writeAsString(jsonEncode(server.toJson()), flush: true);
    }
  }

  /// Hands the server to TDLib. Read when a TDLib client is created, so a
  /// switch needs a new client (AppRoot.reload), not a new process.
  void applyToEnvironment() {
    _setenv('LUMINA_SERVER', address);
    _setenv('LUMINA_SERVER_RSA', key.pkcs1Pem);
  }

  /// Back to Telegram: TDLib clients created from now on use its servers.
  static void clearEnvironment() {
    final unsetenv = ffi.DynamicLibrary.process()
        .lookupFunction<ffi.Int32 Function(ffi.Pointer<Utf8>), int Function(ffi.Pointer<Utf8>)>('unsetenv');
    for (final name in ['LUMINA_SERVER', 'LUMINA_SERVER_RSA']) {
      final n = name.toNativeUtf8();
      try {
        unsetenv(n);
      } finally {
        malloc.free(n);
      }
    }
  }

  static void _setenv(String name, String value) {
    final setenv = ffi.DynamicLibrary.process()
        .lookupFunction<
          ffi.Int32 Function(ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, ffi.Int32),
          int Function(ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, int)
        >('setenv');
    final n = name.toNativeUtf8(), v = value.toNativeUtf8();
    try {
      setenv(n, v, 1);
    } finally {
      malloc
        ..free(n)
        ..free(v);
    }
  }

  // ---- Probe --------------------------------------------------------------------

  /// Opens an MTProto connection (intermediate transport) and sends an
  /// unencrypted req_pq_multi; the server's resPQ lists the fingerprints of
  /// the RSA keys it can use.
  static Future<List<int>> probe(
    String host,
    int port, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final socket = await Socket.connect(host, port, timeout: timeout);
    try {
      final rnd = Random.secure();
      final nonce = Uint8List.fromList(List.generate(16, (_) => rnd.nextInt(256)));
      final body = BytesBuilder()
        ..add(_u32(0xbe7e8ef1))
        ..add(nonce);
      final now = DateTime.now().millisecondsSinceEpoch;
      final msgId = ((now ~/ 1000) << 32) | (((now % 1000) * 4294967) & 0xfffffffc);
      final message = BytesBuilder()
        ..add(_u64(0)) // auth_key_id: unencrypted
        ..add(_u64(msgId))
        ..add(_u32(body.length))
        ..add(body.toBytes());
      final packet = message.toBytes();
      socket.add([0xee, 0xee, 0xee, 0xee]); // intermediate transport tag
      socket.add(_u32(packet.length));
      socket.add(packet);
      await socket.flush();

      final reply = await _readPacket(socket).timeout(timeout);
      if (reply.length == 4) {
        throw ProbeError(
          'The server refused the handshake (code ${ByteData.sublistView(reply).getInt32(0, Endian.little)})',
        );
      }
      final r = ByteData.sublistView(reply);
      var o = 20; // auth_key_id, message_id, message_length
      if (reply.length < o + 4 || r.getUint32(o, Endian.little) != 0x05162463) {
        throw const ProbeError('Not an MTProto server (no resPQ)');
      }
      o += 4;
      for (var i = 0; i < 16; i++) {
        if (reply[o + i] != nonce[i]) throw const ProbeError('The server answered with the wrong nonce');
      }
      o += 32; // nonce, server_nonce
      // pq: TL bytes.
      final short = reply[o];
      final len = short < 254 ? short : reply[o + 1] | reply[o + 2] << 8 | reply[o + 3] << 16;
      final head = short < 254 ? 1 : 4;
      o += (head + len + 3) & ~3;
      if (r.getUint32(o, Endian.little) != 0x1cb5c415) throw const ProbeError('Malformed resPQ');
      final count = r.getInt32(o + 4, Endian.little);
      o += 8;
      return [for (var i = 0; i < count; i++) r.getInt64(o + i * 8, Endian.little)];
    } finally {
      socket.destroy();
    }
  }

  static Future<Uint8List> _readPacket(Socket socket) async {
    final buf = BytesBuilder();
    int? want;
    await for (final chunk in socket) {
      buf.add(chunk);
      final bytes = buf.toBytes();
      if (want == null && bytes.length >= 4) want = ByteData.sublistView(bytes).getUint32(0, Endian.little);
      if (want != null && bytes.length >= 4 + want) return Uint8List.sublistView(bytes, 4, 4 + want);
    }
    throw const ProbeError('The server closed the connection');
  }

  static Uint8List _u32(int v) => Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little);
  static Uint8List _u64(int v) => Uint8List(8)..buffer.asByteData().setInt64(0, v, Endian.little);
}

/// The server's TLS certificate as seen while fetching its key.
class TlsCertificate {
  const TlsCertificate({
    required this.subject,
    required this.issuer,
    required this.validFrom,
    required this.validTo,
    required this.fingerprint,
  });

  final String subject;
  final String issuer;
  final DateTime validFrom;
  final DateTime validTo;

  /// SHA-256 of the DER certificate, colon-separated hex.
  final String fingerprint;

  bool get selfSigned => subject == issuer;

  static TlsCertificate of(X509Certificate c) {
    final h = sha256Hash(c.der);
    return TlsCertificate(
      subject: c.subject,
      issuer: c.issuer,
      validFrom: c.startValidity,
      validTo: c.endValidity,
      fingerprint: h,
    );
  }

  static String sha256Hash(List<int> der) =>
      [for (final b in sha256.convert(der).bytes) b.toRadixString(16).padLeft(2, '0').toUpperCase()]
          .join(':');
}

/// The key a server publishes over HTTPS, with the certificate it came under.
class FetchedKey {
  const FetchedKey({
    required this.pem,
    required this.key,
    required this.url,
    this.certificate,
    required this.caTrusted,
  });

  final String pem;
  final RsaPublicKey key;
  final Uri url;
  final TlsCertificate? certificate;

  /// The certificate chained to a CA the device trusts.
  final bool caTrusted;
}

/// Where a server publishes its MTProto RSA key by default.
Uri defaultKeyUrl(String host) => Uri(scheme: 'https', host: host, path: '/.well-known/mtproto-key.pem');

/// Downloads the server's PEM key. Any TLS certificate is accepted (the user
/// is shown it and decides); a CA-trusted one is reported as such.
Future<FetchedKey> fetchServerKey(Uri url, {Duration timeout = const Duration(seconds: 10)}) async {
  TlsCertificate? cert;
  var caTrusted = true;
  final client = HttpClient()
    ..connectionTimeout = timeout
    ..badCertificateCallback = (c, host, port) {
      cert = TlsCertificate.of(c);
      caTrusted = false;
      return true;
    };
  try {
    final req = await client.getUrl(url).timeout(timeout);
    final res = await req.close().timeout(timeout);
    final peer = res.certificate;
    if (peer != null) cert ??= TlsCertificate.of(peer);
    if (res.statusCode != 200) throw ProbeError('HTTP ${res.statusCode}');
    final body = await res.transform(utf8.decoder).join().timeout(timeout);
    if (body.length > 20000) throw const ProbeError('response too large to be a key');
    final RsaPublicKey key;
    try {
      key = RsaPublicKey.parse(body);
    } on FormatException catch (e) {
      throw ProbeError('not a PEM key (${e.message})');
    }
    return FetchedKey(pem: body.trim(), key: key, url: url, certificate: cert, caTrusted: caTrusted);
  } on SocketException catch (e) {
    throw ProbeError(e.osError?.message ?? e.message);
  } on TimeoutException {
    throw const ProbeError('timed out');
  } finally {
    client.close(force: true);
  }
}

/// Where a server may publish its key, in the order tried: the MTProto port
/// itself (HTTPS, then plain HTTP: NeoMtProto answers HTTP there), then the
/// standard 443/80.
List<Uri> keyUrlCandidates(String host, int port) {
  const path = '/.well-known/mtproto-key.pem';
  final out = <Uri>[
    Uri(scheme: 'https', host: host, port: port, path: path),
    Uri(scheme: 'http', host: host, port: port, path: path),
    Uri(scheme: 'https', host: host, path: path),
    Uri(scheme: 'http', host: host, path: path),
  ];
  return {for (final u in out) u.toString(): u}.values.toList();
}

/// Tries [urls] in turn (HTTPS certificates are all accepted; over HTTP the
/// MTProto fingerprint check vouches for the key). The first key wins.
Future<FetchedKey> fetchServerKeyFrom(List<Uri> urls) async {
  final failures = <String>[];
  for (final url in urls) {
    try {
      return await fetchServerKey(url, timeout: const Duration(seconds: 5));
    } catch (e) {
      failures.add('$url — ${e is ProbeError ? e.message : e}');
    }
  }
  throw ProbeError('Could not fetch the server key:\n${failures.join('\n')}');
}

/// A custom URL first, then the same URL over plain HTTP.
Future<FetchedKey> fetchServerKeyWithFallback(Uri url) => fetchServerKeyFrom([
  url,
  if (url.scheme == 'https')
    url.replace(scheme: 'http', port: url.hasPort && url.port != 443 ? url.port : 80),
]);

class ProbeError implements Exception {
  const ProbeError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// An RSA public key from PEM (PKCS#1 "RSA PUBLIC KEY" or SPKI "PUBLIC KEY"),
/// with the fingerprint MTProto uses to name it.
class RsaPublicKey {
  RsaPublicKey._(this.modulus, this.exponent);

  final Uint8List modulus;
  final Uint8List exponent;

  factory RsaPublicKey.parse(String pem) {
    final lines = pem.trim().split(RegExp(r'\r?\n')).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    if (lines.length < 3 || !lines.first.startsWith('-----BEGIN') || !lines.last.startsWith('-----END')) {
      throw const FormatException('Not a PEM key (-----BEGIN … -----END)');
    }
    final der = base64.decode(lines.sublist(1, lines.length - 1).join());
    final spki = lines.first.contains('BEGIN PUBLIC KEY');
    var r = _Der(der).sequence();
    if (spki) {
      r.sequence(); // algorithm identifier
      final bits = r.bitString();
      r = _Der(bits).sequence();
    }
    final n = r.integer(), e = r.integer();
    return RsaPublicKey._(n, e);
  }

  int get bits => modulus.length * 8 - (modulus.isEmpty ? 0 : _leadingZeros(modulus[0]));

  /// MTProto: the low 64 bits of SHA-1 over the TL-serialized n and e.
  int get fingerprint {
    final tl = BytesBuilder()
      ..add(_tlBytes(modulus))
      ..add(_tlBytes(exponent));
    final h = sha1.convert(tl.toBytes()).bytes;
    return ByteData.sublistView(Uint8List.fromList(h), 12, 20).getInt64(0, Endian.little);
  }

  /// As written in MTProto docs (the unsigned value in hex).
  String get fingerprintHex => fingerprintToHex(fingerprint);

  static String fingerprintToHex(int fp) {
    final b = Uint8List(8)..buffer.asByteData().setInt64(0, fp, Endian.big);
    return [for (final x in b) x.toRadixString(16).padLeft(2, '0')].join();
  }

  /// SHA-256 of the key (n, e), shown for comparing out of band.
  String get sha256Hex {
    final s = sha256.convert([...modulus, ...exponent]).toString();
    return [for (var i = 0; i < s.length; i += 4) s.substring(i, i + 4)].join(' ');
  }

  /// The key re-encoded as PKCS#1 PEM, the form TDLib reads.
  String get pkcs1Pem {
    final der = _derSeq([..._derInt(modulus), ..._derInt(exponent)]);
    final b64 = base64.encode(der);
    final lines = [for (var i = 0; i < b64.length; i += 64) b64.substring(i, min(i + 64, b64.length))];
    return '-----BEGIN RSA PUBLIC KEY-----\n${lines.join('\n')}\n-----END RSA PUBLIC KEY-----\n';
  }

  static int _leadingZeros(int b) {
    var n = 0;
    for (var m = 0x80; m > 0 && b & m == 0; m >>= 1) {
      n++;
    }
    return n;
  }

  static Uint8List _tlBytes(List<int> data) {
    final b = BytesBuilder();
    if (data.length < 254) {
      b.addByte(data.length);
    } else {
      b.add([254, data.length & 0xff, data.length >> 8 & 0xff, data.length >> 16 & 0xff]);
    }
    b.add(data);
    while (b.length % 4 != 0) {
      b.addByte(0);
    }
    return b.toBytes();
  }

  static List<int> _derLen(int n) {
    if (n < 0x80) return [n];
    final out = <int>[];
    for (var v = n; v > 0; v >>= 8) {
      out.insert(0, v & 0xff);
    }
    return [0x80 | out.length, ...out];
  }

  static List<int> _derInt(List<int> v) {
    final body = v.isNotEmpty && v[0] & 0x80 != 0 ? [0, ...v] : v;
    return [0x02, ..._derLen(body.length), ...body];
  }

  static List<int> _derSeq(List<int> body) => [0x30, ..._derLen(body.length), ...body];
}

/// Just enough DER for RSA public keys.
class _Der {
  _Der(this.bytes);
  final Uint8List bytes;
  var _o = 0;

  Uint8List _take(int tag) {
    if (_o >= bytes.length || bytes[_o] != tag) throw const FormatException('Unexpected key structure');
    _o++;
    var len = bytes[_o++];
    if (len & 0x80 != 0) {
      final n = len & 0x7f;
      len = 0;
      for (var i = 0; i < n; i++) {
        len = len << 8 | bytes[_o++];
      }
    }
    final out = Uint8List.sublistView(bytes, _o, _o + len);
    _o += len;
    return out;
  }

  _Der sequence() => _Der(_take(0x30));

  Uint8List integer() {
    var v = _take(0x02);
    while (v.length > 1 && v[0] == 0) {
      v = Uint8List.sublistView(v, 1);
    }
    return v;
  }

  Uint8List bitString() => Uint8List.sublistView(_take(0x03), 1); // skip unused-bits byte
}
