import 'package:cloud_firestore/cloud_firestore.dart';
import 'group_role.dart';

/// 権限機能を持つグループモデル（拡張版）
class GroupWithRoles {
  final String id;
  final String name;
  final String inviteCode;
  final String ownerId;
  final Map<String, GroupRole> memberRoles; // userId -> role のマップ
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isActive;
  final bool isJoinable;

  const GroupWithRoles({
    required this.id,
    required this.name,
    required this.inviteCode,
    required this.ownerId,
    required this.memberRoles,
    required this.createdAt,
    required this.updatedAt,
    this.isActive = true,
    this.isJoinable = true,
  });

  /// Firestoreドキュメントから GroupWithRoles オブジェクトを生成
  factory GroupWithRoles.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // memberRoles を Map<String, GroupRole> に変換
    final rolesData = data['memberRoles'] as Map<String, dynamic>? ?? {};
    final memberRoles = <String, GroupRole>{};
    rolesData.forEach((userId, roleString) {
      memberRoles[userId] = GroupRoleExtension.fromFirestore(roleString as String);
    });

    return GroupWithRoles(
      id: doc.id,
      name: data['name'] ?? '',
      inviteCode: data['inviteCode'] ?? '',
      ownerId: data['ownerId'] ?? '',
      memberRoles: memberRoles,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
      isActive: data['isActive'] ?? true,
      isJoinable: data['isJoinable'] ?? true,
    );
  }

  /// GroupWithRoles オブジェクトを Firestore 用の Map に変換
  Map<String, dynamic> toFirestore() {
    final rolesMap = <String, String>{};
    memberRoles.forEach((userId, role) {
      rolesMap[userId] = role.toFirestore();
    });

    return {
      'name': name,
      'inviteCode': inviteCode,
      'ownerId': ownerId,
      'memberRoles': rolesMap,
      'memberIds': memberRoles.keys.toList(), // 後方互換性のため
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'isActive': isActive,
      'isJoinable': isJoinable,
    };
  }

  /// コピーを作成
  GroupWithRoles copyWith({
    String? id,
    String? name,
    String? inviteCode,
    String? ownerId,
    Map<String, GroupRole>? memberRoles,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isActive,
    bool? isJoinable,
  }) {
    return GroupWithRoles(
      id: id ?? this.id,
      name: name ?? this.name,
      inviteCode: inviteCode ?? this.inviteCode,
      ownerId: ownerId ?? this.ownerId,
      memberRoles: memberRoles ?? this.memberRoles,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isActive: isActive ?? this.isActive,
      isJoinable: isJoinable ?? this.isJoinable,
    );
  }

  /// メンバー数を取得
  int get memberCount => memberRoles.length;

  /// メンバーIDリストを取得
  List<String> get memberIds => memberRoles.keys.toList();

  /// 指定ユーザーの役割を取得
  GroupRole? getRoleForUser(String userId) => memberRoles[userId];

  /// 指定ユーザーがオーナーかどうか
  bool isOwner(String userId) => ownerId == userId;

  /// 指定ユーザーがメンバーかどうか
  bool isMember(String userId) => memberRoles.containsKey(userId);

  /// 指定ユーザーがグループ設定を更新できるか
  bool canUpdateSettings(String userId) {
    final role = getRoleForUser(userId);
    return role != null && GroupPermission.canUpdateGroupSettings(role);
  }

  /// 指定ユーザーがグループを削除できるか
  bool canDelete(String userId) {
    final role = getRoleForUser(userId);
    return role != null && GroupPermission.canDeleteGroup(role);
  }

  /// 指定ユーザーがメンバーを追加できるか
  bool canAddMember(String userId) {
    final role = getRoleForUser(userId);
    return role != null && GroupPermission.canAddMember(role);
  }

  /// 指定ユーザーがメンバーを削除できるか
  bool canRemoveMember(String userId) {
    final role = getRoleForUser(userId);
    return role != null && GroupPermission.canRemoveMember(role);
  }

  /// 指定ユーザーが特定のメンバーを退出させられるか
  /// requestUserId: 退出させようとしているユーザー
  /// targetUserId: 退出させられる対象のユーザー
  bool canRemoveSpecificMember(String requestUserId, String targetUserId) {
    final requestRole = getRoleForUser(requestUserId);
    final targetRole = getRoleForUser(targetUserId);

    if (requestRole == null || targetRole == null) {
      return false;
    }

    // オーナーは退出させられない
    if (targetUserId == ownerId) {
      return false;
    }

    // オーナーは管理者とメンバーを退出させられる
    if (requestRole == GroupRole.owner) {
      return true;
    }

    // 管理者はメンバーのみ退出させられる（他の管理者は不可）
    if (requestRole == GroupRole.admin) {
      return targetRole == GroupRole.member;
    }

    // メンバーは誰も退出させられない
    return false;
  }

  /// 指定ユーザーが役割を変更できるか
  bool canChangeRole(String userId) {
    final role = getRoleForUser(userId);
    return role != null && GroupPermission.canChangeRole(role);
  }

  /// 指定ユーザーがタスクを作成できるか
  bool canCreateTask(String userId) {
    final role = getRoleForUser(userId);
    return role != null && GroupPermission.canCreateTask(role);
  }

  /// 指定ユーザーがタスクを更新できるか
  bool canUpdateTask(String userId) {
    final role = getRoleForUser(userId);
    return role != null && GroupPermission.canUpdateTask(role);
  }

  /// 指定ユーザーがタスクを削除できるか
  bool canDeleteTask(String userId) {
    final role = getRoleForUser(userId);
    return role != null && GroupPermission.canDeleteTask(role);
  }

  /// 指定ユーザーがテンプレートを作成できるか
  bool canCreateTemplate(String userId) {
    final role = getRoleForUser(userId);
    return role != null && GroupPermission.canCreateTemplate(role);
  }

  /// 指定ユーザーがテンプレートを更新できるか
  bool canUpdateTemplate(String userId) {
    final role = getRoleForUser(userId);
    return role != null && GroupPermission.canUpdateTemplate(role);
  }

  /// 指定ユーザーがテンプレートを削除できるか
  bool canDeleteTemplate(String userId) {
    final role = getRoleForUser(userId);
    return role != null && GroupPermission.canDeleteTemplate(role);
  }

  /// 指定ユーザーがグループから退出できるか
  bool canLeaveGroup(String userId) {
    final role = getRoleForUser(userId);
    return role != null && GroupPermission.canLeaveGroup(role);
  }
}
