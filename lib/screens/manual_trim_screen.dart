import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../models/selected_video.dart';
import '../services/clip_export_service.dart';
import '../theme/app_theme.dart';
import '../utils/time_formatter.dart';
import 'saved_clips_screen.dart';

class ManualTrimScreen extends StatefulWidget {
  final SelectedVideo video;

  const ManualTrimScreen({
    super.key,
    required this.video,
  });

  @override
  State<ManualTrimScreen> createState() => _ManualTrimScreenState();
}

class _ManualTrimScreenState extends State<ManualTrimScreen> {
  final ClipExportService _exportService = ClipExportService();

  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  bool _isSaving = false;
  bool _isPreviewingSelection = false;

  double _startSeconds = 0;
  double _endSeconds = 1;
  double _saveProgress = 0.0;
  int? _previewEndSeconds;

  @override
  void initState() {
    super.initState();
    _setupVideo();
  }

  Future<void> _setupVideo() async {
    try {
      final controller = VideoPlayerController.file(File(widget.video.path));
      await controller.initialize();
      controller.addListener(_videoListener);

      final durationSeconds = max(1, controller.value.duration.inSeconds);
      final defaultEnd = min(durationSeconds, 15);

      if (!mounted) {
        controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _isInitialized = true;
        _hasError = false;
        _startSeconds = 0;
        _endSeconds = max(1, defaultEnd).toDouble();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _hasError = true);
    }
  }

  Future<void> _retrySetup() async {
    setState(() {
      _hasError = false;
      _isInitialized = false;
    });
    await _setupVideo();
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
      _isPreviewingSelection = false;
    }

    if (mounted) setState(() {});
  }

  int get _durationSeconds {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return 1;
    return max(1, controller.value.duration.inSeconds);
  }

  int get _clipStartSeconds {
    return _startSeconds.floor().clamp(0, _durationSeconds - 1).toInt();
  }

  int get _clipEndSeconds {
    return _endSeconds.ceil().clamp(_clipStartSeconds + 1, _durationSeconds).toInt();
  }

  int get _clipDurationSeconds => _clipEndSeconds - _clipStartSeconds;

  String get _selectionLabel {
    final start = TimeFormatter.formatDuration(Duration(seconds: _clipStartSeconds));
    final end = TimeFormatter.formatDuration(Duration(seconds: _clipEndSeconds));
    final duration = TimeFormatter.formatDuration(Duration(seconds: _clipDurationSeconds));
    return '$start → $end  •  $duration';
  }

  Future<void> _previewSelection() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _isSaving) return;

    _previewEndSeconds = _clipEndSeconds;
    _isPreviewingSelection = true;
    await controller.seekTo(Duration(seconds: _clipStartSeconds));
    await controller.play();
    if (mounted) setState(() {});
  }

  Future<void> _setStartFromCurrentPosition() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    final current = controller.value.position.inSeconds.clamp(0, _durationSeconds - 1).toInt();
    final safeEnd = max(current + 1, _clipEndSeconds).clamp(1, _durationSeconds).toInt();

    setState(() {
      _startSeconds = current.toDouble();
      _endSeconds = safeEnd.toDouble();
    });
  }

  Future<void> _setEndFromCurrentPosition() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    final current = controller.value.position.inSeconds.clamp(1, _durationSeconds).toInt();
    final safeStart = min(_clipStartSeconds, current - 1).clamp(0, _durationSeconds - 1).toInt();

    setState(() {
      _startSeconds = safeStart.toDouble();
      _endSeconds = current.toDouble();
    });
  }

  Future<void> _saveManualClip() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _isSaving) return;

    await controller.pause();

    setState(() {
      _isSaving = true;
      _saveProgress = 0.0;
      _isPreviewingSelection = false;
      _previewEndSeconds = null;
    });

    try {
      await _exportService.exportClip(
        videoPath: widget.video.path,
        title: 'Manual Clip',
        startSeconds: _clipStartSeconds,
        endSeconds: _clipEndSeconds,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _saveProgress = progress.clamp(0.0, 1.0).toDouble());
        },
      );

      if (!mounted) return;

      await _showSavedDialog();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.lgRadius),
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 18),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text('Failed to save manual clip: $e')),
            ],
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _saveProgress = 0.0;
        });
      }
    }
  }

  Future<void> _showSavedDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.surfaceElevated,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.lgRadius),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.xs),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle, color: AppColors.success),
              ),
              const SizedBox(width: AppSpacing.sm),
              const Expanded(
                child: Text(
                  'Manual Clip Saved',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          content: Text(
            'Saved ${TimeFormatter.formatDuration(Duration(seconds: _clipDurationSeconds))} clip to your library.',
            style: const TextStyle(color: AppColors.textSecondary, height: 1.35),
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
      appBar: AppBar(
        title: const Text('Manual Trim'),
        actions: [
          IconButton(
            tooltip: 'Saved Clips',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SavedClipsScreen()),
            ),
            icon: const Icon(Icons.video_library),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_hasError) {
      return _buildErrorState();
    }

    final controller = _controller;

    if (!_isInitialized || controller == null) {
      return _buildLoadingState();
    }

    return OrientationBuilder(
      builder: (context, orientation) {
        final isLandscape = orientation == Orientation.landscape;

        if (isLandscape) {
          return Row(
            children: [
              SizedBox(
                width: MediaQuery.sizeOf(context).width * 0.48,
                child: Column(
                  children: [
                    Expanded(child: _buildVideoPlayer(controller)),
                    _buildVideoProgressRow(controller),
                  ],
                ),
              ),
              Expanded(child: _buildTrimControls(controller)),
            ],
          );
        }

        return Column(
          children: [
            SizedBox(
              width: double.infinity,
              height: MediaQuery.sizeOf(context).height * 0.34,
              child: _buildVideoPlayer(controller),
            ),
            _buildVideoProgressRow(controller),
            Expanded(child: _buildTrimControls(controller)),
          ],
        );
      },
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.cardBackgroundSubtle,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border),
            ),
            child: const CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.secondary),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const Text(
            'Loading video…',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'This only takes a moment.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.error_outline, color: AppColors.error, size: 30),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text(
              'Could not load this video',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'The file may be missing, moved, or in an unsupported format.',
              style: TextStyle(color: AppColors.textSecondary, height: 1.35),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton.icon(
              onPressed: _retrySetup,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
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

  Widget _buildVideoProgressRow(VideoPlayerController controller) {
    return Container(
      color: AppColors.surfaceElevated,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(
              TimeFormatter.formatDuration(controller.value.position),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: VideoProgressIndicator(
              controller,
              allowScrubbing: true,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              colors: VideoProgressColors(
                playedColor: AppColors.secondary,
                bufferedColor: AppColors.border,
                backgroundColor: AppColors.border.withValues(alpha: 0.4),
              ),
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              TimeFormatter.formatDuration(controller.value.duration),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          IconButton(
            onPressed: _isSaving
                ? null
                : () {
                    setState(() {
                      if (controller.value.isPlaying) {
                        controller.pause();
                        _isPreviewingSelection = false;
                        _previewEndSeconds = null;
                      } else {
                        controller.play();
                      }
                    });
                  },
            icon: Icon(
              controller.value.isPlaying
                  ? Icons.pause_circle_filled
                  : Icons.play_circle_filled,
              color: AppColors.secondary,
              size: 30,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrimControls(VideoPlayerController controller) {
    final durationSeconds = _durationSeconds;
    // For manual editing, there is no max clip length. The user can select
    // from 1 second up to the full source video duration.
    final divisions = durationSeconds > 1 && durationSeconds <= 3600
        ? durationSeconds
        : null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      children: [
        _buildInfoCard(),
        const SizedBox(height: AppSpacing.lg),
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: AppRadius.lgRadius,
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Icon(Icons.content_cut, size: 18, color: AppColors.secondary),
                  SizedBox(width: AppSpacing.xs),
                  Text(
                    'Select Clip Range',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: AppColors.cardBackgroundSubtle,
                  borderRadius: AppRadius.pillRadius,
                ),
                child: Text(
                  _selectionLabel,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: AppColors.secondary,
                  inactiveTrackColor: AppColors.border,
                  thumbColor: AppColors.secondary,
                  overlayColor: AppColors.secondary.withValues(alpha: 0.15),
                  rangeThumbShape: const RoundRangeSliderThumbShape(
                    enabledThumbRadius: 9,
                  ),
                ),
                child: RangeSlider(
                  min: 0,
                  max: durationSeconds.toDouble(),
                  divisions: divisions,
                  values: RangeValues(_clipStartSeconds.toDouble(), _clipEndSeconds.toDouble()),
                  labels: RangeLabels(
                    TimeFormatter.formatDuration(Duration(seconds: _clipStartSeconds)),
                    TimeFormatter.formatDuration(Duration(seconds: _clipEndSeconds)),
                  ),
                  onChanged: _isSaving
                      ? null
                      : (values) {
                          final maxSeconds = durationSeconds.toDouble();
                          var start = values.start.floorToDouble().clamp(0.0, maxSeconds - 1).toDouble();
                          var end = values.end.ceilToDouble().clamp(1.0, maxSeconds).toDouble();

                          if (end - start < 1) {
                            if (start <= _startSeconds) {
                              end = min(maxSeconds, start + 1);
                            } else {
                              start = max(0.0, end - 1);
                            }
                          }

                          setState(() {
                            _startSeconds = start;
                            _endSeconds = end;
                          });
                        },
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isSaving ? null : _setStartFromCurrentPosition,
                      icon: const Icon(Icons.keyboard_double_arrow_left, size: 18),
                      label: const Text('Set Start'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isSaving ? null : _setEndFromCurrentPosition,
                      icon: const Icon(Icons.keyboard_double_arrow_right, size: 18),
                      label: const Text('Set End'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isSaving ? null : _previewSelection,
                icon: Icon(_isPreviewingSelection ? Icons.replay : Icons.play_arrow),
                label: Text(_isPreviewingSelection ? 'Replay Selection' : 'Preview Selection'),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: FilledButton.icon(
                onPressed: _isSaving ? null : _saveManualClip,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_alt, size: 18),
                label: Text(_isSaving ? 'Saving…' : 'Save Clip'),
              ),
            ),
          ],
        ),
        if (_isSaving) ...[
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: AppRadius.pillRadius,
                  child: LinearProgressIndicator(
                    value: _saveProgress == 0 ? null : _saveProgress,
                    minHeight: 8,
                    backgroundColor: AppColors.border,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.secondary),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              SizedBox(
                width: 40,
                child: Text(
                  '${(_saveProgress * 100).round()}%',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.cardBackgroundSubtle,
        borderRadius: AppRadius.lgRadius,
        border: Border.all(color: AppColors.border),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.content_cut, color: AppColors.secondary),
          SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'Manual trim does not run AI and has no 1–5 minute source-video limit. Pick any range from the video, from a 1-second clip up to the full video, preview it, then save it to your clips library.',
              style: TextStyle(color: AppColors.textSecondary, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}