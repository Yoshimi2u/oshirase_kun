import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';

/// アプリのバージョンチェックを管理するクラス
class VersionChecker {
  /// 最後のチェック日時を保存するキー
  static const String _lastCheckDateKey = 'last_update_check';

  /// チェック間隔（日数）
  static const int _checkIntervalDays = 3;

  /// アップデート確認（間隔制御あり）
  static Future<bool> checkForUpdatesWithInterval() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastCheckDate = prefs.getString(_lastCheckDateKey);
      final now = DateTime.now();

      // 最後のチェックから3日経過しているかチェック
      if (lastCheckDate != null) {
        final lastCheck = DateTime.parse(lastCheckDate);
        final daysDiff = now.difference(lastCheck).inDays;
        if (daysDiff < _checkIntervalDays) {
          return false; // まだ間隔期間内
        }
      }

      // 新しいバージョンが利用可能かチェック
      final hasUpdate = await hasNewVersionAvailable();

      if (hasUpdate) {
        // チェック日時を保存
        await prefs.setString(_lastCheckDateKey, now.toIso8601String());
      }

      return hasUpdate;
    } catch (e) {
      debugPrint('アップデート確認エラー: $e');
      return false;
    }
  }

  /// 新しいバージョンが利用可能かチェック（間隔制御なし）
  static Future<bool> hasNewVersionAvailable() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      // Remote Config から最新バージョンを取得
      final rc = FirebaseRemoteConfig.instance;
      final platformKeyPrefix = Platform.isIOS ? 'app_versions_ios' : 'app_versions_android';
      // Remote Configはドットを含むキー名が使えないため全てアンダースコアで繋ぐ
      final latestKey = '${platformKeyPrefix}_latest_version';
      final minKey = '${platformKeyPrefix}_min_supported_version';
      final forceKey = '${platformKeyPrefix}_force_update';
      final storeUrlKey = '${platformKeyPrefix}_store_url';
      final changelogKey = '${platformKeyPrefix}_changelog';

      // 本番ではデフォルトの最小フェッチ間隔を長めに、開発では短く
      try {
        await rc.setConfigSettings(RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 10),
          minimumFetchInterval: kDebugMode ? const Duration(seconds: 5) : const Duration(hours: 12),
        ));
      } catch (_) {
        // 古いSDKではsetConfigSettingsが例外を投げる可能性があるため握りつぶし
      }

      // 初回未設定でも安全に動くようデフォルトを投入
      try {
        final defaultStoreUrl = Platform.isIOS
            ? 'https://apps.apple.com/jp/app/id6749101695'
            : 'https://play.google.com/store/apps/details?id=com.higuraku.oshirasekun';
        await rc.setDefaults({
          latestKey: currentVersion, // 既定は現行=最新扱い
          minKey: currentVersion, // 既定は強制なし
          forceKey: false,
          storeUrlKey: defaultStoreUrl,
          changelogKey: '',
        });
      } catch (e) {
        debugPrint('Remote Config デフォルト設定失敗: $e');
      }

      // フェッチ＆アクティベート（失敗しても既存キャッシュを使用）
      try {
        await rc.fetchAndActivate();
      } catch (e) {
        debugPrint('Remote Config フェッチ失敗（キャッシュを使用）: $e');
      }

      final storeVersion = rc.getString(latestKey).trim();
      final minSupported = rc.getString(minKey).trim();
      final forceUpdate = rc.getBool(forceKey);
      final storeUrl = rc.getString(storeUrlKey).trim();
      final changelog = rc.getString(changelogKey).trim();

      if (storeVersion.isEmpty) {
        debugPrint('Remote Configから最新バージョンが取得できませんでした（キー: $latestKey）');
        return false;
      }

      debugPrint('[UpdateCheck] current=$currentVersion, latest=$storeVersion, min=$minSupported, force=$forceUpdate');
      if (kDebugMode) {
        if (storeUrl.isNotEmpty) debugPrint('[UpdateCheck] storeUrl=$storeUrl');
        if (changelog.isNotEmpty) {
          final previewLen = changelog.length > 120 ? 120 : changelog.length;
          debugPrint('[UpdateCheck] changelog=${changelog.substring(0, previewLen)}');
        }
      }

      // 任意アップデート条件
      final hasNewer = _compareVersions(currentVersion, storeVersion);

      // 将来的に強制アップデートの分岐に利用するが、既存I/Fは bool のみ返すためここでは反映しない
      // final isBelowMin = minSupported.isNotEmpty && _isVersionLowerThan(currentVersion, minSupported);
      // final mustForce = forceUpdate || isBelowMin;

      return hasNewer;
    } catch (e) {
      debugPrint('バージョン確認エラー: $e');
      return false;
    }
  }

  /// バージョンを比較して新しいバージョンが利用可能かチェック
  static bool _compareVersions(String currentVersion, String storeVersion) {
    try {
      final current = currentVersion.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final store = storeVersion.split('.').map((e) => int.tryParse(e) ?? 0).toList();

      // バージョン配列の長さを揃える
      final maxLength = current.length > store.length ? current.length : store.length;
      while (current.length < maxLength) {
        current.add(0);
      }
      while (store.length < maxLength) {
        store.add(0);
      }

      // バージョン比較
      for (int i = 0; i < maxLength; i++) {
        if (store[i] > current[i]) {
          return true; // ストアの方が新しい
        } else if (store[i] < current[i]) {
          return false; // 現在の方が新しい（開発版など）
        }
      }

      return false; // 同じバージョン
    } catch (e) {
      debugPrint('バージョン比較エラー: $e');
      return false;
    }
  }

  /// アップデートチェックの設定をリセット（テスト用）
  static Future<void> resetCheckInterval() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_lastCheckDateKey);
    } catch (e) {
      debugPrint('チェック間隔リセットエラー: $e');
    }
  }
}
