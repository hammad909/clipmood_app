import 'package:flutter/material.dart';
import 'models/selected_video.dart';
import 'screens/manual_trim_screen.dart';
import 'screens/premium_coming_soon_screen.dart';
import 'screens/saved_clips_screen.dart';
import 'screens/video_editor_screen.dart';
import 'services/ad_service.dart';
import 'services/video_picker_service.dart';
import 'widgets/free_banner_ad.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AdService.instance.initialize();
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

  void _refreshSavedClipsCount() {
    if (!mounted) return;
    setState(() {});
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
          // Premium badge/icon — kept separate from Saved Clips icon, does not replace it.
          _PremiumAppBarAction(onTap: _openPremiumScreen),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      bottomNavigationBar: _buildBottomArea(),
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 640;
            final logoSize = compact ? 64.0 : 82.0;
            final verticalGap = compact ? AppSpacing.md : AppSpacing.lg;

            // Fix for rotation / small-viewport pixel overflow:
            // Wrapping the content in a scroll view with a min-height
            // constraint lets the layout still center itself on tall
            // screens (via Expanded) while gracefully scrolling instead
            // of throwing "RenderFlex overflowed by N pixels" whenever
            // the device rotates to landscape or the keyboard/system UI
            // shrinks the available height.
            return LayoutBuilder(
              builder: (context, _) {
                return SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    compact ? AppSpacing.md : AppSpacing.lg,
                    AppSpacing.xl,
                    AppSpacing.lg,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight -
                          (compact ? AppSpacing.md : AppSpacing.lg) -
                          AppSpacing.lg,
                    ),
                    child: IntrinsicHeight(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(height: verticalGap),
                          Expanded(
                            child: Center(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.center,
                                child: SizedBox(
                                  width: constraints.maxWidth -
                                      (AppSpacing.xl * 2),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _buildBrandMark(size: logoSize),
                                      SizedBox(
                                        height: compact
                                            ? AppSpacing.md
                                            : AppSpacing.lg,
                                      ),
                                      Text(
                                        'Find clips worth sharing',
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineSmall
                                            ?.copyWith(
                                              fontSize: compact ? 24 : 28,
                                            ),
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
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  /// Keeps ads outside the main creative/action area.
  /// This feels cleaner than placing a banner between the title and buttons,
  /// and it prevents the ad from breaking the fixed home layout on small phones.
  Widget _buildBottomArea() {
    return SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: AppColors.border, width: 0.8),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 6, bottom: 4),
              child: FreeBannerAd(
                placement: 'home_above_navigation',
                showLabel: true,
              ),
            ),
            NavigationBar(
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
          ],
        ),
      ),
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
          // filterQuality avoids the blocky/aliased "pixel" look when the
          // icon asset is scaled up or down for different logoSize values.
          filterQuality: FilterQuality.high,
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

/// Small "Premium · Free" indicator placed in the AppBar, to the left of the
/// existing Saved Clips icon (which is left untouched). Uses a Stack so the
/// badge text never forces extra layout height/width that could clip or
/// overflow on narrow screens.
class _PremiumAppBarAction extends StatelessWidget {
  final VoidCallback onTap;

  const _PremiumAppBarAction({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.workspace_premium_outlined,
                color: AppColors.secondary,
                size: 22,
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.cardBackgroundSubtle,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Text(
                  'FREE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ignore: unused_element
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