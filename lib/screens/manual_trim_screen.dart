import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../models/selected_video.dart';
import '../services/ad_service.dart';
import '../services/clip_export_service.dart';
import '../theme/app_theme.dart';
import '../utils/time_formatter.dart';
import '../widgets/free_banner_ad.dart';
import 'saved_clips_screen.dart';

enum _TrimMode { manual, autoSplit }

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
  final TextEditingController _customSecondsController = TextEditingController();

  static const List<int> _autoSplitPresets = [5, 10, 15, 20, 30, 45, 60];

  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  bool _isSaving = false;
  bool _isPreviewingSelection = false;

  double _startSeconds = 0;
  double _endSeconds = 1;
  double _saveProgress = 0.0;
  int? _previewEndSeconds;

  _TrimMode _trimMode = _TrimMode.manual;
  int _autoSplitSeconds = 15;
  int _autoSplitCurrentIndex = 0;
  int _autoSplitTotal = 0;

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
        _startSeconds = 0;
        _endSeconds = max(1, defaultEnd).toDouble();
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

  /// Start/end second pairs that the current auto-split interval produces,
  /// covering the video from 0 up to its full duration. The final segment
  /// may be shorter than the chosen interval if it doesn't divide evenly.
  List<List<int>> get _autoSplitSegments {
    final duration = _durationSeconds;
    final interval = _autoSplitSeconds;
    if (interval <= 0) return const [];

    final segments = <List<int>>[];
    for (int start = 0; start < duration; start += interval) {
      final end = min(start + interval, duration);
      if (end - start >= 1) {
        segments.add([start, end]);
      }
    }
    return segments;
  }

  int get _autoSplitClipCount => _autoSplitSegments.length;

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
      if (mounted) {
        AdService.instance.maybeShowInterstitialAfterExport();
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save manual clip: $e')),
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

  Future<void> _applyCustomSeconds() async {
    final value = int.tryParse(_customSecondsController.text.trim());
    if (value == null || value < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid number of seconds (1 or more).')),
      );
      return;
    }

    setState(() {
      _autoSplitSeconds = value.clamp(1, _durationSeconds);
    });
  }

  Future<void> _createAutoSplitClips() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _isSaving) return;

    final segments = _autoSplitSegments;
    if (segments.isEmpty) return;

    await controller.pause();

    setState(() {
      _isSaving = true;
      _saveProgress = 0.0;
      _isPreviewingSelection = false;
      _previewEndSeconds = null;
      _autoSplitCurrentIndex = 0;
      _autoSplitTotal = segments.length;
    });

    var savedCount = 0;

    try {
      for (var i = 0; i < segments.length; i++) {
        if (!mounted) return;

        setState(() => _autoSplitCurrentIndex = i + 1);

        final segment = segments[i];
        await _exportService.exportClip(
          videoPath: widget.video.path,
          title: 'Clip ${i + 1}',
          startSeconds: segment[0],
          endSeconds: segment[1],
          onProgress: (progress) {
            if (!mounted) return;
            final overall = (i + progress.clamp(0.0, 1.0)) / segments.length;
            setState(() => _saveProgress = overall.clamp(0.0, 1.0).toDouble());
          },
        );

        savedCount++;
      }

      if (!mounted) return;

      await _showAutoSplitSavedDialog(savedCount);
      if (mounted) {
        AdService.instance.maybeShowInterstitialAfterExport();
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved $savedCount of ${segments.length} clips before an error: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _saveProgress = 0.0;
          _autoSplitCurrentIndex = 0;
          _autoSplitTotal = 0;
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
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: AppColors.success),
              SizedBox(width: AppSpacing.sm),
              Text('Manual Clip Saved'),
            ],
          ),
          content: Text(
            'Saved ${TimeFormatter.formatDuration(Duration(seconds: _clipDurationSeconds))} clip to your library.',
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

  Future<void> _showAutoSplitSavedDialog(int count) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.surfaceElevated,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.lgRadius),
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: AppColors.success),
              SizedBox(width: AppSpacing.sm),
              Text('Clips Saved'),
            ],
          ),
          content: Text(
            'Saved $count ${count == 1 ? 'clip' : 'clips'} (every $_autoSplitSeconds seconds) to your library.',
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
    _customSecondsController.dispose();
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
      return const Center(
        child: Text(
          'Could not load this video.',
          style: TextStyle(color: AppColors.error),
        ),
      );
    }

    final controller = _controller;

    if (!_isInitialized || controller == null) {
      return const Center(child: CircularProgressIndicator());
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
                    const FreeBannerAd(placement: 'manual_trim_after_preview'),
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
            const FreeBannerAd(placement: 'manual_trim_after_preview'),
            Expanded(child: _buildTrimControls(controller)),
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

  Widget _buildVideoProgressRow(VideoPlayerController controller) {
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
        _buildModeToggle(),
        const SizedBox(height: AppSpacing.lg),
        if (_trimMode == _TrimMode.manual) ...[
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: AppRadius.lgRadius,
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Select Clip Range',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _selectionLabel,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                RangeSlider(
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
                const SizedBox(height: AppSpacing.sm),
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
                  label: Text(_isSaving ? 'Saving...' : 'Save Clip'),
                ),
              ),
            ],
          ),
        ] else
          _buildAutoSplitCard(),
        if (_isSaving) ...[
          const SizedBox(height: AppSpacing.md),
          if (_trimMode == _TrimMode.autoSplit && _autoSplitTotal > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Text(
                'Saving clip $_autoSplitCurrentIndex of $_autoSplitTotal...',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ClipRRect(
            borderRadius: AppRadius.pillRadius,
            child: LinearProgressIndicator(
              value: _saveProgress == 0 ? null : _saveProgress,
              minHeight: 8,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildModeToggle() {
    return Row(
      children: [
        Expanded(
          child: _buildModeButton(
            label: 'Manual Range',
            icon: Icons.content_cut,
            selected: _trimMode == _TrimMode.manual,
            onTap: () => setState(() => _trimMode = _TrimMode.manual),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _buildModeButton(
            label: 'Auto Split',
            icon: Icons.grid_view_rounded,
            selected: _trimMode == _TrimMode.autoSplit,
            onTap: () => setState(() => _trimMode = _TrimMode.autoSplit),
          ),
        ),
      ],
    );
  }

  Widget _buildModeButton({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: _isSaving ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: selected ? AppColors.secondary : AppColors.cardBackground,
          borderRadius: AppRadius.lgRadius,
          border: Border.all(color: selected ? AppColors.secondary : AppColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: selected ? Colors.white : AppColors.textSecondary),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: selected ? Colors.white : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAutoSplitCard() {
    final clipCount = _autoSplitClipCount;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: AppRadius.lgRadius,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Auto-Split by Seconds',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Every $_autoSplitSeconds seconds becomes its own clip, from the start of the video to the end.',
            style: const TextStyle(color: AppColors.textSecondary, height: 1.35),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: _autoSplitPresets.map((seconds) {
              final selected = _autoSplitSeconds == seconds;
              return ChoiceChip(
                label: Text('${seconds}s'),
                selected: selected,
                onSelected: _isSaving
                    ? null
                    : (_) => setState(() => _autoSplitSeconds = seconds),
              );
            }).toList(),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _customSecondsController,
                  enabled: !_isSaving,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Custom seconds',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              OutlinedButton(
                onPressed: _isSaving ? null : _applyCustomSeconds,
                child: const Text('Apply'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            clipCount > 0
                ? 'This will create $clipCount ${clipCount == 1 ? 'clip' : 'clips'} of up to $_autoSplitSeconds seconds each.'
                : 'Choose an interval to see how many clips will be created.',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (_isSaving || clipCount == 0) ? null : _createAutoSplitClips,
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.auto_awesome_mosaic, size: 18),
              label: Text(_isSaving ? 'Saving...' : 'Create Clips'),
            ),
          ),
        ],
      ),
    );
  }
}