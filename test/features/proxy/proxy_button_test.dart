import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/features/proxy/data/proxy_repository.dart';
import 'package:lumina/features/proxy/presentation/widgets/proxy_button.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../helpers/fakes.dart';
import 'call_proxy_test.dart' show proxy;

class _ProxyClient extends FakeTdClient {
  List<td.AddedProxy> proxies = [];

  @override
  Future<T> invoke<T extends td.TdObject>(td.TdFunction function, {Duration? timeout}) async {
    if (function is td.GetProxies) return td.AddedProxies(proxies: proxies) as T;
    return super.invoke(function, timeout: timeout);
  }
}

void main() {
  testWidgets('the shield shows only while connected through a proxy', (tester) async {
    final client = _ProxyClient();
    final repo = ProxyRepository(client: client, prefs: AppPreferences.inMemory(), secure: FakeSecureStore());
    await tester.pumpWidget(
      RepositoryProvider.value(
        value: repo,
        child: const MaterialApp(home: Scaffold(body: ProxyButton())),
      ),
    );
    client.emitUpdate(const td.UpdateAuthorizationState(authorizationState: td.AuthorizationStateReady()));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(find.byType(IconButton), findsNothing);

    client.proxies = [proxy(1, const td.ProxyTypeSocks5(username: '', password: ''))];
    client.emitUpdate(const td.UpdateAuthorizationState(authorizationState: td.AuthorizationStateReady()));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(find.byIcon(Icons.shield_rounded), findsOneWidget);
  });
}
