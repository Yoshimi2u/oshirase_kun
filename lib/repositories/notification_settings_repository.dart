import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/notification_settings.dart';

/// 通知設定のリポジトリ
/// 最適化: 通知設定をusersドキュメントに直接保存（サブコレクション不使用）
class NotificationSettingsRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// 通知設定を取得（存在しない場合はデフォルト設定を作成）
  Future<NotificationSettings> getSettings(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        return NotificationSettings.fromFirestore(data);
      } else {
        // デフォルト設定を作成
        final defaultSettings = NotificationSettings.defaultSettings();
        await _firestore.collection('users').doc(userId).set(
              defaultSettings.toFirestore(),
              SetOptions(merge: true),
            );
        return defaultSettings;
      }
    } catch (e) {
      // エラー時はデフォルト設定を返す
      return NotificationSettings.defaultSettings();
    }
  }

  /// 通知設定をストリームで取得
  Stream<NotificationSettings> watchSettings(String userId) {
    return _firestore.collection('users').doc(userId).snapshots().map((doc) {
      if (doc.exists && doc.data() != null) {
        return NotificationSettings.fromFirestore(doc.data()!);
      } else {
        return NotificationSettings.defaultSettings();
      }
    });
  }

  /// 朝の通知の有効/無効を更新
  Future<void> toggleMorningEnabled(String userId, bool enabled) async {
    await _firestore.collection('users').doc(userId).set(
      {'morningEnabled': enabled},
      SetOptions(merge: true),
    );
  }

  /// 朝の通知時刻を更新
  Future<void> updateMorningHour(String userId, int hour) async {
    await _firestore.collection('users').doc(userId).set(
      {'morningHour': hour},
      SetOptions(merge: true),
    );
  }

  /// 夜の通知の有効/無効を更新
  Future<void> toggleEveningEnabled(String userId, bool enabled) async {
    await _firestore.collection('users').doc(userId).set(
      {'eveningEnabled': enabled},
      SetOptions(merge: true),
    );
  }

  /// 夜の通知時刻を更新
  Future<void> updateEveningHour(String userId, int hour) async {
    await _firestore.collection('users').doc(userId).set(
      {'eveningHour': hour},
      SetOptions(merge: true),
    );
  }
}
