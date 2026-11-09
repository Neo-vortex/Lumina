import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/call_cubit.dart';

/// Voice and video call buttons for a private chat's header.
class CallButtons extends StatelessWidget {
  const CallButtons({super.key, required this.userId, this.video = true});
  final int userId;

  /// Also show the video call button (off when it lives in the ⋮ menu).
  final bool video;

  /// Starts a call, showing why when it can't.
  static Future<void> call(BuildContext context, int userId, {required bool video}) async {
    final messenger = ScaffoldMessenger.of(context);
    final error = await context.read<CallCubit>().startCall(userId, video: video);
    if (error != null) messenger.showSnackBar(SnackBar(content: Text(error)));
  }

  Future<void> _call(BuildContext context, {required bool video}) async {
    final messenger = ScaffoldMessenger.of(context);
    final error = await context.read<CallCubit>().startCall(userId, video: video);
    if (error != null) messenger.showSnackBar(SnackBar(content: Text(error)));
  }

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        tooltip: 'Voice call',
        icon: const Icon(Icons.call_rounded),
        onPressed: () => _call(context, video: false),
      ),
      if (video)
        IconButton(
          tooltip: 'Video call',
          icon: const Icon(Icons.videocam_rounded),
          onPressed: () => _call(context, video: true),
        ),
    ],
  );
}
