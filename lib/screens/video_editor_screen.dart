import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../models/ai_suggestion.dart';
import '../models/clip_intent.dart';
import '../models/ai_scan_options.dart';
import '../models/ai_scan_progress.dart';
import '../models/selected_video.dart';
import '../services/ai_clip_analyzer_service.dart';
import '../services/ai_scan_cancellation_token.dart';
import '../services/clip_export_service.dart';
import '../theme/app_theme.dart';
import '../utils/time_formatter.dart';
import '../widgets/ai_suggestion_card.dart';
import 'ai_debug_results_screen.dart';
import 'clip_edit_screen.dart';
import 'saved_clips_screen.dart';

class VideoEditorScreen extends StatefulWidget {
  final SelectedVideo video;

  const VideoEditorScreen({
    super.key,
    required this.video,
  });

  @override
  State<VideoEditorScreen> createState() => _VideoEditorScreenState();
}

/// Progress snapshot shown in the batch-save dialog.
class _BatchProgress {
  final int index;
  final int total;
  final double clipProgress;
  final String currentTitle;

  const _BatchProgress({
    required this.index,
    required this.total,
    required this.clipProgress,
    required this.currentTitle,
  });
}

class _VideoEditorScreenState extends State<VideoEditorScreen> {
  VideoPlayerController? _controller;

  final AiClipAnalyzerService _aiAnalyzer = AiClipAnalyzerService();
  final ClipExportService _exportService = ClipExportService();

  bool _isInitialized = false;
  bool _hasError = false;
  bool _isScanning = false;
  AiScanMode _selectedScanMode = AiScanMode.balanced;
  AiScanProgress _scanProgress = const AiScanProgress.idle();
  AiScanCancellationToken? _scanCancellationToken;

  List<AiSuggestion> _suggestions = [];
  List<AiDebugEntry> _debugEntries = [];

  final Set<String> _selectedKeys = {};
  final Set<String> _savingKeys = {};
  bool _isBatchSaving = false;

  @override
  void initState() {
    super.initState();
    _setupVideo();
  }

  Future<void> _setupVideo() async {
    try {
      final controller = VideoPlayerController.file(
        File(widget.video.path),
      );

      await controller.initialize();

      controller.addListener(() {
        if (mounted) {
          setState(() {});
        }
      });

      if (!mounted) {
        controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _isInitialized = true;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _hasError = true;
      });
    }
  }

  String _keyFor(AiSuggestion suggestion) {
    return '${suggestion.title}__${suggestion.startSeconds}__'
        '${suggestion.endSeconds}__${suggestion.mood}';
  }

  Future<void> _scanForAiClips() async {
    if (_isScanning) return;

    final controller = _controller;

    if (controller != null && controller.value.isPlaying) {
      await controller.pause();
    }

    final cancellationToken = AiScanCancellationToken();

    setState(() {
      _isScanning = true;
      _suggestions = [];
      _debugEntries = [];
      _selectedKeys.clear();
      _scanCancellationToken = cancellationToken;
      _scanProgress = AiScanProgress(
        stage: AiScanStage.loadingVideo,
        progress: 0.02,
        message: 'Preparing AI scan...',
        detail: '${_selectedScanMode.label} mode • Auto categories',
      );
    });

    try {
      final result = await _aiAnalyzer.analyzeVideo(
        widget.video.path,
        intent: ClipIntent.general,
        options: AiScanOptions.forMode(_selectedScanMode),
        cancellationToken: cancellationToken,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _scanProgress = progress;
          });
        },
      );

      if (!mounted) return;

      setState(() {
        _suggestions = result.suggestions;
        _debugEntries = result.debugEntries;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Found ${result.suggestions.length} clips across ${_countSections(result.suggestions)} section(s) using ${_selectedScanMode.label} mode.',
          ),
        ),
      );
    } on AiScanCancelledException {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('AI scan cancelled.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load AI suggestions: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isScanning = false;
          _scanCancellationToken = null;
          _scanProgress = const AiScanProgress.idle();
        });
      }
    }
  }

  void _cancelAiScan() {
    _scanCancellationToken?.cancel();
  }

  Future<void> _previewSuggestion(AiSuggestion suggestion) async {
    final controller = _controller;
    if (controller == null) return;

    final start = Duration(seconds: suggestion.startSeconds);

    await controller.seekTo(start);
    await controller.play();
  }

  void _editSuggestion(AiSuggestion suggestion) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ClipEditScreen(
          video: widget.video,
          suggestion: suggestion,
        ),
      ),
    );
  }

  Future<void> _quickSaveSuggestion(AiSuggestion suggestion) async {
    final key = _keyFor(suggestion);
    if (_savingKeys.contains(key) || _isBatchSaving) return;

    setState(() => _savingKeys.add(key));

    try {
      await _exportService.exportClip(
        videoPath: widget.video.path,
        title: suggestion.title,
        startSeconds: suggestion.startSeconds,
        endSeconds: suggestion.endSeconds,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved "${suggestion.title}" to your library.')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save clip: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _savingKeys.remove(key));
      }
    }
  }

  Future<void> _runBatchExport(List<AiSuggestion> suggestions) async {
    if (suggestions.isEmpty || _isBatchSaving) return;

    final controller = _controller;
    if (controller != null && controller.value.isPlaying) {
      await controller.pause();
    }

    final progressNotifier = ValueNotifier<_BatchProgress>(
      _BatchProgress(
        index: 0,
        total: suggestions.length,
        clipProgress: 0.0,
        currentTitle: suggestions.first.title,
      ),
    );

    setState(() => _isBatchSaving = true);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _BatchSaveProgressDialog(progress: progressNotifier),
    );

    final results = await _exportService.exportSuggestions(
      videoPath: widget.video.path,
      suggestions: suggestions,
      onProgress: (index, total, clipProgress) {
        progressNotifier.value = _BatchProgress(
          index: index,
          total: total,
          clipProgress: clipProgress,
          currentTitle: suggestions[index].title,
        );
      },
    );

    progressNotifier.dispose();

    if (!mounted) return;

    Navigator.of(context, rootNavigator: true).pop();

    final successCount = results.where((r) => r.isSuccess).length;
    final failedCount = results.length - successCount;

    setState(() {
      _isBatchSaving = false;
      _selectedKeys.clear();
    });

    await _showBatchResultDialog(
      successCount: successCount,
      failedCount: failedCount,
    );
  }

  Future<void> _showBatchResultDialog({
    required int successCount,
    required int failedCount,
  }) async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.surfaceElevated,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.lgRadius),
          title: Row(
            children: [
              Icon(
                failedCount == 0 ? Icons.check_circle : Icons.info_outline,
                color: failedCount == 0 ? AppColors.success : AppColors.warning,
              ),
              const SizedBox(width: AppSpacing.sm),
              const Text('Save Complete'),
            ],
          ),
          content: Text(
            failedCount == 0
                ? 'Saved $successCount clip${successCount == 1 ? '' : 's'} to your library.'
                : 'Saved $successCount clip${successCount == 1 ? '' : 's'}. '
                    '$failedCount failed to export.',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Done'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SavedClipsScreen()),
                );
              },
              child: const Text('View Saved Clips'),
            ),
          ],
        );
      },
    );
  }

  void _openAiDebugResults() {
    if (_debugEntries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Scan a video first to view AI debug results.'),
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AiDebugResultsScreen(entries: _debugEntries),
      ),
    );
  }

  @override
  void dispose() {
    _scanCancellationToken?.cancel();
    _aiAnalyzer.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Video Editor'),
        actions: [
          IconButton(
            tooltip: 'Saved Clips',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const SavedClipsScreen(),
                ),
              );
            },
            icon: const Icon(Icons.video_library),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: SafeArea(
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_hasError) {
      return const Center(
        child: Text(
          'Could not load this video.',
          style: TextStyle(color: AppColors.error),
        ),
      );
    }

    final controller = _controller;

    if (!_isInitialized || controller == null) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final double maxVideoHeight = constraints.maxHeight * 0.38;

        return Column(
          children: [
            Container(
              width: double.infinity,
              height: maxVideoHeight,
              color: Colors.black,
              child: Center(
                child: AspectRatio(
                  aspectRatio: controller.value.aspectRatio,
                  child: VideoPlayer(controller),
                ),
              ),
            ),

            const SizedBox(height: AppSpacing.sm),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Row(
                children: [
                  Text(
                    TimeFormatter.formatDuration(controller.value.position),
                    style: const TextStyle(fontSize: 13),
                  ),
                  Expanded(
                    child: VideoProgressIndicator(
                      controller,
                      allowScrubbing: true,
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    ),
                  ),
                  Text(
                    TimeFormatter.formatDuration(controller.value.duration),
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.sm),

            _buildScanModeSelector(),

            const SizedBox(height: AppSpacing.sm),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.sm,
                children: [
                  IconButton.filled(
                    iconSize: 32,
                    onPressed: () {
                      setState(() {
                        if (controller.value.isPlaying) {
                          controller.pause();
                        } else {
                          controller.play();
                        }
                      });
                    },
                    icon: Icon(
                      controller.value.isPlaying
                          ? Icons.pause
                          : Icons.play_arrow,
                    ),
                  ),

                  FilledButton.icon(
                    onPressed: _isScanning ? null : _scanForAiClips,
                    icon: _isScanning
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome),
                    label: Text(
                      _isScanning
                          ? 'Scanning...'
                          : 'Scan All Clip Types',
                    ),
                  ),

                  OutlinedButton.icon(
                    onPressed: _debugEntries.isEmpty || _isScanning
                        ? null
                        : _openAiDebugResults,
                    icon: const Icon(Icons.bug_report),
                    label: const Text('AI Debug'),
                  ),

                  if (_isScanning)
                    OutlinedButton.icon(
                      onPressed: _scanProgress.canCancel ? _cancelAiScan : null,
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: const Text('Cancel'),
                    ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.sm),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Text(
                widget.video.name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            const SizedBox(height: AppSpacing.sm),

            Expanded(
              child: _buildSuggestionsArea(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildScanModeSelector() {
    return SizedBox(
      height: 82,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Row(
              children: [
                const Icon(Icons.speed, size: 18, color: AppColors.textSecondary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    _selectedScanMode.helperText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              scrollDirection: Axis.horizontal,
              itemCount: AiScanMode.values.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
              itemBuilder: (context, index) {
                final mode = AiScanMode.values[index];
                final selected = mode == _selectedScanMode;

                return ChoiceChip(
                  avatar: Icon(
                    _iconForScanMode(mode),
                    size: 18,
                    color: selected ? null : AppColors.textSecondary,
                  ),
                  selected: selected,
                  label: Text(mode.label),
                  onSelected: _isScanning
                      ? null
                      : (value) {
                          if (!value) return;
                          setState(() {
                            _selectedScanMode = mode;
                            _suggestions = [];
                            _debugEntries = [];
                            _selectedKeys.clear();
                          });
                        },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconForScanMode(AiScanMode mode) {
    switch (mode) {
      case AiScanMode.fast:
        return Icons.flash_on;
      case AiScanMode.balanced:
        return Icons.balance;
      case AiScanMode.accurate:
        return Icons.workspace_premium;
    }
  }

  Widget _buildScanProgressPanel() {
    final progress = _scanProgress.progress <= 0 || _scanProgress.progress >= 1
        ? null
        : _scanProgress.progress;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: progress),
              const SizedBox(height: AppSpacing.xl),
              Text(
                _scanProgress.stage.label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                _scanProgress.message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 15,
                ),
              ),
              if (_scanProgress.detail != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _scanProgress.detail!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textFaint,
                    fontSize: 13,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              OutlinedButton.icon(
                onPressed: _scanProgress.canCancel ? _cancelAiScan : null,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Cancel Scan'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestionsArea() {
    if (_isScanning) {
      return _buildScanProgressPanel();
    }

    if (_suggestions.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.xxl),
          child: Text(
            'No AI suggestions yet.\nChoose a clip type, then tap scan.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 15,
            ),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'AI Clip Sections',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (_debugEntries.isNotEmpty)
              TextButton.icon(
                onPressed: _openAiDebugResults,
                icon: const Icon(Icons.bug_report, size: 18),
                label: Text('${_debugEntries.length} signals'),
              ),
          ],
        ),

        const SizedBox(height: AppSpacing.md),

        _buildSelectionToolbar(),

        const SizedBox(height: AppSpacing.sm),

        ..._buildSuggestionSections(),
      ],
    );
  }

  Widget _buildSelectionToolbar() {
    final allSelected =
        _suggestions.isNotEmpty && _selectedKeys.length == _suggestions.length;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.cardBackgroundSubtle,
        borderRadius: AppRadius.lgRadius,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _selectedKeys.isEmpty
                      ? '${_suggestions.length} clip${_suggestions.length == 1 ? '' : 's'} found'
                      : '${_selectedKeys.length} selected',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
              TextButton(
                onPressed: _isBatchSaving
                    ? null
                    : () {
                        setState(() {
                          if (allSelected) {
                            _selectedKeys.clear();
                          } else {
                            _selectedKeys
                              ..clear()
                              ..addAll(_suggestions.map(_keyFor));
                          }
                        });
                      },
                child: Text(allSelected ? 'Deselect All' : 'Select All'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isBatchSaving || _selectedKeys.isEmpty
                      ? null
                      : () => _runBatchExport(
                            _suggestions
                                .where((s) => _selectedKeys.contains(_keyFor(s)))
                                .toList(),
                          ),
                  icon: const Icon(Icons.playlist_add_check, size: 18),
                  label: Text(
                    'Save Selected'
                    '${_selectedKeys.isEmpty ? '' : ' (${_selectedKeys.length})'}',
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _isBatchSaving || _suggestions.isEmpty
                      ? null
                      : () => _runBatchExport(_suggestions),
                  icon: const Icon(Icons.save, size: 18),
                  label: const Text('Save All'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  int _countSections(List<AiSuggestion> suggestions) {
    return suggestions.map((suggestion) => _ClipSection.fromMood(suggestion.mood).label).toSet().length;
  }

  List<Widget> _buildSuggestionSections() {
    final grouped = <_ClipSection, List<AiSuggestion>>{};

    for (final suggestion in _suggestions) {
      final section = _ClipSection.fromMood(suggestion.mood);
      grouped.putIfAbsent(section, () => []).add(suggestion);
    }

    final sections = grouped.keys.toList()
      ..sort((a, b) => a.order.compareTo(b.order));

    final widgets = <Widget>[];

    for (final section in sections) {
      final suggestions = grouped[section]!..sort(
        (a, b) {
          final startCompare = a.startSeconds.compareTo(b.startSeconds);
          if (startCompare != 0) return startCompare;
          return b.confidence.compareTo(a.confidence);
        },
      );

      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.sm),
          child: Row(
            children: [
              Icon(section.icon, size: 20, color: AppColors.textSecondary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '${section.label} (${suggestions.length})',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      );

      widgets.addAll(
        suggestions.map((suggestion) {
          final key = _keyFor(suggestion);

          return AiSuggestionCard(
            suggestion: suggestion,
            selected: _selectedKeys.contains(key),
            isSaving: _savingKeys.contains(key) || _isBatchSaving,
            onSelectedChanged: (value) {
              setState(() {
                if (value) {
                  _selectedKeys.add(key);
                } else {
                  _selectedKeys.remove(key);
                }
              });
            },
            onPreview: () => _previewSuggestion(suggestion),
            onEdit: () => _editSuggestion(suggestion),
            onQuickSave: () => _quickSaveSuggestion(suggestion),
          );
        }),
      );
    }

    return widgets;
  }
}

class _BatchSaveProgressDialog extends StatelessWidget {
  final ValueNotifier<_BatchProgress> progress;

  const _BatchSaveProgressDialog({required this.progress});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.lgRadius),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: ValueListenableBuilder<_BatchProgress>(
            valueListenable: progress,
            builder: (context, value, _) {
              final overall = value.total == 0
                  ? 0.0
                  : (value.index + value.clipProgress) / value.total;

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Saving Clips',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Clip ${value.index + 1} of ${value.total}',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ClipRRect(
                    borderRadius: AppRadius.pillRadius,
                    child: LinearProgressIndicator(
                      value: overall.clamp(0.0, 1.0),
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    value.currentTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ClipSection {
  final String label;
  final IconData icon;
  final int order;

  const _ClipSection({
    required this.label,
    required this.icon,
    required this.order,
  });

  static _ClipSection fromMood(String mood) {
    switch (mood.toLowerCase()) {
      case 'funny':
        return const _ClipSection(label: 'Funny', icon: Icons.sentiment_very_satisfied, order: 0);
      case 'sad':
        return const _ClipSection(label: 'Sad', icon: Icons.sentiment_dissatisfied, order: 1);
      case 'emotional':
        return const _ClipSection(label: 'Emotional', icon: Icons.favorite, order: 2);
      case 'action':
        return const _ClipSection(label: 'Action', icon: Icons.bolt, order: 3);
      case 'reaction':
        return const _ClipSection(label: 'Reaction', icon: Icons.face_retouching_natural, order: 4);
      case 'hook':
        return const _ClipSection(label: 'Hooks / Quotes', icon: Icons.format_quote, order: 5);
      case 'info':
      case 'informative':
      case 'information':
        return const _ClipSection(label: 'Informative', icon: Icons.lightbulb_outline, order: 6);
      case 'music':
      case 'exciting':
        return const _ClipSection(label: 'Music / Edit', icon: Icons.music_note, order: 7);
      case 'viral':
        return const _ClipSection(label: 'High Energy', icon: Icons.local_fire_department, order: 8);
      case 'weird':
      case 'strange':
        return const _ClipSection(label: 'Weird / Unexpected', icon: Icons.psychology_alt, order: 9);
      default:
        return const _ClipSection(label: 'Highlights', icon: Icons.auto_awesome, order: 10);
    }
  }

  @override
  bool operator ==(Object other) {
    return other is _ClipSection && other.label == label;
  }

  @override
  int get hashCode => label.hashCode;
}