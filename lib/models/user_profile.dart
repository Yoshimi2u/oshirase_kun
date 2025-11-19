import 'package:cloud_firestore/cloud_firestore.dart';

/// ユーザープロフィール
class UserProfile {
  final String uid;
  final String displayName;
  final String? fcmToken;
  final DateTime createdAt;
  final DateTime updatedAt;

  UserProfile({
    required this.uid,
    required this.displayName,
    this.fcmToken,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Firestoreドキュメントから生成
  factory UserProfile.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final now = DateTime.now();

    return UserProfile(
      uid: doc.id,
      displayName: data['displayName'] as String? ?? 'ユーザー',
      fcmToken: data['fcmToken'] as String?,
      createdAt: data['createdAt'] != null ? (data['createdAt'] as Timestamp).toDate() : now,
      updatedAt: data['updatedAt'] != null ? (data['updatedAt'] as Timestamp).toDate() : now,
    );
  }

  /// Firestoreドキュメント用のマップに変換
  Map<String, dynamic> toFirestore() {
    final Map<String, dynamic> data = {
      'displayName': displayName,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };

    // fcmTokenがnullでない場合のみ追加
    if (fcmToken != null) {
      data['fcmToken'] = fcmToken;
    }

    return data;
  }

  /// コピーを作成
  UserProfile copyWith({
    String? uid,
    String? displayName,
    String? fcmToken,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserProfile(
      uid: uid ?? this.uid,
      displayName: displayName ?? this.displayName,
      fcmToken: fcmToken ?? this.fcmToken,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
