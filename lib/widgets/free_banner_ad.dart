import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../services/ad_service.dart';
import '../theme/app_theme.dart';

class FreeBannerAd extends StatefulWidget {
  final String placement;
  final bool showLabel;

  /// In debug mode this shows a small status box when the ad is loading or fails.
  /// In release mode failed/loading ads stay hidden so users do not see debug UI.
  final bool showDebugStatus;

  const FreeBannerAd({
    super.key,
    required this.placement,
    this.showLabel = true,
    this.showDebugStatus = kDebugMode,
  });

  @override
  State<FreeBannerAd> createState() => _FreeBannerAdState();
}

class _FreeBannerAdState extends State<FreeBannerAd> {
  BannerAd? _bannerAd;
  AdSize? _adSize;

  bool _loading = false;
  bool _loaded = false;
  bool _failed = false;
  String? _errorMessage;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadAdIfNeeded();
  }

  Future<void> _loadAdIfNeeded() async {
    if (_loading || _loaded || _bannerAd != null) return;

    if (!AdService.instance.shouldShowAds) {
      debugPrint('Ads disabled for placement: ${widget.placement}');
      return;
    }

    setState(() {
      _loading = true;
      _failed = false;
      _errorMessage = null;
    });

    final screenWidth = MediaQuery.sizeOf(context).width.truncate();

    final adaptiveSize =
        await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(
      screenWidth,
    );

    if (!mounted) return;

    final size = adaptiveSize ?? AdSize.banner;
    _adSize = size;

    debugPrint(
      'Loading banner ad: placement=${widget.placement}, '
      'unit=${AdService.instance.bannerAdUnitId}, size=${size.width}x${size.height}',
    );

    final ad = AdService.instance.createBannerAd(
      size: size,
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          debugPrint('✅ Banner ad loaded: ${widget.placement}');
          if (!mounted) return;
          setState(() {
            _loading = false;
            _loaded = true;
            _failed = false;
            _errorMessage = null;
          });
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint(
            '❌ Banner ad failed: ${widget.placement} | '
            'code=${error.code}, domain=${error.domain}, message=${error.message}',
          );
          ad.dispose();
          if (!mounted) return;
          setState(() {
            _bannerAd = null;
            _loading = false;
            _loaded = false;
            _failed = true;
            _errorMessage = '${error.code}: ${error.message}';
          });
        },
        onAdOpened: (ad) {
          debugPrint('Banner ad opened: ${widget.placement}');
        },
        onAdClosed: (ad) {
          debugPrint('Banner ad closed: ${widget.placement}');
        },
      ),
    );

    _bannerAd = ad;
    await ad.load();
  }

  void _retry() {
    _bannerAd?.dispose();
    setState(() {
      _bannerAd = null;
      _adSize = null;
      _loading = false;
      _loaded = false;
      _failed = false;
      _errorMessage = null;
    });
    _loadAdIfNeeded();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!AdService.instance.shouldShowAds) {
      return const SizedBox.shrink();
    }

    final ad = _bannerAd;
    final adSize = _adSize;

    if (ad != null && adSize != null && _loaded) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.only(top: 6, bottom: 6),
        decoration: const BoxDecoration(
          color: AppColors.cardBackground,
          border: Border(
            top: BorderSide(color: AppColors.border),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.showLabel) ...[
              const Text(
                'Sponsored',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
            ],
            Center(
              child: SizedBox(
                width: adSize.width.toDouble(),
                height: adSize.height.toDouble(),
                child: AdWidget(ad: ad),
              ),
            ),
          ],
        ),
      );
    }

    if (!widget.showDebugStatus || !kDebugMode) {
      return const SizedBox.shrink();
    }

    if (_loading) {
      return _AdDebugBox(
        icon: Icons.hourglass_bottom,
        title: 'Loading test ad...',
        message: widget.placement,
      );
    }

    if (_failed) {
      return _AdDebugBox(
        icon: Icons.error_outline,
        title: 'Ad failed to load',
        message: _errorMessage ?? 'Unknown error',
        onRetry: _retry,
      );
    }

    return const SizedBox.shrink();
  }
}

class _AdDebugBox extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;

  const _AdDebugBox({
    required this.icon,
    required this.title,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: const BoxDecoration(
        color: AppColors.cardBackground,
        border: Border(
          top: BorderSide(color: AppColors.border),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.warning),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  }
}
