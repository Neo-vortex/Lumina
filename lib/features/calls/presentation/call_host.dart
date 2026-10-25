import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/telegram/display.dart';
import '../../../core/telegram/telegram_cache.dart';
import '../../../core/theme/glow_colors.dart';
import '../bloc/call_cubit.dart';
import 'call_screen.dart';

/// Wraps the app (MaterialApp.builder): opens the call screen when a call
/// starts or rings, and shows a "return to call" pill while it's minimized.
/// With Lumina's calling account the Phone app shows the call instead.
class CallHost extends StatefulWidget {
  const CallHost({super.key, required this.navigatorKey, required this.child});

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<CallHost> createState() => _CallHostState();
}

class _CallHostState extends State<CallHost> {
  Timer? _tick;

  void _open() {
    if (CallScreen.visible.value) return;
    widget.navigatorKey.currentState?.push(CallScreen.route());
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocConsumer<CallCubit, CallState>(
    listenWhen: (a, b) => a.phase != b.phase || a.callId != b.callId,
    listener: (context, state) {
      final starting = state.phase == CallPhase.incoming || state.phase == CallPhase.requesting;
      if (starting && !state.systemUi) _open();
      _tick?.cancel();
      if (state.inCall) _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    },
    builder: (context, state) => ValueListenableBuilder(
      valueListenable: CallScreen.visible,
      builder: (context, screenVisible, child) => Stack(
        children: [
          child!,
          if (state.inCall && !screenVisible)
            Positioned(
              left: 12,
              right: 12,
              top: MediaQuery.paddingOf(context).top + 6,
              child: _ReturnPill(state: state, onTap: _open),
            ),
        ],
      ),
      child: widget.child,
    ),
  );
}

class _ReturnPill extends StatelessWidget {
  const _ReturnPill({required this.state, required this.onTap});
  final CallState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cache = context.read<TelegramCache>();
    final name = Display.userName(cache.users[state.userId]);
    final since = state.connectedAt;
    final detail = since == null
        ? (state.phase == CallPhase.incoming ? 'Incoming call' : 'Calling…')
        : Display.duration(DateTime.now().difference(since).inSeconds);
    return Semantics(
      button: true,
      label: 'Return to call with $name, $detail',
      excludeSemantics: true,
      child: Material(
        color: GlowColors.teal,
        borderRadius: BorderRadius.circular(24),
        elevation: 6,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.call_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
                Text(detail, style: const TextStyle(color: Colors.white)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
