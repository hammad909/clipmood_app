import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'models/selected_video.dart';
import 'screens/manual_trim_screen.dart';
import 'screens/premium_coming_soon_screen.dart';
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

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final VideoPickerService _videoPickerService = VideoPickerService();

  bool _isPickingAiVideo = false;
  bool _isPickingManualVideo = false;

  bool get _isPickingVideo => _isPickingAiVideo || _isPickingManualVideo;

  late Future<int> _savedClipsCountFuture;

  @override
  void initState() {
    super.initState();
    _savedClipsCountFuture = _loadSavedClipsCount();
  }

  Future<int> _loadSavedClipsCount() async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final clipsDir = Directory('${docsDir.path}/clips');

      if (!await clipsDir.exists()) return 0;

      return clipsDir
          .listSync()
          .whereType<File>()
          .where((file) => file.path.toLowerCase().endsWith('.mp4'))
          .length;
    } catch (_) {
      return 0;
    }
  }

  void _refreshSavedClipsCount() {
    if (!mounted) return;
    setState(() {
      _savedClipsCountFuture = _loadSavedClipsCount();
    });
  }

  Future<SelectedVideo?> _pickAndValidateFreePlanVideo() async {
    final selectedVideo = await _videoPickerService.pickVideoFromGallery();

    if (!mounted) return null;

    if (selectedVideo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No video selected.')),
      );
      return null;
    }

    final validation = await _videoPickerService.validateFreeVideoDuration(
      selectedVideo.path,
    );

    if (!mounted) return null;

    if (!validation.isValid) {
      await _showVideoLimitDialog(validation);
      return null;
    }

    return selectedVideo;
  }

  Future<void> _showVideoLimitDialog(
    VideoDurationValidationResult validation,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.surfaceElevated,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.lgRadius),
          title: const Row(
            children: [
              Icon(Icons.lock_clock, color: AppColors.warning),
              SizedBox(width: AppSpacing.sm),
              Expanded(child: Text('Video not allowed')),
            ],
          ),
          content: Text(
            validation.message ??
                'Free AI scan supports videos from 1 minute to 5 minutes.',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Choose Another'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickVideo() async {
    if (_isPickingVideo) return;

    setState(() {
      _isPickingAiVideo = true;
    });

    try {
      final selectedVideo = await _pickAndValidateFreePlanVideo();

      if (!mounted || selectedVideo == null) return;

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VideoEditorScreen(video: selectedVideo),
        ),
      );

      _refreshSavedClipsCount();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pick video: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isPickingAiVideo = false;
        });
      }
    }
  }

  Future<void> _pickVideoForManualTrim() async {
    if (_isPickingVideo) return;

    setState(() {
      _isPickingManualVideo = true;
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
          builder: (_) => ManualTrimScreen(video: selectedVideo),
        ),
      );

      _refreshSavedClipsCount();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to open manual trim: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isPickingManualVideo = false;
        });
      }
    }
  }

  Future<void> _openSavedClips() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SavedClipsScreen()),
    );

    _refreshSavedClipsCount();
  }

  Future<void> _openPremiumScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PremiumComingSoonScreen()),
    );
  }

  void _onBottomNavSelected(int index) {
    switch (index) {
      case 0:
        break;
      case 1:
        _openSavedClips();
        break;
      case 2:
        _openPremiumScreen();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: const Text('ClipMood Studio'),
        actions: [
          IconButton(
            tooltip: 'Saved Clips',
            onPressed: _openSavedClips,
            icon: const Icon(Icons.video_library_outlined),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        onDestinationSelected: _onBottomNavSelected,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Studio',
          ),
          NavigationDestination(
            icon: Icon(Icons.video_library_outlined),
            selectedIcon: Icon(Icons.video_library),
            label: 'Saved',
          ),
          NavigationDestination(
            icon: Icon(Icons.workspace_premium_outlined),
            selectedIcon: Icon(Icons.workspace_premium),
            label: 'Premium',
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 640;
            final logoSize = compact ? 64.0 : 82.0;
            final verticalGap = compact ? AppSpacing.md : AppSpacing.lg;

            return Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.xl,
                compact ? AppSpacing.md : AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildPlanSelector(compact: compact),
                  SizedBox(height: verticalGap),
                  Expanded(
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.center,
                        child: SizedBox(
                          width: constraints.maxWidth - (AppSpacing.xl * 2),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildBrandMark(size: logoSize),
                              SizedBox(height: compact ? AppSpacing.md : AppSpacing.lg),
                              Text(
                                'Find clips worth sharing',
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(fontSize: compact ? 24 : 28),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              const Text(
                                'Use AI for fast clip discovery, or manually cut the exact moment you want.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: AppColors.textSecondary,
                                  height: 1.35,
                                ),
                              ),
                              if (!compact) ...[
                                const SizedBox(height: AppSpacing.xl),
                                _buildFeatureRow(),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: verticalGap),
                  _buildPrimaryActions(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPlanSelector({required bool compact}) {
    return Row(
      children: [
        Expanded(
          child: _PlanMiniCard(
            title: 'Free',
            price: r'$0',
            subtitle: compact ? 'Available now' : 'AI clips + manual trim',
            icon: Icons.auto_awesome,
            selected: true,
            onTap: null,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: _PlanMiniCard(
            title: 'Premium',
            price: r'$49',
            subtitle: compact ? 'Coming soon' : 'Links + stronger AI',
            icon: Icons.workspace_premium,
            selected: false,
            onTap: _openPremiumScreen,
          ),
        ),
      ],
    );
  }

  Widget _buildBrandMark({required double size}) {
    return Center(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.28),
          boxShadow: AppShadows.glow(AppColors.primary),
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.asset(
          'assets/icon/clipmood_icon.png',
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(size * 0.28),
                gradient: AppGradients.hero,
              ),
              child: Icon(
                Icons.movie_creation_rounded,
                color: Colors.white,
                size: size * 0.44,
              ),
            );
          },
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
            label: 'Manual Trim',
          ),
        ),
        SizedBox(width: AppSpacing.md),
        Expanded(
          child: _FeatureChip(
            icon: Icons.ios_share,
            label: 'Save & Share',
          ),
        ),
      ],
    );
  }

  Widget _buildPrimaryActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ElevatedButton.icon(
          onPressed: _isPickingVideo ? null : _pickVideo,
          icon: _isPickingAiVideo
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.auto_awesome),
          label: Text(_isPickingAiVideo ? 'Opening Gallery...' : 'Start AI Scan'),
        ),
        const SizedBox(height: AppSpacing.md),
        OutlinedButton.icon(
          onPressed: _isPickingVideo ? null : _pickVideoForManualTrim,
          icon: _isPickingManualVideo
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.content_cut),
          label: Text(_isPickingManualVideo ? 'Opening Gallery...' : 'Manual Trim'),
        ),
        const SizedBox(height: AppSpacing.sm),
        const Text(
          'AI scan supports 1–5 min videos. Manual Trim supports any video length.',
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 11.5,
            height: 1.25,
          ),
        ),
      ],
    );
  }
}

class _PlanMiniCard extends StatelessWidget {
  final String title;
  final String price;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  const _PlanMiniCard({
    required this.title,
    required this.price,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = selected ? AppColors.primary : AppColors.border;
    final iconColor = selected ? AppColors.primary : AppColors.secondary;

    return Material(
      color: selected ? AppColors.cardBackgroundSubtle : AppColors.cardBackground,
      borderRadius: AppRadius.lgRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.lgRadius,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: AppRadius.lgRadius,
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: AppRadius.mdRadius,
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        Text(
                          price,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: selected ? AppColors.primary : AppColors.secondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
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
        vertical: AppSpacing.md,
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
          Icon(icon, color: AppColors.secondary, size: 20),
          const SizedBox(height: AppSpacing.sm),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
