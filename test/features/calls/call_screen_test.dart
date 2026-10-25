import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_tdlib/api.dart' as td;
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/features/calls/bloc/call_cubit.dart';
import 'package:lumina/features/calls/data/call_engine.dart';
import 'package:lumina/features/calls/data/calls_repository.dart';
import 'package:lumina/features/calls/presentation/call_host.dart';

import '../../helpers/fakes.dart';
import 'calls_test.dart' show FakeEngine, call, ready;

void main() {
  late FakeTdClient client;
  late CallCubit cubit;
  late FakeEngine engine;

  // Created inside each test: stream deliveries must run in the test's
  // fake-async zone.
  void setUpCall() {
    client = FakeTdClient()
      ..respond = (f) => switch (f) {
        td.GetOption() => const td.OptionValueInteger(value: 20000),
        td.CreateCall() => const td.CallId(id: 5),
        _ => const td.Ok(),
      };
    engine = FakeEngine();
    cubit = CallCubit(repository: CallsRepository(client), engine: engine, nameOf: (_) => 'Ada');
    addTearDown(cubit.close);
  }

  Future<void> pump(WidgetTester tester) async {
    setUpCall();
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      RepositoryProvider(
        create: (_) => TelegramCache(client),
        child: BlocProvider.value(
          value: cubit,
          child: MaterialApp(
            navigatorKey: key,
            builder: (context, child) => CallHost(navigatorKey: key, child: child!),
            home: const Scaffold(body: Text('chats')),
          ),
        ),
      ),
    );
  }

  Future<void> update(WidgetTester tester, td.Call c) async {
    client.emitUpdate(td.UpdateCall(call: c));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('an incoming call opens the call screen; answering accepts it', (tester) async {
    await pump(tester);
    await update(
      tester,
      call(8, const td.CallStatePending(isCreated: true, isReceived: true), outgoing: false),
    );
    expect(find.text('Incoming call'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Answer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(client.sentOf<td.AcceptCall>(), hasLength(1));
    await update(tester, call(8, ready(), outgoing: false));
    expect(find.text('Connecting…'), findsOneWidget);
    expect(find.textContaining('🐱'), findsOneWidget);
  });

  testWidgets('minimizing shows the return pill, which reopens the screen', (tester) async {
    await pump(tester);
    await update(
      tester,
      call(8, const td.CallStatePending(isCreated: true, isReceived: true), outgoing: false),
    );
    await tester.tap(find.byTooltip('Minimize'));
    await tester.pumpAndSettle();
    expect(find.text('chats'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Return to call')), findsOneWidget);
    await tester.tap(find.bySemanticsLabel(RegExp('Return to call')));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Incoming call'), findsOneWidget);
  });

  testWidgets('remote video fills the screen; our camera shows in a corner; controls appear', (tester) async {
    await pump(tester);
    await cubit.startCall(42, video: true);
    await update(tester, call(5, ready(), video: true));
    engine.emit(const EngineRemoteMedia(muted: false, videoOn: true));
    engine.emit(const EngineVideoSize(remote: true, width: 720, height: 1280));
    engine.emit(const EngineVideoSize(remote: false, width: 480, height: 640));
    await tester.pump();
    await tester.pump();
    expect(find.byType(Texture), findsNWidgets(2));
    expect(find.bySemanticsLabel(RegExp('Your camera')), findsOneWidget);
    expect(find.bySemanticsLabel('Share screen'), findsOneWidget);
    expect(find.bySemanticsLabel('Flip'), findsOneWidget);
  });

  testWidgets('a call that asks for a rating shows stars', (tester) async {
    await pump(tester);
    await update(
      tester,
      call(8, const td.CallStatePending(isCreated: true, isReceived: true), outgoing: false),
    );
    await update(
      tester,
      call(
        8,
        const td.CallStateDiscarded(
          reason: td.CallDiscardReasonHungUp(),
          needRating: true,
          needDebugInformation: false,
          needLog: false,
        ),
        outgoing: false,
      ),
    );
    expect(find.text('How was the call?'), findsOneWidget);
    await tester.tap(find.byTooltip('4 stars'));
    await tester.pump();
    expect(client.sentOf<td.SendCallRating>().single.rating, 4);
  });
}
