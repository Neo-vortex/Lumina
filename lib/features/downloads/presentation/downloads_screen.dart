import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:open_filex/open_filex.dart';

import '../../../core/telegram/display.dart';
import '../../../core/theme/glow_colors.dart';
import '../../../core/widgets/glow_button.dart';
import '../../../core/widgets/glow_sheet.dart';
import '../bloc/downloads_cubit.dart';
import '../data/download_policy.dart';
import 'download_row.dart';
import '../../../core/widgets/smooth_progress.dart';

typedef OpenMessage = void Function(BuildContext context, int chatId, int messageId);

/// Every download over 1 MB: progress, pause/resume, priorities by order,
/// filters and search, Wi-Fi only; finished files open with a tap.
class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key, required this.openMessage});

  final OpenMessage openMessage;

  static Route<void> route({required OpenMessage openMessage}) => MaterialPageRoute(
    builder: (_) => _Visible(child: DownloadsScreen(openMessage: openMessage)),
  );

  void _toast(BuildContext context, String text) =>
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));

  Future<void> _run(BuildContext context, Future<void> Function() action) async {
    try {
      await action();
    } on Exception {
      if (context.mounted) _toast(context, 'Couldn’t update the download');
    }
  }

  Future<void> _open(BuildContext context, DownloadItem i) async {
    final path = i.file?.local.path ?? '';
    if (path.isEmpty) return;
    final result = await OpenFilex.open(path);
    if (result.type != ResultType.done && context.mounted) {
      _toast(context, 'No app can open this file (${result.message})');
    }
  }

  void _toggle(BuildContext context, DownloadItem i) {
    final policy = context.read<DownloadPolicy>();
    final cubit = context.read<DownloadsCubit>();
    if (policy.isWaitingForWifi(i.fileId)) {
      // Already paused by Lumina; now the user wants it to stay paused.
      policy.userPaused(i.fileId);
      return;
    }
    if (i.isPaused) policy.userResumed(i.fileId).ignore();
    _run(context, () => cubit.togglePaused(i));
  }

  Future<bool> _confirmRemove(BuildContext context, DownloadItem i) async {
    final picked = await showGlowSheet<bool>(
      context,
      title: 'Remove from downloads?',
      builder: (sheet) => _RemoveSheet(name: i.name),
    );
    if (picked == null || !context.mounted) return false;
    await _run(context, () => context.read<DownloadsCubit>().remove(i, deleteFile: picked));
    return true;
  }

  Future<void> _actions(BuildContext context, DownloadItem i) async {
    final policy = context.read<DownloadPolicy>();
    final cubit = context.read<DownloadsCubit>();
    await showGlowSheet<void>(
      context,
      title: i.name,
      builder: (sheet) => ListenableBuilder(
        listenable: policy.changes,
        builder: (sheet, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!i.isCompleted)
              SwitchListTile(
                secondary: const Icon(Icons.wifi_rounded, color: GlowColors.cyan),
                activeThumbColor: GlowColors.cyan,
                title: const Text('Wi-Fi only'),
                value: policy.isWifiOnly(i.fileId),
                onChanged: (v) async {
                  await policy.setWifiOnly(i.fileId, v);
                  await policy.apply(cubit.state.activeStates);
                },
              ),
            if (!i.isCompleted)
              ListTile(
                leading: const Icon(Icons.vertical_align_top_rounded, color: GlowColors.violet),
                title: const Text('Move to top'),
                onTap: () {
                  Navigator.of(sheet).pop();
                  _run(context, () => cubit.moveToTop(i));
                },
              ),
            ListTile(
              leading: const Icon(Icons.chat_bubble_rounded, color: GlowColors.cyan),
              title: const Text('Open chat'),
              onTap: () {
                Navigator.of(sheet).pop();
                openMessage(context, i.message.chatId, i.message.id);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, DownloadsState state, DownloadItem i, {Widget? dragHandle}) {
    final policy = context.read<DownloadPolicy>();
    return Dismissible(
      key: ValueKey('download-${i.fileId}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: GlowColors.error.withValues(alpha: 0.2),
        child: const Icon(Icons.delete_outline_rounded, color: GlowColors.error),
      ),
      confirmDismiss: (_) => _confirmRemove(context, i),
      child: DownloadRow(
        item: i,
        status: statusOf(i, waitingForWifi: policy.isWaitingForWifi(i.fileId)),
        wifiOnly: policy.isWifiOnly(i.fileId),
        bytesPerSecond: i.isCompleted || i.isPaused ? 0 : state.bytesPerSecond,
        onToggle: () => _toggle(context, i),
        onOpen: () => _open(context, i),
        onOpenChat: () => openMessage(context, i.message.chatId, i.message.id),
        onRetry: () => _run(context, () => context.read<DownloadsCubit>().retry(i)),
        onLongPress: () => _actions(context, i),
        dragHandle: dragHandle,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final policy = context.read<DownloadPolicy>();
    return BlocBuilder<DownloadsCubit, DownloadsState>(
      builder: (context, state) {
        final cubit = context.read<DownloadsCubit>();
        final allPaused = state.active.isNotEmpty && state.active.every((i) => i.isPaused);
        final active = state.visibleActive;
        final completed = state.visibleCompleted;
        final empty = state.active.isEmpty && state.completed.isEmpty && !state.loading;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Downloads'),
            actions: [
              if (state.active.isNotEmpty)
                IconButton(
                  tooltip: allPaused ? 'Resume all' : 'Pause all',
                  icon: Icon(allPaused ? Icons.play_arrow_rounded : Icons.pause_rounded),
                  onPressed: () => _run(context, () => cubit.setAllPaused(!allPaused)),
                ),
            ],
          ),
          body: empty
              ? const _Empty()
              : ListenableBuilder(
                  listenable: policy.changes,
                  builder: (context, _) => CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(child: _Header(state: state)),
                      SliverToBoxAdapter(
                        child: _Search(state: state, cubit: cubit),
                      ),
                      if (active.isNotEmpty) const SliverToBoxAdapter(child: _SectionTitle('Downloading')),
                      if (active.isNotEmpty && !state.isFiltered)
                        SliverReorderableList(
                          itemCount: active.length,
                          onReorder: (from, to) {
                            // Flutter reports the slot before removal.
                            final target = to > from ? to - 1 : to;
                            _run(context, () => cubit.reorder(from, target));
                          },
                          itemBuilder: (context, i) => Material(
                            key: ValueKey('active-${active[i].fileId}'),
                            type: MaterialType.transparency,
                            child: _row(
                              context,
                              state,
                              active[i],
                              dragHandle: ReorderableDragStartListener(
                                index: i,
                                child: const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: Icon(Icons.drag_handle_rounded, color: GlowColors.textMuted),
                                ),
                              ),
                            ),
                          ),
                        )
                      else if (active.isNotEmpty)
                        SliverList.builder(
                          itemCount: active.length,
                          itemBuilder: (context, i) => _row(context, state, active[i]),
                        ),
                      if (completed.isNotEmpty) const SliverToBoxAdapter(child: _SectionTitle('Finished')),
                      SliverList.builder(
                        itemCount: completed.length,
                        itemBuilder: (context, i) {
                          if (i == completed.length - 1 && state.hasMoreCompleted) {
                            WidgetsBinding.instance.addPostFrameCallback((_) => cubit.loadMoreCompleted());
                          }
                          return _row(context, state, completed[i]);
                        },
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 32)),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state});

  final DownloadsState state;

  @override
  Widget build(BuildContext context) {
    if (state.active.isEmpty) return const SizedBox(height: 8);
    final left = (state.totalSize - state.downloadedSize).clamp(0, 1 << 50);
    final progress = state.totalSize > 0 ? (state.downloadedSize / state.totalSize).clamp(0.0, 1.0) : 0.0;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: GlowColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: GlowColors.cyan.withValues(alpha: 0.35)),
        boxShadow: glow(GlowColors.cyan, intensity: 0.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${state.active.length} downloading · ${Display.fileSize(left)} left',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          if (state.bytesPerSecond > 0)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '${Display.fileSize(state.bytesPerSecond)}/s',
                style: const TextStyle(color: GlowColors.textMuted, fontSize: 12),
              ),
            ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SmoothProgress(
              value: progress,
              builder: (context, v) => LinearProgressIndicator(
                value: v,
                minHeight: 6,
                color: GlowColors.cyan,
                backgroundColor: GlowColors.outline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Search extends StatelessWidget {
  const _Search({required this.state, required this.cubit});

  final DownloadsState state;
  final DownloadsCubit cubit;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          onChanged: cubit.setQuery,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search_rounded),
            hintText: 'Search downloads',
            border: InputBorder.none,
          ),
        ),
        Wrap(
          spacing: 8,
          children: [
            for (final f in DownloadFilter.values)
              ChoiceChip(
                label: Text(f.label),
                selected: state.filter == f,
                selectedColor: GlowColors.violet.withValues(alpha: 0.3),
                onSelected: (_) => cubit.setFilter(f),
              ),
          ],
        ),
      ],
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: GlowColors.violet,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
      ),
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.download_for_offline_rounded, size: 56, color: GlowColors.cyan),
          SizedBox(height: 12),
          Text('No downloads yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          SizedBox(height: 6),
          Text(
            'Files over 1 MB you download show up here',
            textAlign: TextAlign.center,
            style: TextStyle(color: GlowColors.textMuted),
          ),
        ],
      ),
    ),
  );
}

class _RemoveSheet extends StatefulWidget {
  const _RemoveSheet({required this.name});

  final String name;

  @override
  State<_RemoveSheet> createState() => _RemoveSheetState();
}

class _RemoveSheetState extends State<_RemoveSheet> {
  var _delete = false;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: GlowColors.textMuted),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          activeColor: GlowColors.error,
          title: const Text('Also delete the file'),
          value: _delete,
          onChanged: (v) => setState(() => _delete = v ?? false),
        ),
        const SizedBox(height: 8),
        GlowButton(label: 'Remove', onPressed: () => Navigator.of(context).pop(_delete)),
      ],
    ),
  );
}

/// Tells the cubit the screen is up, so finished files don't also notify.
class _Visible extends StatefulWidget {
  const _Visible({required this.child});

  final Widget child;

  @override
  State<_Visible> createState() => _VisibleState();
}

class _VisibleState extends State<_Visible> {
  late final DownloadsCubit _cubit = context.read<DownloadsCubit>()..screenShown();

  @override
  void dispose() {
    _cubit.screenHidden();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
