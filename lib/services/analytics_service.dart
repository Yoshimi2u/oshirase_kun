import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

/// Firebase Analytics統合サービス
class AnalyticsService {
  static FirebaseAnalytics? _analytics;

  /// Firebase Analyticsインスタンスを取得
  static FirebaseAnalytics get analytics {
    _analytics ??= FirebaseAnalytics.instance;
    return _analytics!;
  }

  /// アプリ起動イベント
  static Future<void> logAppOpen() async {
    try {
      await analytics.logAppOpen();
      if (kDebugMode) {
        print('[Analytics] App Open イベント送信');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[Analytics] App Open エラー: $e');
      }
    }
  }

  /// 画面表示イベント
  static Future<void> logScreenView(String screenName) async {
    try {
      await analytics.logScreenView(
        screenName: screenName,
        screenClass: screenName,
      );
      if (kDebugMode) {
        print('[Analytics] Screen View: $screenName');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[Analytics] Screen View エラー: $e');
      }
    }
  }

  /// レシピ作成イベント
  static Future<void> logRecipeCreated({
    required String recipeId,
    required String category,
    int? ingredientCount,
  }) async {
    try {
      await analytics.logEvent(
        name: 'recipe_created',
        parameters: {
          'recipe_id': recipeId,
          'category': category,
          if (ingredientCount != null) 'ingredient_count': ingredientCount,
        },
      );
      if (kDebugMode) {
        print('[Analytics] Recipe Created: $recipeId');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[Analytics] Recipe Created エラー: $e');
      }
    }
  }

  /// お買い物リスト作成イベント
  static Future<void> logShoppingListCreated({
    required String listId,
    required int itemCount,
    String? source, // 'recipe' or 'usual' or 'manual'
  }) async {
    try {
      await analytics.logEvent(
        name: 'shopping_list_created',
        parameters: {
          'list_id': listId,
          'item_count': itemCount,
          if (source != null) 'source': source,
        },
      );
      if (kDebugMode) {
        print('[Analytics] Shopping List Created: $listId');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[Analytics] Shopping List Created エラー: $e');
      }
    }
  }

  /// お買い物完了イベント
  static Future<void> logShoppingCompleted({
    required String listId,
    required int totalItems,
    required int completedItems,
    required Duration shoppingDuration,
  }) async {
    try {
      await analytics.logEvent(
        name: 'shopping_completed',
        parameters: {
          'list_id': listId,
          'total_items': totalItems,
          'completed_items': completedItems,
          'completion_rate': (completedItems / totalItems * 100).round(),
          'duration_minutes': shoppingDuration.inMinutes,
        },
      );
      if (kDebugMode) {
        print('[Analytics] Shopping Completed: $listId');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[Analytics] Shopping Completed エラー: $e');
      }
    }
  }

  /// チュートリアル開始イベント
  static Future<void> logTutorialBegin(String tutorialName) async {
    try {
      await analytics.logTutorialBegin(
        parameters: {
          'tutorial_name': tutorialName,
        },
      );
      if (kDebugMode) {
        print('[Analytics] Tutorial Begin: $tutorialName');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[Analytics] Tutorial Begin エラー: $e');
      }
    }
  }

  /// チュートリアル完了イベント
  static Future<void> logTutorialComplete(String tutorialName) async {
    try {
      await analytics.logTutorialComplete(
        parameters: {
          'tutorial_name': tutorialName,
        },
      );
      if (kDebugMode) {
        print('[Analytics] Tutorial Complete: $tutorialName');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[Analytics] Tutorial Complete エラー: $e');
      }
    }
  }

  /// レビュー依頼イベント
  static Future<void> logReviewRequest() async {
    try {
      await analytics.logEvent(
        name: 'review_request_shown',
        parameters: {
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
      );
      if (kDebugMode) {
        print('[Analytics] Review Request Shown');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[Analytics] Review Request エラー: $e');
      }
    }
  }

  /// カスタムイベント
  static Future<void> logCustomEvent({
    required String eventName,
    Map<String, Object>? parameters,
  }) async {
    try {
      await analytics.logEvent(
        name: eventName,
        parameters: parameters,
      );
      if (kDebugMode) {
        print('[Analytics] Custom Event: $eventName');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[Analytics] Custom Event エラー: $e');
      }
    }
  }

  /// ユーザープロパティを設定
  static Future<void> setUserProperty({
    required String name,
    required String? value,
  }) async {
    try {
      await analytics.setUserProperty(
        name: name,
        value: value,
      );
      if (kDebugMode) {
        print('[Analytics] User Property Set: $name = $value');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[Analytics] User Property エラー: $e');
      }
    }
  }

  // =============================================================================
  // 広告最適化のための統計強化機能
  // =============================================================================

  /// 広告表示イベント（広告最適化の核心）
  static Future<void> logAdImpression({
    required String adType, // 'banner', 'interstitial', 'rewarded'
    required String adUnitId,
    required String placement, // 画面名や配置場所
    String? networkName, // AdMob, Unity, etc.
    double? ecpm,
  }) async {
    try {
      await analytics.logEvent(
        name: 'ad_impression',
        parameters: {
          'ad_format': adType,
          'ad_unit_id': adUnitId,
          'placement': placement,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          if (networkName != null) 'ad_network': networkName,
          if (ecpm != null) 'ecpm': ecpm,
        },
      );
      if (kDebugMode) {
        print('[Analytics] Ad Impression: $adType at $placement');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[Analytics] Ad Impression エラー: $e');
      }
    }
  }

  /// 広告クリックイベント
  static Future<void> logAdClick({
    required String adType,
    required String adUnitId,
    required String placement,
    String? networkName,
  }) async {
    try {
      await analytics.logEvent(
        name: 'ad_click',
        parameters: {
          'ad_format': adType,
          'ad_unit_id': adUnitId,
          'placement': placement,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          if (networkName != null) 'ad_network': networkName,
        },
      );
      if (kDebugMode) {
        print('[Analytics] Ad Click: $adType at $placement');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[Analytics] Ad Click エラー: $e');
      }
    }
  }

  /// 広告読み込み失敗イベント
  static Future<void> logAdLoadFailure({
    required String adType,
    required String adUnitId,
    required String placement,
    required int errorCode,
    required String errorMessage,
    int? loadAttempt,
  }) async {
    try {
      await analytics.logEvent(
        name: 'ad_load_failed',
        parameters: {
          'ad_format': adType,
          'ad_unit_id': adUnitId,
          'placement': placement,
          'error_code': errorCode,
          'error_message': errorMessage,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          if (loadAttempt != null) 'load_attempt': loadAttempt,
        },
      );
      if (kDebugMode) {
        print('[Analytics] Ad Load Failed: $adType - $errorMessage (Code: $errorCode)');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[Analytics] Ad Load Failed エラー: $e');
      }
    }
  }

  /// 広告読み込み時間イベント
  static Future<void> logAdLoadTime({
    required String adType,
    required String adUnitId,
    required String placement,
    required Duration loadTime,
    bool isSuccess = true,
  }) async {
    try {
      await analytics.logEvent(
        name: 'ad_load_time',
        parameters: {
          'ad_format': adType,
          'ad_unit_id': adUnitId,
          'placement': placement,
          'load_time_ms': loadTime.inMilliseconds,
          'is_success': isSuccess,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
      );
      if (kDebugMode) {
        print('[Analytics] Ad Load Time: $adType - ${loadTime.inMilliseconds}ms');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[Analytics] Ad Load Time エラー: $e');
      }
    }
  }

  /// セッション開始イベント
  static Future<void> logSessionStart() async {
    try {
      await analytics.logEvent(
        name: 'session_start',
        parameters: {
          'session_id': DateTime.now().millisecondsSinceEpoch.toString(),
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
      );
      if (kDebugMode) {
        print('[Analytics] Session Start');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[Analytics] Session Start エラー: $e');
      }
    }
  }

  /// エンゲージメント時間イベント
  static Future<void> logEngagementTime({
    required String screenName,
    required Duration timeSpent,
  }) async {
    try {
      await analytics.logEvent(
        name: 'engagement_time_msec',
        parameters: {
          'screen_name': screenName,
          'engagement_time_msec': timeSpent.inMilliseconds,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
      );
      if (kDebugMode) {
        print('[Analytics] Engagement Time: $screenName - ${timeSpent.inSeconds}s');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[Analytics] Engagement Time エラー: $e');
      }
    }
  }

  /// 機能使用頻度イベント
  static Future<void> logFeatureUsage({
    required String featureName,
    required String action, // 'used', 'completed', 'cancelled'
    Map<String, Object>? additionalParams,
  }) async {
    try {
      final params = <String, Object>{
        'feature_name': featureName,
        'action': action,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      if (additionalParams != null) {
        params.addAll(additionalParams);
      }

      await analytics.logEvent(
        name: 'feature_usage',
        parameters: params,
      );
      if (kDebugMode) {
        print('[Analytics] Feature Usage: $featureName - $action');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[Analytics] Feature Usage エラー: $e');
      }
    }
  }

  /// アプリ使用パターン分析
  static Future<void> logUsagePattern({
    required String patternType, // 'daily_active', 'power_user', 'casual_user'
    required int usageDays,
    required int sessionCount,
    required int featureUsageCount,
  }) async {
    try {
      await analytics.logEvent(
        name: 'usage_pattern',
        parameters: {
          'pattern_type': patternType,
          'usage_days': usageDays,
          'session_count': sessionCount,
          'feature_usage_count': featureUsageCount,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
      );
      if (kDebugMode) {
        print('[Analytics] Usage Pattern: $patternType');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[Analytics] Usage Pattern エラー: $e');
      }
    }
  }

  /// ユーザー属性設定（広告最適化用）
  static Future<void> setUserDemographics({
    String? userType, // 'new', 'returning', 'power_user'
    String? engagementLevel, // 'high', 'medium', 'low'
    String? primaryFeature, // 'recipe', 'shopping', 'mixed'
  }) async {
    try {
      if (userType != null) {
        await setUserProperty(name: 'user_type', value: userType);
      }
      if (engagementLevel != null) {
        await setUserProperty(name: 'engagement_level', value: engagementLevel);
      }
      if (primaryFeature != null) {
        await setUserProperty(name: 'primary_feature', value: primaryFeature);
      }
      if (kDebugMode) {
        print('[Analytics] User Demographics Set');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[Analytics] User Demographics エラー: $e');
      }
    }
  }

  /// LTV（生涯価値）推定イベント
  static Future<void> logUserLtvEstimate({
    required double estimatedValue,
    required String calculationMethod,
    required int daysSinceInstall,
  }) async {
    try {
      await analytics.logEvent(
        name: 'user_ltv_estimate',
        parameters: {
          'estimated_value': estimatedValue,
          'calculation_method': calculationMethod,
          'days_since_install': daysSinceInstall,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
      );
      if (kDebugMode) {
        print('[Analytics] User LTV Estimate: \$${estimatedValue.toStringAsFixed(2)}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[Analytics] User LTV Estimate エラー: $e');
      }
    }
  }

  /// 広告収益イベント（AdMob連携用）
  static Future<void> logAdRevenue({
    required String adType,
    required String adUnitId,
    required double revenue,
    required String currency,
    String? adNetwork,
  }) async {
    try {
      await analytics.logEvent(
        name: 'ad_revenue',
        parameters: {
          'ad_format': adType,
          'ad_unit_id': adUnitId,
          'value': revenue,
          'currency': currency,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          if (adNetwork != null) 'ad_network': adNetwork,
        },
      );
      if (kDebugMode) {
        print('[Analytics] Ad Revenue: $currency $revenue from $adType');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[Analytics] Ad Revenue エラー: $e');
      }
    }
  }
}
