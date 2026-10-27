# Download manager — design

Date: 2026-10-27. Status: approved in conversation, spec awaiting review.

## Goal

One place for every large download: see progress, pause/resume each or
all, reorder (priority), filter and search, Wi-Fi-only downloads, and
progress/completion notifications while Lumina runs in the background.

## Decisions (owner)

| Topic | Choice |
|---|---|
| Entry point | Glowing ring in the chat list header (only while active/paused) + Settings → Data & storage → Downloads |
| Scope | Full: baseline + reorder, filters, search + Wi-Fi only + notifications |
| What's listed | Every download over 1 MB, whatever started it |

## TDLib

TDLib keeps the download list itself: `addFileToDownloads(fileId,
chatId, messageId, priority)`, `toggleDownloadIsPaused`,
`toggleAllDownloadsArePaused`, `removeFileFromDownloads(fileId,
deleteFromCache)`, `removeAllFilesFromDownloads`, `searchFileDownloads(
query, onlyActive, onlyCompleted, offset, limit)`; updates
`updateFileAddedToDownloads`, `updateFileDownload`,
`updateFileRemovedFromDownloads`, `updateFileDownloads(totalSize,
totalCount, downloadedSize)`. Lumina mirrors it; it does not keep its own
copy of the list beyond per-file Wi-Fi-only flags.

## Architecture

New feature `lib/features/downloads/`:

- `data/downloads_repository.dart` — the TDLib calls above.
- `bloc/downloads_cubit.dart` — app-wide (non-lazy): mirrors the list
  from `searchFileDownloads` + the updates (active vs completed, totals,
  speed from size deltas over time), filter + query, reorder.
- `data/download_policy.dart` — Wi-Fi only: per-file flags (prefs) and
  the default for new downloads; pauses flagged downloads on mobile /
  roaming and resumes them on Wi-Fi (via `AutoDownloadService` network
  changes).
- Presentation: `DownloadsRing` (header), `DownloadsScreen`, row, glow
  sheets (remove + delete file, row actions).
- Notifications: native `dev.lumina/downloads` channel —
  one ongoing progress notification (Pause all action) and one per
  completed file (tap opens it); posted only while downloads run.

Hook-in, through `lib/app/` only:
- A core `DownloadRegistry` interface (`lib/core/telegram/`) with
  `track(td.File file, td.Message message)`. `FileStore.download` callers
  that know the message (`AutoFetch`, `TransferRing` on message content,
  `DocumentContent`, media viewer save, voice/music/video players) call it;
  it adds files over 1 MB (size or expected size) to TDLib's downloads with
  the message. Calls for files ≤ 1 MB or already listed are no-ops.
- `ChatListExtensions.headerActions` gets the ring.
- Settings entry under Data & storage (with the Wi-Fi-only default).

## Behaviour

### Ring
- Visible while any download is active or paused; fill = downloaded /
  total of active ones; paused-only → dimmed ring with a pause glyph.
- Tap opens `DownloadsScreen`. Semantics: "Downloads, N active, X%".

### Screen
- Header: "N downloading · X left", total speed, Pause all / Resume all,
  search field (file name), filter chips All / Videos / Files / Music /
  Photos (by file's message content type).
- Active section: reorderable; order → priority (top = 32, decreasing,
  floor 1), applied with `addFileToDownloads` re-prioritisation (or
  `downloadFile` priority) for each moved file.
- Row: thumbnail or type icon, name, chat title, size and progress,
  speed, pause/resume button; "Waiting for Wi-Fi" state; Wi-Fi badge.
- Completed section: newest first; tap opens the file (system viewer);
  tapping the chat name opens the chat at the message.
- Swipe left → remove from list; glow sheet offers "Also delete the
  file" (`deleteFromCache`). Long-press → glow sheet: Wi-Fi only toggle,
  Move to top, Open chat, Copy link (message link, when available).
- Empty states: "No downloads yet" with a short hint.

### Wi-Fi only
- Per-file flag and a default for new downloads (Settings → Data &
  storage → Downloads → "New downloads: Any network / Wi-Fi only").
- On mobile/roaming, flagged active downloads are paused by Lumina and
  shown as "Waiting for Wi-Fi" (distinct from user-paused); on Wi-Fi they
  resume. User pause always wins (a user-paused file is not resumed).

### Notifications
- While ≥ 1 download is active: one low-importance ongoing notification
  "Downloading N files · X%" with Pause all; removed when none are active.
- Each completion: "Downloaded: name" (tap opens the file). Not posted
  while the Downloads screen is in front.
- Background: downloads continue while the process lives (the existing
  `connected` background mode keeps it alive).

## Errors

- TDLib errors on toggle/remove/search: toast; the list re-syncs from
  `searchFileDownloads`.
- A file whose message was deleted: row stays, chat link disabled.
- Low storage / failed download (`updateFile` with download stopped and
  not completed): row shows "Failed" with Retry.

## Testing

- Repository: requests built correctly (`FakeTdClient`).
- Cubit: initial load, updates (add, progress, complete, remove), totals
  and speed, filters and search, reorder → priorities.
- Registry: > 1 MB tracked with message, ≤ 1 MB and duplicates ignored.
- Wi-Fi policy: mobile pauses flagged, Wi-Fi resumes them, user pause not
  overridden, default applied to new downloads.
- Widgets: ring visibility and progress; screen sections, swipe-remove
  sheet with delete option, pause/resume, filter chips, search.
- Native notifications: channel calls asserted from Dart; device check.
