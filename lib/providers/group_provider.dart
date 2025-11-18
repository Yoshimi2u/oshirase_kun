import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/group.dart';
import '../repositories/group_repository.dart';

/// GroupRepositoryのプロバイダー
final groupRepositoryProvider = Provider<GroupRepository>((ref) {
  return GroupRepository();
});

/// 現在のユーザーのグループ一覧を監視するプロバイダー
final userGroupsStreamProvider = StreamProvider.autoDispose<List<Group>>((ref) {
  final user = FirebaseAuth.instance.currentUser;

  if (user == null) {
    return Stream.value([]);
  }

  final repository = ref.watch(groupRepositoryProvider);
  return repository.getUserGroupsStream(user.uid);
});

/// グループ操作を管理するStateNotifierProvider
final groupNotifierProvider = StateNotifierProvider<GroupNotifier, AsyncValue<void>>((ref) {
  final repository = ref.watch(groupRepositoryProvider);
  return GroupNotifier(repository);
});

/// グループ操作を管理するStateNotifier
class GroupNotifier extends StateNotifier<AsyncValue<void>> {
  final GroupRepository _repository;

  GroupNotifier(this._repository) : super(const AsyncValue.data(null));

  /// グループを作成
  Future<Group?> createGroup({
    required String name,
    required String ownerId,
  }) async {
    state = const AsyncValue.loading();

    try {
      final group = await _repository.createGroup(
        name: name,
        ownerId: ownerId,
      );

      state = const AsyncValue.data(null);
      return group;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow; // エラーを再スローして詳細を確認できるようにする
    }
  }

  /// 招待コードでグループに参加
  Future<Group?> joinGroup({
    required String inviteCode,
    required String userId,
  }) async {
    state = const AsyncValue.loading();

    try {
      final group = await _repository.joinGroupByInviteCode(
        inviteCode: inviteCode,
        userId: userId,
      );

      state = const AsyncValue.data(null);
      return group;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return null;
    }
  }

  /// グループから退出
  Future<bool> leaveGroup({
    required String groupId,
    required String userId,
  }) async {
    state = const AsyncValue.loading();

    try {
      await _repository.leaveGroup(groupId, userId);

      state = const AsyncValue.data(null);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// グループ名を更新
  Future<bool> updateGroupName({
    required String groupId,
    required String name,
  }) async {
    state = const AsyncValue.loading();

    try {
      await _repository.updateGroupName(groupId, name);

      state = const AsyncValue.data(null);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// グループを削除
  Future<bool> deleteGroup(String groupId) async {
    state = const AsyncValue.loading();

    try {
      await _repository.deleteGroup(groupId);

      state = const AsyncValue.data(null);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// メンバーを削除（オーナーのみ）
  Future<bool> removeMember({
    required String groupId,
    required String userId,
  }) async {
    state = const AsyncValue.loading();

    try {
      await _repository.removeMember(groupId, userId);

      state = const AsyncValue.data(null);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }
}

/// 特定のグループを取得するプロバイダー
final groupProvider = FutureProvider.autoDispose.family<Group?, String>((ref, groupId) async {
  final repository = ref.watch(groupRepositoryProvider);
  return await repository.getGroup(groupId);
});
