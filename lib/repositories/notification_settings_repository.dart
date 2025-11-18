import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/notification_settings.dart';

/// 通知設定のFirestore操作を管理するRepository
class NotificationSettingsRepository {
  final FirebaseFirestore _firestore;

  NotificationSettingsRepository({FirebaseFirestore? firestore}) : _firestore = firestore ?? FirebaseFirestore.instance;

  /// ユーザードキュメントの参照を取得
  DocumentReference _getUserDoc(String userId) {
    return _firestore.collection('users').doc(userId);
  }

  /// 通知設定を取得
  Future<NotificationSettings> getSettings(String userId) async {
    try {
      final doc = await _getUserDoc(userId).get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data() as Map<String, dynamic>;
        return NotificationSettings.fromFirestore(data);
      }
      return NotificationSettings.defaultSettings();
    } catch (e) {
      print('通知設定の取得エラー: $e');
      return NotificationSettings.defaultSettings();
    }
  }

  /// 通知設定を保存
  Future<void> saveSettings(String userId, NotificationSettings settings) async {
    try {
      await _getUserDoc(userId).set(
        settings.toFirestore(),
        SetOptions(merge: true),
      );
    } catch (e) {
      print('通知設定の保存エラー: $e');
      rethrow;
    }
  }

  /// 通知設定のストリームを取得
  Stream<NotificationSettings> getSettingsStream(String userId) {
    return _getUserDoc(userId).snapshots().map((doc) {
      if (doc.exists && doc.data() != null) {
        final data = doc.data() as Map<String, dynamic>;
        return NotificationSettings.fromFirestore(data);
      }
      return NotificationSettings.defaultSettings();
    });
  }
}
