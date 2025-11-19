import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../models/schedule.dart';
import '../models/completion_history.dart';
import '../providers/schedule_provider.dart';
import '../providers/completion_history_provider.dart';
import '../providers/group_provider.dart';
import '../utils/toast_utils.dart';

/// カレンダー画面
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late DateTime _focusedDay;
  late DateTime _selectedDay;
  CalendarFormat _calendarFormat = CalendarFormat.month;

  @override
  void initState() {
    super.initState();
    _focusedDay = DateTime.now();
    _selectedDay = DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    final schedulesAsync = ref.watch(schedulesStreamProvider);

    return schedulesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            const Text(
              'エラーが発生しました',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '予定の読み込みに失敗しました',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
      data: (schedules) => Column(
        children: [
          _buildCalendar(schedules),
          const Divider(height: 1),
          Expanded(
            child: _buildScheduleList(schedules),
          ),
        ],
      ),
    );
  }

  /// カレンダーウィジェット
  Widget _buildCalendar(List<Schedule> schedules) {
    return TableCalendar(
      firstDay: DateTime.utc(2020, 1, 1),
      lastDay: DateTime.utc(2030, 12, 31),
      focusedDay: _focusedDay,
      selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
      calendarFormat: _calendarFormat,
      locale: 'ja_JP',
      startingDayOfWeek: StartingDayOfWeek.sunday,
      calendarStyle: CalendarStyle(
        todayDecoration: BoxDecoration(
          color: Colors.blue.withOpacity(0.3),
          shape: BoxShape.circle,
        ),
        selectedDecoration: const BoxDecoration(
          color: Colors.blue,
          shape: BoxShape.circle,
        ),
        markerDecoration: const BoxDecoration(
          color: Colors.orange,
          shape: BoxShape.circle,
        ),
        markersMaxCount: 3,
      ),
      headerStyle: HeaderStyle(
        formatButtonVisible: true,
        titleCentered: true,
        formatButtonDecoration: BoxDecoration(
          color: Colors.blue,
          borderRadius: BorderRadius.circular(8),
        ),
        formatButtonTextStyle: const TextStyle(color: Colors.white),
      ),
      onDaySelected: (selectedDay, focusedDay) {
        setState(() {
          _selectedDay = selectedDay;
          _focusedDay = focusedDay;
          // 日付を選択したらweek表示に切り替え
          _calendarFormat = CalendarFormat.week;
        });
      },
      onFormatChanged: (format) {
        setState(() {
          _calendarFormat = format;
        });
      },
      onPageChanged: (focusedDay) {
        _focusedDay = focusedDay;
      },
      eventLoader: (day) {
        return _getEventsForDay(day, schedules);
      },
    );
  }

  /// 指定日のイベントを取得
  List<Schedule> _getEventsForDay(DateTime day, List<Schedule> schedules) {
    final targetDate = DateTime(day.year, day.month, day.day);
    return schedules.where((schedule) {
      // 完了履歴をチェック
      final isCompleted = schedule.completionHistory.any((completedDate) {
        final completed = DateTime(
          completedDate.year,
          completedDate.month,
          completedDate.day,
        );
        return isSameDay(completed, targetDate);
      });

      // 次回予定日をチェック
      if (schedule.nextScheduledDate != null) {
        final scheduleDate = DateTime(
          schedule.nextScheduledDate!.year,
          schedule.nextScheduledDate!.month,
          schedule.nextScheduledDate!.day,
        );
        return isSameDay(scheduleDate, targetDate) || isCompleted;
      }

      // 次回予定日がない場合は完了履歴のみでチェック
      return isCompleted;
    }).toList();
  }

  /// 選択日の予定リスト
  Widget _buildScheduleList(List<Schedule> schedules) {
    // 選択日の完了履歴を取得
    final completionHistoriesAsync = ref.watch(completionHistoriesByDateProvider(_selectedDay));

    return completionHistoriesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(
        child: Text('完了履歴の読み込みに失敗しました: $error'),
      ),
      data: (completionHistories) {
        // 選択日に完了したスケジュールIDの一覧
        final completedScheduleIds = completionHistories.map((h) => h.scheduleId).toSet();

        // 選択日の予定（完了済みを除外）
        final selectedDaySchedules = schedules.where((schedule) {
          if (schedule.nextScheduledDate == null) return false;

          final scheduleDate = DateTime(
            schedule.nextScheduledDate!.year,
            schedule.nextScheduledDate!.month,
            schedule.nextScheduledDate!.day,
          );

          // 選択日と一致し、かつ完了済みではない
          return isSameDay(scheduleDate, _selectedDay) && !completedScheduleIds.contains(schedule.id);
        }).toList();

        final dateFormat = DateFormat('M月d日(E)', 'ja_JP');

        return Container(
          color: Theme.of(context).colorScheme.surface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  dateFormat.format(_selectedDay),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (selectedDaySchedules.isEmpty && completionHistories.isEmpty)
                const Expanded(
                  child: Center(
                    child: Text(
                      '予定がありません',
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 16,
                      ),
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      // 予定されているタスク
                      if (selectedDaySchedules.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Text(
                            '予定',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                        ),
                        ...selectedDaySchedules.map((schedule) => _buildScheduleCard(schedule, false)),
                      ],

                      // 完了したタスク
                      if (completionHistories.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Text(
                            '完了済み',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                        ),
                        ...completionHistories.map((history) => _buildCompletionHistoryCard(history)),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// 予定カード
  Widget _buildScheduleCard(Schedule schedule, bool isCompleted) {
    final status = schedule.getStatus();

    // ステータスに応じた左アクセントバーの色を取得
    Color getAccentColor() {
      if (isCompleted) return Colors.green;
      switch (status) {
        case ScheduleStatus.overdue:
          return Colors.red;
        case ScheduleStatus.pending:
          return Colors.blue;
        case ScheduleStatus.completed:
          return Colors.green;
      }
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: isCompleted
            ? null // 完了済みタスクは編集不可
            : () {
                // nextScheduledDateがある場合はクエリパラメータとして渡す
                final uri = Uri(
                  path: '/schedule/edit/${schedule.id}',
                  queryParameters: schedule.nextScheduledDate != null
                      ? {'initialDate': schedule.nextScheduledDate!.toIso8601String()}
                      : null,
                );
                context.push(uri.toString());
              },
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 左アクセントバー
              Container(
                width: 4,
                color: getAccentColor(),
              ),
              // メインコンテンツ
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // グループバッジ（設定されている場合）
                      if (schedule.isGroupSchedule && schedule.groupId != null) ...[
                        const SizedBox(height: 6),
                        Consumer(
                          builder: (context, ref, child) {
                            final groupAsync = ref.watch(groupProvider(schedule.groupId!));
                            return groupAsync.when(
                              data: (group) {
                                if (group == null) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.group, size: 14, color: Colors.blue[700]),
                                        const SizedBox(width: 2),
                                        Text(
                                          'グループ',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.blue[700],
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.group, size: 14, color: Colors.blue[700]),
                                      const SizedBox(width: 2),
                                      Text(
                                        group.name,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.blue[700],
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                              loading: () => Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.group, size: 14, color: Colors.blue[700]),
                                    const SizedBox(width: 2),
                                    Text(
                                      'グループ',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.blue[700],
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              error: (_, __) => Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.group, size: 14, color: Colors.blue[700]),
                                    const SizedBox(width: 2),
                                    Text(
                                      'グループ',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.blue[700],
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                      const SizedBox(height: 8),
                      // タイトルと通知アイコン
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              schedule.title,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                height: 1.3,
                                color: isCompleted ? Colors.grey : null,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (schedule.description.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          schedule.description,
                          style: TextStyle(
                            fontSize: 14,
                            color: isCompleted ? Colors.grey : Colors.grey[700],
                            height: 1.4,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 10),
                      // 繰り返し情報
                      Row(
                        children: [
                          Icon(
                            _getRepeatIcon(schedule.repeatType),
                            size: 18,
                            color: isCompleted
                                ? Colors.grey
                                : (Theme.of(context).brightness == Brightness.dark
                                    ? Colors.grey[300]
                                    : Colors.grey[800]),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            schedule.repeatTypeLabel,
                            style: TextStyle(
                              fontSize: 13,
                              color: isCompleted
                                  ? Colors.grey
                                  : (Theme.of(context).brightness == Brightness.dark
                                      ? Colors.grey[300]
                                      : Colors.grey[800]),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      // 完了ボタン（未完了で完了必須の場合）
                      if (schedule.requiresCompletion && !isCompleted) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              await ref.read(scheduleNotifierProvider.notifier).completeSchedule(schedule);
                              if (context.mounted) {
                                ToastUtils.showSuccess('タスクを完了しました');
                              }
                            },
                            icon: const Icon(Icons.check),
                            label: const Text('完了する'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 完了履歴カード
  Widget _buildCompletionHistoryCard(CompletionHistory history) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: null, // 完了履歴は編集不可
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 左アクセントバー（緑色）
              Container(
                width: 4,
                color: Colors.green,
              ),
              // メインコンテンツ
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // タイトル
                      Text(
                        history.scheduleTitle,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // 完了者情報（グループタスクの場合）
                      if (history.groupId != null && history.completedByMemberName != null) ...[
                        Row(
                          children: [
                            const Icon(Icons.check_circle, size: 16, color: Colors.green),
                            const SizedBox(width: 4),
                            Text(
                              '${history.completedByMemberName}さんが完了',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                      ],
                      // グループバッジ
                      if (history.groupId != null) ...[
                        Consumer(
                          builder: (context, ref, child) {
                            final groupAsync = ref.watch(groupProvider(history.groupId!));
                            return groupAsync.when(
                              data: (group) {
                                if (group == null) return const SizedBox.shrink();
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.group, size: 14, color: Colors.blue[700]),
                                      const SizedBox(width: 2),
                                      Text(
                                        group.name,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.blue[700],
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                              loading: () => const SizedBox.shrink(),
                              error: (_, __) => const SizedBox.shrink(),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getRepeatIcon(RepeatType repeatType) {
    switch (repeatType) {
      case RepeatType.daily:
        return Icons.repeat;
      case RepeatType.weekly:
        return Icons.calendar_view_week;
      case RepeatType.monthly:
        return Icons.calendar_today;
      case RepeatType.custom:
        return Icons.event_repeat;
      case RepeatType.none:
        return Icons.event;
    }
  }
}
