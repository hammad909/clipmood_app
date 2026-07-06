import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import '../theme/app_theme.dart';
import '../utils/time_formatter.dart';
import 'clip_preview_screen.dart';

enum _SortMode { newest, oldest, largest, smallest, nameAz }

extension on _SortMode {
  String get label {
    switch (this) {
      case _SortMode.newest:
        return 'Newest first';
      case _SortMode.oldest:
        return 'Oldest first';
      case _SortMode.largest:
        return 'Largest size';
      case _SortMode.smallest:
        return 'Smallest size';
      case _SortMode.nameAz:
        return 'Name (A–Z)';
    }
  }

  IconData get icon {
    switch (this) {
      case _SortMode.newest:
        return Icons.schedule;
      case _SortMode.oldest:
        return Icons.history;
      case _SortMode.largest:
        return Icons.arrow_upward;
      case _SortMode.smallest:
        return Icons.arrow_downward;
      case _SortMode.nameAz:
        return Icons.sort_by_alpha;
    }
  }
}

class SavedClipsScreen extends StatefulWidget {
  const SavedClipsScreen({super.key});

  @override
  State<SavedClipsScreen> createState() => _SavedClipsScreenState();
}

class _SavedClipsScreenState extends State<SavedClipsScreen> {
  bool _isLoading = true;
  bool _hasError = false;
  List<File> _clips = [];

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  _SortMode _sortMode = _SortMode.newest;

  bool _isSelectionMode = false;
  final Set<String> _selectedPaths = {};
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
    _loadSavedClips();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedClips() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final clipsDir = Directory('${docsDir.path}/clips');

      if (!await clipsDir.exists()) {
        await clipsDir.create(recursive: true);
      }

      final files = clipsDir
          .listSync()
          .whereType<File>()
          .where((file) => file.path.toLowerCase().endsWith('.mp4'))
          .toList();

      if (!mounted) return;

      setState(() {
        _clips = files;
        _isLoading = false;
        _selectedPaths.removeWhere(
          (path) => !files.any((f) => f.path == path),
        );
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _clips = [];
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  List<File> get _visibleClips {
    var clips = _clips;

    if (_searchQuery.isNotEmpty) {
      clips = clips
          .where((f) => _cleanFileName(f.path).toLowerCase().contains(_searchQuery))
          .toList();
    } else {
      clips = List.of(clips);
    }

    switch (_sortMode) {
      case _SortMode.newest:
        clips.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
        break;
      case _SortMode.oldest:
        clips.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
        break;
      case _SortMode.largest:
        clips.sort((a, b) => b.lengthSync().compareTo(a.lengthSync()));
        break;
      case _SortMode.smallest:
        clips.sort((a, b) => a.lengthSync().compareTo(b.lengthSync()));
        break;
      case _SortMode.nameAz:
        clips.sort((a, b) =>
            _cleanFileName(a.path).toLowerCase().compareTo(_cleanFileName(b.path).toLowerCase()));
        break;
    }

    return clips;
  }

  int get _totalBytes => _clips.fold<int>(0, (sum, f) => sum + f.lengthSync());

  void _toggleSelectionMode([bool? value]) {
    setState(() {
      _isSelectionMode = value ?? !_isSelectionMode;
      if (!_isSelectionMode) _selectedPaths.clear();
    });
  }

  void _toggleSelected(File clip) {
    setState(() {
      if (_selectedPaths.contains(clip.path)) {
        _selectedPaths.remove(clip.path);
      } else {
        _selectedPaths.add(clip.path);
      }
    });
  }

  Future<void> _shareClip(File clip) async {
    if (!await clip.exists()) return;

    await SharePlus.instance.share(
      ShareParams(
        text: 'Check out this clip created with ClipMood.',
        files: [XFile(clip.path)],
      ),
    );
  }

  Future<void> _shareSelected() async {
    final selected = _clips.where((c) => _selectedPaths.contains(c.path)).toList();
    if (selected.isEmpty) return;

    await SharePlus.instance.share(
      ShareParams(
        text: 'Check out these clips created with ClipMood.',
        files: selected.map((c) => XFile(c.path)).toList(),
      ),
    );
  }

  Future<void> _deleteClip(File clip) async {
    final shouldDelete = await _confirmDelete(
      message: 'This will delete:\n${_cleanFileName(clip.path)}',
    );

    if (shouldDelete != true) return;

    try {
      if (await clip.exists()) {
        await clip.delete();
      }

      await _loadSavedClips();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Clip deleted.')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete clip: $e')),
      );
    }
  }

  Future<void> _deleteSelected() async {
    final selected = _clips.where((c) => _selectedPaths.contains(c.path)).toList();
    if (selected.isEmpty || _isBusy) return;

    final shouldDelete = await _confirmDelete(
      message: 'Delete ${selected.length} selected clip${selected.length == 1 ? '' : 's'}? '
          'This cannot be undone.',
    );

    if (shouldDelete != true) return;

    setState(() => _isBusy = true);

    var failedCount = 0;

    for (final clip in selected) {
      try {
        if (await clip.exists()) {
          await clip.delete();
        }
      } catch (_) {
        failedCount++;
      }
    }

    if (!mounted) return;

    setState(() {
      _isBusy = false;
      _isSelectionMode = false;
      _selectedPaths.clear();
    });

    await _loadSavedClips();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failedCount == 0
              ? 'Deleted ${selected.length} clip${selected.length == 1 ? '' : 's'}.'
              : 'Deleted ${selected.length - failedCount} clip(s). $failedCount failed.',
        ),
      ),
    );
  }

  Future<bool?> _confirmDelete({required String message}) {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.surfaceElevated,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.lgRadius),
          title: const Text('Delete clip?'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  void _openClip(File clip) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => ClipPreviewScreen(clipPath: clip.path),
          ),
        )
        .then((_) => _loadSavedClips());
  }

  String _cleanFileName(String path) {
    final name = path.split(Platform.pathSeparator).last;
    return name.replaceAll('.mp4', '').replaceAll('_', ' ');
  }

  String _fileSize(File file) {
    final bytes = file.lengthSync();
    return _formatBytes(bytes);
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';

    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';

    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';

    final gb = mb / 1024;
    return '${gb.toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isSelectionMode ? '${_selectedPaths.length} selected' : 'Saved Clips'),
        leading: _isSelectionMode
            ? IconButton(
                tooltip: 'Cancel',
                onPressed: _isBusy ? null : () => _toggleSelectionMode(false),
                icon: const Icon(Icons.close),
              )
            : null,
        actions: _isSelectionMode
            ? [
                IconButton(
                  tooltip: 'Share selected',
                  onPressed: _selectedPaths.isEmpty || _isBusy ? null : _shareSelected,
                  icon: const Icon(Icons.share),
                ),
                IconButton(
                  tooltip: 'Delete selected',
                  onPressed: _selectedPaths.isEmpty || _isBusy ? null : _deleteSelected,
                  icon: const Icon(Icons.delete_outline, color: AppColors.error),
                ),
                const SizedBox(width: AppSpacing.xs),
              ]
            : [
                if (_clips.isNotEmpty)
                  IconButton(
                    tooltip: 'Select clips',
                    onPressed: () => _toggleSelectionMode(true),
                    icon: const Icon(Icons.checklist),
                  ),
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: _isLoading ? null : _loadSavedClips,
                  icon: const Icon(Icons.refresh),
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadSavedClips,
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return _buildLoadingState();
    }

    if (_hasError) {
      return _buildErrorState();
    }

    if (_clips.isEmpty) {
      return _buildEmptyState();
    }

    final visible = _visibleClips;

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              0,
            ),
            child: _buildSummaryCard(),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              0,
            ),
            child: _buildToolsRow(),
          ),
        ),
        if (visible.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: _NoSearchResultsState(),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.xl,
            ),
            sliver: SliverLayoutBuilder(
              builder: (context, constraints) {
                final crossExtent = constraints.crossAxisExtent;
                final maxTileWidth = crossExtent > 700 ? 210.0 : 175.0;

                return SliverGrid(
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: maxTileWidth,
                    mainAxisSpacing: AppSpacing.md,
                    crossAxisSpacing: AppSpacing.md,
                    mainAxisExtent: 268,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final clip = visible[index];

                      return _SavedClipCard(
                        clip: clip,
                        title: _cleanFileName(clip.path),
                        size: _fileSize(clip),
                        selectionMode: _isSelectionMode,
                        selected: _selectedPaths.contains(clip.path),
                        onOpen: () => _openClip(clip),
                        onShare: () => _shareClip(clip),
                        onDelete: () => _deleteClip(clip),
                        onToggleSelected: () => _toggleSelected(clip),
                        onLongPress: () {
                          if (!_isSelectionMode) {
                            _toggleSelectionMode(true);
                          }
                          _toggleSelected(clip);
                        },
                      );
                    },
                    childCount: visible.length,
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        borderRadius: AppRadius.xlRadius,
        gradient: AppGradients.headerCard(context),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.18),
              borderRadius: AppRadius.mdRadius,
            ),
            child: Icon(
              Icons.video_library,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_clips.length} clip${_clips.length == 1 ? '' : 's'} saved',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  'Using ${_formatBytes(_totalBytes)} of storage',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolsRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search clips by name',
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: _searchQuery.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () => _searchController.clear(),
                  ),
            isDense: true,
            filled: true,
            fillColor: AppColors.cardBackgroundSubtle,
            border: OutlineInputBorder(
              borderRadius: AppRadius.mdRadius,
              borderSide: BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: AppRadius.mdRadius,
              borderSide: BorderSide(color: AppColors.border),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: Text(
                _searchQuery.isEmpty
                    ? '${_clips.length} clip${_clips.length == 1 ? '' : 's'}'
                    : '${_visibleClips.length} match${_visibleClips.length == 1 ? '' : 'es'}',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
            PopupMenuButton<_SortMode>(
              initialValue: _sortMode,
              onSelected: (mode) => setState(() => _sortMode = mode),
              itemBuilder: (context) => _SortMode.values.map((mode) {
                return PopupMenuItem<_SortMode>(
                  value: mode,
                  child: Row(
                    children: [
                      Icon(mode.icon, size: 18, color: AppColors.textSecondary),
                      const SizedBox(width: AppSpacing.sm),
                      Text(mode.label),
                    ],
                  ),
                );
              }).toList(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: AppColors.cardBackgroundSubtle,
                  borderRadius: AppRadius.pillRadius,
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_sortMode.icon, size: 16, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Text(
                      _sortMode.label,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_drop_down, size: 18, color: AppColors.textSecondary),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (_isSelectionMode) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isBusy
                      ? null
                      : () {
                          setState(() {
                            if (_selectedPaths.length == _visibleClips.length) {
                              _selectedPaths.clear();
                            } else {
                              _selectedPaths
                                ..clear()
                                ..addAll(_visibleClips.map((c) => c.path));
                            }
                          });
                        },
                  icon: const Icon(Icons.select_all, size: 18),
                  label: Text(
                    _selectedPaths.length == _visibleClips.length && _visibleClips.isNotEmpty
                        ? 'Deselect All'
                        : 'Select All',
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildLoadingState() {
    return GridView.builder(
      padding: const EdgeInsets.all(AppSpacing.lg),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 175,
        mainAxisSpacing: AppSpacing.md,
        crossAxisSpacing: AppSpacing.md,
        mainAxisExtent: 268,
      ),
      itemCount: 6,
      itemBuilder: (context, index) => const _SkeletonCard(),
    );
  }

  Widget _buildErrorState() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xxl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 52,
                      color: AppColors.error,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    const Text(
                      'Couldn\'t load your clips',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    const Text(
                      'Something went wrong while reading your saved clips folder.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textMuted, height: 1.35),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    FilledButton.icon(
                      onPressed: _loadSavedClips,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try Again'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xxl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 76,
                      height: 76,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.cardBackground,
                      ),
                      child: const Icon(
                        Icons.video_collection_outlined,
                        size: 34,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    const Text(
                      'No saved clips yet',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    const Text(
                      'Create a clip from the video editor and it will show up here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 14,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NoSearchResultsState extends StatelessWidget {
  const _NoSearchResultsState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.search_off,
              size: 48,
              color: AppColors.textDisabled,
            ),
            const SizedBox(height: AppSpacing.md),
            const Text(
              'No clips match your search',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Try a different name or clear the search field.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkeletonCard extends StatefulWidget {
  const _SkeletonCard();

  @override
  State<_SkeletonCard> createState() => _SkeletonCardState();
}

class _SkeletonCardState extends State<_SkeletonCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final opacity = 0.35 + (_controller.value * 0.25);

        return Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: AppRadius.lgRadius,
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.cardBackgroundSubtle.withValues(alpha: opacity),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 12,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: AppColors.cardBackgroundSubtle.withValues(alpha: opacity),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 10,
                      width: 60,
                      decoration: BoxDecoration(
                        color: AppColors.cardBackgroundSubtle.withValues(alpha: opacity),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SavedClipCard extends StatefulWidget {
  final File clip;
  final String title;
  final String size;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onOpen;
  final VoidCallback onShare;
  final VoidCallback onDelete;
  final VoidCallback onToggleSelected;
  final VoidCallback onLongPress;

  const _SavedClipCard({
    required this.clip,
    required this.title,
    required this.size,
    required this.selectionMode,
    required this.selected,
    required this.onOpen,
    required this.onShare,
    required this.onDelete,
    required this.onToggleSelected,
    required this.onLongPress,
  });

  @override
  State<_SavedClipCard> createState() => _SavedClipCardState();
}

enum _ThumbnailStatus { loading, ready, failed }

class _SavedClipCardState extends State<_SavedClipCard> {
  VideoPlayerController? _controller;
  _ThumbnailStatus _status = _ThumbnailStatus.loading;

  @override
  void initState() {
    super.initState();
    _setupPreview();
  }

  Future<void> _setupPreview() async {
    try {
      final controller = VideoPlayerController.file(widget.clip);
      await controller.initialize();

      if (!mounted) {
        controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _status = _ThumbnailStatus.ready;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _status = _ThumbnailStatus.failed;
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: AppRadius.lgRadius,
        border: Border.all(
          color: widget.selected ? Theme.of(context).colorScheme.primary : AppColors.border,
          width: widget.selected ? 1.6 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.selectionMode ? widget.onToggleSelected : widget.onOpen,
        onLongPress: widget.onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_status == _ThumbnailStatus.ready && controller != null)
                    FittedBox(
                      fit: BoxFit.cover,
                      clipBehavior: Clip.hardEdge,
                      child: SizedBox(
                        width: controller.value.size.width,
                        height: controller.value.size.height,
                        child: VideoPlayer(controller),
                      ),
                    )
                  else if (_status == _ThumbnailStatus.loading)
                    Container(
                      color: Colors.black,
                      child: const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  else
                    Container(
                      color: Colors.black,
                      child: const Center(
                        child: Icon(
                          Icons.broken_image_outlined,
                          size: 28,
                          color: AppColors.textDisabled,
                        ),
                      ),
                    ),
                  Container(color: Colors.black.withValues(alpha: 0.14)),
                  if (!widget.selectionMode && _status == _ThumbnailStatus.ready)
                    const Center(
                      child: Icon(
                        Icons.play_circle_fill,
                        size: 34,
                        color: Colors.white,
                      ),
                    ),
                  if (_status == _ThumbnailStatus.ready && controller != null)
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          TimeFormatter.formatDuration(controller.value.duration),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  if (widget.selectionMode)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: _SelectionDot(selected: widget.selected),
                    ),
                  if (!widget.selectionMode)
                    Positioned(
                      top: 2,
                      right: 2,
                      child: IconButton(
                        tooltip: 'Delete',
                        onPressed: widget.onDelete,
                        icon: const Icon(Icons.delete_outline, size: 18),
                        color: Colors.white,
                        style: IconButton.styleFrom(
                          minimumSize: const Size(32, 32),
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.sm,
                AppSpacing.sm,
                AppSpacing.xs,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.size,
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                        ),
                      ),
                      if (!widget.selectionMode)
                        InkWell(
                          onTap: widget.onShare,
                          borderRadius: BorderRadius.circular(20),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.share, size: 15, color: AppColors.textSecondary),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectionDot extends StatelessWidget {
  final bool selected;

  const _SelectionDot({required this.selected});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? Theme.of(context).colorScheme.primary : Colors.black.withValues(alpha: 0.45),
        border: Border.all(color: Colors.white, width: 1.4),
      ),
      child: selected
          ? const Icon(Icons.check, size: 14, color: Colors.white)
          : null,
    );
  }
}