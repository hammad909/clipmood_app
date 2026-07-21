import 'dart:ui';

import 'package:flutter/material.dart';

import 'models/selected_video.dart';
import 'screens/premium_coming_soon_screen.dart';
import 'screens/saved_clips_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/manual_trim_screen.dart';
import 'screens/video_editor_screen.dart';
import 'services/ad_service.dart';
import 'services/video_picker_service.dart';
import 'theme/app_theme.dart';

const String _appBackgroundAsset =
    'assets/images/Gemini_Generated_Image_49hhhd49hhhd49hh.png';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AdService.instance.initialize();
  runApp(const ClipMoodApp());
}

class ClipMoodApp extends StatefulWidget {
  const ClipMoodApp({super.key});

  @override
  State<ClipMoodApp> createState() => _ClipMoodAppState();
}

class _ClipMoodAppState extends State<ClipMoodApp> {
  bool _backgroundEnabled = true;
  double _backgroundOpacity = 0.90;

  void _setBackgroundEnabled(bool value) {
    setState(() {
      _backgroundEnabled = value;
    });
  }

  void _setBackgroundOpacity(double value) {
    setState(() {
      _backgroundOpacity = value.clamp(0.35, 1.0);
    });
  }

  void _resetAppearance() {
    setState(() {
      _backgroundEnabled = true;
      _backgroundOpacity = 0.90;
    });
  }

  @override
  Widget build(BuildContext context) {
    final baseTheme = AppTheme.darkTheme;

    return MaterialApp(
      title: 'ClipMood',
      debugShowCheckedModeBanner: false,
      theme: baseTheme.copyWith(
        scaffoldBackgroundColor: Colors.transparent,
        canvasColor: Colors.transparent,
        appBarTheme: baseTheme.appBarTheme.copyWith(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
      ),
      builder: (context, child) {
        return _AppBackground(
          enabled: _backgroundEnabled,
          imageOpacity: _backgroundOpacity,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: HomeScreen(
        backgroundEnabled: _backgroundEnabled,
        backgroundOpacity: _backgroundOpacity,
        onBackgroundEnabledChanged: _setBackgroundEnabled,
        onBackgroundOpacityChanged: _setBackgroundOpacity,
        onResetAppearance: _resetAppearance,
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final bool backgroundEnabled;
  final double backgroundOpacity;
  final ValueChanged<bool> onBackgroundEnabledChanged;
  final ValueChanged<double> onBackgroundOpacityChanged;
  final VoidCallback onResetAppearance;

  const HomeScreen({
    super.key,
    required this.backgroundEnabled,
    required this.backgroundOpacity,
    required this.onBackgroundEnabledChanged,
    required this.onBackgroundOpacityChanged,
    required this.onResetAppearance,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final VideoPickerService _videoPickerService = VideoPickerService();

  bool _isPickingAiVideo = false;
  bool _isPickingManualVideo = false;

  bool get _isPickingVideo =>
      _isPickingAiVideo || _isPickingManualVideo;

  void _refreshSavedClipsCount() {
    if (!mounted) return;
    setState(() {});
  }

  Future<SelectedVideo?> _pickAndValidateFreePlanVideo() async {
    final selectedVideo = await _videoPickerService.pickVideoFromGallery();

    if (!mounted) return null;

    if (selectedVideo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No video selected.'),
        ),
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
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.lgRadius,
          ),
          title: const Row(
            children: [
              Icon(
                Icons.lock_clock,
                color: AppColors.warning,
              ),
              SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text('Video not allowed'),
              ),
            ],
          ),
          content: Text(
            validation.message ??
                'Free AI scan supports videos from 1 minute to 5 minutes.',
            style: const TextStyle(
              color: AppColors.textSecondary,
            ),
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

  Future<void> _pickVideoForAiScan() async {
    if (_isPickingVideo) return;

    setState(() {
      _isPickingAiVideo = true;
    });

    try {
      final selectedVideo = await _pickAndValidateFreePlanVideo();

      if (!mounted || selectedVideo == null) return;

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VideoEditorScreen(
            video: selectedVideo,
          ),
        ),
      );

      _refreshSavedClipsCount();
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to pick video: $error'),
        ),
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
      final selectedVideo =
          await _videoPickerService.pickVideoFromGallery();

      if (!mounted) return;

      if (selectedVideo == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No video selected.'),
          ),
        );
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ManualTrimScreen(
            video: selectedVideo,
          ),
        ),
      );

      _refreshSavedClipsCount();
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to open manual trim: $error'),
        ),
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
      MaterialPageRoute(
        builder: (_) => const SavedClipsScreen(),
      ),
    );

    _refreshSavedClipsCount();
  }

  Future<void> _openPremiumScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const PremiumComingSoonScreen(),
      ),
    );
  }

  void _onBottomNavigationSelected(int index) {
    switch (index) {
      case 0:
        // Already on Studio.
        break;
      case 1:
        _pickVideoForManualTrim();
        break;
      case 2:
        _pickVideoForAiScan();
        break;
      case 3:
        _openSavedClips();
        break;
      case 4:
        _openSettings();
        break;
    }
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          backgroundEnabled: widget.backgroundEnabled,
          backgroundOpacity: widget.backgroundOpacity,
          onBackgroundEnabledChanged:
              widget.onBackgroundEnabledChanged,
          onBackgroundOpacityChanged:
              widget.onBackgroundOpacityChanged,
          onResetAppearance: widget.onResetAppearance,
          onOpenSavedClips: _openSavedClips,
          onOpenPremium: _openPremiumScreen,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        title: const Text('ClipMood Studio'),
        actions: [
          _PremiumAppBarAction(
            onTap: _openPremiumScreen,
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.sm,
        ),
        child: _ClipMoodBottomNavigationBar(
          selectedIndex: 0,
          isScanning: _isPickingAiVideo,
          isManualTrimOpening: _isPickingManualVideo,
          onDestinationSelected: _onBottomNavigationSelected,
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 640;
            final logoSize = compact ? 66.0 : 86.0;

            return SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                AppSpacing.xl,
                compact ? AppSpacing.md : AppSpacing.xl,
                AppSpacing.xl,
                124,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 124,
                ),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Spacer(),
                      _buildBrandMark(size: logoSize),
                      SizedBox(
                        height: compact ? AppSpacing.md : AppSpacing.lg,
                      ),
                      Text(
                        'Find clips worth sharing',
                        textAlign: TextAlign.center,
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontSize: compact ? 25 : 29,
                                  fontWeight: FontWeight.w900,
                                ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      const Text(
                        'Choose a video and let ClipMood find the strongest, '
                        'most eye-catching moments for you.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                      SizedBox(
                        height: compact ? AppSpacing.lg : AppSpacing.xl,
                      ),
                      const _AiScanHintCard(),
                      if (!compact) ...[
                        const SizedBox(height: AppSpacing.xl),
                        _buildFeatureRow(),
                      ],
                      const Spacer(),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBrandMark({
    required double size,
  }) {
    return Center(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.28),
          boxShadow: AppShadows.glow(
            AppColors.primary,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.asset(
          'assets/icon/clipmood_icon.png',
          fit: BoxFit.cover,
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
            icon: Icons.bolt_rounded,
            label: 'Smart Highlights',
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
}

class _AppBackground extends StatelessWidget {
  final Widget child;
  final bool enabled;
  final double imageOpacity;

  const _AppBackground({
    required this.child,
    required this.enabled,
    required this.imageOpacity,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(
          color: Color(0xFF07091D),
        ),
        if (enabled) ...[
          Positioned.fill(
            child: IgnorePointer(
              child: Opacity(
                opacity: imageOpacity,
                child: Image.asset(
                  _appBackgroundAsset,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (context, error, stackTrace) {
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
          ),
          const Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x1A000000),
                      Color(0x12000000),
                      Color(0x70000000),
                    ],
                    stops: [
                      0.0,
                      0.48,
                      1.0,
                    ],
                  ),
                ),
              ),
            ),
          ),
          const Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0.72, -0.84),
                    radius: 1.25,
                    colors: [
                      Color(0x249C68FF),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
        child,
      ],
    );
  }
}

class _AiScanHintCard extends StatelessWidget {
  const _AiScanHintCard();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: AppRadius.lgRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: 16,
          sigmaY: 16,
        ),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: const Color(0xA817193A),
            borderRadius: AppRadius.lgRadius,
            border: Border.all(
              color: Colors.white.withAlpha(35),
            ),
          ),
          child: const Row(
            children: [
              _HintIcon(),
              SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ready to scan?',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Tap the purple AI Scan button below to choose a video.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                        height: 1.35,
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

class _HintIcon extends StatelessWidget {
  const _HintIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppGradients.hero,
        boxShadow: AppShadows.glow(
          AppColors.primary,
        ),
      ),
      child: const Icon(
        Icons.auto_awesome,
        color: Colors.white,
        size: 23,
      ),
    );
  }
}

class _ClipMoodBottomNavigationBar extends StatelessWidget {
  final int selectedIndex;
  final bool isScanning;
  final bool isManualTrimOpening;
  final ValueChanged<int> onDestinationSelected;

  const _ClipMoodBottomNavigationBar({
    required this.selectedIndex,
    required this.isScanning,
    required this.isManualTrimOpening,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final primary = colorScheme.primary;
    final secondary = colorScheme.secondary;

    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: 22,
          sigmaY: 22,
        ),
        child: Container(
          height: 82,
          padding: const EdgeInsets.symmetric(
            horizontal: 6,
          ),
          decoration: BoxDecoration(
            color: const Color(0xD9161738),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: Colors.white.withAlpha(38),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(80),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
              BoxShadow(
                color: primary.withAlpha(38),
                blurRadius: 24,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: _NavigationItemButton(
                  label: 'Studio',
                  icon: Icons.home_outlined,
                  selectedIcon: Icons.home_rounded,
                  selected: selectedIndex == 0,
                  activeColor: primary,
                  onTap: isScanning || isManualTrimOpening
                      ? () {}
                      : () => onDestinationSelected(0),
                ),
              ),
              Expanded(
                child: _NavigationItemButton(
                  label: isManualTrimOpening
                      ? 'Opening...'
                      : 'Trim',
                  icon: isManualTrimOpening
                      ? Icons.hourglass_top_rounded
                      : Icons.content_cut_outlined,
                  selectedIcon: Icons.content_cut_rounded,
                  selected: selectedIndex == 1,
                  activeColor: primary,
                  onTap: isScanning || isManualTrimOpening
                      ? () {}
                      : () => onDestinationSelected(1),
                ),
              ),
              Expanded(
                child: _CenterAiScanButton(
                  isScanning: isScanning,
                  primary: primary,
                  secondary: secondary,
                  onTap: isScanning || isManualTrimOpening
                      ? null
                      : () => onDestinationSelected(2),
                ),
              ),
              Expanded(
                child: _NavigationItemButton(
                  label: 'Saved',
                  icon: Icons.video_library_outlined,
                  selectedIcon: Icons.video_library_rounded,
                  selected: selectedIndex == 3,
                  activeColor: primary,
                  onTap: isScanning || isManualTrimOpening
                      ? () {}
                      : () => onDestinationSelected(3),
                ),
              ),
              Expanded(
                child: _NavigationItemButton(
                  label: 'Settings',
                  icon: Icons.settings_outlined,
                  selectedIcon: Icons.settings_rounded,
                  selected: selectedIndex == 4,
                  activeColor: primary,
                  onTap: isScanning || isManualTrimOpening
                      ? () {}
                      : () => onDestinationSelected(4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavigationItemButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final bool selected;
  final Color activeColor;
  final VoidCallback onTap;

  const _NavigationItemButton({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.selected,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final inactiveColor = Colors.white.withAlpha(150);

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(
            horizontal: 1,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            color: selected
                ? activeColor.withAlpha(30)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                selected ? selectedIcon : icon,
                size: 24,
                color: selected ? activeColor : inactiveColor,
              ),
              const SizedBox(height: 5),
              Text(
                label,
                style: TextStyle(
                  color: selected ? activeColor : inactiveColor,
                  fontSize: 9,
                  height: 1,
                  fontWeight:
                      selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CenterAiScanButton extends StatelessWidget {
  final bool isScanning;
  final Color primary;
  final Color secondary;
  final VoidCallback? onTap;

  const _CenterAiScanButton({
    required this.isScanning,
    required this.primary,
    required this.secondary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'AI Scan',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    primary,
                    secondary,
                  ],
                ),
                border: Border.all(
                  color: Colors.white.withAlpha(85),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: primary.withAlpha(125),
                    blurRadius: 21,
                    spreadRadius: 1,
                    offset: const Offset(0, 7),
                  ),
                ],
              ),
              child: isScanning
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(
                      Icons.auto_awesome_rounded,
                      color: Colors.white,
                      size: 27,
                    ),
            ),
            const SizedBox(height: 3),
            Text(
              isScanning ? 'Opening...' : 'AI Scan',
              maxLines: 1,
              overflow: TextOverflow.fade,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                height: 1,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PremiumAppBarAction extends StatelessWidget {
  final VoidCallback onTap;

  const _PremiumAppBarAction({
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 6,
            vertical: 4,
          ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: AppColors.cardBackgroundSubtle,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: AppColors.border,
                  ),
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

class _FeatureChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _FeatureChip({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: AppRadius.lgRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: 12,
          sigmaY: 12,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.md,
            horizontal: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: const Color(0x99171938),
            borderRadius: AppRadius.lgRadius,
            border: Border.all(
              color: Colors.white.withAlpha(30),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: AppColors.secondary,
                size: 20,
              ),
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
        ),
      ),
    );
  }
}