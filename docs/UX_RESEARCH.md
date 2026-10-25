# UI / UX Behaviour Research

Research pass done before the bloc migration (2026-10-25). Each finding is
turned into a concrete requirement (`UX-xx`) with the phase it lands in.
Sources are listed at the end; vendor blogs are treated as practice, not
standards. Where a claim was checkable locally (Flutter SDK source, contrast
maths) it was verified rather than taken from the source.

## 1. Accessibility & contrast (verified against our palette)

Contrast ratios computed with the WCAG 2.x relative-luminance formula:

| Pair | Ratio | WCAG AA (4.5 text / 3.0 UI) |
|---|---|---|
| text `#E6EAF0` on surface `#14171C` | 14.9 | pass |
| muted `#8B95A4` on surface | 5.9 | pass |
| error `#FF7A8A` on surface | 7.2 | pass |
| **white on violet `#9A5CFF`** | **3.9** | **fail** (button label) |
| **white on magenta `#E052D6`** | **3.3** | **fail** |
| **white on amber `#FFB850`** | **1.7** | **fail** (outgoing bubble) |
| **white on coral `#FF6E66`** | **2.7** | **fail** |
| near-black on amber | 11.6 | pass |
| near-black on teal `#1C9AAE` | 6.0 | pass |
| **outline `#262B33` vs surface** | **1.3** | **fail** (input boundary, WCAG 1.4.11) |

- **UX-01** Text on warm/cool accent gradients (outgoing amber→coral, incoming
  cyan→teal) is near-black, never white. *(phase 3 bubbles; applied now to
  the "Log out" / "Reset" buttons)*
- **UX-02** Violet→magenta used under white text is darkened to
  `#7440E0 → #A83599` (5.9 / 5.8 : 1). The bright `#9A5CFF / #E052D6` stay for
  glows and non-text accents only. *(applied)*
- **UX-03** Input fields get a boundary of at least 3 : 1 against the surface
  (`#5E6878`, 3.2 : 1); the glow is extra, not the only focus cue. *(applied)*
- **UX-04** Glow is decoration: never behind body text (halation is tiring,
  especially with astigmatism), never the only state signal. Read receipts as
  an "edge-glow colour shift" (spec §9.3) therefore also need a non-colour cue
  (shape/icon change) and a TalkBack label. *(phase 3)*
- **UX-05** Avoid pure black backgrounds; base is `#0D0F12` (upper end of
  the spec's range) to reduce halation. *(applied)*
- **UX-06** Touch targets ≥ 48 dp, including the send orb, timeline nodes and
  media-cluster tiles; small visuals get padding, not a smaller hit area.
  *(all phases)*
- **UX-07** Every interactive custom widget gets a purpose-describing
  semantics label ("Send message", not "orb"); decorative layers (background
  orbs, particles, glows) are excluded from semantics. *(applied for current
  widgets)*
- **UX-08** A chat message is one merged semantics node: sender, text,
  time, state ("read"). New incoming messages are announced politely.
  *(phase 3)*

## 2. Motion

- Flutter ships the M3 tokens as `Durations` (short1 50 ms … extralong4
  1000 ms) and `Easing` (`emphasizedDecelerate = Cubic(0.05, 0.7, 0.1, 1)`, …).
  Verified in the 3.47 SDK source.
- **UX-09** All durations/curves come from `core/theme/motion.dart`, which maps
  onto the M3 tokens. No ad-hoc millisecond literals in widgets. *(applied)*
- **UX-10** `MediaQuery.disableAnimations` (Android "Remove animations") turns
  ambient motion off: background drift, button breathing, particle trails,
  pulse effects. Transitions collapse to fades. *(applied for current
  widgets)*
- **UX-11** Ambient animation is slow and low-amplitude ("relaxation"):
  ≥ 2 s cycles, opacity/scale changes ≤ 10 %. It never competes with content
  changes, which use the faster M3 tokens.

## 3. Android platform behaviour

- Targeting SDK 35+ makes the app edge-to-edge, and Android 16 removes the
  opt-out. Content must pad for system bars and the IME itself.
- Flutter's default Android page transition is already
  `PredictiveBackPageTransitionsBuilder` (verified in SDK source). The system
  animation also needs `android:enableOnBackInvokedCallback="true"`.
  Cancelling a back gesture at the moment it happens is deprecated. Apps
  declare up front with `PopScope(canPop:)`.
- **UX-12** All screens use `SafeArea` / inset padding. The chat composer is
  pinned above `MediaQuery.viewInsets.bottom` and the nav bar inset. A
  transparent nav bar still eats touches, so nothing tappable sits under it.
  *(applied for auth; phase 3 composer)*
- **UX-13** Manifest opts in to predictive back. *(applied)*
- **UX-14** Back steps backwards through the auth flow instead of closing the
  app: code / password / email screens go back to phone entry via `PopScope`.
  *(applied)*

## 4. Login & OTP

- **UX-15** One OTP field (not one box per digit), so paste and autofill
  work. Use the `oneTimeCode` autofill hint, numeric keyboard, and no masking.
  *(applied)*
- **UX-16** Auto-submit when the code reaches the length TDLib reports; keep
  the manual button. *(applied)*
- **UX-17** Clear the code field after a wrong code, and keep focus in it.
  *(applied)*
- **UX-18** The resend countdown comes from TDLib's `codeInfo.timeout`, since
  the server is the source of truth. The resend label says which channel comes
  next (SMS / call / …). *(applied)*
- **UX-19** Errors and countdowns are announced to TalkBack
  (`Semantics(liveRegion: true)`), not only drawn in red. *(applied)*
- **UX-20** `allowSmsRetrieverApi` / Firebase settings are documented by TDLib
  as **official apps only**. They are not set, so SMS codes are typed or
  autofilled from the keyboard suggestion. *(decision, documented)*
- **UX-21** Flood-wait disables submit with a visible, announced countdown
  (spec §4.2). *(applied)*

## 5. Conversation behaviour (phase 3+ requirements)

- **UX-22** Bubbles: sender is distinguishable by alignment *and* colour
  family (spec gradients). In groups, the sender name/avatar sits on the first
  bubble of a run, and names are tinted, not whole bubbles.
- **UX-23** Grouping: consecutive messages from one sender within ~60 s form a
  run. Only the last bubble of a run shows the time and the asymmetric "tail"
  radius. Sticky date headers use "Today" / "Yesterday" / a date, in local
  time.
- **UX-24** Optimistic send: the bubble appears immediately (TDLib's
  `messageSendingStatePending`), then shows sent / failed. A failure offers
  Retry and Delete, never a silent drop.
- **UX-25** Opening a chat lands on the first unread message (TDLib
  `last_read_inbox_message_id`, then the next one) with an "Unread messages"
  divider. With no unreads it lands at the bottom.
- **UX-26** A scroll-to-bottom button appears only after the user scrolls up,
  with an unread counter. Tapping it jumps to the newest message, not just to
  an offset.
- **UX-27** New messages auto-scroll only when the user is already at the
  bottom; otherwise the button counter increases.
- **UX-28** Swipe-to-reply on a bubble (spec "swipe-to-send" glow scales
  with drag) has a threshold with a haptic tick and an accessible alternative
  in the long-press menu.
- **UX-29** Long-press opens a context menu (reply, forward, copy, edit,
  pin, delete for me / everyone, react) with `Feedback.forLongPress`.

## 6. Voice recording (phase 5)

- **UX-30** Hold the send orb (when empty, mic) to record. Slide left to
  cancel, slide up to lock. The thresholds are separate and tunable. Holding
  under ~300 ms is treated as an accidental tap: show a hint, don't send.
- **UX-31** While recording: elapsed time, live waveform, cancel affordance.
  When locked: stop, play back, discard, send. The orb morphs to stop
  (spec §9.3).
- **UX-32** Waveform in a sent voice message uses a fixed bar count
  (consistent bubble width), with height from segment average power. TDLib
  supplies `voiceNote.waveform`.

## 7. Haptics

- **UX-33** Haptics follow platform helpers: `Feedback.forLongPress` on
  long-press, a light impact on send, selection clicks on threshold crossings
  (swipe-to-reply, record lock/cancel). No haptics on passive events.

## Gaps (searched, not found)

- No sources tested glow/neon effects for readability specifically. UX-04
  is inferred from the halation guidance.
- No authoritative chat-specific TalkBack patterns were found. UX-08 follows
  the general merge-semantics guidance and needs a TalkBack pass on device.

## Sources

- [CometChat – chat app design best practices](https://www.cometchat.com/blog/chat-app-design-best-practices)
- [UXPin – Chat UI design 2026](https://www.uxpin.com/studio/?p=44235)
- [Uxcel – chat & messaging best practices](https://uxcel.com/lessons/chat--messaging-best-practices-001)
- [SaaSUI – chat messaging UX patterns](https://www.saasui.design/blog/saas-chat-messaging-ux-patterns)
- [UX Design Institute – designing for dark mode](https://www.uxdesigninstitute.com/blog/dark-mode/)
- [Uxcel – 12 principles of dark mode design](https://uxcel.com/blog/12-principles-of-dark-mode-design-627)
- [accessibilitychecker.org – dark mode accessibility](https://www.accessibilitychecker.org/blog/dark-mode-accessibility/)
- [Flutter – default SystemUiMode edge-to-edge](https://docs.flutter.dev/release/breaking-changes/default-systemuimode-edge-to-edge)
- [Fix: Flutter UI overlaps nav bar after targeting SDK 35](https://startdebugging.net/2026/08/fix-flutter-ui-overlaps-the-android-navigation-bar-after-targeting-sdk-35/)
- [ProAndroidDev – Android 16 edge-to-edge mandate](https://proandroiddev.com/android-16s-edge-to-edge-mandate-why-your-simple-fix-will-break-at-scale-7c1e7bcdb22b)
- [Flutter – predictive back](https://docs.flutter.dev/platform-integration/android/predictive-back)
- [Flutter – Android predictive back breaking change](https://docs.flutter.dev/release/breaking-changes/android-predictive-back)
- [Flutter API – Easing](https://api.flutter.dev/flutter/material/Easing-class.html)
- [Flutter API – MediaQueryData.disableAnimations](https://api.flutter.dev/flutter/widgets/MediaQueryData/disableAnimations.html)
- [Twilio – OTP input best practices (Android)](https://www.twilio.com/en-us/blog/developers/best-practices/best-practices-for-otp-input-forms-in-android)
- [Twilio – OTP input forms (HTML)](https://www.twilio.com/en-us/blog/developers/best-practices/otp-input-forms-html)
- [Visa Design – one-time passcode pattern](https://design.visa.com/patterns/one-time-passcode/)
- [TDLib – phoneNumberAuthenticationSettings](https://core.telegram.org/tdlib/docs/classtd_1_1td__api_1_1phone_number_authentication_settings.html)
- [Stream – Flutter voice recording](https://getstream.io/chat/docs/sdk/flutter/stream-chat-flutter/stream-voice-recording/)
- [9to5Google – Google Messages voice redesign](https://9to5google.com/2023/10/27/google-voice-messages-redesign/)
- [Stream – ScrollToBottomButton](https://getstream.io/chat/docs/sdk/react-native/ui-components/scroll-to-bottom-button/)
- [LivePerson – scroll behaviour configuration](https://developers.liveperson.com/mobile-app-messaging-sdk-for-ios-advanced-features-scroll-behavior-configuration.html)
- [Android Developers – make apps more accessible](https://developer.android.com/guide/topics/ui/accessibility/apps)
- [Android codelab – accessibility in Compose (48 dp targets)](https://developer.android.com/codelabs/jetpack-compose-accessibility)
- [Flutter API – Feedback.forLongPress](https://api.flutter.dev/flutter/widgets/Feedback/forLongPress.html)
