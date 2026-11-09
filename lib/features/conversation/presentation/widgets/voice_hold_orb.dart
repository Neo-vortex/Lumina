import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/glow_colors.dart';
import 'send_orb.dart';

enum _Hold { idle, holding, locked, unlocked }

/// The mic orb's voice-message gestures, Telegram-style:
///
/// * hold to record; let go to send; slide left to cancel;
/// * slide up onto the lock to keep recording hands-free (a quick tap on the
///   mic starts that way too); the orb becomes Send;
/// * tap the closed lock to unlock: the next press on the mic is a hold
///   again (let go sends, slide up locks, slide left cancels).
class VoiceHoldOrb extends StatefulWidget {
  const VoiceHoldOrb({
    super.key,
    required this.recording,
    required this.onStart,
    required this.onFinish,
    this.size = 52,
  });

  /// A voice message is being recorded (the recorder's state).
  final bool recording;
  final VoidCallback onStart;

  /// Sends the recording, or throws it away.
  final void Function({required bool send}) onFinish;
  final double size;

  @override
  State<VoiceHoldOrb> createState() => _VoiceHoldOrbState();
}

class _VoiceHoldOrbState extends State<VoiceHoldOrb> {
  static const _holdDelay = Duration(milliseconds: 200);
  static const _lockDistance = 80.0;
  static const _cancelDistance = 120.0;

  final _link = LayerLink();
  final _portal = OverlayPortalController();
  var _state = _Hold.idle;
  Timer? _holdTimer;
  Offset _origin = Offset.zero;
  var _lift = 0.0, _pull = 0.0;
  var _tapToSend = false;

  @override
  void didUpdateWidget(VoiceHoldOrb old) {
    super.didUpdateWidget(old);
    // Ended elsewhere (the bar's delete button, an error): start over.
    if (old.recording && !widget.recording && _state != _Hold.idle && _state != _Hold.holding) _reset();
    _syncPortal();
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  void _syncPortal() {
    final show = _state != _Hold.idle;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (show && !_portal.isShowing) _portal.show();
      if (!show && _portal.isShowing) _portal.hide();
    });
  }

  void _set(_Hold s) {
    setState(() {
      _state = s;
      if (s != _Hold.holding) _lift = _pull = 0;
    });
    _syncPortal();
  }

  void _reset() {
    _holdTimer?.cancel();
    _holdTimer = null;
    _tapToSend = false;
    _set(_Hold.idle);
  }

  void _down(PointerDownEvent e) {
    _origin = e.position;
    switch (_state) {
      case _Hold.idle:
        if (widget.recording) {
          // Recording we don't track (e.g. after a rebuild): a tap sends.
          _tapToSend = true;
          return;
        }
        _holdTimer = Timer(_holdDelay, () {
          _holdTimer = null;
          HapticFeedback.mediumImpact();
          widget.onStart();
          _set(_Hold.holding);
        });
      case _Hold.locked:
        _tapToSend = true;
      case _Hold.unlocked:
        HapticFeedback.selectionClick();
        _set(_Hold.holding);
      case _Hold.holding:
        break;
    }
  }

  void _move(PointerMoveEvent e) {
    if (_state != _Hold.holding) return;
    final d = e.position - _origin;
    setState(() {
      _lift = (-d.dy / _lockDistance).clamp(0.0, 1.0);
      _pull = (-d.dx / _cancelDistance).clamp(0.0, 1.0);
    });
    if (_lift >= 1) {
      HapticFeedback.heavyImpact();
      _set(_Hold.locked);
    } else if (_pull >= 1) {
      HapticFeedback.heavyImpact();
      widget.onFinish(send: false);
      _reset();
    }
  }

  void _up(PointerUpEvent e) {
    if (_holdTimer != null) {
      // A quick tap: record hands-free.
      _holdTimer!.cancel();
      _holdTimer = null;
      HapticFeedback.lightImpact();
      widget.onStart();
      _set(_Hold.locked);
      return;
    }
    if (_state == _Hold.holding || _tapToSend) {
      HapticFeedback.lightImpact();
      widget.onFinish(send: true);
      _reset();
    }
  }

  void _cancel(PointerCancelEvent e) {
    _holdTimer?.cancel();
    _holdTimer = null;
    // Something took the touch: keep the recording rather than lose it.
    if (_state == _Hold.holding) _set(_Hold.locked);
    _tapToSend = false;
  }

  void _toggleLock() {
    HapticFeedback.selectionClick();
    _set(_state == _Hold.locked ? _Hold.unlocked : _Hold.locked);
  }

  @override
  Widget build(BuildContext context) {
    final mode = switch (_state) {
      _Hold.idle => widget.recording ? OrbMode.send : OrbMode.mic,
      _Hold.holding => OrbMode.stop,
      _Hold.locked || _Hold.unlocked => OrbMode.send,
    };
    final label = switch (_state) {
      _Hold.idle => 'Record voice message. Hold to talk, or tap to record hands-free',
      _Hold.holding => 'Recording. Release to send, slide up to lock, slide left to cancel',
      _Hold.locked => 'Send voice message',
      _Hold.unlocked => 'Hold to keep talking, release to send',
    };
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: CompositedTransformTarget(
        link: _link,
        child: OverlayPortal(
          controller: _portal,
          overlayChildBuilder: _overlay,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _down,
            onPointerMove: _move,
            onPointerUp: _up,
            onPointerCancel: _cancel,
            child: IgnorePointer(
              child: AnimatedScale(
                scale: _state == _Hold.holding ? 1.25 : 1,
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutBack,
                child: SendOrb(mode: mode, charge: 0, onTap: () {}, size: widget.size),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _overlay(BuildContext context) {
    final locked = _state == _Hold.locked;
    final holding = _state == _Hold.holding;
    return Stack(
      children: [
        // The lock: rises with the finger; tap it to lock or unlock.
        CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.topCenter,
          followerAnchor: Alignment.bottomCenter,
          offset: Offset(0, -12 - 28 * _lift),
          child: Semantics(
            button: true,
            label: locked ? 'Recording locked. Tap to unlock' : 'Tap to lock the recording',
            excludeSemantics: true,
            child: GestureDetector(
              onTap: holding ? null : _toggleLock,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 44,
                height: holding ? 92 : 48,
                decoration: BoxDecoration(
                  color: GlowColors.surfaceHigh.withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: locked ? GlowColors.violet : Color.lerp(GlowColors.outlineStrong, GlowColors.violet, _lift)!,
                  ),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 12)],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      locked ? Icons.lock_rounded : Icons.lock_open_rounded,
                      size: 20,
                      color: locked || _lift > 0.6 ? GlowColors.violet : GlowColors.text,
                    ),
                    if (holding) ...[
                      const SizedBox(height: 10),
                      Opacity(
                        opacity: 1 - _lift,
                        child: const Icon(Icons.keyboard_arrow_up_rounded, size: 22, color: GlowColors.textMuted),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        // What the finger can do now, beside the orb.
        if (holding || _state == _Hold.unlocked)
          CompositedTransformFollower(
            link: _link,
            targetAnchor: Alignment.centerLeft,
            followerAnchor: Alignment.centerRight,
            offset: Offset(-10 - 40 * _pull, 0),
            child: IgnorePointer(
              child: Opacity(
                opacity: holding ? (1 - _pull).clamp(0.0, 1.0) : 1,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: GlowColors.surfaceHigh.withValues(alpha: 0.96),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    holding ? '‹  Slide to cancel' : 'Hold the mic to talk',
                    style: const TextStyle(color: GlowColors.textMuted, fontSize: 13),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
