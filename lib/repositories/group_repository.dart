import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/group.dart';
import '../models/group_with_roles.dart';
import '../models/group_role.dart';
import '../services/invite_code_service.dart';

/// グループのCRUD操作を管理するリポジトリクラス
class GroupRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final InviteCodeService _inviteCodeService = InviteCodeService();

  /// グループコレクションの参照を取得
  CollectionReference get _groupsCollection => _firestore.collection('groups');

  /// グループを作成
  Future<Group> createGroup({
    required String name,
    required String ownerId,
  }) async {
    try {
      // ユニークな招待コードを生成
      final inviteCode = await _inviteCodeService.generateUniqueInviteCode();

      final now = DateTime.now();
      final docRef = _groupsCollection.doc();

      final group = Group(
        id: docRef.id,
        name: name,
        inviteCode: inviteCode,
        ownerId: ownerId,
        memberIds: [ownerId], // 作成者を最初のメンバーに追加
        createdAt: now,
        updatedAt: now,
        isActive: true,
      );

      final data = group.toFirestore();

      // 権限システム用のmemberRolesを追加
      data['memberRoles'] = {
        ownerId: GroupRole.owner.toFirestore(),
      };

      await docRef.set(data);

      return group;
    } catch (e) {
      throw Exception('グループの作成に失敗しました: $e');
    }
  }

  /// グループIDでグループを取得
  Future<Group?> getGroup(String groupId) async {
    try {
      final doc = await _groupsCollection.doc(groupId).get();

      if (!doc.exists) {
        return null;
      }

      return Group.fromFirestore(doc);
    } catch (e) {
      throw Exception('グループの取得に失敗しました: $e');
    }
  }

  /// グループIDでグループを監視（ストリーム）
  Stream<Group?> getGroupStream(String groupId) {
    return _groupsCollection.doc(groupId).snapshots().map((doc) {
      if (!doc.exists) {
        return null;
      }
      return Group.fromFirestore(doc);
    });
  }

  /// 招待コードでグループを検索
  Future<Group?> getGroupByInviteCode(String inviteCode) async {
    try {
      final doc = await _inviteCodeService.findGroupByInviteCode(inviteCode);

      if (doc == null) {
        return null;
      }

      final group = Group.fromFirestore(doc);
      return group;
    } catch (e) {
      throw Exception('グループの検索に失敗しました: $e');
    }
  }

  /// ユーザーが所属するグループ一覧を取得（ストリーム）
  Stream<List<Group>> getUserGroupsStream(String userId) {
    return _groupsCollection
        .where('memberIds', arrayContains: userId)
        .where('isActive', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => Group.fromFirestore(doc)).toList();
    });
  }

  /// ユーザーが所属するグループ一覧を取得（一度だけ）
  Future<List<Group>> getUserGroups(String userId) async {
    try {
      final snapshot = await _groupsCollection
          .where('memberIds', arrayContains: userId)
          .where('isActive', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs.map((doc) => Group.fromFirestore(doc)).toList();
    } catch (e) {
      throw Exception('グループ一覧の取得に失敗しました: $e');
    }
  }

  /// グループにメンバーを追加
  Future<void> addMember(String groupId, String userId) async {
    try {
      // memberRolesも更新（デフォルトはmember）
      await _groupsCollection.doc(groupId).update({
        'memberIds': FieldValue.arrayUnion([userId]),
        'memberRoles.$userId': GroupRole.member.toFirestore(),
        'updatedAt': Timestamp.now(),
      });
    } catch (e) {
      throw Exception('メンバーの追加に失敗しました: $e');
    }
  }

  /// グループからメンバーを削除
  Future<void> removeMember(String groupId, String userId) async {
    try {
      await _groupsCollection.doc(groupId).update({
        'memberIds': FieldValue.arrayRemove([userId]),
        'updatedAt': Timestamp.now(),
      });
    } catch (e) {
      throw Exception('メンバーの削除に失敗しました: $e');
    }
  }

  /// グループ名を更新
  Future<void> updateGroupName(String groupId, String name) async {
    try {
      await _groupsCollection.doc(groupId).update({
        'name': name,
        'updatedAt': Timestamp.now(),
      });
    } catch (e) {
      throw Exception('グループ名の更新に失敗しました: $e');
    }
  }

  /// グループの参加可否を切り替え
  Future<void> updateJoinable(String groupId, bool isJoinable) async {
    try {
      await _groupsCollection.doc(groupId).update({
        'isJoinable': isJoinable,
        'updatedAt': Timestamp.now(),
      });
    } catch (e) {
      throw Exception('参加設定の更新に失敗しました: $e');
    }
  }

  /// グループを削除（論理削除）
  Future<void> deleteGroup(String groupId) async {
    try {
      // グループに関連する全てのタスクを削除
      final tasksSnapshot =
          await FirebaseFirestore.instance.collection('tasks').where('groupId', isEqualTo: groupId).get();

      // バッチ処理でタスクを削除
      final batch = FirebaseFirestore.instance.batch();

      for (final doc in tasksSnapshot.docs) {
        batch.delete(doc.reference);
      }

      // グループを非アクティブ化
      batch.update(_groupsCollection.doc(groupId), {
        'isActive': false,
        'updatedAt': Timestamp.now(),
      });

      await batch.commit();
    } catch (e) {
      throw Exception('グループの削除に失敗しました: $e');
    }
  }

  /// グループから退出（自分を削除）
  Future<void> leaveGroup(String groupId, String userId) async {
    try {
      final group = await getGroup(groupId);

      if (group == null) {
        throw Exception('グループが見つかりません');
      }

      // オーナーの場合は退出できない
      if (group.isOwner(userId)) {
        throw Exception('グループのオーナーは退出できません。グループを削除してください。');
      }

      await removeMember(groupId, userId);
    } catch (e) {
      throw Exception('グループの退出に失敗しました: $e');
    }
  }

  /// 招待コードでグループに参加
  Future<Group> joinGroupByInviteCode({
    required String inviteCode,
    required String userId,
  }) async {
    try {
      // 招待コードの形式チェック
      if (!_inviteCodeService.isValidInviteCode(inviteCode)) {
        throw Exception('招待コードの形式が正しくありません');
      }

      // グループを検索
      final group = await getGroupByInviteCode(inviteCode);

      if (group == null) {
        throw Exception('招待コードが見つかりません');
      }

      // 既にメンバーの場合
      if (group.isMember(userId)) {
        throw Exception('既にこのグループに参加しています');
      }

      // メンバーを追加
      await addMember(group.id, userId);

      // 更新されたグループを返す
      final updatedGroup = await getGroup(group.id);
      return updatedGroup!;
    } catch (e) {
      if (e.toString().contains('招待コード') || e.toString().contains('既にこのグループ')) {
        rethrow;
      }
      throw Exception('グループへの参加に失敗しました: $e');
    }
  }

  /// グループIDでGroupWithRolesを取得
  Future<GroupWithRoles?> getGroupWithRoles(String groupId) async {
    try {
      final doc = await _groupsCollection.doc(groupId).get();

      if (!doc.exists) {
        return null;
      }

      return GroupWithRoles.fromFirestore(doc);
    } catch (e) {
      throw Exception('グループの取得に失敗しました: $e');
    }
  }

  /// メンバーの役割を更新
  Future<void> updateMemberRole({
    required String groupId,
    required String requestUserId,
    required String targetUserId,
    required GroupRole newRole,
  }) async {
    try {
      final group = await getGroupWithRoles(groupId);

      if (group == null) {
        throw Exception('グループが見つかりません');
      }

      // 権限チェック（オーナーのみ）
      if (!group.canChangeRole(requestUserId)) {
        throw Exception('メンバーの役割を変更する権限がありません');
      }

      // オーナーの役割は変更できない
      if (targetUserId == group.ownerId) {
        throw Exception('オーナーの役割は変更できません');
      }

      // 役割更新
      final updatedRoles = Map<String, GroupRole>.from(group.memberRoles);
      updatedRoles[targetUserId] = newRole;

      await _groupsCollection.doc(groupId).update({
        'memberRoles': updatedRoles.map((k, v) => MapEntry(k, v.toFirestore())),
        'updatedAt': Timestamp.now(),
      });
    } catch (e) {
      rethrow;
    }
  }

  /// メンバーを削除（権限チェック付き）
  Future<void> removeMemberWithPermission({
    required String groupId,
    required String requestUserId,
    required String targetUserId,
  }) async {
    try {
      final group = await getGroupWithRoles(groupId);

      if (group == null) {
        throw Exception('グループが見つかりません');
      }

      // 詳細な権限チェック
      if (!group.canRemoveSpecificMember(requestUserId, targetUserId)) {
        final targetRole = group.getRoleForUser(targetUserId);

        if (targetUserId == group.ownerId) {
          throw Exception('オーナーは削除できません');
        } else if (targetRole == GroupRole.admin) {
          throw Exception('管理者は他の管理者を削除できません');
        } else {
          throw Exception('このメンバーを削除する権限がありません');
        }
      }

      // メンバー削除
      final updatedRoles = Map<String, GroupRole>.from(group.memberRoles);
      updatedRoles.remove(targetUserId);

      await _groupsCollection.doc(groupId).update({
        'memberRoles': updatedRoles.map((k, v) => MapEntry(k, v.toFirestore())),
        'memberIds': updatedRoles.keys.toList(),
        'updatedAt': Timestamp.now(),
      });
    } catch (e) {
      rethrow;
    }
  }
}
