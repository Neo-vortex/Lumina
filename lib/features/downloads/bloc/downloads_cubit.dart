import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../core/telegram/file_store.dart';
import '../data/downloads_repository.dart';
import '../domain/download_item.dart';

export '../domain/download_item.dart';

class DownloadsState {
  const DownloadsState({
    this.active = const [],
    this.completed = const [],
    this.totalSize = 0,
    this.downloadedSize = 0,
    this.bytesPerSecond = 0,
    this.filter = DownloadFilter.all,
    this.query = '',
    this.loading = true,
    this.hasMoreCompleted = false,
  });

  final List<DownloadItem> active;
  final List<DownloadItem> completed;
  final int totalSize;
  final int downloadedSize;
  final int bytesPerSecond;
  final DownloadFilter filter;
  final String query;
  final bool loading;
  final bool hasMoreCompleted;

  bool get anyActive => active.isNotEmpty;

  /// Narrowed by the filter chips or the search field (reordering is off).
  bool get isFiltered => filter != DownloadFilter.all || query.trim().isNotEmpty;

  bool _matches(DownloadItem i) =>
      (filter == DownloadFilter.all || i.kind == filter) &&
      (query.trim().isEmpty || i.name.toLowerCase().contains(query.trim().toLowerCase()));

  List<DownloadItem> get visibleActive => active.where(_matches).toList();
  List<DownloadItem> get visibleCompleted => completed.where(_matches).toList();

  DownloadsState copyWith({
    List<DownloadItem>? active,
    List<DownloadItem>? completed,
    int? totalSize,
    int? downloadedSize,
    int? bytesPerSecond,
    DownloadFilter? filter,
    String? query,
    bool? loading,
    bool? hasMoreCompleted,
  }) => DownloadsState(
    active: active ?? this.active,
    completed: completed ?? this.completed,
    totalSize: totalSize ?? this.totalSize,
    downloadedSize: downloadedSize ?? this.downloadedSize,
    bytesPerSecond: bytesPerSecond ?? this.bytesPerSecond,
    filter: filter ?? this.filter,
    query: query ?? this.query,
    loading: loading ?? this.loading,
    hasMoreCompleted: hasMoreCompleted ?? this.hasMoreCompleted,
  );
}

/// The Downloads screen's model: a mirror of TDLib's download list kept
/// current by its updates, plus totals, speed, filters and priorities.
class DownloadsCubit extends Cubit<DownloadsState> {
  DownloadsCubit({required DownloadsRepository repository, required this._files, DateTime Function()? now})
    : _repo = repository,
      _now = now ?? DateTime.now,
      super(const DownloadsState());

  final DownloadsRepository _repo;
  final FileStore _files;
  final DateTime Function() _now;
  StreamSubscription<td.Update>? _updates;
  String _completedOffset = '';
  final _progress = <int, (int, DateTime)>{};
  final _rates = <int, double>{};

  Future<void> start() async {
    _updates ??= _repo.updates.listen(_onUpdate);
    await _sync();
  }

  Future<void> _sync() async {
    try {
      final active = await _repo.search(onlyActive: true, limit: 100);
      final done = await _repo.search(onlyCompleted: true, limit: 30);
      _completedOffset = done.nextOffset;
      if (isClosed) return;
      emit(
        state.copyWith(
          active: [for (final d in active.files) _withFile(DownloadItem.of(d))],
          completed: [for (final d in done.files) _withFile(DownloadItem.of(d))],
          hasMoreCompleted: done.nextOffset.isNotEmpty,
          loading: false,
        ),
      );
    } on Exception {
      if (!isClosed) emit(state.copyWith(loading: false));
    }
  }

  DownloadItem _withFile(DownloadItem i) {
    final f = _files[i.fileId];
    return f == null ? i : i.copyWith(file: f);
  }

  Future<void> loadMoreCompleted() async {
    if (!state.hasMoreCompleted) return;
    final page = await _repo.search(onlyCompleted: true, offset: _completedOffset, limit: 30);
    _completedOffset = page.nextOffset;
    final known = {for (final i in state.completed) i.fileId};
    emit(
      state.copyWith(
        completed: [
          ...state.completed,
          for (final d in page.files)
            if (!known.contains(d.fileId)) _withFile(DownloadItem.of(d)),
        ],
        hasMoreCompleted: page.nextOffset.isNotEmpty,
      ),
    );
  }

  void _onUpdate(td.Update u) {
    if (isClosed) return;
    switch (u) {
      case td.UpdateFileAddedToDownloads(:final fileDownload):
        final item = _withFile(DownloadItem.of(fileDownload));
        final active = state.active.where((i) => i.fileId != item.fileId).toList();
        final completed = state.completed.where((i) => i.fileId != item.fileId).toList();
        emit(
          item.isCompleted
              ? state.copyWith(active: active, completed: [item, ...completed])
              : state.copyWith(active: [item, ...active], completed: completed),
        );
      case td.UpdateFileDownload(:final fileId, :final completeDate, :final isPaused):
        final index = state.active.indexWhere((i) => i.fileId == fileId);
        if (index >= 0) {
          final item = state.active[index].copyWith(completeDate: completeDate, isPaused: isPaused);
          final active = [...state.active]..removeAt(index);
          if (item.isCompleted) {
            _progress.remove(fileId);
            _rates.remove(fileId);
            emit(state.copyWith(active: active, completed: [item, ...state.completed]));
          } else {
            active.insert(index, item);
            emit(state.copyWith(active: active));
          }
        } else {
          emit(
            state.copyWith(
              completed: [
                for (final i in state.completed)
                  i.fileId == fileId ? i.copyWith(completeDate: completeDate, isPaused: isPaused) : i,
              ],
            ),
          );
        }
      case td.UpdateFileRemovedFromDownloads(:final fileId):
        _progress.remove(fileId);
        _rates.remove(fileId);
        emit(
          state.copyWith(
            active: state.active.where((i) => i.fileId != fileId).toList(),
            completed: state.completed.where((i) => i.fileId != fileId).toList(),
          ),
        );
      case td.UpdateFileDownloads(:final totalSize, :final downloadedSize):
        emit(state.copyWith(totalSize: totalSize, downloadedSize: downloadedSize));
      case td.UpdateFile(:final file):
        _onFile(file);
      default:
        break;
    }
  }

  void _onFile(td.File f) {
    final inActive = state.active.indexWhere((i) => i.fileId == f.id);
    final inCompleted = state.completed.indexWhere((i) => i.fileId == f.id);
    if (inActive < 0 && inCompleted < 0) return;
    var speed = state.bytesPerSecond;
    if (inActive >= 0) {
      final now = _now();
      final bytes = f.local.downloadedSize;
      final prev = _progress[f.id];
      _progress[f.id] = (bytes, now);
      if (prev != null) {
        final dt = now.difference(prev.$2).inMicroseconds / 1e6;
        if (dt > 0) _rates[f.id] = (bytes - prev.$1).clamp(0, 1 << 40) / dt;
      }
      if (!f.local.isDownloadingActive) _rates.remove(f.id);
      final instant = _rates.values.fold(0.0, (s, r) => s + r);
      speed = (0.3 * instant + 0.7 * state.bytesPerSecond).round();
    }
    emit(
      state.copyWith(
        active: inActive < 0
            ? null
            : ([...state.active]..[inActive] = state.active[inActive].copyWith(file: f)),
        completed: inCompleted < 0
            ? null
            : ([...state.completed]..[inCompleted] = state.completed[inCompleted].copyWith(file: f)),
        bytesPerSecond: speed,
      ),
    );
  }

  void setFilter(DownloadFilter f) => emit(state.copyWith(filter: f));

  void setQuery(String q) => emit(state.copyWith(query: q));

  Future<void> togglePaused(DownloadItem i) async {
    await _guard(() => _repo.setPaused(i.fileId, !i.isPaused));
  }

  /// Starts a download TDLib stopped (e.g. out of space) again.
  Future<void> retry(DownloadItem i) => _guard(() => _repo.setPriority(i.fileId, 16));

  Future<void> setAllPaused(bool paused) => _guard(() => _repo.setAllPaused(paused));

  Future<void> remove(DownloadItem i, {required bool deleteFile}) async {
    emit(
      state.copyWith(
        active: state.active.where((x) => x.fileId != i.fileId).toList(),
        completed: state.completed.where((x) => x.fileId != i.fileId).toList(),
      ),
    );
    await _guard(() => _repo.remove(i.fileId, deleteFile: deleteFile));
  }

  /// Moves the active item at [oldIndex] so it ends up at [newIndex], then
  /// gives every active item a priority from its place: 32 at the top,
  /// one less per row, never below 1.
  Future<void> reorder(int oldIndex, int newIndex) async {
    final active = [...state.active];
    if (oldIndex < 0 || oldIndex >= active.length) return;
    final item = active.removeAt(oldIndex);
    active.insert(newIndex.clamp(0, active.length), item);
    emit(state.copyWith(active: active));
    await _guard(() async {
      for (var i = 0; i < active.length; i++) {
        await _repo.setPriority(active[i].fileId, (32 - i).clamp(1, 32));
      }
    });
  }

  Future<void> moveToTop(DownloadItem i) async {
    final index = state.active.indexWhere((x) => x.fileId == i.fileId);
    if (index > 0) await reorder(index, 0);
  }

  /// Errors go to the caller (a toast); the list re-syncs from TDLib.
  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on Exception {
      await _sync();
      rethrow;
    }
  }

  @override
  Future<void> close() async {
    await _updates?.cancel();
    return super.close();
  }
}
