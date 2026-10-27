# Download Manager Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every download over 1 MB lands in TDLib's download list and in a Lumina Downloads screen (header ring + Settings entry) with pause/resume, pause all, reorder (priority), filters, search, Wi-Fi-only downloads and progress/completion notifications.

**Architecture:** `lib/features/downloads/` mirrors TDLib's own download list (`searchFileDownloads` + `updateFileAddedToDownloads` / `updateFileDownload` / `updateFileRemovedFromDownloads` / `updateFileDownloads`) in an app-wide `DownloadsCubit`. A core `DownloadRegistry` interface lets content widgets register files with their message; the feature implements it. Wi-Fi-only lives in `DownloadPolicy` on top of `AutoDownloadService` network changes. A new native channel `dev.lumina/downloads` posts the notifications.

**Tech Stack:** Flutter, flutter_bloc, TDLib (`lumina_tdlib`), Kotlin (NotificationCompat), `open_filex` (already a dependency).

**Spec:** `docs/superpowers/specs/2026-10-27-download-manager-design.md`

## Global Constraints

- Build/test only via `tool/flutter.sh` (`tool/flutter.sh test --timeout 60s <path>`).
- Feature-first; presentation never calls `TdClient`; other features never import `features/downloads` (core interface + `lib/app/` wiring).
- Colors `GlowColors`, motion `Motion`; no stock dialogs (glow sheets); semantics + 48 dp targets; no `pumpAndSettle` with `GlowButton` on screen; widget tests 1080x2400 @3x.
- Threshold: files over 1 MB (`1024 * 1024` bytes, size or expected size).
- Priority: top of the active list 32, then decreasing by 1, floor 1.
- Do not touch the owner's uncommitted files (see `git status`): notably `android/app/src/main/kotlin/dev/lumina/background/MessageNotifications.kt`, `Background.kt`, `AndroidManifest.xml`. New native code goes in a new file.
- `dart format` touched files (width 110); analyzer clean for touched files; explicit `git add` paths; commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

- A file already completed when tracked (opened from cache): it must not appear as active nor start a download — Task 1 test.
- Network flips mobile→Wi-Fi→mobile while a Wi-Fi-only download was also paused by the user: never auto-resumed — Task 3 test.
- A download removed while the screen is open (swipe, or from elsewhere via update): row disappears, totals update, no crash — Task 2 test.
- Hundreds of completed downloads: the list pages (`nextOffset`) instead of loading all at once — Task 2 test.
- App restart: the list comes back from TDLib (`searchFileDownloads`), Wi-Fi flags from prefs — Task 2 + Task 3 tests.

---

### Task 1: Repository and registry

**Files:**
- Create: `lib/core/telegram/download_registry.dart`
- Create: `lib/features/downloads/data/downloads_repository.dart`
- Create: `lib/features/downloads/data/tdlib_download_registry.dart`
- Test: `test/features/downloads/downloads_repository_test.dart`

**Interfaces:**
- Produces:
  - `abstract interface class DownloadRegistry { void track(td.File file, td.Message message); static DownloadRegistry of(BuildContext context); }` — `of` returns a no-op registry when none is provided.
  - `class DownloadsRepository { DownloadsRepository(TdClient c); Future<void> add(int fileId, {required int chatId, required int messageId, int priority = 16}); Future<void> setPaused(int fileId, bool paused); Future<void> setAllPaused(bool paused); Future<void> remove(int fileId, {required bool deleteFile}); Future<td.FoundFileDownloads> search({String query = '', bool onlyActive = false, bool onlyCompleted = false, String offset = '', int limit = 50}); Future<void> setPriority(int fileId, int priority); Stream<td.Update> get updates; }` — `setPriority` = `downloadFile(fileId, priority, 0, 0, synchronous: false)`; `updates` = the client's download-related updates.
  - `class TdlibDownloadRegistry implements DownloadRegistry { TdlibDownloadRegistry(DownloadsRepository repo, {int Function()? defaultPriority}); static const threshold = 1024 * 1024; }` — tracks once per file id per session; ignores files ≤ threshold, completed files, and files that cannot be downloaded.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/features/downloads/data/downloads_repository.dart';
import 'package:lumina/features/downloads/data/tdlib_download_registry.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../core/telegram/transfer_ring_test.dart' show downloading;
import '../../helpers/fakes.dart';

td.File file(int id, int size, {bool done = false}) {
  final f = downloading(size: size);
  return f.copyWith(
    id: id,
    local: f.local.copyWith(isDownloadingActive: false, isDownloadingCompleted: done, downloadedSize: 0),
  );
}

void main() {
  test('requests are built from the arguments', () async {
    final client = FakeTdClient()
      ..respond = (f) => f is td.SearchFileDownloads
          ? const td.FoundFileDownloads(
              totalCounts: td.DownloadedFileCounts(activeCount: 0, pausedCount: 0, completedCount: 0),
              files: [],
              nextOffset: '',
            )
          : f is td.DownloadFile
          ? file(3, 10)
          : const td.Ok();
    final repo = DownloadsRepository(client);
    await repo.add(3, chatId: 1, messageId: 9, priority: 20);
    await repo.setPaused(3, true);
    await repo.setAllPaused(false);
    await repo.remove(3, deleteFile: true);
    await repo.search(query: 'mp4', onlyActive: true, offset: 'x', limit: 20);
    await repo.setPriority(3, 31);
    final add = client.sentOf<td.AddFileToDownloads>().single;
    expect((add.fileId, add.chatId, add.messageId, add.priority), (3, 1, 9, 20));
    expect(client.sentOf<td.ToggleDownloadIsPaused>().single.isPaused, isTrue);
    expect(client.sentOf<td.ToggleAllDownloadsArePaused>().single.arePaused, isFalse);
    expect(client.sentOf<td.RemoveFileFromDownloads>().single.deleteFromCache, isTrue);
    final s = client.sentOf<td.SearchFileDownloads>().single;
    expect((s.query, s.onlyActive, s.onlyCompleted, s.offset, s.limit), ('mp4', true, false, 'x', 20));
    expect(client.sentOf<td.DownloadFile>().single.priority, 31);
  });

  test('the registry tracks big files once, with their message, and skips the rest', () async {
    final client = FakeTdClient();
    final registry = TdlibDownloadRegistry(DownloadsRepository(client));
    final m = fakeMessage(9, chatId: 1);
    registry.track(file(3, 5 * 1024 * 1024), m);
    registry.track(file(3, 5 * 1024 * 1024), m); // again
    registry.track(file(4, 1024 * 1024), m); // exactly 1 MB: not over
    registry.track(file(5, 9 * 1024 * 1024, done: true), m); // already downloaded
    await pumpEventQueue();
    final adds = client.sentOf<td.AddFileToDownloads>();
    expect(adds.map((a) => a.fileId), [3]);
    expect((adds.single.chatId, adds.single.messageId), (1, 9));
  });
}
```

- [ ] **Step 2: Run, expect FAIL (missing files).**

Run: `tool/flutter.sh test --timeout 60s test/features/downloads/downloads_repository_test.dart`

- [ ] **Step 3: Implement**

`download_registry.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

/// Where large downloads are recorded (Downloads screen). Content widgets
/// call [track] when they start a download they know the message of.
abstract interface class DownloadRegistry {
  void track(td.File file, td.Message message);

  static DownloadRegistry of(BuildContext context) {
    try {
      return context.read<DownloadRegistry>();
    } on ProviderNotFoundException {
      return const _None();
    }
  }
}

class _None implements DownloadRegistry {
  const _None();

  @override
  void track(td.File file, td.Message message) {}
}
```

`downloads_repository.dart`:

```dart
import 'package:lumina_tdlib/api.dart' as td;

import '../../../core/tdlib/td_client.dart';

/// TDLib's download list (what the Downloads screen shows).
class DownloadsRepository {
  DownloadsRepository(this._client);

  final TdClient _client;

  Stream<td.Update> get updates => _client.updates.where(
    (u) =>
        u is td.UpdateFileAddedToDownloads ||
        u is td.UpdateFileDownload ||
        u is td.UpdateFileRemovedFromDownloads ||
        u is td.UpdateFileDownloads ||
        u is td.UpdateFile,
  );

  Future<void> add(int fileId, {required int chatId, required int messageId, int priority = 16}) => _client
      .invoke<td.File>(
        td.AddFileToDownloads(fileId: fileId, chatId: chatId, messageId: messageId, priority: priority),
      );

  Future<void> setPaused(int fileId, bool paused) =>
      _client.invoke<td.Ok>(td.ToggleDownloadIsPaused(fileId: fileId, isPaused: paused));

  Future<void> setAllPaused(bool paused) =>
      _client.invoke<td.Ok>(td.ToggleAllDownloadsArePaused(arePaused: paused));

  Future<void> remove(int fileId, {required bool deleteFile}) =>
      _client.invoke<td.Ok>(td.RemoveFileFromDownloads(fileId: fileId, deleteFromCache: deleteFile));

  Future<td.FoundFileDownloads> search({
    String query = '',
    bool onlyActive = false,
    bool onlyCompleted = false,
    String offset = '',
    int limit = 50,
  }) => _client.invoke<td.FoundFileDownloads>(
    td.SearchFileDownloads(
      query: query,
      onlyActive: onlyActive,
      onlyCompleted: onlyCompleted,
      offset: offset,
      limit: limit,
    ),
  );

  Future<void> setPriority(int fileId, int priority) => _client.invoke<td.File>(
    td.DownloadFile(fileId: fileId, priority: priority, offset: 0, limit: 0, synchronous: false),
  );
}
```

(Check `AddFileToDownloads`' return type in `packages/lumina_tdlib/lib/src/tdapi/functions/add_file_to_downloads.dart` — the doc comment says `Returns [File]`; adjust `invoke<...>` to match.)

`tdlib_download_registry.dart`:

```dart
import 'package:lumina_tdlib/api.dart' as td;

import '../../../core/telegram/download_registry.dart';
import 'downloads_repository.dart';

/// Puts every download over 1 MB into TDLib's download list, once.
class TdlibDownloadRegistry implements DownloadRegistry {
  TdlibDownloadRegistry(this._repo, {int Function()? defaultPriority})
    : _priority = defaultPriority ?? (() => 16);

  static const threshold = 1024 * 1024;

  final DownloadsRepository _repo;
  final int Function() _priority;
  final _tracked = <int>{};

  @override
  void track(td.File file, td.Message message) {
    final size = file.size > 0 ? file.size : file.expectedSize;
    if (size <= threshold) return;
    if (file.local.isDownloadingCompleted || !file.local.canBeDownloaded) return;
    if (!_tracked.add(file.id)) return;
    _repo.add(file.id, chatId: message.chatId, messageId: message.id, priority: _priority()).catchError((_) {
      _tracked.remove(file.id);
    });
  }
}
```

- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit**

```bash
git add lib/core/telegram/download_registry.dart lib/features/downloads/data/downloads_repository.dart lib/features/downloads/data/tdlib_download_registry.dart test/features/downloads/downloads_repository_test.dart
git commit -m "Downloads: repository over TDLib's download list, registry for big files"
```

---

### Task 2: DownloadsCubit (mirror, totals, speed, filters, reorder)

**Files:**
- Create: `lib/features/downloads/bloc/downloads_cubit.dart`
- Create: `lib/features/downloads/domain/download_item.dart`
- Test: `test/features/downloads/downloads_cubit_test.dart`

**Interfaces:**
- Consumes: `DownloadsRepository` (Task 1), `FileStore` (`watch`, `[]`, `remember`).
- Produces:
  - `enum DownloadFilter { all, videos, files, music, photos }` (label getter: 'All', 'Videos', 'Files', 'Music', 'Photos').
  - `class DownloadItem { final int fileId; final td.Message message; final int addDate; final int completeDate; final bool isPaused; final td.File? file; bool get isCompleted => completeDate != 0; DownloadFilter get kind; String get name; int get size; int get downloaded; DownloadItem copyWith(...); }` — `kind` from `message.content` (MessageVideo/VideoNote/Animation → videos, MessageAudio/VoiceNote → music, MessagePhoto → photos, everything else → files); `name` = document/audio/video file name, else 'Photo'/'Video'/'Voice message'.
  - `class DownloadsState { final List<DownloadItem> active; final List<DownloadItem> completed; final int totalSize; final int downloadedSize; final int bytesPerSecond; final DownloadFilter filter; final String query; final bool loading; final bool hasMoreCompleted; List<DownloadItem> get visibleActive; List<DownloadItem> get visibleCompleted; bool get anyActive; }` — `visible*` apply filter and case-insensitive name query; `anyActive` = `active.isNotEmpty`.
  - `class DownloadsCubit extends Cubit<DownloadsState> { DownloadsCubit({required DownloadsRepository repository, required FileStore files, DateTime Function()? now}); Future<void> start(); Future<void> loadMoreCompleted(); void setFilter(DownloadFilter f); void setQuery(String q); Future<void> togglePaused(DownloadItem i); Future<void> setAllPaused(bool paused); Future<void> remove(DownloadItem i, {required bool deleteFile}); Future<void> reorder(int oldIndex, int newIndex); Future<void> moveToTop(DownloadItem i); }`
  - `start()`: `search(onlyActive: true, limit: 100)` + `search(onlyCompleted: true, limit: 30)` (`hasMoreCompleted` = `nextOffset.isNotEmpty`), then listens to `repository.updates`.
  - Updates: `UpdateFileAddedToDownloads` → insert into active (or completed if `completeDate != 0`) at the front; `UpdateFileDownload` → update `completeDate`/`isPaused`, move to completed when it completes; `UpdateFileRemovedFromDownloads` → drop; `UpdateFileDownloads` → totals; `UpdateFile` for a listed file → attach the file and recompute speed.
  - Speed: sum over active files of (downloadedSize delta) / (time delta), smoothed (exponential, factor 0.3), using `now()`.
  - `reorder` reorders `active` (visible order = list order) and calls `setPriority` for every moved item: index 0 → 32, then 31, … floor 1.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/telegram/file_store.dart';
import 'package:lumina/features/downloads/bloc/downloads_cubit.dart';
import 'package:lumina/features/downloads/data/downloads_repository.dart';
import 'package:lumina/features/downloads/domain/download_item.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../helpers/fakes.dart';
import 'downloads_repository_test.dart' show file;

const counts = td.DownloadedFileCounts(activeCount: 0, pausedCount: 0, completedCount: 0);

td.FileDownload dl(int id, {int complete = 0, bool paused = false, td.MessageContent? content}) => td.FileDownload(
  fileId: id,
  message: fakeMessage(id, content: content),
  addDate: 100 + id,
  completeDate: complete,
  isPaused: paused,
);

void main() {
  late FakeTdClient client;
  late DownloadsCubit cubit;
  var clock = DateTime(2026);

  Future<void> start({List<td.FileDownload> active = const [], List<td.FileDownload> done = const [], String more = ''}) async {
    client = FakeTdClient()
      ..respond = (f) => switch (f) {
        td.SearchFileDownloads(onlyActive: true) => td.FoundFileDownloads(totalCounts: counts, files: active, nextOffset: ''),
        td.SearchFileDownloads(onlyCompleted: true, offset: '') => td.FoundFileDownloads(totalCounts: counts, files: done, nextOffset: more),
        td.SearchFileDownloads() => td.FoundFileDownloads(totalCounts: counts, files: [dl(99, complete: 5)], nextOffset: ''),
        td.DownloadFile(:final fileId) => file(fileId, 10),
        _ => const td.Ok(),
      };
    cubit = DownloadsCubit(repository: DownloadsRepository(client), files: FileStore(client), now: () => clock);
    await cubit.start();
  }

  tearDown(() => cubit.close());

  test('loads active and completed from TDLib (survives restarts)', () async {
    await start(active: [dl(1), dl(2, paused: true)], done: [dl(3, complete: 200)]);
    expect(cubit.state.active.map((i) => i.fileId), [1, 2]);
    expect(cubit.state.completed.map((i) => i.fileId), [3]);
    expect(cubit.state.active[1].isPaused, isTrue);
  });

  test('updates add, complete and remove; totals follow', () async {
    await start(active: [dl(1)]);
    client.emitUpdate(td.UpdateFileAddedToDownloads(fileDownload: dl(2), counts: counts));
    client.emitUpdate(const td.UpdateFileDownload(fileId: 1, completeDate: 300, isPaused: false, counts: counts));
    client.emitUpdate(const td.UpdateFileDownloads(totalSize: 1000, totalCount: 1, downloadedSize: 250));
    await pumpEventQueue();
    expect(cubit.state.active.map((i) => i.fileId), [2]);
    expect(cubit.state.completed.map((i) => i.fileId), [1]);
    expect((cubit.state.totalSize, cubit.state.downloadedSize), (1000, 250));
    client.emitUpdate(const td.UpdateFileRemovedFromDownloads(fileId: 2, counts: counts));
    await pumpEventQueue();
    expect(cubit.state.active, isEmpty);
    expect(cubit.state.anyActive, isFalse);
  });

  test('completed downloads page instead of loading all', () async {
    await start(done: [dl(3, complete: 1)], more: 'next');
    expect(cubit.state.hasMoreCompleted, isTrue);
    await cubit.loadMoreCompleted();
    expect(cubit.state.completed.map((i) => i.fileId), [3, 99]);
    expect(cubit.state.hasMoreCompleted, isFalse);
  });

  test('speed comes from progress over time', () async {
    await start(active: [dl(1)]);
    final f = file(1, 10000000);
    client.emitUpdate(td.UpdateFile(file: f.copyWith(local: f.local.copyWith(downloadedSize: 0, isDownloadingActive: true))));
    await pumpEventQueue();
    clock = clock.add(const Duration(seconds: 1));
    client.emitUpdate(td.UpdateFile(file: f.copyWith(local: f.local.copyWith(downloadedSize: 1000000, isDownloadingActive: true))));
    await pumpEventQueue();
    expect(cubit.state.bytesPerSecond, greaterThan(0));
  });

  test('filters and search narrow what is shown', () async {
    await start(active: [
      dl(1, content: const td.MessageText(text: td.FormattedText(text: 'x', entities: []))),
      dl(2, content: td.MessagePhoto(
        photo: const td.Photo(hasStickers: false, sizes: []),
        caption: const td.FormattedText(text: '', entities: []),
        showCaptionAboveMedia: false, hasSpoiler: false, isSecret: false,
      )),
    ]);
    cubit.setFilter(DownloadFilter.photos);
    expect(cubit.state.visibleActive.map((i) => i.fileId), [2]);
    cubit
      ..setFilter(DownloadFilter.all)
      ..setQuery('PHOTO');
    expect(cubit.state.visibleActive.map((i) => i.fileId), [2]);
  });

  test('reordering sets priorities from the top', () async {
    await start(active: [dl(1), dl(2), dl(3)]);
    await cubit.reorder(2, 0);
    expect(cubit.state.active.map((i) => i.fileId), [3, 1, 2]);
    final p = {for (final d in client.sentOf<td.DownloadFile>()) d.fileId: d.priority};
    expect(p, {3: 32, 1: 31, 2: 30});
  });
}
```

(`reorder(oldIndex, newIndex)` uses the semantics of the final position — `newIndex` is where the item ends up; document this in the method's doc comment and keep the screen's `onReorderItem` callback consistent, Task 5.)

- [ ] **Step 2: Run, expect FAIL.**

Run: `tool/flutter.sh test --timeout 60s test/features/downloads/downloads_cubit_test.dart`

- [ ] **Step 3: Implement `download_item.dart` and `downloads_cubit.dart`** per the interfaces. Notes:
  - Keep `DownloadsState` immutable with `copyWith`; recompute `visible*` as getters.
  - Name for content: `MessageDocument → document.fileName`, `MessageAudio → audio.fileName.isEmpty ? audio.title : audio.fileName`, `MessageVideo → video.fileName.isEmpty ? 'Video' : video.fileName`, `MessagePhoto → 'Photo'`, `MessageVoiceNote → 'Voice message'`, `MessageVideoNote → 'Video message'`, `MessageAnimation → animation.fileName.isEmpty ? 'GIF' : animation.fileName`, else 'File'.
  - Speed state per file: `Map<int, (int bytes, DateTime at)>`; on `UpdateFile` for a listed active file: `delta = bytes - prev.bytes`, `dt = now - prev.at` (skip if ≤ 0); instantaneous total = sum of the latest per-file rates; `bytesPerSecond = (0.3 * inst + 0.7 * previous).round()`.
  - `remove` calls the repository and drops the row immediately (the update then is a no-op).
  - Errors from repository calls: rethrow to the UI (it shows a toast) and re-sync with `start()`'s searches.

- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit**

```bash
git add lib/features/downloads/bloc/downloads_cubit.dart lib/features/downloads/domain/download_item.dart test/features/downloads/downloads_cubit_test.dart
git commit -m "Downloads: cubit mirroring TDLib's list with totals, speed, filters and priorities"
```

---

### Task 3: Wi-Fi only

**Files:**
- Create: `lib/features/downloads/data/download_policy.dart`
- Modify: `lib/core/storage/app_preferences.dart` (Downloads section)
- Test: `test/features/downloads/download_policy_test.dart`

**Interfaces:**
- Consumes: `DownloadsRepository.setPaused`, `AutoDownloadService` (`network`, `changes`) via a narrow interface.
- Produces:
  - `AppPreferences`: `bool get downloadsWifiOnlyDefault` / setter (key `downloads.wifiOnly`, default false); `Set<int> get downloadsWifiOnly` / `setDownloadsWifiOnly(Set<int>)` (key `downloads.wifiOnlyFiles`, space-separated ids).
  - `abstract interface class NetworkWatch { bool get onWifi; Listenable get changes; }` (in `download_policy.dart`) and an adapter `class AutoDownloadNetworkWatch implements NetworkWatch { AutoDownloadNetworkWatch(AutoDownloadService s); }` with `onWifi => s.network == NetworkKind.wifi`.
  - `class DownloadPolicy { DownloadPolicy({required DownloadsRepository repository, required AppPreferences prefs, required NetworkWatch network}); bool isWifiOnly(int fileId); Future<void> setWifiOnly(int fileId, bool on); bool isWaitingForWifi(int fileId); void onAdded(int fileId); void userPaused(int fileId, bool paused); Future<void> apply(Iterable<int> activeFileIds); Listenable get changes; void dispose(); }`
  - Semantics: `onAdded` applies the default flag. `apply` (called on every network change and after `onAdded`): when not on Wi-Fi, every flagged active file that the user hasn't paused is paused via the repository and marked waiting; when on Wi-Fi, every waiting file is resumed and unmarked. `userPaused(id, true)` marks a user pause (never auto-resumed); `userPaused(id, false)` clears it.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/features/downloads/data/download_policy.dart';
import 'package:lumina/features/downloads/data/downloads_repository.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../helpers/fakes.dart';

class _Net extends ChangeNotifier implements NetworkWatch {
  @override
  bool onWifi = true;

  @override
  Listenable get changes => this;

  void set(bool wifi) {
    onWifi = wifi;
    notifyListeners();
  }
}

void main() {
  late FakeTdClient client;
  late _Net net;
  late AppPreferences prefs;

  DownloadPolicy policy() => DownloadPolicy(repository: DownloadsRepository(client), prefs: prefs, network: net);
  List<(int, bool)> toggles() => [for (final t in client.sentOf<td.ToggleDownloadIsPaused>()) (t.fileId, t.isPaused)];

  setUp(() {
    client = FakeTdClient();
    net = _Net();
    prefs = AppPreferences.inMemory();
  });

  test('on mobile data Wi-Fi-only downloads wait, and resume on Wi-Fi', () async {
    final p = policy();
    await p.setWifiOnly(1, true);
    net.set(false);
    await p.apply([1, 2]);
    expect(toggles(), [(1, true)]);
    expect(p.isWaitingForWifi(1), isTrue);
    net.set(true);
    await p.apply([1, 2]);
    expect(toggles(), [(1, true), (1, false)]);
    expect(p.isWaitingForWifi(1), isFalse);
  });

  test("a download the user paused is never resumed by the network", () async {
    final p = policy();
    await p.setWifiOnly(1, true);
    p.userPaused(1, true);
    net.set(false);
    await p.apply([1]);
    net.set(true);
    await p.apply([1]);
    net.set(false);
    await p.apply([1]);
    expect(toggles(), isEmpty);
  });

  test('the default applies to new downloads and flags survive a restart', () async {
    prefs.downloadsWifiOnlyDefault = true;
    final p = policy()..onAdded(7);
    expect(p.isWifiOnly(7), isTrue);
    expect(policy().isWifiOnly(7), isTrue, reason: 'stored in prefs');
  });
}
```

- [ ] **Step 2: Run, expect FAIL.**

Run: `tool/flutter.sh test --timeout 60s test/features/downloads/download_policy_test.dart`

- [ ] **Step 3: Implement** prefs (follow the existing `_bool`/`_string`/`_set` helpers) and `DownloadPolicy` per the semantics above. `apply` is idempotent: it only toggles files whose waiting state changes. `changes` is a `ChangeNotifier` bumped when flags or waiting state change.

- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit**

```bash
git add lib/features/downloads/data/download_policy.dart lib/core/storage/app_preferences.dart test/features/downloads/download_policy_test.dart
git commit -m "Downloads: Wi-Fi-only downloads wait for Wi-Fi; user pauses win"
```

---

### Task 4: Register downloads from content widgets

**Files:**
- Modify: `lib/features/conversation/presentation/widgets/content/auto_fetch.dart` (track after starting a download)
- Modify: `lib/features/conversation/presentation/widgets/content/document_content.dart:45` (track on tap-download)
- Modify: `lib/features/conversation/presentation/widgets/content/media_content.dart` (the `TransferRing` on video media: pass an `onDownload` that tracks)
- Modify: `lib/core/telegram/widgets/file_progress.dart` (`TransferRing` gets optional `ValueChanged<td.File>? onStart`, called when its tap starts a download)
- Modify: media viewer save action — find with `grep -rn "Save" lib/features/media/presentation/screens/media_viewer_screen.dart`; track the file being saved with its message
- Test: `test/features/conversation/widgets/auto_fetch_test.dart` (extend), `test/core/telegram/transfer_ring_test.dart` (extend)

**Interfaces:**
- Consumes: `DownloadRegistry.of(context).track(file, message)` (Task 1).
- Produces: `TransferRing({..., ValueChanged<td.File>? onStart})`.

- [ ] **Step 1: Write the failing tests**

In `auto_fetch_test.dart`, add a `_Registry implements DownloadRegistry` recording `(fileId, messageId)`, provide it, and:

```dart
  testWidgets('auto-started downloads are registered with their message', (tester) async {
    final registry = _Registry();
    await pumpWith(tester, _Gate({MediaKind.files}), document(idle(12, 5000000)), registry: registry);
    expect(registry.tracked, [(12, 5)]);
  });
```

(Refactor the file's `pump` into `pumpWith(..., {DownloadRegistry? registry})` that adds `RepositoryProvider<DownloadRegistry>.value` when given; keep the existing tests calling it without a registry.)

In `transfer_ring_test.dart`:

```dart
  testWidgets('a tap that starts a download reports it', (tester) async {
    final client = FakeTdClient()..respond = (_) => downloading(size: 100);
    td.File? started;
    final idle = downloading(size: 100).copyWith(
      local: downloading(size: 100).local.copyWith(isDownloadingActive: false),
    );
    await tester.pumpWidget(
      RepositoryProvider(
        create: (_) => FileStore(client),
        child: MaterialApp(home: TransferRing(file: idle, onStart: (f) => started = f)),
      ),
    );
    await tester.tap(find.byType(TransferRing));
    await tester.pump();
    expect(started?.id, idle.id);
  });
```

(Check the file's existing imports/provider setup and reuse them.)

- [ ] **Step 2: Run, expect FAIL.**

Run: `tool/flutter.sh test --timeout 60s test/features/conversation/widgets/auto_fetch_test.dart test/core/telegram/transfer_ring_test.dart`

- [ ] **Step 3: Implement**
  - `AutoFetch`: after `store.download(...)` call `DownloadRegistry.of(context).track(f, m)`; same after the preload `requestRange` (no — preload is partial; do not track it).
  - `TransferRing`: in the tap handler, when starting (not cancelling), `onStart?.call(f)`.
  - `MediaTile`: `TransferRing(file: v.media!, size: 36, onStart: (f) => DownloadRegistry.of(context).track(f, widget.message))`, and the photo ring likewise with `v.file!`.
  - `DocumentContent`: after `store.download(f.id, priority: 24)` → `DownloadRegistry.of(context).track(f, message)`.
  - Media viewer save: track the full-size file with the message before downloading it.

- [ ] **Step 4: Run those tests + `test/features/conversation`, expect PASS.**
- [ ] **Step 5: Commit**

```bash
git add lib/features/conversation/presentation/widgets/content/auto_fetch.dart lib/features/conversation/presentation/widgets/content/document_content.dart lib/features/conversation/presentation/widgets/content/media_content.dart lib/core/telegram/widgets/file_progress.dart lib/features/media/presentation/screens/media_viewer_screen.dart test/features/conversation/widgets/auto_fetch_test.dart test/core/telegram/transfer_ring_test.dart
git commit -m "Downloads: big downloads from chats are registered with their message"
```

---

### Task 5: Downloads screen

**Files:**
- Create: `lib/features/downloads/presentation/downloads_screen.dart`
- Create: `lib/features/downloads/presentation/download_row.dart`
- Test: `test/features/downloads/downloads_screen_test.dart`

**Interfaces:**
- Consumes: `DownloadsCubit` (Task 2), `DownloadPolicy` (Task 3), `FileStore`, `TelegramCache` (chat titles), `ChatAvatar`/`TdFileImage`, `open_filex`.
- Produces: `class DownloadsScreen extends StatelessWidget { static Route<void> route({required void Function(BuildContext, int chatId, int messageId) openMessage}); }`.

Layout:
- `AppBar('Downloads')`, actions: Pause all / Resume all (`IconButton` with tooltip; resume when every active item is paused).
- Header card (glass): "N downloading · X left" (`Display.fileSize(total - downloaded)`), speed "1.2 MB/s" when > 0, a thin glowing progress bar.
- Search `TextField` (prefix search icon, hint 'Search downloads') → `setQuery`; filter `ChoiceChip`s for `DownloadFilter.values` → `setFilter`.
- Active: `ReorderableListView` (shrinkWrap inside a `CustomScrollView` is costly — use `SliverReorderableList` inside a `CustomScrollView`) of `DownloadRow`; `onReorderItem(old, new)` → `cubit.reorder(old, new)` (indices in the visible list map to the full list when a filter/query is active — disable reordering while filtered and show drag handles only when unfiltered).
- Completed: `SliverList` of `DownloadRow`s; at the end, when `hasMoreCompleted`, trigger `loadMoreCompleted()` (on build of the last item).
- Empty: centred "No downloads yet" + "Files over 1 MB you download show up here".
- `DownloadRow`: leading thumbnail (`TdFileImage` of the message's thumbnail when any) or an icon per `kind`; title `name`; subtitle `chat title · size`, plus `LinearProgressIndicator`-like glowing bar and "X/s" for active; states: "Paused", "Waiting for Wi-Fi" (`policy.isWaitingForWifi`), "Failed" (file not active, not completed, `downloadedSize < size`, and not paused) with Retry; trailing pause/resume `IconButton` (active) or open icon (completed). Wi-Fi badge (`Icons.wifi_rounded`, 14) when `policy.isWifiOnly`.
- Swipe left (`Dismissible`, `DismissDirection.endToStart`, `confirmDismiss`) → glow sheet "Remove from downloads?" with a `CheckboxListTile` "Also delete the file" and a Remove `GlowButton`; returns the choice; then `cubit.remove(item, deleteFile: choice)`.
- Long-press → glow sheet: Wi-Fi only (switch → `policy.setWifiOnly`), Move to top (active only), Open chat (`openMessage`).
- Tap: completed → `OpenFilex.open(file.local.path)`; chat title tap → `openMessage(context, chatId, messageId)`; pause button → `cubit.togglePaused(item)` and `policy.userPaused(id, !item.isPaused)`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/core/telegram/file_store.dart';
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/features/downloads/bloc/downloads_cubit.dart';
import 'package:lumina/features/downloads/data/download_policy.dart';
import 'package:lumina/features/downloads/data/downloads_repository.dart';
import 'package:lumina/features/downloads/presentation/downloads_screen.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../helpers/fakes.dart';
import 'download_policy_test.dart' show NetForTests;
import 'downloads_cubit_test.dart' show counts, dl;

void main() {
  late FakeTdClient client;
  late DownloadsCubit cubit;

  Future<void> pump(WidgetTester tester, {List<td.FileDownload> active = const [], List<td.FileDownload> done = const []}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    client = FakeTdClient()
      ..respond = (f) => switch (f) {
        td.SearchFileDownloads(onlyActive: true) => td.FoundFileDownloads(totalCounts: counts, files: active, nextOffset: ''),
        td.SearchFileDownloads() => td.FoundFileDownloads(totalCounts: counts, files: done, nextOffset: ''),
        _ => const td.Ok(),
      };
    final repo = DownloadsRepository(client);
    final prefs = AppPreferences.inMemory();
    cubit = DownloadsCubit(repository: repo, files: FileStore(client));
    await cubit.start();
    addTearDown(cubit.close);
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider.value(value: prefs),
          RepositoryProvider(create: (_) => FileStore(client)),
          RepositoryProvider.value(value: TelegramCache.detached()..apply(td.UpdateNewChat(chat: fakeChat(1, title: 'Ada')))),
          RepositoryProvider(create: (_) => DownloadPolicy(repository: repo, prefs: prefs, network: NetForTests())),
        ],
        child: BlocProvider.value(
          value: cubit,
          child: MaterialApp(
            home: Builder(builder: (c) => DownloadsScreen(openMessage: (_, _, _) {})),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('empty state', (tester) async {
    await pump(tester);
    expect(find.text('No downloads yet'), findsOneWidget);
  });

  testWidgets('pause, and swipe to remove with "also delete"', (tester) async {
    await pump(tester, active: [dl(1)]);
    await tester.tap(find.byTooltip('Pause'));
    await tester.pump();
    expect(client.sentOf<td.ToggleDownloadIsPaused>().single.isPaused, isTrue);
    await tester.drag(find.byKey(const ValueKey('download-1')), const Offset(-600, 0));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Also delete the file'));
    await tester.pump();
    await tester.tap(find.text('Remove'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(client.sentOf<td.RemoveFileFromDownloads>().single.deleteFromCache, isTrue);
  });

  testWidgets('filter chips and pause all', (tester) async {
    await pump(tester, active: [dl(1), dl(2)]);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Photos'));
    await tester.pump();
    expect(find.byKey(const ValueKey('download-1')), findsNothing);
    await tester.tap(find.byTooltip('Pause all'));
    await tester.pump();
    expect(client.sentOf<td.ToggleAllDownloadsArePaused>().single.arePaused, isTrue);
  });
}
```

Rename `_Net` in `download_policy_test.dart` to a public `NetForTests` (same body) so this test can import it; DownloadsScreen's constructor takes `openMessage` directly (route wraps it). Row keys: `ValueKey('download-${item.fileId}')`.

- [ ] **Step 2: Run, expect FAIL.**

Run: `tool/flutter.sh test --timeout 60s test/features/downloads/downloads_screen_test.dart`

- [ ] **Step 3: Implement** per the layout.
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit**

```bash
git add lib/features/downloads/presentation/downloads_screen.dart lib/features/downloads/presentation/download_row.dart test/features/downloads/downloads_screen_test.dart test/features/downloads/download_policy_test.dart
git commit -m "Downloads: the Downloads screen"
```

---

### Task 6: Header ring, Settings entry, wiring

**Files:**
- Create: `lib/features/downloads/presentation/downloads_ring.dart`
- Create: `lib/features/downloads/presentation/downloads_settings.dart`
- Modify: `lib/app/feature_wiring.dart` (providers: `DownloadsRepository`, `DownloadRegistry` → `TdlibDownloadRegistry`, `DownloadPolicy` with `AutoDownloadNetworkWatch`, app-wide non-lazy `DownloadsCubit` started on creation; policy hook: on `UpdateFileAddedToDownloads` → `policy.onAdded`; on network change → `policy.apply(active ids)`; Settings entry under `SettingsCategory.data` before Auto-download)
- Modify: `lib/app/app_chat_list_extensions.dart:27` (`headerActions` → `[DownloadsRing(...), ProxyButton()]`)
- Test: `test/features/downloads/downloads_ring_test.dart`

**Interfaces:**
- Produces: `class DownloadsRing extends StatelessWidget { const DownloadsRing({super.key, required this.onOpen}); }` — reads `DownloadsCubit`; renders nothing (`SizedBox.shrink`) when `!anyActive`; else a 40 dp `CustomPaint` ring (track `GlowColors.outline`, arc `GlowColors.cyan` with `glow`) with a down-arrow, dimmed with a pause glyph when every active item is paused; `Semantics(button: true, label: 'Downloads, N active, X%')`; 48 dp touch target.
- `DownloadsSettings`: `SettingsSection('Downloads')` with a tile "Downloads" (subtitle "N active · X completed") → `DownloadsScreen.route(...)`, and a `SwitchListTile` "New downloads: Wi-Fi only" bound to `prefs.downloadsWifiOnlyDefault`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/telegram/file_store.dart';
import 'package:lumina/features/downloads/bloc/downloads_cubit.dart';
import 'package:lumina/features/downloads/data/downloads_repository.dart';
import 'package:lumina/features/downloads/presentation/downloads_ring.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../helpers/fakes.dart';
import 'downloads_cubit_test.dart' show counts, dl;

void main() {
  Future<DownloadsCubit> pump(WidgetTester tester, List<td.FileDownload> active, {void Function()? onOpen}) async {
    final client = FakeTdClient()
      ..respond = (f) => f is td.SearchFileDownloads
          ? td.FoundFileDownloads(totalCounts: counts, files: f.onlyActive ? active : const [], nextOffset: '')
          : const td.Ok();
    final cubit = DownloadsCubit(repository: DownloadsRepository(client), files: FileStore(client));
    await cubit.start();
    addTearDown(cubit.close);
    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: MaterialApp(home: Scaffold(body: DownloadsRing(onOpen: onOpen ?? () {}))),
      ),
    );
    await tester.pump();
    return cubit;
  }

  testWidgets('hidden with nothing to download', (tester) async {
    await pump(tester, const []);
    expect(find.bySemanticsLabel(RegExp('^Downloads')), findsNothing);
  });

  testWidgets('shows while downloading and opens the screen', (tester) async {
    var opened = false;
    await pump(tester, [dl(1)], onOpen: () => opened = true);
    expect(find.bySemanticsLabel(RegExp('^Downloads, 1 active')), findsOneWidget);
    await tester.tap(find.byType(DownloadsRing));
    expect(opened, isTrue);
  });
}
```

- [ ] **Step 2: Run, expect FAIL.**

Run: `tool/flutter.sh test --timeout 60s test/features/downloads/downloads_ring_test.dart`

- [ ] **Step 3: Implement** ring, settings section, wiring. `openMessage` in the wiring: `Navigator.of(context).push(ConversationScreen.route(chatId, focusMessageId: messageId))`.
- [ ] **Step 4: Run the ring test, then the full suite: `tool/flutter.sh test --timeout 60s`.** Expected PASS.
- [ ] **Step 5: Commit**

```bash
git add lib/features/downloads/presentation/downloads_ring.dart lib/features/downloads/presentation/downloads_settings.dart lib/app/feature_wiring.dart lib/app/app_chat_list_extensions.dart test/features/downloads/downloads_ring_test.dart
git commit -m "Downloads: header ring, Settings entry and wiring"
```

---

### Task 7: Notifications

**Files:**
- Create: `android/app/src/main/kotlin/dev/lumina/background/DownloadNotifications.kt`
- Modify: `android/app/src/main/kotlin/dev/lumina/lumina/LuminaEngine.kt` (register it, like `NetworkChannel`)
- Create: `lib/features/downloads/data/download_notifier.dart`
- Modify: `lib/app/feature_wiring.dart` (non-lazy `DownloadNotifier` listening to the cubit)
- Modify: `docs/REMAINING.md`
- Test: `test/features/downloads/download_notifier_test.dart`

**Interfaces:**
- Produces:
  - Native channel `dev.lumina/downloads` methods: `progress({count: int, percent: int})` (ongoing, low importance, channel id `downloads`, action "Pause all" → event `pauseAll` on `dev.lumina/downloads/events`), `clearProgress()`, `completed({id: int, name: String, path: String})` (tap opens the file via `Intent.ACTION_VIEW` + `FileProvider` — check `android/app/src/main/res/xml/` for an existing provider path config and the manifest `<provider>`; if none exists, open via the app: tap launches `MainActivity` with extra `open_download_path`, which Dart handles by `OpenFilex.open`).
  - `class DownloadNotifier { DownloadNotifier({required DownloadsCubit cubit, required DownloadsChannel channel, bool Function()? screenVisible}); void dispose(); }` and `abstract interface class DownloadsChannel { Future<void> progress(int count, int percent); Future<void> clearProgress(); Future<void> completed(int id, String name, String path); Stream<String> get events; }` with `MethodDownloadsChannel` as the platform implementation.
  - Behaviour: on state changes, if `active.isNotEmpty` → `progress(count, percent)` (throttled: only when count or percent changes); when it becomes empty → `clearProgress()`; when an item moves from active to completed and `screenVisible()` is false → `completed(fileId, name, path)`. Event `pauseAll` → `cubit.setAllPaused(true)`.

- [ ] **Step 1: Write the failing test** (`FakeChannel` records calls):

```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/telegram/file_store.dart';
import 'package:lumina/features/downloads/bloc/downloads_cubit.dart';
import 'package:lumina/features/downloads/data/download_notifier.dart';
import 'package:lumina/features/downloads/data/downloads_repository.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../helpers/fakes.dart';
import 'downloads_cubit_test.dart' show counts, dl;

class FakeChannel implements DownloadsChannel {
  final calls = <String>[];
  final _events = StreamController<String>.broadcast();

  @override
  Future<void> progress(int count, int percent) async => calls.add('progress $count');

  @override
  Future<void> clearProgress() async => calls.add('clear');

  @override
  Future<void> completed(int id, String name, String path) async => calls.add('done $id');

  @override
  Stream<String> get events => _events.stream;

  void emit(String e) => _events.add(e);
}

void main() {
  test('progress while active, a note per completion, clear when done, pause all from the notification', () async {
    final client = FakeTdClient()
      ..respond = (f) => f is td.SearchFileDownloads
          ? td.FoundFileDownloads(totalCounts: counts, files: f.onlyActive ? [dl(1)] : const [], nextOffset: '')
          : const td.Ok();
    final cubit = DownloadsCubit(repository: DownloadsRepository(client), files: FileStore(client));
    final channel = FakeChannel();
    final notifier = DownloadNotifier(cubit: cubit, channel: channel);
    await cubit.start();
    await pumpEventQueue();
    expect(channel.calls, contains('progress 1'));
    client.emitUpdate(const td.UpdateFileDownload(fileId: 1, completeDate: 9, isPaused: false, counts: counts));
    await pumpEventQueue();
    expect(channel.calls, containsAllInOrder(['done 1', 'clear']));
    channel.emit('pauseAll');
    await pumpEventQueue();
    expect(client.sentOf<td.ToggleAllDownloadsArePaused>().single.arePaused, isTrue);
    notifier.dispose();
    await cubit.close();
  });
}
```

- [ ] **Step 2: Run, expect FAIL.**

Run: `tool/flutter.sh test --timeout 60s test/features/downloads/download_notifier_test.dart`

- [ ] **Step 3: Implement** the Dart notifier + `MethodDownloadsChannel` (`MethodChannel('dev.lumina/downloads')`, `EventChannel('dev.lumina/downloads/events')`), and `DownloadNotifications.kt` (create the `downloads` notification channel at low importance; ongoing progress notification id 4100 with `setProgress(100, percent, false)`, `setOnlyAlertOnce(true)`, small icon `R.drawable.ic_stat_lumina` if it exists in the committed tree — `git ls-files android/app/src/main/res/drawable` — else `android.R.drawable.stat_sys_download`; completion notifications id `4200 + (fileId % 1000)` with `android.R.drawable.stat_sys_download_done`). Register in `LuminaEngine.ensure` after `NetworkChannel`.
- [ ] **Step 4: Run the notifier test, the full suite, and a release build to compile Kotlin:**

Run: `tool/flutter.sh test --timeout 60s` then `tool/flutter.sh build apk --release --target-platform android-arm64`
Expected: all PASS; build succeeds.

- [ ] **Step 5: Docs, commit**

`docs/REMAINING.md` Done list: "download manager (header ring, Settings → Data & storage → Downloads; pause/resume, reorder, filters, search, Wi-Fi only, notifications)".

```bash
git add android/app/src/main/kotlin/dev/lumina/background/DownloadNotifications.kt android/app/src/main/kotlin/dev/lumina/lumina/LuminaEngine.kt lib/features/downloads/data/download_notifier.dart lib/app/feature_wiring.dart test/features/downloads/download_notifier_test.dart docs/REMAINING.md
git commit -m "Downloads: progress and completion notifications"
```
