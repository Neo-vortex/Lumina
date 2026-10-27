import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/features/proxy/data/proxy_config.dart';
import 'package:lumina/features/proxy/data/proxy_repository.dart';
import 'package:lumina/features/proxy/presentation/widgets/proxy_link_dialog.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../helpers/fakes.dart';
import 'call_proxy_test.dart' show proxy;

void main() {
  Future<FakeTdClient> open(WidgetTester tester, {bool reachable = true}) async {
    final client = FakeTdClient()
      ..respond = (f) => switch (f) {
        td.TestProxy() => reachable ? const td.Ok() : const td.TdError(code: 400, message: 'timeout'),
        td.AddProxy() => proxy(5, const td.ProxyTypeSocks5(username: '', password: '')),
        _ => const td.Ok(),
      };
    final repo = ProxyRepository(client: client, prefs: AppPreferences.inMemory(), secure: FakeSecureStore());
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepositoryProvider.value(
        value: repo,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => confirmProxyLink(
                  context,
                  const ProxyConfig(
                    server: 'proxy.example',
                    port: 443,
                    kind: ProxyKind.mtproto,
                    secret: 'ee00',
                  ),
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    return client;
  }

  testWidgets('the proxy sheet shows details and checks status by itself', (tester) async {
    final client = await open(tester);
    expect(find.text('proxy.example:443'), findsOneWidget);
    expect(find.text('MTProto'), findsOneWidget);
    expect(client.sentOf<td.TestProxy>(), hasLength(1));
    expect(find.textContaining('Online'), findsOneWidget);
    await tester.tap(find.text('Connect'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(client.sentOf<td.AddProxy>().single.enable, isTrue);
  });

  testWidgets('an unreachable proxy says so; it can still be saved without connecting', (tester) async {
    final client = await open(tester, reachable: false);
    expect(find.textContaining('Unreachable'), findsOneWidget);
    await tester.tap(find.text('Save only'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(client.sentOf<td.AddProxy>().single.enable, isFalse);
  });
}
