/// グループメンバーの役割
enum GroupRole {
  owner, // オーナー（全権限）
  admin, // 管理者（オーナー以外のほぼ全権限）
  member, // 一般メンバー（タスクの追加・更新が可能）
}

/// グループ権限
class GroupPermission {
  /// グループ設定の更新（名前、招待設定など）
  static bool canUpdateGroupSettings(GroupRole role) {
    return role == GroupRole.owner || role == GroupRole.admin;
  }

  /// グループの削除
  static bool canDeleteGroup(GroupRole role) {
    return role == GroupRole.owner;
  }

  /// メンバーの追加
  static bool canAddMember(GroupRole role) {
    return role == GroupRole.owner || role == GroupRole.admin;
  }

  /// メンバーの削除（他のメンバーを強制退出させる）
  static bool canRemoveMember(GroupRole role) {
    return role == GroupRole.owner || role == GroupRole.admin;
  }

  /// メンバーの役割変更
  static bool canChangeRole(GroupRole role) {
    return role == GroupRole.owner;
  }

  /// グループタスクの作成
  static bool canCreateTask(GroupRole role) {
    return true; // 全メンバーが作成可能
  }

  /// グループタスクの更新（完了・未完了の切り替えなど）
  static bool canUpdateTask(GroupRole role) {
    return true; // 全メンバーが更新可能
  }

  /// グループタスクの削除
  static bool canDeleteTask(GroupRole role) {
    return role == GroupRole.owner || role == GroupRole.admin;
  }

  /// スケジュールテンプレートの作成
  static bool canCreateTemplate(GroupRole role) {
    return role == GroupRole.owner || role == GroupRole.admin;
  }

  /// スケジュールテンプレートの更新
  static bool canUpdateTemplate(GroupRole role) {
    return role == GroupRole.owner || role == GroupRole.admin;
  }

  /// スケジュールテンプレートの削除
  static bool canDeleteTemplate(GroupRole role) {
    return role == GroupRole.owner || role == GroupRole.admin;
  }

  /// グループから退出
  static bool canLeaveGroup(GroupRole role) {
    // オーナーは退出不可（他のメンバーに譲渡が必要）
    return role != GroupRole.owner;
  }
}

/// 役割名を日本語で取得
extension GroupRoleExtension on GroupRole {
  String get displayName {
    switch (this) {
      case GroupRole.owner:
        return 'オーナー';
      case GroupRole.admin:
        return '管理者';
      case GroupRole.member:
        return 'メンバー';
    }
  }

  String get description {
    switch (this) {
      case GroupRole.owner:
        return 'グループの全権限を持ちます';
      case GroupRole.admin:
        return 'グループの管理と繰り返しタスクの編集が可能';
      case GroupRole.member:
        return 'タスクの追加・完了が可能';
    }
  }

  /// Firestoreに保存する文字列
  String toFirestore() => name;

  /// Firestoreから復元
  static GroupRole fromFirestore(String value) {
    return GroupRole.values.firstWhere(
      (role) => role.name == value,
      orElse: () => GroupRole.member, // デフォルトはmember
    );
  }
}
