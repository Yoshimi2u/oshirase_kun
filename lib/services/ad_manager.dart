import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:io';
import 'dart:async';

/// 広告管理クラス
class AdManager {
  static String get bannerAdUnitId {
    if (kDebugMode) {
      print('[AdManager] テスト用バナー広告ID使用');
      // デバッグモードではテスト用IDを使用
      if (Platform.isAndroid) {
        return 'ca-app-pub-3940256099942544/6300978111';
      } else if (Platform.isIOS) {
        return 'ca-app-pub-3940256099942544/2934735716';
      }
    } else {
      // 本番環境では.envから読み込み
      if (Platform.isAndroid) {
        return dotenv.env['ADMOB_BANNER_ANDROID'] ?? 'ca-app-pub-3940256099942544/6300978111';
      } else if (Platform.isIOS) {
        return dotenv.env['ADMOB_BANNER_IOS'] ?? 'ca-app-pub-3940256099942544/2934735716';
      }
    }
    throw UnsupportedError('Unsupported platform');
  }

  // インタースティシャル広告は未使用のためIDは廃止

  /// 設定画面などのインライン表示用バナー広告ユニットIDを取得（今日のタスク用）
  static String get inlineBannerAdUnitId {
    if (kDebugMode) {
      print('[AdManager] テスト用インラインバナー広告ID使用');
      // デバッグモードではテスト用IDを使用
      if (Platform.isAndroid) {
        return 'ca-app-pub-3940256099942544/6300978111';
      } else if (Platform.isIOS) {
        return 'ca-app-pub-3940256099942544/2934735716';
      }
    } else {
      // 本番環境では.envから読み込み
      if (Platform.isAndroid) {
        return dotenv.env['ADMOB_INLINE_BANNER_ANDROID'] ?? 'ca-app-pub-3940256099942544/6300978111';
      } else if (Platform.isIOS) {
        return dotenv.env['ADMOB_INLINE_BANNER_IOS'] ?? 'ca-app-pub-3940256099942544/2934735716';
      }
    }
    throw UnsupportedError('Unsupported platform');
  }

  /// 全予定タブ用のインライン表示用バナー広告ユニットIDを取得
  static String get scheduleInlineBannerAdUnitId {
    if (kDebugMode) {
      print('[AdManager] テスト用全予定タブインラインバナー広告ID使用');
      // デバッグモードではテスト用IDを使用
      if (Platform.isAndroid) {
        return 'ca-app-pub-3940256099942544/6300978111';
      } else if (Platform.isIOS) {
        return 'ca-app-pub-3940256099942544/2934735716';
      }
    } else {
      // 本番環境では.envから読み込み
      if (Platform.isAndroid) {
        return dotenv.env['ADMOB_SCHEDULE_INLINE_BANNER_ANDROID'] ?? 'ca-app-pub-3940256099942544/6300978111';
      } else if (Platform.isIOS) {
        return dotenv.env['ADMOB_SCHEDULE_INLINE_BANNER_IOS'] ?? 'ca-app-pub-3940256099942544/2934735716';
      }
    }
    throw UnsupportedError('Unsupported platform');
  }

  /// Mobile Ads SDKとUnity Adsを初期化
  static Future<void> initialize() async {
    try {
      // Google Mobile Ads SDK初期化
      await MobileAds.instance.initialize();
      if (kDebugMode) {
        print('[AdManager] Google Mobile Ads SDK初期化完了');
      }
    } catch (e) {
      // 初期化エラーは再スローせず、アプリの続行を許可
      if (kDebugMode) {
        print('[AdManager] エラーを無視してアプリを続行します: $e');
      }
    }
  }

  /// バナー広告のサイズを取得
  static AdSize getBannerAdSize() {
    return AdSize.fullBanner;
  }
}

/// インライン（設定画面等）で使うAnchored Adaptiveバナーの簡易キャッシュ
/// 同じ幅であれば再読み込みせず、画面を開き直しても再利用します。
class InlineBannerCache {
  static BannerAd? _ad;
  static AnchoredAdaptiveBannerAdSize? _size;
  static int? _widthPx;
  static bool _loading = false;
  static Future<BannerAd?>? _loadingFuture;

  static AnchoredAdaptiveBannerAdSize? get size => _size;

  /// 指定幅に最適化したバナーを取得（未ロードなら読み込む）
  static Future<BannerAd?> getOrLoad(int widthPx) async {
    if (AdManager.inlineBannerAdUnitId.isEmpty) return null;

    if (_ad != null && _widthPx == widthPx) {
      return _ad;
    }
    if (_loading && _loadingFuture != null) {
      return _loadingFuture;
    }

    final completer = Completer<BannerAd?>();
    _loading = true;
    _loadingFuture = completer.future;

    try {
      await MobileAds.instance.initialize();
      final anchored = await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(widthPx);
      _size = anchored;

      final ad = BannerAd(
        size: anchored ?? AdSize.banner,
        adUnitId: AdManager.inlineBannerAdUnitId,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            _ad = ad as BannerAd;
            _widthPx = widthPx;
            _loading = false;
            completer.complete(_ad);
          },
          onAdFailedToLoad: (ad, error) {
            ad.dispose();
            _ad = null;
            _loading = false;
            completer.complete(null);
          },
        ),
      );

      await ad.load();
    } catch (_) {
      _ad = null;
      _loading = false;
      completer.complete(null);
    }

    return _loadingFuture;
  }

  /// キャッシュをクリア（明示的に再読み込みしたい時に使用）
  static void clear() {
    try {
      _ad?.dispose();
    } catch (_) {}
    _ad = null;
    _size = null;
    _widthPx = null;
    _loading = false;
    _loadingFuture = null;
  }
}
