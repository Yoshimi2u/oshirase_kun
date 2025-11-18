import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_profile.dart';
import '../repositories/user_profile_repository.dart';

/// ユーザープロフィールリポジトリのプロバイダー
final userProfileRepositoryProvider = Provider<UserProfileRepository>((ref) {
  return UserProfileRepository();
});

/// 現在のユーザーIDプロバイダー
final currentUserIdProvider = Provider<String?>((ref) {
  final user = FirebaseAuth.instance.currentUser;
  return user?.uid;
});

/// ユーザープロフィールのStreamプロバイダー（自動作成付き）
final userProfileStreamProvider = StreamProvider.autoDispose<UserProfile?>((ref) async* {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) {
    yield null;
    return;
  }

  final repository = ref.watch(userProfileRepositoryProvider);

  // 初回アクセス時にプロフィールが存在しない場合は作成
  final profile = await repository.getUserProfile(userId);
  if (profile == null) {
    await repository.createProfileIfNotExists(userId);
  }

  // Streamを返す
  yield* repository.getUserProfileStream(userId);
});

/// ユーザープロフィールの状態管理Notifier
class UserProfileNotifier extends StateNotifier<AsyncValue<UserProfile?>> {
  final UserProfileRepository _repository;
  final String? _userId;

  UserProfileNotifier(this._repository, this._userId) : super(const AsyncValue.loading()) {
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    if (_userId == null) {
      state = const AsyncValue.data(null);
      return;
    }

    state = const AsyncValue.loading();
    try {
      final profile = await _repository.getUserProfile(_userId!);
      state = AsyncValue.data(profile);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  /// 表示名を更新
  Future<void> updateDisplayName(String displayName) async {
    if (_userId == null) return;

    try {
      await _repository.updateDisplayName(_userId!, displayName);
      await _loadProfile();
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
      rethrow;
    }
  }

  /// プロフィールを作成（存在しない場合のみ）
  Future<void> createProfileIfNotExists({String displayName = 'ユーザー'}) async {
    if (_userId == null) return;

    try {
      await _repository.createProfileIfNotExists(_userId!, displayName: displayName);
      await _loadProfile();
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
      rethrow;
    }
  }
}

/// ユーザープロフィールNotifierのプロバイダー
final userProfileNotifierProvider = StateNotifierProvider<UserProfileNotifier, AsyncValue<UserProfile?>>((ref) {
  final repository = ref.watch(userProfileRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);
  return UserProfileNotifier(repository, userId);
});
