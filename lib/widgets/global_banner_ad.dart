import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../services/ad_manager.dart';

/// アプリ全体の画面下部に表示するバナー広告
class GlobalBannerAd extends StatefulWidget {
  final Widget child;

  const GlobalBannerAd({required this.child, super.key});

  @override
  State<GlobalBannerAd> createState() => _GlobalBannerAdState();
}

class _GlobalBannerAdState extends State<GlobalBannerAd> {
  BannerAd? _bannerAd;
  bool _isBannerAdLoaded = false;

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  /// バナー広告を読み込む
  Future<void> _loadBannerAd(int width) async {
    final AnchoredAdaptiveBannerAdSize? size = await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(width);

    if (size == null || !mounted) {
      return;
    }

    _bannerAd = BannerAd(
      adUnitId: AdManager.bannerAdUnitId,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (mounted) {
            setState(() {
              _isBannerAdLoaded = true;
            });
          }
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
        },
      ),
    );
    _bannerAd?.load();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 広告がまだ読み込まれていない場合、読み込みを開始
        if (_bannerAd == null && !_isBannerAdLoaded) {
          // 次のフレームで読み込みを開始
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _loadBannerAd(constraints.maxWidth.truncate());
            }
          });
        }

        return Column(
          children: [
            Expanded(child: widget.child),
            // バナー広告
            if (_isBannerAdLoaded && _bannerAd != null)
              SafeArea(
                top: false,
                child: Container(
                  width: _bannerAd!.size.width.toDouble(),
                  height: _bannerAd!.size.height.toDouble(),
                  alignment: Alignment.center,
                  child: AdWidget(ad: _bannerAd!),
                ),
              ),
          ],
        );
      },
    );
  }
}
