import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:async';

/// 広告管理クラス
class AdManager {
  // デバッグフラグ（より確実にデバッグモードを判定）
  static bool get _isDebugMode {
    bool debugMode = false;
    assert(debugMode = true); // Debug モードの場合のみ true になる
    return debugMode;
  }

  static String get bannerAdUnitId {
    if (_isDebugMode) {
      // デバッグモード時はテスト用の広告ユニットIDを使用
      if (kDebugMode) {
        print('[AdManager] デバッグモード - テスト用バナー広告ID使用');
      }
      if (Platform.isAndroid) {
        return 'ca-app-pub-3940256099942544/6300978111';
      } else if (Platform.isIOS) {
        return 'ca-app-pub-3940256099942544/2934735716';
      }
    } else {
      // リリースモード時は本番用の広告ユニットIDを使用
      if (kDebugMode) {
        print('[AdManager] リリースモード - メディエーション対応バナー広告ID使用');
      }
      if (Platform.isAndroid) {
        // メディエーション設定は既存の広告ユニットIDに対して適用される
        // AdMobダッシュボードでメディエーション設定を完了後、このIDでUnity Ads配信開始
        return 'ca-app-pub-4176965988231465/6369731480';
      } else if (Platform.isIOS) {
        // メディエーション設定は既存の広告ユニットIDに対して適用される
        // AdMobダッシュボードでメディエーション設定を完了後、このIDでUnity Ads配信開始
        return 'ca-app-pub-4176965988231465/8727914473';
      }
    }
    throw UnsupportedError('Unsupported platform');
  }

  // インタースティシャル広告は未使用のためIDは廃止

  /// 設定画面などのインライン表示用バナー広告ユニットIDを取得
  /// 注意：本番IDは後で差し替えます。未設定時（空文字）の場合はUI側でプレースホルダー表示にフォールバックしてください。
  static String get inlineBannerAdUnitId {
    if (_isDebugMode) {
      // デバッグ時は標準のテスト用バナーIDを使用
      if (kDebugMode) {
        print('[AdManager] デバッグモード - テスト用インラインバナー広告ID使用');
      }
      if (Platform.isAndroid) {
        return 'ca-app-pub-3940256099942544/6300978111';
      } else if (Platform.isIOS) {
        return 'ca-app-pub-3940256099942544/2934735716';
      }
    } else {
      // 本番IDは取得後に設定する。現時点では空文字を返し、UIでプレースホルダーに委ねる。
      if (kDebugMode) {
        print('[AdManager] リリースモード - インラインバナー広告IDは未設定');
      }
      if (Platform.isAndroid) {
        return 'ca-app-pub-4176965988231465/4223703115';
      } else if (Platform.isIOS) {
        return 'ca-app-pub-4176965988231465/7707103810';
      }
    }
    throw UnsupportedError('Unsupported platform');
  }

  /// リワード広告のユニットIDを取得
  static String get rewardedAdUnitId {
    if (_isDebugMode) {
      if (kDebugMode) {
        print('[AdManager] デバッグモード - テスト用リワード広告ID使用');
      }
      if (Platform.isAndroid) {
        return 'ca-app-pub-3940256099942544/5224354917';
      } else if (Platform.isIOS) {
        return 'ca-app-pub-3940256099942544/1712485313';
      }
    } else {
      if (kDebugMode) {
        print('[AdManager] リリースモード - メディエーション対応リワード広告ID使用');
      }
      if (Platform.isAndroid) {
        return 'ca-app-pub-4176965988231465/1771614459';
      } else if (Platform.isIOS) {
        return 'ca-app-pub-4176965988231465/4437429953';
      }
    }
    throw UnsupportedError('Unsupported platform');
  }

  /// Unity Game IDを取得
  static String get unityGameId {
    if (_isDebugMode) {
      // デバッグモード時はテスト用のGame IDを使用
      return Platform.isAndroid ? '14851' : '14850';
    } else {
      // リリースモード時は本番用のGame IDを使用
      return Platform.isAndroid ? '5921213' : '5921212';
    }
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
