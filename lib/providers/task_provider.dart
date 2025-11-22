import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/schedule_instance.dart';
import '../models/schedule_template.dart';
import '../repositories/task_repository.dart';
import 'group_provider.dart';
import 'schedule_template_provider.dart';

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

/// 明日以降のタスク一覧のプロバイダー（予定一覧画面用、1週間分）
final upcomingTasksProvider = FutureProvider.autoDispose<List<Task>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);

  if (userId == null) {
    return [];
  }

  // 30分間キャッシュを保持（Firestore読み取り回数削減）
  final link = ref.keepAlive();
  Timer(const Duration(minutes: 30), () {
    link.close();
  });

  try {
    final repository = ref.watch(taskRepositoryProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // 明日から1週間分を取得（明日 + 6日 = 7日間）
    final startDate = today.add(const Duration(days: 1));
    final endDate = startDate.add(const Duration(days: 6));

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

/// 明日のタスク一覧のプロバイダー（予定一覧画面の初期表示用）
final tomorrowTasksProvider = FutureProvider.autoDispose<List<Task>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);

  if (userId == null) {
    return [];
  }

  // 30分間キャッシュを保持（Firestore読み取り回数削減）
  final link = ref.keepAlive();
  Timer(const Duration(minutes: 30), () {
    link.close();
  });

  try {
    final repository = ref.watch(taskRepositoryProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // 明日のみを取得
    final startDate = today.add(const Duration(days: 1));
    final endDate = startDate;

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

/// 明日以降のタスク一覧のプロバイダー（拡張版：翌月末まで）
final extendedUpcomingTasksProvider = FutureProvider.autoDispose<List<Task>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);

  if (userId == null) {
    return [];
  }

  // 30分間キャッシュを保持（Firestore読み取り回数削減）
  final link = ref.keepAlive();
  Timer(const Duration(minutes: 30), () {
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
/// 14日以降は仮想タスクを生成して表示
final tasksByDateRangeProvider = FutureProvider.autoDispose.family<List<Task>, DateRangeParams>((ref, params) async {
  final userId = ref.watch(currentUserIdProvider);

  if (userId == null) {
    return [];
  }

  // 30分間キャッシュを保持（月切り替え時の再読み取りを防ぐ、Firestore読み取り回数削減）
  final link = ref.keepAlive();
  Timer(const Duration(minutes: 30), () {
    link.close();
  });

  try {
    final repository = ref.watch(taskRepositoryProvider);
    final templateRepository = ref.watch(scheduleTemplateRepositoryProvider);

    // 自分のタスクを取得（Future版）
    final myTasks = await repository.getTasksByDateRange(userId, params.startDate, params.endDate);

    // グループ一覧を取得
    final groups = await ref.watch(userGroupsStreamProvider.future);

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

    // 14日後の日付を計算
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final generationLimit = todayDate.add(const Duration(days: 14));

    // 仮想タスクが必要な範囲かチェック
    if (params.endDate.isAfter(generationLimit)) {
      // テンプレート一覧を取得（個人 + グループ）
      final templates = await templateRepository.getActiveTemplates(userId);

      if (kDebugMode) {
        print('📅 [tasksByDateRangeProvider] 個人テンプレート数: ${templates.length}');
      }

      // グループテンプレートも取得
      for (final group in groups) {
        try {
          final groupTemplates = await templateRepository.getGroupTemplates(group.id);
          if (kDebugMode) {
            print('📅 [tasksByDateRangeProvider] グループ ${group.name} のテンプレート数: ${groupTemplates.length}');
          }
          templates.addAll(groupTemplates);
        } catch (e) {
          if (kDebugMode) {
            print('⚠️ [tasksByDateRangeProvider] グループテンプレート取得エラー: $e');
          }
          continue;
        }
      }

      if (kDebugMode) {
        print('📅 [tasksByDateRangeProvider] 合計テンプレート数: ${templates.length}');
      }

      // 既存タスクのマップを作成（templateId + 日付 -> Task）
      // 論理削除されたタスク(isDeleted=true)も含めて、その日付には仮想タスクを生成しない
      final existingTasksMap = <String, Task>{};
      for (final task in allTasks) {
        // 論理削除されたタスクも含める(削除した日付に仮想タスクを表示しない)
        final dateKey = _getDateKey(task.scheduledDate);
        final key = '${task.templateId}_$dateKey';
        existingTasksMap[key] = task;
      }

      // 各テンプレートから仮想タスクを生成
      int virtualTaskCount = 0;
      for (final template in templates) {
        // 繰り返しなし、カスタム繰り返しはスキップ（Cloud Functionが処理しない）
        if (template.repeatType == RepeatType.none || template.repeatType == RepeatType.custom) {
          continue;
        }

        // テンプレートから期間内の日付を生成
        final virtualStartDate = generationLimit.add(const Duration(days: 1));
        final virtualEndDate = params.endDate;

        if (kDebugMode) {
          print(
              '📅 [tasksByDateRangeProvider] テンプレート: ${template.title}, isGroupSchedule: ${template.isGroupSchedule}, 生成期間: $virtualStartDate ~ $virtualEndDate');
        }

        // 日付を生成
        DateTime currentDate = virtualStartDate;
        while (currentDate.isBefore(virtualEndDate) || currentDate.isAtSameMomentAs(virtualEndDate)) {
          final dateKey = _getDateKey(currentDate);
          final key = '${template.id}_$dateKey';

          // 既存タスクがなければ仮想タスクを作成
          if (!existingTasksMap.containsKey(key) && _shouldGenerateTaskForDate(template, currentDate)) {
            final virtualTask = Task(
              id: 'virtual_${template.id}_$dateKey', // 仮想タスク用のID
              userId: template.isGroupSchedule ? userId : template.userId, // グループタスクの場合は現在のユーザーID
              templateId: template.id,
              title: template.title,
              description: template.description,
              scheduledDate: currentDate,
              completedAt: null,
              completedByMemberId: null,
              groupId: template.groupId,
              isGroupSchedule: template.isGroupSchedule,
              repeatType: template.repeatType.name,
              weekdays: template.selectedWeekdays,
              repeatInterval: template.repeatInterval,
              monthlyDay: template.monthlyDay,
              isVirtual: true,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            );
            allTasks.add(virtualTask);
            virtualTaskCount++;
          }

          currentDate = currentDate.add(const Duration(days: 1));
        }
      }

      if (kDebugMode) {
        print('📅 [tasksByDateRangeProvider] 生成された仮想タスク数: $virtualTaskCount');
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

/// 日付をキー文字列に変換
String _getDateKey(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

/// 指定された日付にタスクを生成すべきかチェック
bool _shouldGenerateTaskForDate(ScheduleTemplate template, DateTime date) {
  switch (template.repeatType) {
    case RepeatType.daily:
      return true;

    case RepeatType.customWeekly:
      if (template.selectedWeekdays == null || template.selectedWeekdays!.isEmpty) {
        return false;
      }
      return template.selectedWeekdays!.contains(date.weekday);

    case RepeatType.monthly:
      if (template.monthlyDay == null) return false;
      return date.day == template.monthlyDay;

    case RepeatType.monthlyLastDay:
      // 月末日かチェック
      final nextMonth = DateTime(date.year, date.month + 1, 1);
      final lastDay = nextMonth.subtract(const Duration(days: 1));
      return date.day == lastDay.day;

    case RepeatType.none:
    case RepeatType.custom:
      return false;
  }
}
