part of 'call_cubit.dart';

enum CallPhase {
  idle,

  /// createCall sent, no call id yet.
  requesting,

  /// Outgoing, waiting for the other side ([CallState.ringing] once it rings).
  outgoing,

  /// Incoming, ringing here.
  incoming,

  /// Keys exchanged / engine connecting.
  connecting,
  active,
  reconnecting,
  ending,

  /// Over; shown until dismissed (and rated, if TDLib asks).
  ended,
}

class CallState {
  const CallState({
    this.phase = CallPhase.idle,
    this.callId,
    this.userId,
    this.outgoing = false,
    this.video = false,
    this.ringing = false,
    this.emojis = const [],
    this.connectedAt,
    this.muted = false,
    this.speaker = false,
    this.held = false,
    this.signalBars,
    this.remoteMuted = false,
    this.remoteVideo = false,
    this.endReason,
    this.needRating = false,
    this.error,
  });

  final CallPhase phase;
  final int? callId;
  final int? userId;
  final bool outgoing;
  final bool video;

  /// Outgoing call reached the other device.
  final bool ringing;

  /// Key verification emojis, compared out loud.
  final List<String> emojis;
  final DateTime? connectedAt;
  final bool muted;
  final bool speaker;

  /// On hold for another (e.g. cellular) call.
  final bool held;
  final int? signalBars;
  final bool remoteMuted;
  final bool remoteVideo;
  final td.CallDiscardReason? endReason;
  final bool needRating;
  final String? error;

  bool get inCall => phase != CallPhase.idle && phase != CallPhase.ended;

  CallState copyWith({
    CallPhase? phase,
    int? callId,
    int? userId,
    bool? outgoing,
    bool? video,
    bool? ringing,
    List<String>? emojis,
    DateTime? connectedAt,
    bool? muted,
    bool? speaker,
    bool? held,
    int? signalBars,
    bool? remoteMuted,
    bool? remoteVideo,
    td.CallDiscardReason? endReason,
    bool? needRating,
    String? error,
  }) => CallState(
    phase: phase ?? this.phase,
    callId: callId ?? this.callId,
    userId: userId ?? this.userId,
    outgoing: outgoing ?? this.outgoing,
    video: video ?? this.video,
    ringing: ringing ?? this.ringing,
    emojis: emojis ?? this.emojis,
    connectedAt: connectedAt ?? this.connectedAt,
    muted: muted ?? this.muted,
    speaker: speaker ?? this.speaker,
    held: held ?? this.held,
    signalBars: signalBars ?? this.signalBars,
    remoteMuted: remoteMuted ?? this.remoteMuted,
    remoteVideo: remoteVideo ?? this.remoteVideo,
    endReason: endReason ?? this.endReason,
    needRating: needRating ?? this.needRating,
    error: error ?? this.error,
  );
}
