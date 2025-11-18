import 'package:cloud_firestore/cloud_firestore.dart';

/// グループモデル
class Group {
  final String id;
  final String name; // グループ名
  final String inviteCode; // 6桁の招待コード
  final String ownerId; // グループ作成者のUID
  final List<String> memberIds; // メンバーのUIDリスト
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isActive; // グループが有効かどうか

  const Group({
    required this.id,
    required this.name,
    required this.inviteCode,
    required this.ownerId,
    required this.memberIds,
    required this.createdAt,
    required this.updatedAt,
    this.isActive = true,
  });

  /// Firestoreドキュメントから Group オブジェクトを生成
  factory Group.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Group(
      id: doc.id,
      name: data['name'] ?? '',
      inviteCode: data['inviteCode'] ?? '',
      ownerId: data['ownerId'] ?? '',
      memberIds: List<String>.from(data['memberIds'] ?? []),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
      isActive: data['isActive'] ?? true,
    );
  }

  /// Group オブジェクトを Firestore 用の Map に変換
  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'inviteCode': inviteCode,
      'ownerId': ownerId,
      'memberIds': memberIds,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'isActive': isActive,
    };
  }

  /// コピーを作成（一部のフィールドを変更）
  Group copyWith({
    String? id,
    String? name,
    String? inviteCode,
    String? ownerId,
    List<String>? memberIds,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isActive,
  }) {
    return Group(
      id: id ?? this.id,
      name: name ?? this.name,
      inviteCode: inviteCode ?? this.inviteCode,
      ownerId: ownerId ?? this.ownerId,
      memberIds: memberIds ?? this.memberIds,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isActive: isActive ?? this.isActive,
    );
  }

  /// メンバー数を取得
  int get memberCount => memberIds.length;

  /// 自分がオーナーかどうか
  bool isOwner(String userId) => ownerId == userId;

  /// メンバーに含まれているかどうか
  bool isMember(String userId) => memberIds.contains(userId);
}
