import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/notification_settings.dart';

/// 通知設定のリポジトリ
class NotificationSettingsRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// 通知設定を取得（存在しない場合はデフォルト設定を作成）
  Future<NotificationSettings> getSettings(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).collection('settings').doc('notifications').get();

      if (doc.exists) {
        return NotificationSettings.fromFirestore(doc.data()!);
      } else {
        // デフォルト設定を作成
        final defaultSettings = NotificationSettings.defaultSettings();
        await _firestore
            .collection('users')
            .doc(userId)
            .collection('settings')
            .doc('notifications')
            .set(defaultSettings.toFirestore());
        return defaultSettings;
      }
    } catch (e) {
      // エラー時はデフォルト設定を返す
      return NotificationSettings.defaultSettings();
    }
  }

  /// 通知設定をストリームで取得
  Stream<NotificationSettings> watchSettings(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('settings')
        .doc('notifications')
        .snapshots()
        .map((doc) {
      if (doc.exists) {
        return NotificationSettings.fromFirestore(doc.data()!);
      } else {
        return NotificationSettings.defaultSettings();
      }
    });
  }

  /// 朝の通知の有効/無効を更新
  Future<void> toggleMorningEnabled(String userId, bool enabled) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('settings')
        .doc('notifications')
        .set({'morningEnabled': enabled}, SetOptions(merge: true));
  }

  /// 朝の通知時刻を更新
  Future<void> updateMorningHour(String userId, int hour) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('settings')
        .doc('notifications')
        .set({'morningHour': hour}, SetOptions(merge: true));
  }

  /// 夜の通知の有効/無効を更新
  Future<void> toggleEveningEnabled(String userId, bool enabled) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('settings')
        .doc('notifications')
        .set({'eveningEnabled': enabled}, SetOptions(merge: true));
  }

  /// 夜の通知時刻を更新
  Future<void> updateEveningHour(String userId, int hour) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('settings')
        .doc('notifications')
        .set({'eveningHour': hour}, SetOptions(merge: true));
  }
}
