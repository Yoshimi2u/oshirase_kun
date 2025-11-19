import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/user_profile.dart';

/// ユーザープロフィールリポジトリ
class UserProfileRepository {
  final FirebaseFirestore _firestore;

  UserProfileRepository({FirebaseFirestore? firestore}) : _firestore = firestore ?? FirebaseFirestore.instance;

  /// ユーザープロフィールを取得
  Future<UserProfile?> getUserProfile(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (!doc.exists) {
        return null;
      }
      return UserProfile.fromFirestore(doc);
    } catch (e) {
      if (kDebugMode) {
        print('[UserProfileRepository] ユーザープロフィール取得エラー: $e');
      }
      rethrow;
    }
  }

  /// ユーザープロフィールをリアルタイムで監視
  Stream<UserProfile?> getUserProfileStream(String uid) {
    return _firestore.collection('users').doc(uid).snapshots().map((doc) {
      if (!doc.exists) {
        return null;
      }
      return UserProfile.fromFirestore(doc);
    });
  }

  /// ユーザープロフィールを作成または更新
  Future<void> setUserProfile(UserProfile profile) async {
    try {
      await _firestore.collection('users').doc(profile.uid).set(
            profile.toFirestore(),
            SetOptions(merge: true),
          );
      if (kDebugMode) {
        print('[UserProfileRepository] ユーザープロフィール保存成功: ${profile.uid}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[UserProfileRepository] ユーザープロフィール保存エラー: $e');
      }
      rethrow;
    }
  }

  /// 表示名を更新
  Future<void> updateDisplayName(String uid, String displayName) async {
    try {
      final now = DateTime.now();
      await _firestore.collection('users').doc(uid).set({
        'displayName': displayName,
        'updatedAt': Timestamp.fromDate(now),
      }, SetOptions(merge: true));

      if (kDebugMode) {
        print('[UserProfileRepository] 表示名更新成功: $uid -> $displayName');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[UserProfileRepository] 表示名更新エラー: $e');
      }
      rethrow;
    }
  }

  /// 初回プロフィール作成（存在しない場合のみ）
  Future<void> createProfileIfNotExists(String uid, {String displayName = 'ユーザー'}) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (!doc.exists) {
        final now = DateTime.now();
        // 初回作成時は、プロフィール情報と通知設定のデフォルト値を一緒に保存
        await _firestore.collection('users').doc(uid).set({
          'displayName': displayName,
          'createdAt': Timestamp.fromDate(now),
          'updatedAt': Timestamp.fromDate(now),
          // 通知設定のデフォルト値
          'morningEnabled': true,
          'morningHour': 8,
          'eveningEnabled': true,
          'eveningHour': 20,
        });
        if (kDebugMode) {
          print('[UserProfileRepository] 初回プロフィール作成: $uid (名前: $displayName)');
        }
      } else {
        // ドキュメントが存在するがdisplayNameが空の場合は更新
        final data = doc.data();
        if (data != null) {
          final currentDisplayName = data['displayName'] as String?;
          if (currentDisplayName == null || currentDisplayName.isEmpty) {
            await updateDisplayName(uid, displayName);
            if (kDebugMode) {
              print('[UserProfileRepository] 既存プロフィールのdisplayNameを更新: $uid (名前: $displayName)');
            }
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('[UserProfileRepository] プロフィール作成エラー: $e');
      }
      rethrow;
    }
  }

  /// プロフィールを取得または作成（存在しない場合は自動作成）
  Future<UserProfile> getOrCreateProfile(String uid) async {
    try {
      final profile = await getUserProfile(uid);
      if (profile != null) {
        return profile;
      }

      // 存在しない場合は作成
      await createProfileIfNotExists(uid);
      final newProfile = await getUserProfile(uid);
      return newProfile!;
    } catch (e) {
      if (kDebugMode) {
        print('[UserProfileRepository] プロフィール取得/作成エラー: $e');
      }
      rethrow;
    }
  }
}
