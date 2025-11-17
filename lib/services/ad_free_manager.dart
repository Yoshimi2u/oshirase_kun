import 'dart:async';

/// 広告非表示管理クラス
/// AdMobポリシー準拠のため、機能を無効化（常にfalseを返す）
class AdFreeManager {
  // 広告非表示状態の変更を通知するStreamController
  static final StreamController<bool> _adFreeStatusController = StreamController<bool>.broadcast();

  // 初期化済みフラグ
  static bool _isInitialized = false;

  /// 広告非表示状態の変更を監視するStream
  static Stream<bool> get adFreeStatusStream => _adFreeStatusController.stream;

  /// 初期化済みかどうか
  static bool get isInitialized => _isInitialized;

  /// キャッシュされた広告非表示状態（AdMobポリシー準拠のため常にfalse）
  static bool? get cachedAdFreeStatus => false;

  /// 24時間の広告非表示を設定（AdMobポリシー準拠のため無効化）
  static Future<void> setAdFreeFor24Hours() async {
    // AdMobポリシー準拠のため、実際の広告非表示機能は無効化
    return;
  }

  /// 現在広告非表示期間中かチェック（AdMobポリシー準拠のため常にfalse）
  static Future<bool> isAdFree() async {
    // AdMobポリシー準拠のため、常にfalseを返す
    return false;
  }

  /// 初期化を実行（AdMobポリシー準拠のため最小限の処理）
  static Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    // 常にfalseの状態をStreamに通知
    _adFreeStatusController.add(false);
  }

  /// キャッシュされた状態を取得（AdMobポリシー準拠のため常にfalse）
  static bool getCachedAdFreeStatus() {
    return false;
  }

  /// 残り時間を取得（AdMobポリシー準拠のため常にnull）
  static Future<Duration?> getRemainingAdFreeTime() async {
    return null;
  }

  /// リソースのクリーンアップ
  static void dispose() {
    _adFreeStatusController.close();
  }
}
