import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/custom_server/custom_server.dart';

// Telegram's production key, as bundled in TDLib; its MTProto fingerprint is
// documented as 0xd09d1d85de64fd85.
const _telegram = '''-----BEGIN RSA PUBLIC KEY-----
MIIBCgKCAQEA6LszBcC1LGzyr992NzE0ieY+BSaOW622Aa9Bd4ZHLl+TuFQ4lo4g
5nKaMBwK/BIb9xUfg0Q29/2mgIR6Zr9krM7HjuIcCzFvDtr+L0GQjae9H0pRB2OO
62cECs5HKhT5DZ98K33vmWiLowc621dQuwKWSQKjWf50XYFw42h21P2KXUGyp2y/
+aEyZ+uVgLLQbRA1dEjSDZ2iGRy12Mk5gpYc397aYp438fsJoHIgJ2lgMv5h7WY9
t6N/byY9Nw9p21Og3AoXSL2q/2IJ1WRUhebgAdGVMlV1fkuOQoEzR7EdpqtQD9Cs
5+bfo3Nhmcyvk5ftB0WkJ9z6bNZ7yxrP8wIDAQAB
-----END RSA PUBLIC KEY-----''';

void main() {
  test('MTProto fingerprint of Telegram\'s key', () {
    final key = RsaPublicKey.parse(_telegram);
    expect(key.fingerprintHex, 'd09d1d85de64fd85');
    expect(key.bits, 2048);
  });

  test('re-encoded PKCS#1 PEM round-trips', () {
    final key = RsaPublicKey.parse(_telegram);
    expect(RsaPublicKey.parse(key.pkcs1Pem).fingerprint, key.fingerprint);
    expect(key.pkcs1Pem.replaceAll('\n', ''), _telegram.replaceAll('\n', ''));
  });

  test('rejects text that is not a PEM key', () {
    expect(() => RsaPublicKey.parse('hello'), throwsFormatException);
  });
}
