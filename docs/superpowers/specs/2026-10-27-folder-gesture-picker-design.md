# Folder gesture picker — design

Date: 2026-10-27. Status: approved in conversation, spec awaiting review.

## Goal

A new, default way to switch chat folders ("lenses"): hold the folder
name at the top of the chat list, slide a finger along a glowing list of
folders with a live preview of each, release to switch. The current
drop-down panel (`showLensPicker`) stays as the "Classic" style and for
New / Edit folders.

## Decisions (owner)

| Topic | Choice |
|---|---|
| Horizontal movement | The list bends toward the finger (fisheye: scale, glow, lean); far pull = cancel |
| Preview | Mini chat list, unread first, with "N unread in M chats" |
| List position | Tall list on the thumb's edge, fixed slots; edge auto-scroll for long lists |
| Default | Gesture style is the default; Classic selectable |

## Interaction

- Long-press `LensTitle` (~250 ms, light haptic) opens the gesture
  overlay; the same pointer keeps driving it (no lift needed). Tap keeps
  opening `showLensPicker`. With Classic style, long-press does nothing
  extra.
- Edge: right if the press is right of the screen centre, else left.
- Slots: folder names in evenly spaced slots (about 56 dp) in a column on
  that edge, vertically centred on the screen. The slot under the
  finger's y is highlighted. If the list is taller than the safe area,
  holding within 64 dp of the top/bottom auto-scrolls it, speed growing
  toward the edge.
- Horizontal: each name's scale, glow and lean toward the finger fall off
  smoothly with vertical distance from the finger and grow as the finger
  moves toward the list. Pulling more than 40% of the screen width away
  from the list enters the cancel zone: everything dims, no highlight.
- Release on a highlighted folder switches to it (firm haptic); release
  in the cancel zone, or a system cancel, switches nothing.
- Haptic selection tick on each highlight change.

## Visuals

- Backdrop: the chat list blurred once on open, with a radial gradient
  that darkens and blurs more toward the outer edges.
- Highlighted name glows in its lens colour. Unread counts as small
  glowing badges next to names.
- Preview card (glass) on the side opposite the list: "N unread in M
  chats", then the top 5–6 chats, unread first (avatar, name, last
  message line, badge); crossfades on highlight change.
- Reduced motion: no lean/scale animation, straight highlight swaps and
  fades.

## Performance

- Blur captured once on open; finger movement only changes transforms and
  opacities (no rebuild of the chat list).
- Preview chats from the data the chat list already has (`TelegramCache`
  and the lens's chat list), loaded once per folder on first highlight.

## Code

- `lib/features/chats/presentation/widgets/folder_gesture_picker.dart` —
  the overlay, started from `LensTitle`'s long-press.
- `FolderPickerLayout` (pure Dart): slot under the finger, per-item
  fisheye factor, cancel zone, auto-scroll speed, edge choice.
- Pref `chats.folderPicker` (`gesture` default / `classic`) in
  `AppPreferences`; Settings → Chats → "Folder picker".

## Testing

- Unit: `FolderPickerLayout` (slot mapping, falloff, cancel threshold,
  auto-scroll speed, edge choice).
- Widget: long-press then release on a folder switches; release in the
  cancel zone does not; preview lists unread first with the right count;
  Classic keeps tap only; tap still opens the panel.
- Device: feel of the gesture, blur cost on the owner's phone.
