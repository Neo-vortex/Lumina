import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/glow_colors.dart';
import 'td_errors.dart';

/// Requests the server answered with "not implemented": a self-hosted
/// server (NeoMtProto) implements only part of Telegram's API. The app
/// shows a small toast for each (see [UnsupportedApiToasts]).
class UnsupportedApi {
  UnsupportedApi._();

  static final _events = StreamController<String>.broadcast();

  /// The TDLib request type (e.g. `getChatAdministrators`) per failure.
  static Stream<String> get events => _events.stream;

  static const _markers = ['METHOD_NOT_IMPLEMENTED', 'INPUT_CONSTRUCTOR_INVALID', 'NOT_IMPLEMENTED'];

  static bool matches(TdException e) => _markers.any(e.message.contains);

  static void report(String request) => _events.add(request);

  /// `getChatAdministrators` → `Get chat administrators`.
  static String readable(String type) {
    final words = type.replaceAllMapped(RegExp('([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}').toLowerCase();
    return words.isEmpty ? type : words[0].toUpperCase() + words.substring(1);
  }
}

/// Shows "Not supported by this server: …" as a small floating toast, once
/// a minute per request type at most.
class UnsupportedApiToasts extends StatefulWidget {
  const UnsupportedApiToasts({super.key, required this.messengerKey, required this.child});

  final GlobalKey<ScaffoldMessengerState> messengerKey;
  final Widget child;

  @override
  State<UnsupportedApiToasts> createState() => _UnsupportedApiToastsState();
}

class _UnsupportedApiToastsState extends State<UnsupportedApiToasts> {
  StreamSubscription<String>? _sub;
  final _shown = <String, DateTime>{};

  @override
  void initState() {
    super.initState();
    _sub = UnsupportedApi.events.listen(_show);
  }

  void _show(String request) {
    final now = DateTime.now();
    final last = _shown[request];
    if (last != null && now.difference(last) < const Duration(minutes: 1)) return;
    _shown[request] = now;
    widget.messengerKey.currentState?.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        backgroundColor: GlowColors.surfaceHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: GlowColors.amber.withValues(alpha: 0.5)),
        ),
        content: Row(
          children: [
            const Icon(Icons.dns_rounded, size: 18, color: GlowColors.amber),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Not supported by this server: ${UnsupportedApi.readable(request)}',
                style: const TextStyle(color: GlowColors.text, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
