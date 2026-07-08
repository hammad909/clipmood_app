import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../models/ai_suggestion.dart';
import '../models/selected_video.dart';
import '../services/ad_service.dart';
import '../services/clip_export_service.dart';
import '../theme/app_theme.dart';
import '../utils/time_formatter.dart';
import '../widgets/app_loading_indicator.dart';
import '../widgets/free_banner_ad.dart';
import 'clip_preview_screen.dart';

class ClipEditScreen extends StatefulWidget {
  final SelectedVideo video;
  final AiSuggestion suggestion;

  const ClipEditScreen({
    super.key,
    required this.video,
    required this.suggestion,
  });

  @override
  State<ClipEditScreen> createState() => _ClipEditScreenState();
}

class _ClipEditScreenState extends State<ClipEditScreen> {
  final ClipExportService _exportService = ClipExportService();

  VideoPlayerController? _controller;

  bool _isInitialized = false;
  bool _hasError = false;

  bool _isExporting = false;
  double _exportProgress = 0.0;
  String? _exportedClipPath;

  late int _startSeconds;
  late int _endSeconds;
  late RangeValues _trimRange;

  String get _clipTitle => widget.suggestion.title;

  @override
  void initState() {
    super.initState();

    _startSeconds = widget.suggestion.startSeconds;
    _endSeconds = widget.suggestion.endSeconds;

    _trimRange = RangeValues(
      _startSeconds.toDouble(),
      _endSeconds.toDouble(),
    );

    _setupVideo();
  }

  Future<void> _setupVideo() async {
    setState(() {
      _hasError = false;
      _isInitialized = false;
    });

    try {
      final controller = VideoPlayerController.file(
        File(widget.video.path),
      );

      await controller.initialize();

      final durationSeconds = max(1, controller.value.duration.inSeconds);

      _startSeconds = _startSeconds.clamp(0, durationSeconds - 1).toInt();
      _endSeconds = _endSeconds.clamp(_startSeconds + 1, durationSeconds).toInt();

      _trimRange = RangeValues(
        _startSeconds.toDouble(),
        _endSeconds.toDouble(),
      );

      await controller.seekTo(Duration(seconds: _startSeconds));

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

      setState(() {
        _hasError = true;
      });
    }
  }

  void _videoListener() {
    final controller = _controller;
    if (controller == null) return;
    if (!controller.value.isInitialized) return;

    final currentSeconds = controller.value.position.inSeconds;

    if (currentSeconds >= _endSeconds && controller.value.isPlaying) {
      controller.pause();
      controller.seekTo(Duration(seconds: _startSeconds));
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _playClipPreview() async {
    final controller = _controller;
    if (controller == null) return;

    await controller.seekTo(Duration(seconds: _startSeconds));
    await controller.play();
  }

  Future<void> _seekToStart() async {
    final controller = _controller;
    if (controller == null) return;

    await controller.seekTo(Duration(seconds: _startSeconds));
  }

  void _updateExportProgress(double progress) {
    setState(() {
      _exportProgress = progress;
    });
  }

  void _updateTrimRange(RangeValues values) {
    if (values.end - values.start < 2) {
      return;
    }

    setState(() {
      _trimRange = values;
      _startSeconds = values.start.round();
      _endSeconds = values.end.round();
    });
  }

  Future<void> _onTrimRangeChangeEnd(RangeValues values) async {
    final controller = _controller;
    if (controller == null) return;

    await controller.pause();
    await controller.seekTo(Duration(seconds: values.start.round()));
  }

  Future<void> _createClip() async {
    if (_isExporting) return;

    if (_endSeconds <= _startSeconds) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('End time must be greater than start time.'),
        ),
      );
      return;
    }

    setState(() {
      _isExporting = true;
      _exportProgress = 0.0;
      _exportedClipPath = null;
    });

    try {
      final exportedPath = await _exportService.exportClip(
        videoPath: widget.video.path,
        title: widget.suggestion.title,
        startSeconds: _startSeconds,
        endSeconds: _endSeconds,
        onProgress: (progress) {
          if (!mounted) return;
          _updateExportProgress(progress);
        },
      );

      if (!mounted) return;

      setState(() {
        _exportedClipPath = exportedPath;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Clip created successfully.'),
        ),
      );

      AdService.instance.maybeShowInterstitialAfterExport();

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ClipPreviewScreen(
            clipPath: exportedPath,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to create clip: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  @override
  void dispose() {
    final controller = _controller;

    if (controller != null) {
      controller.removeListener(_videoListener);
      controller.dispose();
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Clip'),
      ),
      body: SafeArea(
        child: _buildBody(),
      ),
      bottomNavigationBar: const SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: AppSpacing.xs),
          child: FreeBannerAd(
            placement: 'clip_edit_bottom',
            showLabel: true,
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_hasError) {
      return AppErrorView(
        message: 'Could not load clip editor.',
        onRetry: _setupVideo,
      );
    }

    final controller = _controller;

    if (!_isInitialized || controller == null) {
      return const AppLoadingView(
        message: 'Loading clip editor...',
        icon: Icons.content_cut,
      );
    }

    return OrientationBuilder(
      builder: (context, orientation) {
        final isLandscape = orientation == Orientation.landscape;

        if (isLandscape) {
          return Row(
            children: [
              SizedBox(
                width: MediaQuery.sizeOf(context).width * 0.45,
                child: Column(
                  children: [
                    Expanded(child: _buildVideoPlayer(controller)),
                    _buildTransportRow(controller),
                    _buildPlaybackButtons(),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                ),
              ),
              Expanded(child: _buildEditorPanel()),
            ],
          );
        }

        return Column(
          children: [
            SizedBox(
              width: double.infinity,
              height: MediaQuery.sizeOf(context).height * 0.32,
              child: _buildVideoPlayer(controller),
            ),
            const SizedBox(height: AppSpacing.sm),
            _buildTransportRow(controller),
            const SizedBox(height: AppSpacing.md),
            _buildPlaybackButtons(),
            const SizedBox(height: AppSpacing.sm),
            Expanded(child: _buildEditorPanel()),
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

  Widget _buildTransportRow(VideoPlayerController controller) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
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
    );
  }

  Widget _buildPlaybackButtons() {
    final controller = _controller!;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton.outlined(
          tooltip: 'Go to clip start',
          onPressed: _seekToStart,
          icon: const Icon(Icons.skip_previous),
        ),
        const SizedBox(width: AppSpacing.md),
        IconButton.filled(
          iconSize: 34,
          onPressed: controller.value.isPlaying
              ? () {
                  setState(() {
                    controller.pause();
                  });
                }
              : _playClipPreview,
          icon: Icon(
            controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
          ),
        ),
      ],
    );
  }

  Widget _buildEditorPanel() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        children: [
          _buildClipTitleCard(),
          const SizedBox(height: AppSpacing.lg),
          _buildTrimSlider(),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: _buildTimeDisplay(
                  title: 'Start Time',
                  value: _startSeconds,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _buildTimeDisplay(
                  title: 'End Time',
                  value: _endSeconds,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          _buildDurationCard(),
          const SizedBox(height: AppSpacing.xl),
          if (_isExporting) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.cardBackground,
                borderRadius: AppRadius.lgRadius,
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  AppLoadingIndicator(size: 48, icon: Icons.content_cut),
                  const SizedBox(height: AppSpacing.md),
                  ClipRRect(
                    borderRadius: AppRadius.pillRadius,
                    child: LinearProgressIndicator(
                      value: _exportProgress == 0.0 ? null : _exportProgress,
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Exporting clip... ${(_exportProgress * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _createClip,
                icon: const Icon(Icons.content_cut),
                label: const Text('Create Clip'),
              ),
            ),
          ],
          if (_exportedClipPath != null) ...[
            const SizedBox(height: AppSpacing.lg),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                borderRadius: AppRadius.mdRadius,
                color: AppColors.success.withValues(alpha: 0.12),
                border: Border.all(
                  color: AppColors.success.withValues(alpha: 0.35),
                ),
              ),
              child: Text(
                'Saved clip:\n$_exportedClipPath',
                style: const TextStyle(
                  color: AppColors.success,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildClipTitleCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        borderRadius: AppRadius.lgRadius,
        color: AppColors.cardBackground,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Clip Title',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            _clipTitle,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (widget.suggestion.reason.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              widget.suggestion.reason.first,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTrimSlider() {
    final controller = _controller;

    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }

    final durationSeconds = controller.value.duration.inSeconds;

    if (durationSeconds <= 1) {
      return const SizedBox.shrink();
    }

    final safeRange = RangeValues(
      _trimRange.start.clamp(0, durationSeconds).toDouble(),
      _trimRange.end.clamp(0, durationSeconds).toDouble(),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        borderRadius: AppRadius.lgRadius,
        color: AppColors.cardBackground,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Adjust Clip Timing',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          RangeSlider(
            values: safeRange,
            min: 0,
            max: durationSeconds.toDouble(),
            divisions: durationSeconds,
            labels: RangeLabels(
              TimeFormatter.formatDuration(
                Duration(seconds: safeRange.start.round()),
              ),
              TimeFormatter.formatDuration(
                Duration(seconds: safeRange.end.round()),
              ),
            ),
            onChanged: _isExporting ? null : _updateTrimRange,
            onChangeEnd: _isExporting ? null : _onTrimRangeChangeEnd,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Start: ${TimeFormatter.formatDuration(Duration(seconds: _startSeconds))}',
                style: const TextStyle(color: AppColors.textMuted),
              ),
              Text(
                'End: ${TimeFormatter.formatDuration(Duration(seconds: _endSeconds))}',
                style: const TextStyle(color: AppColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Clip length: ${_endSeconds - _startSeconds}s',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDurationCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        borderRadius: AppRadius.lgRadius,
        color: AppColors.cardBackground,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          const Text(
            'Selected Clip Duration',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${_endSeconds - _startSeconds} seconds',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeDisplay({
    required String title,
    required int value,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        borderRadius: AppRadius.lgRadius,
        color: AppColors.cardBackground,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            TimeFormatter.formatDuration(Duration(seconds: value)),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}