import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../theme/app_theme.dart';
import 'clip_preview_screen.dart';

class SavedClipsScreen extends StatefulWidget {
  const SavedClipsScreen({super.key});

  @override
  State<SavedClipsScreen> createState() => _SavedClipsScreenState();
}

class _SavedClipsScreenState extends State<SavedClipsScreen> {
  bool _isLoading = true;
  List<File> _clips = [];

  @override
  void initState() {
    super.initState();
    _loadSavedClips();
  }

  Future<void> _loadSavedClips() async {
    setState(() {
      _isLoading = true;
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

      files.sort(
        (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
      );

      if (!mounted) return;

      setState(() {
        _clips = files;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _clips = [];
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load saved clips: $e'),
        ),
      );
    }
  }

  Future<void> _shareClip(File clip) async {
    if (!await clip.exists()) return;

    // ignore: deprecated_member_use
    await Share.shareXFiles(
      [XFile(clip.path)],
      text: 'Check out this ClipMood clip!',
    );
  }

  Future<void> _deleteClip(File clip) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete clip?'),
          content: Text(
            'This will delete:\n${_cleanFileName(clip.path)}',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.error,
              ),
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) return;

    try {
      if (await clip.exists()) {
        await clip.delete();
      }

      await _loadSavedClips();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Clip deleted.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete clip: $e'),
        ),
      );
    }
  }

  void _openClip(File clip) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ClipPreviewScreen(
          clipPath: clip.path,
        ),
      ),
    ).then((_) => _loadSavedClips());
  }

  String _cleanFileName(String path) {
    final name = path.split(Platform.pathSeparator).last;
    return name.replaceAll('.mp4', '').replaceAll('_', ' ');
  }

  String _fileSize(File file) {
    final bytes = file.lengthSync();

    if (bytes < 1024) {
      return '$bytes B';
    }

    final kb = bytes / 1024;

    if (kb < 1024) {
      return '${kb.toStringAsFixed(1)} KB';
    }

    final mb = kb / 1024;

    return '${mb.toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Clips'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadSavedClips,
            icon: const Icon(Icons.refresh),
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
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_clips.isEmpty) {
      return Center(
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
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
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
      );
    }

    return RefreshIndicator(
      onRefresh: _loadSavedClips,
      child: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.lg),
        itemCount: _clips.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
        itemBuilder: (context, index) {
          final clip = _clips[index];

          return _SavedClipCard(
            clip: clip,
            title: _cleanFileName(clip.path),
            size: _fileSize(clip),
            onOpen: () => _openClip(clip),
            onShare: () => _shareClip(clip),
            onDelete: () => _deleteClip(clip),
          );
        },
      ),
    );
  }
}

class _SavedClipCard extends StatefulWidget {
  final File clip;
  final String title;
  final String size;
  final VoidCallback onOpen;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  const _SavedClipCard({
    required this.clip,
    required this.title,
    required this.size,
    required this.onOpen,
    required this.onShare,
    required this.onDelete,
  });

  @override
  State<_SavedClipCard> createState() => _SavedClipCardState();
}

class _SavedClipCardState extends State<_SavedClipCard> {
  VideoPlayerController? _controller;
  bool _isVideoReady = false;

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
        _isVideoReady = true;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _isVideoReady = false;
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
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onOpen,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: AspectRatio(
                aspectRatio: 9 / 14,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_isVideoReady && controller != null)
                      FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: controller.value.size.width,
                          height: controller.value.size.height,
                          child: VideoPlayer(controller),
                        ),
                      )
                    else
                      Container(
                        color: Colors.black,
                        child: const Center(
                          child: Icon(
                            Icons.movie,
                            size: 32,
                            color: AppColors.textDisabled,
                          ),
                        ),
                      ),
                    Container(
                      color: Colors.black.withValues(alpha: 0.16),
                    ),
                    const Center(
                      child: Icon(
                        Icons.play_circle_fill,
                        size: 36,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      widget.size,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(48, 40),
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                            ),
                            onPressed: widget.onShare,
                            icon: const Icon(Icons.share, size: 16),
                            label: const Text('Share'),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        IconButton(
                          tooltip: 'Delete',
                          onPressed: widget.onDelete,
                          icon: const Icon(
                            Icons.delete_outline,
                            color: AppColors.error,
                          ),
                        ),
                      ],
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
}