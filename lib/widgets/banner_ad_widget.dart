import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../services/ad_manager.dart';
import '../services/ad_free_manager.dart';
import '../services/analytics_service.dart';

/// バナー広告ウィジェット
class BannerAdWidget extends StatefulWidget {
  const BannerAdWidget({super.key});

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;
  int _loadAttempts = 0;
  static const int _maxLoadAttempts = 3;
  double? _lastWidth; // 直近でロードした幅（向き/幅変化対応）

  @override
  void initState() {
    super.initState();
    // サイズが分かってからロードする（LayoutBuilderで処理）
  }

  /// Anchored Adaptive サイズを算出してバナー広告を読み込み
  Future<void> _loadBannerAdForWidth(double availableWidth) async {
    if (_loadAttempts >= _maxLoadAttempts) {
      debugPrint('BannerAdWidget: 最大試行回数($_maxLoadAttempts)に達したため停止');
      return; // 最大試行回数に達した場合は停止
    }

    debugPrint('BannerAdWidget: バナー広告読み込み開始 (試行回数: ${_loadAttempts + 1}, 幅: ${availableWidth.toStringAsFixed(1)})');

    _bannerAd?.dispose(); // 既存の広告があれば破棄
    _isLoaded = false;

    // 端末の向きに合わせた Anchored Adaptive サイズを取得
    final int adWidth = availableWidth.truncate();
    AnchoredAdaptiveBannerAdSize? adaptiveSize;
    try {
      adaptiveSize = await AdSize.getAnchoredAdaptiveBannerAdSize(
        MediaQuery.of(context).orientation,
        adWidth,
      );
    } catch (e) {
      // 互換API（現行向き）にフォールバック
      try {
        adaptiveSize = await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(adWidth);
      } catch (e2) {
        debugPrint('BannerAdWidget: Adaptiveサイズ取得に失敗。fallbackでAdSize.bannerを使用: $e2');
      }
    }

    final AdSize sizeToUse = adaptiveSize ?? AdSize.banner;

    _bannerAd = BannerAd(
      adUnitId: AdManager.bannerAdUnitId,
      size: sizeToUse,
      request: const AdRequest(), // SDK 6.0.0 - シンプルなAdRequest
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          debugPrint('BannerAdWidget: バナー広告読み込み成功');

          // 広告表示統計を送信（広告最適化の核心）
          AnalyticsService.logAdImpression(
            adType: 'banner',
            adUnitId: AdManager.bannerAdUnitId,
            placement: 'main_screen',
            networkName: 'AdMob',
          );

          if (mounted) {
            setState(() {
              _isLoaded = true;
            });
            _loadAttempts = 0; // 成功時は試行回数をリセット
          }
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('BannerAdWidget: バナー広告読み込み失敗 - ${error.message} (コード: ${error.code})');
          debugPrint('BannerAdWidget: エラードメイン: ${error.domain}');

          // 広告読み込み失敗統計を送信
          AnalyticsService.logAdLoadFailure(
            adType: 'banner',
            adUnitId: AdManager.bannerAdUnitId,
            placement: 'main_screen',
            errorCode: error.code,
            errorMessage: error.message,
            loadAttempt: _loadAttempts + 1,
          );

          ad.dispose();
          _loadAttempts++;

          // 再試行（指数バックオフ）
          if (_loadAttempts < _maxLoadAttempts) {
            final delaySeconds = _loadAttempts * 5; // 5秒、10秒、15秒...
            debugPrint('BannerAdWidget: $delaySeconds秒後に再試行 ($_loadAttempts/$_maxLoadAttempts)');
            Future.delayed(Duration(seconds: delaySeconds), () {
              if (mounted) {
                if (_lastWidth != null) {
                  _loadBannerAdForWidth(_lastWidth!);
                }
              }
            });
          } else {
            debugPrint('BannerAdWidget: 全ての再試行が失敗しました');
          }
        },
        onAdOpened: (ad) {
          debugPrint('BannerAdWidget: バナー広告がタップされました');

          // 広告クリック統計を送信（重要な収益指標）
          AnalyticsService.logAdClick(
            adType: 'banner',
            adUnitId: AdManager.bannerAdUnitId,
            placement: 'main_screen',
            networkName: 'AdMob',
          );
        },
        onAdClosed: (ad) {
          debugPrint('BannerAdWidget: バナー広告が閉じられました');
        },
      ),
    );

    _bannerAd!.load();
    _lastWidth = availableWidth;
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double maxWidth =
            constraints.maxWidth.isFinite ? constraints.maxWidth : MediaQuery.of(context).size.width;
        if (_lastWidth == null || (maxWidth - (_lastWidth ?? 0)).abs() > 1.0) {
          // 幅が未設定または変化したら再ロード
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _loadBannerAdForWidth(maxWidth);
            }
          });
        }

        return StreamBuilder<bool>(
          stream: AdFreeManager.adFreeStatusStream,
          initialData: AdFreeManager.getCachedAdFreeStatus(),
          builder: (context, snapshot) {
            final isAdFree = snapshot.data ?? false;

            // 広告非表示期間中は表示しない
            if (isAdFree) return const SizedBox.shrink();

            // 読み込み前は非表示
            if (!_isLoaded || _bannerAd == null) return const SizedBox.shrink();

            return RepaintBoundary(
              child: Container(
                width: _bannerAd!.size.width.toDouble(),
                height: _bannerAd!.size.height.toDouble() + 20,
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  border: Border(
                    top: BorderSide(
                      color: Colors.grey[300]!,
                      width: 1,
                    ),
                  ),
                ),
                child: AdWidget(ad: _bannerAd!),
              ),
            );
          },
        );
      },
    );
  }
}
