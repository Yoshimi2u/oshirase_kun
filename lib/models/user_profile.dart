import 'package:cloud_firestore/cloud_firestore.dart';

/// ユーザープロフィール
class UserProfile {
  final String uid;
  final String displayName;
  final DateTime createdAt;
  final DateTime updatedAt;

  UserProfile({
    required this.uid,
    required this.displayName,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Firestoreドキュメントから生成
  factory UserProfile.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final now = DateTime.now();

    return UserProfile(
      uid: doc.id,
      displayName: data['displayName'] as String? ?? '',
      createdAt: data['createdAt'] != null ? (data['createdAt'] as Timestamp).toDate() : now,
      updatedAt: data['updatedAt'] != null ? (data['updatedAt'] as Timestamp).toDate() : now,
    );
  }

  /// Firestoreドキュメント用のマップに変換
  Map<String, dynamic> toFirestore() {
    return {
      'displayName': displayName,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  /// コピーを作成
  UserProfile copyWith({
    String? uid,
    String? displayName,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserProfile(
      uid: uid ?? this.uid,
      displayName: displayName ?? this.displayName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
