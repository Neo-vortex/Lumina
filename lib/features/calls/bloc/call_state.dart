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
    this.systemUi = false,
    this.camera = false,
    this.frontCamera = true,
    this.screenSharing = false,
    this.screenWithCamera = false,
    this.pipCorner = PipCorner.bottomRight,
    this.textures,
    this.remoteSize,
    this.localSize,
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

  /// The Phone app's in-call screen shows this call (calling account), so
  /// Lumina doesn't open its own.
  final bool systemUi;

  /// Our camera is sending (not while the screen is shared).
  final bool camera;
  final bool frontCamera;
  final bool screenSharing;

  /// The shared screen carries the camera bubble.
  final bool screenWithCamera;
  final PipCorner pipCorner;

  /// Flutter textures of the remote video and our preview.
  final ({int remote, int local})? textures;
  final ({int width, int height})? remoteSize;
  final ({int width, int height})? localSize;
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
    bool? systemUi,
    bool? camera,
    bool? frontCamera,
    bool? screenSharing,
    bool? screenWithCamera,
    PipCorner? pipCorner,
    ({int remote, int local})? textures,
    ({int width, int height})? remoteSize,
    ({int width, int height})? localSize,
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
    systemUi: systemUi ?? this.systemUi,
    camera: camera ?? this.camera,
    frontCamera: frontCamera ?? this.frontCamera,
    screenSharing: screenSharing ?? this.screenSharing,
    screenWithCamera: screenWithCamera ?? this.screenWithCamera,
    pipCorner: pipCorner ?? this.pipCorner,
    textures: textures ?? this.textures,
    remoteSize: remoteSize ?? this.remoteSize,
    localSize: localSize ?? this.localSize,
    signalBars: signalBars ?? this.signalBars,
    remoteMuted: remoteMuted ?? this.remoteMuted,
    remoteVideo: remoteVideo ?? this.remoteVideo,
    endReason: endReason ?? this.endReason,
    needRating: needRating ?? this.needRating,
    error: error ?? this.error,
  );
}
