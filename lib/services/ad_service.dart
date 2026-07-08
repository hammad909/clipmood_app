import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Central AdMob configuration for ClipMood.
///
/// Development uses Google's official sample ad unit IDs so you can test safely.
/// Replace the production IDs before publishing the app.
class AdService {
  AdService._();

  static final AdService instance = AdService._();

  /// Keep true while developing/testing.
  /// Set false only after adding real AdMob app/ad unit IDs.
  static const bool useTestAds = true;

  /// Later connect this to your real premium entitlement/subscription state.
  static const bool isPremiumUser = false;

  /// Replace these before release.
  static const String androidProductionBannerAdUnitId =
      'ca-app-pub-4216236017253903/5566465090';
  static const String iosProductionBannerAdUnitId =
      'ca-app-pub-xxxxxxxxxxxxxxxx/yyyyyyyyyy';
  static const String androidProductionInterstitialAdUnitId =
      'ca-app-pub-4216236017253903/6093114090';
  static const String iosProductionInterstitialAdUnitId =
      'ca-app-pub-xxxxxxxxxxxxxxxx/yyyyyyyyyy';

  /// Official Google sample ad unit IDs.
  static const String androidTestBannerAdUnitId =
      'ca-app-pub-3940256099942544/6300978111';
  static const String iosTestBannerAdUnitId =
      'ca-app-pub-3940256099942544/2934735716';
  static const String androidTestInterstitialAdUnitId =
      'ca-app-pub-3940256099942544/1033173712';
  static const String iosTestInterstitialAdUnitId =
      'ca-app-pub-3940256099942544/4411468910';

  bool _initialized = false;
  bool _interstitialLoading = false;
  InterstitialAd? _interstitialAd;
  int _successfulExportCounter = 0;

  bool get isInitialized => _initialized;

  bool get canRequestAds {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  bool get shouldShowAds => canRequestAds && !isPremiumUser;

  String get bannerAdUnitId {
    if (!canRequestAds) return '';

    if (Platform.isAndroid) {
      return useTestAds
          ? androidTestBannerAdUnitId
          : androidProductionBannerAdUnitId;
    }

    return useTestAds ? iosTestBannerAdUnitId : iosProductionBannerAdUnitId;
  }

  String get interstitialAdUnitId {
    if (!canRequestAds) return '';

    if (Platform.isAndroid) {
      return useTestAds
          ? androidTestInterstitialAdUnitId
          : androidProductionInterstitialAdUnitId;
    }

    return useTestAds
        ? iosTestInterstitialAdUnitId
        : iosProductionInterstitialAdUnitId;
  }

  Future<void> initialize() async {
    if (_initialized) {
      debugPrint('AdMob already initialized.');
      return;
    }

    if (!canRequestAds) {
      debugPrint('AdMob skipped: unsupported platform.');
      return;
    }

    debugPrint('Initializing AdMob... useTestAds=$useTestAds');

    final status = await MobileAds.instance.initialize();
    _initialized = true;

    if (kDebugMode) {
      debugPrint('✅ AdMob initialized. Adapter status: ${status.adapterStatuses}');
      debugPrint('Banner unit: $bannerAdUnitId');
      debugPrint('Interstitial unit: $interstitialAdUnitId');
    }

    loadInterstitialAd();
  }

  BannerAd createBannerAd({
    required AdSize size,
    required BannerAdListener listener,
  }) {
    if (!_initialized) {
      debugPrint(
        '⚠️ Banner requested before AdMob initialization finished. '
        'Make sure main() awaits AdService.instance.initialize().',
      );
    }

    return BannerAd(
      adUnitId: bannerAdUnitId,
      size: size,
      request: const AdRequest(),
      listener: listener,
    );
  }

  void loadInterstitialAd() {
    if (!shouldShowAds || !_initialized) {
      debugPrint('Interstitial skipped: ads disabled or AdMob not initialized.');
      return;
    }

    if (_interstitialLoading || _interstitialAd != null) return;

    _interstitialLoading = true;
    debugPrint('Loading interstitial ad: $interstitialAdUnitId');

    InterstitialAd.load(
      adUnitId: interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          debugPrint('✅ Interstitial ad loaded.');
          _interstitialLoading = false;
          _interstitialAd = ad;
        },
        onAdFailedToLoad: (error) {
          debugPrint(
            '❌ Interstitial failed: '
            'code=${error.code}, domain=${error.domain}, message=${error.message}',
          );
          _interstitialLoading = false;
          _interstitialAd = null;
        },
      ),
    );
  }

  /// Use after meaningful actions only.
  /// Current rule: show an interstitial after every 2 successful single exports.
  void maybeShowInterstitialAfterExport() {
    if (!shouldShowAds || !_initialized) return;

    _successfulExportCounter++;

    if (_successfulExportCounter % 2 != 0) {
      debugPrint(
        'Export saved. Interstitial counter=$_successfulExportCounter. '
        'Will show after next successful export.',
      );
      loadInterstitialAd();
      return;
    }

    _showLoadedInterstitial(reason: 'every_2_exports');
  }

  /// Use after batch exports such as Save All / Save Selected.
  /// This tries to show immediately after the batch completes, because the user
  /// is at a natural break and the export flow is finished.
  void showInterstitialAfterBatchExport() {
    if (!shouldShowAds || !_initialized) return;

    debugPrint('Batch export completed. Trying to show interstitial.');
    _showLoadedInterstitial(reason: 'batch_export_complete');
  }

  void _showLoadedInterstitial({required String reason}) {
    final ad = _interstitialAd;
    if (ad == null) {
      debugPrint('Interstitial not ready for $reason. Loading again.');
      loadInterstitialAd();
      return;
    }

    _interstitialAd = null;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        debugPrint('Interstitial shown. reason=$reason');
      },
      onAdDismissedFullScreenContent: (ad) {
        debugPrint('Interstitial dismissed.');
        ad.dispose();
        loadInterstitialAd();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint(
          '❌ Interstitial failed to show: '
          'code=${error.code}, domain=${error.domain}, message=${error.message}',
        );
        ad.dispose();
        loadInterstitialAd();
      },
    );

    ad.show();
  }

  void disposeInterstitial() {
    _interstitialAd?.dispose();
    _interstitialAd = null;
  }
}
