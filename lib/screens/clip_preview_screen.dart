import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';
import '../services/ad_service.dart';
import '../theme/app_theme.dart';
import '../utils/time_formatter.dart';
import '../widgets/app_loading_indicator.dart';
import '../widgets/free_banner_ad.dart';

class ClipPreviewScreen extends StatefulWidget {
  final String clipPath;

  const ClipPreviewScreen({
    super.key,
    required this.clipPath,
  });

  @override
  State<ClipPreviewScreen> createState() => _ClipPreviewScreenState();
}

class _ClipPreviewScreenState extends State<ClipPreviewScreen> {
  VideoPlayerController? _controller;

  bool _isInitialized = false;
  bool _hasError = false;
  bool _isSaving = false;
  bool _isSharing = false;

  @override
  void initState() {
    super.initState();
    _setupClip();
  }

  Future<void> _setupClip() async {
    setState(() {
      _hasError = false;
      _isInitialized = false;
    });

    try {
      final controller = VideoPlayerController.file(
        File(widget.clipPath),
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
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _hasError = true;
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    final controller = _controller;
    if (controller == null) return;

    setState(() {
      if (controller.value.isPlaying) {
        controller.pause();
      } else {
        controller.play();
      }
    });
  }

  Future<void> _saveToGallery() async {
    if (_isSaving) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final hasAccess = await Gal.hasAccess();

      if (!hasAccess) {
        await Gal.requestAccess();
      }

      await Gal.putVideo(widget.clipPath);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Clip saved to gallery.'),
        ),
      );

      AdService.instance.maybeShowInterstitialAfterExport();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save to gallery: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _shareClip() async {
    if (_isSharing) return;

    setState(() {
      _isSharing = true;
    });

    try {
      final file = File(widget.clipPath);

      if (!await file.exists()) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Clip file not found.'),
          ),
        );
        return;
      }

      await SharePlus.instance.share(
        ShareParams(
          text: 'Check out this clip created with ClipMood.',
          files: [
            XFile(widget.clipPath),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to share clip: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSharing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clip Preview'),
      ),
      body: SafeArea(
        child: _buildBody(),
      ),
      bottomNavigationBar: const SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: AppSpacing.xs),
          child: FreeBannerAd(
            placement: 'clip_preview_bottom',
            showLabel: true,
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_hasError) {
      return AppErrorView(
        message: 'Could not load exported clip.',
        onRetry: _setupClip,
      );
    }

    if (!_isInitialized || _controller == null) {
      return const AppLoadingView(
        message: 'Loading clip...',
        icon: Icons.movie_outlined,
      );
    }

    final controller = _controller!;

    // The video + metadata section can be taller than the available space on
    // smaller screens (e.g. tall aspect-ratio clips, larger text scales), so
    // it scrolls independently while the Save/Share/Done actions stay
    // pinned below it. This avoids the bottom overflow that a fixed-height
    // Column + Spacer combination would hit once content no longer fits.
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  height: MediaQuery.sizeOf(context).height * 0.4,
                  color: Colors.black,
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: controller.value.aspectRatio,
                      child: VideoPlayer(controller),
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.md),

                Padding(
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
                ),

                const SizedBox(height: AppSpacing.xl),

                IconButton.filled(
                  iconSize: 42,
                  onPressed: _togglePlayPause,
                  icon: Icon(
                    controller.value.isPlaying
                        ? Icons.pause
                        : Icons.play_arrow,
                  ),
                ),

                const SizedBox(height: AppSpacing.xl),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.cardBackground,
                      borderRadius: AppRadius.mdRadius,
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.check_circle,
                          color: AppColors.success,
                          size: 18,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            widget.clipPath.split(Platform.pathSeparator).last,
                            maxLines: 1,
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
                ),

                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          ),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _isSaving ? null : _saveToGallery,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.download),
                      label: const Text('Save'),
                    ),
                  ),

                  const SizedBox(width: AppSpacing.md),

                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _isSharing ? null : _shareClip,
                      icon: _isSharing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.share),
                      label: const Text('Share'),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: AppSpacing.md),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.check),
                  label: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}