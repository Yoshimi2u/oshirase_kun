import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/schedule_instance.dart';
import '../repositories/task_repository.dart';
import 'group_provider.dart';

/// 期間パラメータ用のクラス
class DateRangeParams {
  final DateTime startDate;
  final DateTime endDate;

  const DateRangeParams({
    required this.startDate,
    required this.endDate,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DateRangeParams &&
          runtimeType == other.runtimeType &&
          startDate == other.startDate &&
          endDate == other.endDate;

  @override
  int get hashCode => startDate.hashCode ^ endDate.hashCode;
}

/// TaskRepository のプロバイダー
final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  return TaskRepository();
});

/// 現在のユーザーIDのプロバイダー
final currentUserIdProvider = Provider<String?>((ref) {
  return FirebaseAuth.instance.currentUser?.uid;
});

/// 今日のタスク一覧のストリームプロバイダー（自分のタスク + グループタスク）
final todayTasksStreamProvider = StreamProvider.autoDispose<List<Task>>((ref) {
  final userId = ref.watch(currentUserIdProvider);

  if (userId == null) {
    return Stream.value([]);
  }

  try {
    final repository = ref.watch(taskRepositoryProvider);

    // 自分のタスクストリーム
    final myTasksStream = repository.watchTodayTasks(userId);

    // グループタスクストリームを取得するため、グループ一覧を監視
    return ref.watch(userGroupsStreamProvider).when(
      data: (groups) {
        if (groups.isEmpty) {
          // グループがない場合は自分のタスクのみ
          return myTasksStream;
        }

        // すべてのストリームをリアルタイムで結合
        final controller = StreamController<List<Task>>();
        final subscriptions = <StreamSubscription>[];

        // 最新のタスクを保持
        final myTasks = <Task>[];
        final groupTasksMap = <String, List<Task>>{}; // groupId -> tasks

        void updateTasks() {
          // すべてのタスクを結合
          final allTasks = <Task>[...myTasks];
          for (final tasks in groupTasksMap.values) {
            allTasks.addAll(tasks);
          }

          // 重複を削除（同じIDのタスク）
          final uniqueTasks = <String, Task>{};
          for (final task in allTasks) {
            uniqueTasks[task.id] = task;
          }

          // scheduledDateでソート
          final sortedTasks = uniqueTasks.values.toList()..sort((a, b) => a.scheduledDate.compareTo(b.scheduledDate));

          controller.add(sortedTasks);
        }

        // 自分のタスクを監視
        subscriptions.add(myTasksStream.listen(
          (tasks) {
            myTasks.clear();
            myTasks.addAll(tasks);
            updateTasks();
          },
          onError: (error) => controller.addError(error),
        ));

        // 各グループタスクを監視
        for (final group in groups) {
          final today = DateTime.now();
          final startOfDay = DateTime(today.year, today.month, today.day);
          final endOfDay = DateTime(today.year, today.month, today.day, 23, 59, 59);

          subscriptions.add(
            repository.watchGroupTasks(group.id).listen(
              (tasks) {
                // 今日のタスク + 過去の未完了タスクのみフィルタ
                final todayTasks = tasks.where((task) {
                  final taskDate = task.scheduledDate;

                  // 今日のタスクは全て含める
                  if (taskDate.isAfter(startOfDay.subtract(const Duration(seconds: 1))) &&
                      taskDate.isBefore(endOfDay.add(const Duration(seconds: 1)))) {
                    return true;
                  }
                  // 過去のタスクは未完了のみ含める
                  if (taskDate.isBefore(startOfDay)) {
                    return !task.isCompleted;
                  }
                  // 未来のタスクは含めない
                  return false;
                }).toList();

                groupTasksMap[group.id] = todayTasks;
                updateTasks();
              },
              onError: (error) {
                // エラーが発生してもそのグループだけスキップ
                groupTasksMap[group.id] = [];
                updateTasks();
              },
            ),
          );
        }

        // クリーンアップ
        ref.onDispose(() {
          for (final subscription in subscriptions) {
            subscription.cancel();
          }
          controller.close();
        });

        return controller.stream;
      },
      loading: () {
        return myTasksStream;
      },
      error: (error, stack) {
        return myTasksStream;
      },
    );
  } catch (e) {
    return Stream.value([]);
  }
});

/// 明日以降のタスク一覧のプロバイダー（予定一覧画面用）
final upcomingTasksProvider = FutureProvider.autoDispose<List<Task>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);

  if (userId == null) {
    return [];
  }

  // 5分間キャッシュを保持（短時間の画面遷移に対応）
  final link = ref.keepAlive();
  Timer(const Duration(minutes: 5), () {
    link.close();
  });

  try {
    final repository = ref.watch(taskRepositoryProvider);
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final startDate = DateTime(tomorrow.year, tomorrow.month, tomorrow.day);
    // 翌月末まで取得
    final endDate = DateTime(tomorrow.year, tomorrow.month + 2, 0);

    // 自分のタスクを取得（Future版）
    final myTasks = await repository.getTasksByDateRange(userId, startDate, endDate);

    // グループ一覧を取得
    final groups = await ref.watch(userGroupsStreamProvider.future);

    if (groups.isEmpty) {
      // グループがない場合は自分のタスクのみ
      return myTasks;
    }

    // すべてのタスクを結合
    final allTasks = <Task>[...myTasks];

    // 各グループタスクを取得
    for (final group in groups) {
      try {
        final groupTasks = await repository.getGroupTasksByDateRange(
          group.id,
          startDate,
          endDate,
        );
        allTasks.addAll(groupTasks);
      } catch (e) {
        // エラーが発生しても続行（他のグループタスクは取得）
        continue;
      }
    }

    // 重複を削除（同じIDのタスク）
    final uniqueTasks = <String, Task>{};
    for (final task in allTasks) {
      uniqueTasks[task.id] = task;
    }

    // scheduledDateでソート
    final sortedTasks = uniqueTasks.values.toList()..sort((a, b) => a.scheduledDate.compareTo(b.scheduledDate));

    return sortedTasks;
  } catch (e) {
    return [];
  }
});

/// 指定日のタスク一覧のストリームプロバイダー
final tasksByDateStreamProvider = StreamProvider.autoDispose.family<List<Task>, DateTime>((ref, date) {
  final userId = ref.watch(currentUserIdProvider);

  if (userId == null) {
    return Stream.value([]);
  } else {
    try {
      final repository = ref.watch(taskRepositoryProvider);
      return repository.watchTasksByDate(userId, date);
    } catch (e) {
      return Stream.value([]);
    }
  }
});

/// グループタスク一覧のストリームプロバイダー
final groupTasksStreamProvider = StreamProvider.autoDispose.family<List<Task>, String>((ref, groupId) {
  try {
    final repository = ref.watch(taskRepositoryProvider);
    return repository.watchGroupTasks(groupId);
  } catch (e) {
    return Stream.value([]);
  }
});

/// 期間内のタスク一覧のストリームプロバイダー（カレンダー用）
final tasksByDateRangeStreamProvider = StreamProvider.autoDispose.family<List<Task>, DateRangeParams>((ref, params) {
  final userId = ref.watch(currentUserIdProvider);

  if (userId == null) {
    return Stream.value([]);
  }

  // 5分間キャッシュを保持（月切り替え時の再読み取りを防ぐ）
  final link = ref.keepAlive();
  Timer(const Duration(minutes: 5), () {
    link.close();
  });

  try {
    final repository = ref.watch(taskRepositoryProvider);

    // 自分のタスクストリーム
    final myTasksStream = repository.watchTasksByDateRange(userId, params.startDate, params.endDate);

    // グループタスクストリームを取得するため、グループ一覧を監視
    return ref.watch(userGroupsStreamProvider).when(
          data: (groups) {
            if (groups.isEmpty) {
              // グループがない場合は自分のタスクのみ
              return myTasksStream;
            }

            // すべてのストリームをリアルタイムで結合
            final controller = StreamController<List<Task>>();
            final subscriptions = <StreamSubscription>[];

            // 最新のタスクを保持
            final myTasks = <Task>[];
            final groupTasksMap = <String, List<Task>>{}; // groupId -> tasks

            void updateTasks() {
              // すべてのタスクを結合
              final allTasks = <Task>[...myTasks];
              for (final tasks in groupTasksMap.values) {
                allTasks.addAll(tasks);
              }

              // 重複を削除（同じIDのタスク）
              final uniqueTasks = <String, Task>{};
              for (final task in allTasks) {
                uniqueTasks[task.id] = task;
              }

              // scheduledDateでソート
              final sortedTasks = uniqueTasks.values.toList()
                ..sort((a, b) => a.scheduledDate.compareTo(b.scheduledDate));

              controller.add(sortedTasks);
            }

            // 自分のタスクを監視
            subscriptions.add(myTasksStream.listen(
              (tasks) {
                myTasks.clear();
                myTasks.addAll(tasks);
                updateTasks();
              },
              onError: (error) => controller.addError(error),
            ));

            // 各グループタスクを監視
            for (final group in groups) {
              subscriptions.add(
                repository.watchGroupTasks(group.id).listen(
                  (tasks) {
                    // 指定期間のタスクのみフィルタ
                    final endOfDay =
                        DateTime(params.endDate.year, params.endDate.month, params.endDate.day, 23, 59, 59);
                    final filteredTasks = tasks.where((task) {
                      return task.scheduledDate.isAfter(params.startDate.subtract(const Duration(seconds: 1))) &&
                          task.scheduledDate.isBefore(endOfDay.add(const Duration(seconds: 1)));
                    }).toList();

                    groupTasksMap[group.id] = filteredTasks;
                    updateTasks();
                  },
                  onError: (error) {
                    // エラーが発生してもそのグループだけスキップ
                    groupTasksMap[group.id] = [];
                    updateTasks();
                  },
                ),
              );
            }

            // クリーンアップ
            ref.onDispose(() {
              for (final subscription in subscriptions) {
                subscription.cancel();
              }
              controller.close();
            });

            return controller.stream;
          },
          loading: () => myTasksStream,
          error: (_, __) => myTasksStream,
        );
  } catch (e) {
    return Stream.value([]);
  }
});

/// 期間内のタスク一覧のプロバイダー（カレンダー用、Future版）
final tasksByDateRangeProvider = FutureProvider.autoDispose.family<List<Task>, DateRangeParams>((ref, params) async {
  final userId = ref.watch(currentUserIdProvider);

  if (userId == null) {
    return [];
  }

  // 5分間キャッシュを保持（月切り替え時の再読み取りを防ぐ）
  final link = ref.keepAlive();
  Timer(const Duration(minutes: 5), () {
    link.close();
  });

  try {
    final repository = ref.watch(taskRepositoryProvider);

    // 自分のタスクを取得（Future版）
    final myTasks = await repository.getTasksByDateRange(userId, params.startDate, params.endDate);

    // グループ一覧を取得
    final groups = await ref.watch(userGroupsStreamProvider.future);

    if (groups.isEmpty) {
      // グループがない場合は自分のタスクのみ
      return myTasks;
    }

    // すべてのタスクを結合
    final allTasks = <Task>[...myTasks];

    // 各グループタスクを取得
    for (final group in groups) {
      try {
        final groupTasks = await repository.getGroupTasksByDateRange(
          group.id,
          params.startDate,
          params.endDate,
        );
        allTasks.addAll(groupTasks);
      } catch (e) {
        // エラーが発生しても続行（他のグループタスクは取得）
        continue;
      }
    }

    // 重複を削除（同じIDのタスク）
    final uniqueTasks = <String, Task>{};
    for (final task in allTasks) {
      uniqueTasks[task.id] = task;
    }

    // scheduledDateでソート
    final sortedTasks = uniqueTasks.values.toList()..sort((a, b) => a.scheduledDate.compareTo(b.scheduledDate));

    return sortedTasks;
  } catch (e) {
    return [];
  }
});
