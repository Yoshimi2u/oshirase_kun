import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/schedule.dart';
import '../repositories/schedule_repository.dart';

/// ScheduleRepository のプロバイダー
final scheduleRepositoryProvider = Provider<ScheduleRepository>((ref) {
  return ScheduleRepository();
});

/// 現在のユーザーIDを取得するStreamProvider（認証状態の変更を監視）
final currentUserIdProvider = StreamProvider<String?>((ref) {
  return FirebaseAuth.instance.authStateChanges().map((user) => user?.uid);
});

/// すべての予定を取得するStreamProvider
final schedulesStreamProvider = StreamProvider.autoDispose<List<Schedule>>((ref) {
  final userIdAsync = ref.watch(currentUserIdProvider);
  return userIdAsync.when(
    data: (userId) {
      if (userId == null) {
        return Stream.value([]);
      }
      final repository = ref.watch(scheduleRepositoryProvider);
      return repository.getSchedulesStream(userId);
    },
    loading: () => Stream.value([]),
    error: (_, __) => Stream.value([]),
  );
});

/// 今日のタスクを取得するStreamProvider
final todaySchedulesStreamProvider = StreamProvider.autoDispose<List<Schedule>>((ref) {
  final userIdAsync = ref.watch(currentUserIdProvider);
  return userIdAsync.when(
    data: (userId) {
      if (userId == null) {
        return Stream.value([]);
      }
      final repository = ref.watch(scheduleRepositoryProvider);
      return repository.getTodaySchedulesStream(userId);
    },
    loading: () => Stream.value([]),
    error: (_, __) => Stream.value([]),
  );
});

/// 遅延タスクを取得するStreamProvider
final overdueSchedulesStreamProvider = StreamProvider.autoDispose<List<Schedule>>((ref) {
  final userIdAsync = ref.watch(currentUserIdProvider);
  return userIdAsync.when(
    data: (userId) {
      if (userId == null) {
        return Stream.value([]);
      }
      final repository = ref.watch(scheduleRepositoryProvider);
      return repository.getOverdueSchedulesStream(userId);
    },
    loading: () => Stream.value([]),
    error: (_, __) => Stream.value([]),
  );
});

/// 今日以降のタスクを取得するStreamProvider
final upcomingSchedulesStreamProvider = StreamProvider.autoDispose<List<Schedule>>((ref) {
  final userIdAsync = ref.watch(currentUserIdProvider);
  return userIdAsync.when(
    data: (userId) {
      if (userId == null) {
        return Stream.value([]);
      }
      final repository = ref.watch(scheduleRepositoryProvider);
      return repository.getUpcomingSchedulesStream(userId);
    },
    loading: () => Stream.value([]),
    error: (_, __) => Stream.value([]),
  );
});

/// 今日完了したタスクを取得するStreamProvider
final todayCompletedSchedulesStreamProvider = StreamProvider.autoDispose<List<Schedule>>((ref) {
  final userIdAsync = ref.watch(currentUserIdProvider);
  return userIdAsync.when(
    data: (userId) {
      if (userId == null) {
        return Stream.value([]);
      }
      final repository = ref.watch(scheduleRepositoryProvider);
      return repository.getTodayCompletedSchedulesStream(userId);
    },
    loading: () => Stream.value([]),
    error: (_, __) => Stream.value([]),
  );
});

/// アクティブな予定のみを取得するStreamProvider
final activeSchedulesStreamProvider = StreamProvider.autoDispose<List<Schedule>>((ref) {
  final userIdAsync = ref.watch(currentUserIdProvider);
  return userIdAsync.when(
    data: (userId) {
      if (userId == null) {
        return Stream.value([]);
      }
      final repository = ref.watch(scheduleRepositoryProvider);
      return repository.getActiveSchedulesStream(userId);
    },
    loading: () => Stream.value([]),
    error: (_, __) => Stream.value([]),
  );
});

/// 予定の作成・更新・削除を管理するStateNotifierProvider
final scheduleNotifierProvider = StateNotifierProvider<ScheduleNotifier, AsyncValue<void>>((ref) {
  final repository = ref.watch(scheduleRepositoryProvider);
  final userIdAsync = ref.watch(currentUserIdProvider);
  final userId = userIdAsync.maybeWhen(
    data: (id) => id,
    orElse: () => null,
  );
  return ScheduleNotifier(repository, userId);
});

class ScheduleNotifier extends StateNotifier<AsyncValue<void>> {
  final ScheduleRepository _repository;
  final String? _userId;

  ScheduleNotifier(
    this._repository,
    this._userId,
  ) : super(const AsyncValue.data(null));

  /// 予定を作成
  Future<void> createSchedule(Schedule schedule) async {
    if (_userId == null) {
      state = AsyncValue.error('ユーザーが認証されていません', StackTrace.current);
      return;
    }

    state = const AsyncValue.loading();
    try {
      // nextScheduledDateを初期化
      final initialSchedule = schedule.copyWith(
        nextScheduledDate: schedule.startDate ?? DateTime.now(),
      );

      await _repository.createSchedule(_userId!, initialSchedule);

      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow; // エラーを再スローしてUIで検出できるようにする
    }
  }

  /// 予定を更新
  Future<void> updateSchedule(Schedule schedule) async {
    if (_userId == null) {
      state = AsyncValue.error('ユーザーが認証されていません', StackTrace.current);
      return;
    }

    state = const AsyncValue.loading();
    try {
      await _repository.updateSchedule(_userId!, schedule);

      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// 予定を削除
  Future<void> deleteSchedule(String scheduleId) async {
    if (_userId == null) {
      state = AsyncValue.error('ユーザーが認証されていません', StackTrace.current);
      return;
    }

    state = const AsyncValue.loading();
    try {
      await _repository.deleteSchedule(_userId!, scheduleId);

      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// 予定を完了する
  Future<void> completeSchedule(Schedule schedule) async {
    if (_userId == null) {
      state = AsyncValue.error('ユーザーが認証されていません', StackTrace.current);
      return;
    }

    state = const AsyncValue.loading();
    try {
      await _repository.completeSchedule(_userId!, schedule);

      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}
