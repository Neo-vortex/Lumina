import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/custom_server/custom_server.dart';

/// Against a running NeoMtProto: LUMINA_LIVE_SERVER=host:port.
void main() {
  final live = Platform.environment['LUMINA_LIVE_SERVER'];
  test('probe + key fetch agree on a live server', () async {
    final i = live!.lastIndexOf(':');
    final host = live.substring(0, i), port = int.parse(live.substring(i + 1));
    final offered = await CustomServer.probe(host, port);
    final fetched = await fetchServerKeyFrom(keyUrlCandidates(host, port));
    // ignore: avoid_print
    print(
      'offered ${offered.map(RsaPublicKey.fingerprintToHex)}; fetched ${fetched.key.fingerprintHex} from ${fetched.url}',
    );
    expect(offered, contains(fetched.key.fingerprint));
  }, skip: live == null ? 'set LUMINA_LIVE_SERVER' : false);
}
