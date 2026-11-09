import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/custom_server/custom_server.dart';

const _pem = '''-----BEGIN RSA PUBLIC KEY-----
MIIBCgKCAQEA6LszBcC1LGzyr992NzE0ieY+BSaOW622Aa9Bd4ZHLl+TuFQ4lo4g
5nKaMBwK/BIb9xUfg0Q29/2mgIR6Zr9krM7HjuIcCzFvDtr+L0GQjae9H0pRB2OO
62cECs5HKhT5DZ98K33vmWiLowc621dQuwKWSQKjWf50XYFw42h21P2KXUGyp2y/
+aEyZ+uVgLLQbRA1dEjSDZ2iGRy12Mk5gpYc397aYp438fsJoHIgJ2lgMv5h7WY9
t6N/byY9Nw9p21Og3AoXSL2q/2IJ1WRUhebgAdGVMlV1fkuOQoEzR7EdpqtQD9Cs
5+bfo3Nhmcyvk5ftB0WkJ9z6bNZ7yxrP8wIDAQAB
-----END RSA PUBLIC KEY-----''';

void main() {
  final cert = Platform.environment['LUMINA_TEST_TLS_CERT'];
  final key = Platform.environment['LUMINA_TEST_TLS_KEY'];

  test('fetches the key from a self-signed HTTPS server and reports its certificate', () async {
    final ctx = SecurityContext()
      ..useCertificateChain(cert!)
      ..usePrivateKey(key!);
    final server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, ctx);
    server.listen(
      (r) => r.response
        ..write(_pem)
        ..close(),
    );
    try {
      final got = await fetchServerKey(
        Uri.parse('https://127.0.0.1:${server.port}/.well-known/mtproto-key.pem'),
      );
      expect(got.key.fingerprintHex, 'd09d1d85de64fd85');
      expect(got.caTrusted, isFalse);
      expect(got.certificate?.subject, contains('lumina-test'));
      expect(got.certificate?.fingerprint, matches(RegExp(r'^([0-9A-F]{2}:){31}[0-9A-F]{2}$')));
    } finally {
      await server.close(force: true);
    }
  }, skip: cert == null ? 'set LUMINA_TEST_TLS_CERT/KEY' : false);

  test('a non-key response is an error', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(
      (r) => r.response
        ..write('<html>nope</html>')
        ..close(),
    );
    try {
      await expectLater(
        fetchServerKey(Uri.parse('http://127.0.0.1:${server.port}/k.pem')),
        throwsA(isA<ProbeError>()),
      );
    } finally {
      await server.close(force: true);
    }
  });

  test('falls back to plain HTTP when HTTPS fails', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(
      (r) => r.response
        ..write(_pem)
        ..close(),
    );
    try {
      // HTTPS against a plain-HTTP port fails the handshake; HTTP then works.
      final got = await fetchServerKeyWithFallback(Uri.parse('https://127.0.0.1:${server.port}/k.pem'));
      expect(got.url.scheme, 'http');
      expect(got.certificate, isNull);
      expect(got.key.fingerprintHex, 'd09d1d85de64fd85');
    } finally {
      await server.close(force: true);
    }
  });
}
