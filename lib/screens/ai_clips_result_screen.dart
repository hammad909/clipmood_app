import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../models/ai_suggestion.dart';
import '../models/selected_video.dart';
import '../services/ad_service.dart';
import '../services/clip_export_service.dart';
import '../theme/app_theme.dart';
import '../utils/time_formatter.dart';
import '../widgets/ai_suggestion_card.dart';
import '../widgets/app_loading_indicator.dart';
import '../widgets/free_banner_ad.dart';
import 'clip_edit_screen.dart';
import 'manual_trim_screen.dart';
import 'saved_clips_screen.dart';

class AiClipsResultScreen extends StatefulWidget {
  final SelectedVideo video;
  final List<AiSuggestion> suggestions;

  const AiClipsResultScreen({
    super.key,
    required this.video,
    required this.suggestions,
  });

  @override
  State<AiClipsResultScreen> createState() => _AiClipsResultScreenState();
}

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

class _AiClipsResultScreenState extends State<AiClipsResultScreen> {
  final ClipExportService _exportService = ClipExportService();

  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;

  String? _previewingKey;
  int? _previewEndSeconds;

  final Set<String> _selectedKeys = {};
  final Set<String> _savingKeys = {};
  bool _isBatchSaving = false;

  @override
  void initState() {
    super.initState();
    _setupVideo();
  }

  Future<void> _setupVideo() async {
    setState(() {
      _hasError = false;
      _isInitialized = false;
    });

    try {
      final controller = VideoPlayerController.file(File(widget.video.path));
      await controller.initialize();
      controller.addListener(_videoListener);

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
      setState(() => _hasError = true);
    }
  }

  void _videoListener() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    final endSeconds = _previewEndSeconds;
    if (endSeconds != null &&
        controller.value.isPlaying &&
        controller.value.position.inSeconds >= endSeconds) {
      controller.pause();
      _previewEndSeconds = null;
      _previewingKey = null;
    }

    if (mounted) setState(() {});
  }

  String _keyFor(AiSuggestion suggestion) {
    return '${suggestion.title}__${suggestion.startSeconds}__'
        '${suggestion.endSeconds}__${suggestion.mood}';
  }

  Future<void> _previewSuggestion(AiSuggestion suggestion) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    _previewEndSeconds = suggestion.endSeconds;
    _previewingKey = _keyFor(suggestion);
    await controller.seekTo(Duration(seconds: suggestion.startSeconds));
    await controller.play();
    if (mounted) setState(() {});
  }

  Future<void> _editSuggestion(AiSuggestion suggestion) async {
    await _controller?.pause();
    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ClipEditScreen(
          video: widget.video,
          suggestion: suggestion,
        ),
      ),
    );
  }


  Future<void> _openManualTrim() async {
    await _controller?.pause();
    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ManualTrimScreen(video: widget.video),
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

      AdService.instance.maybeShowInterstitialAfterExport();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save clip: $e')),
      );
    } finally {
      if (mounted) setState(() => _savingKeys.remove(key));
    }
  }

  Future<void> _runBatchExport(List<AiSuggestion> suggestions) async {
    if (suggestions.isEmpty || _isBatchSaving) return;

    await _controller?.pause();

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

    if (successCount > 0) {
      AdService.instance.showInterstitialAfterBatchExport();
    }
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

  @override
  void dispose() {
    _controller?.removeListener(_videoListener);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Eye-Catching Clips'),
            Text(
              '${widget.suggestions.length} clip${widget.suggestions.length == 1 ? '' : 's'} ready for review',
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<_ResultMenuAction>(
            tooltip: 'More actions',
            onSelected: (action) {
              switch (action) {
                case _ResultMenuAction.manualTrim:
                  _openManualTrim();
                  break;
                case _ResultMenuAction.savedClips:
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SavedClipsScreen()),
                  );
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _ResultMenuAction.manualTrim,
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.content_cut),
                  title: Text('Manual Trim'),
                ),
              ),
              PopupMenuItem(
                value: _ResultMenuAction.savedClips,
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.video_library_outlined),
                  title: Text('Saved Clips'),
                ),
              ),
            ],
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_hasError) {
      return AppErrorView(
        message: 'Could not load this video.',
        onRetry: _setupVideo,
      );
    }

    final controller = _controller;

    if (!_isInitialized || controller == null) {
      return const AppLoadingView(
        message: 'Loading video...',
        icon: Icons.movie_outlined,
      );
    }

    return OrientationBuilder(
      builder: (context, orientation) {
        final isLandscape = orientation == Orientation.landscape;

        if (isLandscape) {
          return Row(
            children: [
              SizedBox(
                width: MediaQuery.sizeOf(context).width * 0.42,
                child: Column(
                  children: [
                    Expanded(child: _buildVideoPlayer(controller)),
                    _buildProgressRow(controller),
                    const FreeBannerAd(
                      placement: 'ai_results_after_preview',
                      showLabel: true,
                    ),
                  ],
                ),
              ),
              Expanded(child: _buildSuggestionsList()),
            ],
          );
        }

        return Column(
          children: [
            SizedBox(
              width: double.infinity,
              height: MediaQuery.sizeOf(context).height * 0.30,
              child: _buildVideoPlayer(controller),
            ),
            _buildProgressRow(controller),
            const FreeBannerAd(
              placement: 'ai_results_after_preview',
              showLabel: true,
            ),
            Expanded(child: _buildSuggestionsList()),
          ],
        );
      },
    );
  }

  Widget _buildVideoPlayer(VideoPlayerController controller) {
    return Container(
      width: double.infinity,
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }

  Widget _buildProgressRow(VideoPlayerController controller) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Text(
            TimeFormatter.formatDuration(controller.value.position),
            style: const TextStyle(fontSize: 12),
          ),
          Expanded(
            child: VideoProgressIndicator(
              controller,
              allowScrubbing: true,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            ),
          ),
          Text(
            TimeFormatter.formatDuration(controller.value.duration),
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(width: AppSpacing.xs),
          IconButton(
            onPressed: () {
              setState(() {
                if (controller.value.isPlaying) {
                  controller.pause();
                  _previewEndSeconds = null;
                  _previewingKey = null;
                } else {
                  controller.play();
                }
              });
            },
            icon: Icon(
              controller.value.isPlaying
                  ? Icons.pause_circle_filled
                  : Icons.play_circle_filled,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionsList() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      children: [
        _buildSelectionToolbar(),
        const SizedBox(height: AppSpacing.md),
        ..._buildSuggestionSections(),
      ],
    );
  }

  Widget _buildSelectionToolbar() {
    final suggestions = widget.suggestions;
    final allSelected =
        suggestions.isNotEmpty && _selectedKeys.length == suggestions.length;

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
                      ? '${suggestions.length} eye-catching clip${suggestions.length == 1 ? '' : 's'} found'
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
                              ..addAll(suggestions.map(_keyFor));
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
                            suggestions
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
                  onPressed: _isBatchSaving || suggestions.isEmpty
                      ? null
                      : () => _runBatchExport(suggestions),
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

  double _normalizedConfidence(double confidence) {
    final normalized = confidence > 1 ? confidence / 100 : confidence;
    return normalized.clamp(0.0, 1.0).toDouble();
  }

  String _postingRecommendation(double confidence) {
    final score = _normalizedConfidence(confidence);

    if (score >= 0.65) {
      return 'Worth Posting';
    }

    if (score >= 0.50) {
      return 'Worth Posting After Editing';
    }

    return 'Review Before Posting';
  }

  Color _postingRecommendationColor(double confidence) {
    final score = _normalizedConfidence(confidence);

    if (score >= 0.65) {
      return AppColors.success;
    }

    if (score >= 0.50) {
      return AppColors.warning;
    }

    return AppColors.textMuted;
  }

  IconData _postingRecommendationIcon(double confidence) {
    final score = _normalizedConfidence(confidence);

    if (score >= 0.65) {
      return Icons.check_circle_outline;
    }

    if (score >= 0.50) {
      return Icons.auto_fix_high;
    }

    return Icons.visibility_outlined;
  }

  String _moodDescription(String mood) {
    switch (mood.trim().toLowerCase()) {
      case 'funny':
        return 'a funny and entertaining moment';
      case 'sad':
        return 'an emotional or sad moment';
      case 'emotional':
        return 'an emotional moment';
      case 'romantic':
        return 'a romantic moment';
      case 'angry':
        return 'a tense or argumentative moment';
      case 'action':
        return 'an action-filled moment';
      case 'fight':
        return 'a fight or confrontation';
      case 'weird':
      case 'strange':
        return 'an unexpected or unusual moment';
      case 'entertaining':
        return 'an entertaining moment';
      case 'reaction':
        return 'a strong reaction';
      case 'hook':
        return 'a strong hook or memorable quote';
      case 'info':
      case 'informative':
      case 'information':
        return 'an informative moment';
      case 'music':
        return 'a music-focused or edit-friendly moment';
      case 'exciting':
        return 'an exciting, high-energy moment';
      case 'viral':
        return 'a high-energy moment with strong posting potential';
      default:
        return 'an attention-grabbing highlight';
    }
  }

  String _clipExplanation(AiSuggestion suggestion) {
    final title = suggestion.title.trim();
    final description = _moodDescription(suggestion.mood);

    if (title.isEmpty) {
      return 'This clip shows $description from the video.';
    }

    return 'This clip shows $description: $title';
  }

  List<Widget> _buildSuggestionSections() {
    final suggestions = [...widget.suggestions]
      ..sort((a, b) {
        final confidenceCompare = b.confidence.compareTo(a.confidence);
        if (confidenceCompare != 0) return confidenceCompare;
        return a.startSeconds.compareTo(b.startSeconds);
      });

    final widgets = <Widget>[
      Container(
        width: double.infinity,
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
                const Icon(
                  Icons.auto_awesome,
                  size: 22,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Eye-Catching Clips (${suggestions.length})',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'These clips show the most attention-grabbing moments found '
              'in your video. Each result explains what the clip shows and '
              'whether it looks worth posting.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.md),
    ];

    if (suggestions.isEmpty) {
      widgets.add(
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: BoxDecoration(
            color: AppColors.cardBackgroundSubtle,
            borderRadius: AppRadius.lgRadius,
            border: Border.all(color: AppColors.border),
          ),
          child: const Column(
            children: [
              Icon(
                Icons.search_off,
                size: 40,
                color: AppColors.textMuted,
              ),
              SizedBox(height: AppSpacing.sm),
              Text(
                'No eye-catching clips were found.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      );

      return widgets;
    }

    for (final suggestion in suggestions) {
      final key = _keyFor(suggestion);
      final isPreviewing = _previewingKey == key;
      final recommendation = _postingRecommendation(suggestion.confidence);
      final recommendationColor =
          _postingRecommendationColor(suggestion.confidence);
      final recommendationIcon =
          _postingRecommendationIcon(suggestion.confidence);

      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AiSuggestionCard(
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
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.cardBackgroundSubtle,
                      borderRadius: AppRadius.lgRadius,
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _clipExplanation(suggestion),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.xs,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Text(
                              'Posting recommendation:',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: recommendationColor.withAlpha(31),
                                borderRadius: AppRadius.pillRadius,
                                border: Border.all(
                                  color: recommendationColor.withAlpha(115),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    recommendationIcon,
                                    size: 14,
                                    color: recommendationColor,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    recommendation,
                                    style: TextStyle(
                                      color: recommendationColor,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (isPreviewing)
                Positioned(
                  top: AppSpacing.sm,
                  right: AppSpacing.sm,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: AppRadius.pillRadius,
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.play_arrow,
                          size: 12,
                          color: Colors.white,
                        ),
                        SizedBox(width: 3),
                        Text(
                          'Previewing',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
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
              final color = Theme.of(context).colorScheme.primary;

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppLoadingIndicator(size: 52, icon: Icons.save_alt),
                  const SizedBox(height: AppSpacing.lg),
                  const Text(
                    'Saving Clips',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Clip ${value.index + 1} of ${value.total}',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  ClipRRect(
                    borderRadius: AppRadius.pillRadius,
                    child: LinearProgressIndicator(
                      value: overall.clamp(0.0, 1.0),
                      minHeight: 8,
                      backgroundColor: AppColors.border,
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    '${(overall.clamp(0.0, 1.0) * 100).round()}% complete',
                    style: TextStyle(
                      color: color,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
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

enum _ResultMenuAction {
  manualTrim,
  savedClips,
}
