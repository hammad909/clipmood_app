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
import '../theme/app_theme.dart';
import '../utils/time_formatter.dart';
import '../widgets/ai_scan_progress_panel.dart';
import '../widgets/app_loading_indicator.dart';
import 'ai_clips_result_screen.dart';
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

class _VideoEditorScreenState extends State<VideoEditorScreen> {
  VideoPlayerController? _controller;

  final AiClipAnalyzerService _aiAnalyzer = AiClipAnalyzerService();

  bool _isInitialized = false;
  bool _hasError = false;
  bool _isScanning = false;
  AiScanMode _selectedScanMode = AiScanMode.balanced;
  AiScanProgress _scanProgress = const AiScanProgress.idle();
  AiScanCancellationToken? _scanCancellationToken;

  List<AiSuggestion> _lastSuggestions = [];

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

  Future<void> _scanForAiClips() async {
    if (_isScanning) return;

    final controller = _controller;

    if (controller != null && controller.value.isPlaying) {
      await controller.pause();
    }

    final cancellationToken = AiScanCancellationToken();

    setState(() {
      _isScanning = true;
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
        _lastSuggestions = result.suggestions;
      });

      if (result.suggestions.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No clips found. Try a different scan mode.'),
          ),
        );
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AiClipsResultScreen(
            video: widget.video,
            suggestions: result.suggestions,
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

  void _reopenLastResults() {
    if (_lastSuggestions.isEmpty) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AiClipsResultScreen(
          video: widget.video,
          suggestions: _lastSuggestions,
        ),
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

        final videoBlock = _buildVideoBlock(controller, isLandscape);
        final controlsBlock = _buildScanControls();

        if (isLandscape) {
          return Row(
            children: [
              SizedBox(
                width: MediaQuery.sizeOf(context).width * 0.42,
                child: videoBlock,
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: controlsBlock,
                ),
              ),
            ],
          );
        }

        return Column(
          children: [
            videoBlock,
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: controlsBlock,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildVideoBlock(VideoPlayerController controller, bool isLandscape) {
    return Column(
      mainAxisSize: isLandscape ? MainAxisSize.max : MainAxisSize.min,
      children: [
        isLandscape
            ? Expanded(
                child: Container(
                  width: double.infinity,
                  color: Colors.black,
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: controller.value.aspectRatio,
                      child: VideoPlayer(controller),
                    ),
                  ),
                ),
              )
            : Container(
                width: double.infinity,
                height: MediaQuery.sizeOf(context).height * 0.32,
                color: Colors.black,
                child: Center(
                  child: AspectRatio(
                    aspectRatio: controller.value.aspectRatio,
                    child: VideoPlayer(controller),
                  ),
                ),
              ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
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
            controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
    );
  }

  Widget _buildScanControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.video.name,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (_isScanning) ...[
          AiScanProgressPanel(
            progress: _scanProgress,
            onCancel: _cancelAiScan,
          ),
        ] else ...[
          _buildScanModeSelector(),
          const SizedBox(height: AppSpacing.lg),
          FilledButton.icon(
            onPressed: _scanForAiClips,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Scan All Clip Types'),
          ),
          if (_lastSuggestions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: _reopenLastResults,
              icon: const Icon(Icons.history),
              label: Text('View Last Results (${_lastSuggestions.length})'),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildScanModeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
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
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 42,
          child: ListView.separated(
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
                        });
                      },
              );
            },
          ),
        ),
      ],
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
}