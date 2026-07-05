import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'screens/saved_clips_screen.dart';
import 'screens/video_editor_screen.dart';
import 'services/video_picker_service.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const ClipMoodApp());
}

class ClipMoodApp extends StatelessWidget {
  const ClipMoodApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ClipMood',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const HomeScreen(),
    );
  }
}

/// Snapshot of the local clips library used to drive the home screen.
class _ClipsSummary {
  final int count;
  final List<File> recent;

  const _ClipsSummary({required this.count, required this.recent});

  static const empty = _ClipsSummary(count: 0, recent: []);
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final VideoPickerService _videoPickerService = VideoPickerService();

  bool _isPickingVideo = false;
  late Future<_ClipsSummary> _clipsSummaryFuture;

  @override
  void initState() {
    super.initState();
    _clipsSummaryFuture = _loadClipsSummary();
  }

  Future<_ClipsSummary> _loadClipsSummary() async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final clipsDir = Directory('${docsDir.path}/clips');

      if (!await clipsDir.exists()) return _ClipsSummary.empty;

      final files = clipsDir
          .listSync()
          .whereType<File>()
          .where((file) => file.path.toLowerCase().endsWith('.mp4'))
          .toList()
        ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

      return _ClipsSummary(
        count: files.length,
        recent: files.take(3).toList(),
      );
    } catch (_) {
      return _ClipsSummary.empty;
    }
  }

  void _refreshClipsSummary() {
    if (!mounted) return;
    setState(() {
      _clipsSummaryFuture = _loadClipsSummary();
    });
  }

  Future<void> _pickVideo() async {
    if (_isPickingVideo) return;

    setState(() {
      _isPickingVideo = true;
    });

    try {
      final selectedVideo = await _videoPickerService.pickVideoFromGallery();

      if (!mounted) return;

      if (selectedVideo == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No video selected.')),
        );
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VideoEditorScreen(video: selectedVideo),
        ),
      );

      _refreshClipsSummary();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pick video: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isPickingVideo = false;
        });
      }
    }
  }

  Future<void> _openSavedClips() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SavedClipsScreen()),
    );

    _refreshClipsSummary();
  }

  String _cleanFileName(String path) {
    final name = path.split(Platform.pathSeparator).last;
    return name.replaceAll('.mp4', '').replaceAll('_', ' ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.xxl,
                AppSpacing.xl,
                AppSpacing.xl,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - AppSpacing.xxl * 2,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildBrandMark(),
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      'ClipMood',
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontSize: 30),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    const Text(
                      'AI finds the best moments in your video.\nYou just pick, trim, and share.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxxl),
                    _buildFeatureRow(),
                    const SizedBox(height: AppSpacing.xxxl),
                    FutureBuilder<_ClipsSummary>(
                      future: _clipsSummaryFuture,
                      builder: (context, snapshot) {
                        final summary = snapshot.data ?? _ClipsSummary.empty;

                        if (summary.count == 0) {
                          return const SizedBox.shrink();
                        }

                        return Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
                          child: _buildRecentClipsCard(summary),
                        );
                      },
                    ),
                    ElevatedButton.icon(
                      onPressed: _isPickingVideo ? null : _pickVideo,
                      icon: _isPickingVideo
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.video_call_outlined),
                      label: Text(
                        _isPickingVideo ? 'Opening Gallery...' : 'Import a Video',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _buildSavedClipsButton(),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBrandMark() {
    return Center(
      child: Container(
        width: 88,
        height: 88,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: AppGradients.hero,
          boxShadow: AppShadows.glow(AppColors.primary),
        ),
        child: const Icon(
          Icons.movie_creation_rounded,
          color: Colors.white,
          size: 40,
        ),
      ),
    );
  }

  Widget _buildFeatureRow() {
    return const Row(
      children: [
        Expanded(
          child: _FeatureChip(
            icon: Icons.auto_awesome,
            label: 'AI Detection',
          ),
        ),
        SizedBox(width: AppSpacing.md),
        Expanded(
          child: _FeatureChip(
            icon: Icons.content_cut,
            label: 'Smart Trim',
          ),
        ),
        SizedBox(width: AppSpacing.md),
        Expanded(
          child: _FeatureChip(
            icon: Icons.ios_share,
            label: 'Instant Share',
          ),
        ),
      ],
    );
  }

  Widget _buildRecentClipsCard(_ClipsSummary summary) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: AppRadius.lgRadius,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.history, size: 18, color: AppColors.secondary),
              const SizedBox(width: AppSpacing.sm),
              const Expanded(
                child: Text(
                  'Recent Clips',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                '${summary.count} total',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ...summary.recent.map(
            (file) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.cardBackgroundSubtle,
                      borderRadius: AppRadius.mdRadius,
                    ),
                    child: const Icon(
                      Icons.movie_outlined,
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      _cleanFileName(file.path),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: _openSavedClips,
              child: const Text('View All Saved Clips'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSavedClipsButton() {
    return FutureBuilder<_ClipsSummary>(
      future: _clipsSummaryFuture,
      builder: (context, snapshot) {
        final count = snapshot.data?.count ?? 0;

        return OutlinedButton.icon(
          onPressed: _openSavedClips,
          icon: const Icon(Icons.video_library_outlined),
          label: Text(count > 0 ? 'Saved Clips  ·  $count' : 'Saved Clips'),
        );
      },
    );
  }
}

class _FeatureChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _FeatureChip({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.lg,
        horizontal: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: AppRadius.lgRadius,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.secondary, size: 22),
          const SizedBox(height: AppSpacing.sm),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}