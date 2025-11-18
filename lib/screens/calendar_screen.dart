import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import '../models/schedule.dart';
import '../providers/schedule_provider.dart';
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
        child: Text('エラーが発生しました: $error'),
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
      if (schedule.nextScheduledDate == null) return false;
      final scheduleDate = DateTime(
        schedule.nextScheduledDate!.year,
        schedule.nextScheduledDate!.month,
        schedule.nextScheduledDate!.day,
      );

      // 完了履歴もチェック
      final isCompleted = schedule.completionHistory.any((completedDate) {
        final completed = DateTime(
          completedDate.year,
          completedDate.month,
          completedDate.day,
        );
        return isSameDay(completed, targetDate);
      });

      return isSameDay(scheduleDate, targetDate) || isCompleted;
    }).toList();
  }

  /// 選択日の予定リスト
  Widget _buildScheduleList(List<Schedule> schedules) {
    // 選択日に完了した予定のID一覧
    final completedScheduleIds = schedules
        .where((schedule) {
          return schedule.completionHistory.any((completedDate) {
            final completed = DateTime(
              completedDate.year,
              completedDate.month,
              completedDate.day,
            );
            return isSameDay(completed, _selectedDay);
          });
        })
        .map((s) => s.id)
        .toSet();

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

    // 選択日に完了した予定
    final completedOnSelectedDay = schedules.where((schedule) {
      return completedScheduleIds.contains(schedule.id);
    }).toList();

    final dateFormat = DateFormat('M月d日(E)', 'ja_JP');

    return Container(
      color: Colors.grey[50],
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
          if (selectedDaySchedules.isEmpty && completedOnSelectedDay.isEmpty)
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
                  if (completedOnSelectedDay.isNotEmpty) ...[
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
                    ...completedOnSelectedDay.map((schedule) => _buildScheduleCard(schedule, true)),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 予定カード
  Widget _buildScheduleCard(Schedule schedule, bool isCompleted) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      child: ListTile(
        leading: Icon(
          isCompleted ? Icons.check_circle : Icons.circle_outlined,
          color: isCompleted ? Colors.green : Colors.blue,
        ),
        title: Row(
          children: [
            // グループアイコンとグループ名
            if (schedule.isGroupSchedule && schedule.groupId != null) ...[
              Consumer(
                builder: (context, ref, child) {
                  final groupAsync = ref.watch(groupProvider(schedule.groupId!));
                  return groupAsync.when(
                    data: (group) {
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.group, size: 16, color: Colors.blue[700]),
                          const SizedBox(width: 4),
                          Text(
                            group?.name ?? 'グループ',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue[700],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                      );
                    },
                    loading: () => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.group, size: 16, color: Colors.blue[700]),
                        const SizedBox(width: 4),
                      ],
                    ),
                    error: (_, __) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.group, size: 16, color: Colors.blue[700]),
                        const SizedBox(width: 4),
                      ],
                    ),
                  );
                },
              ),
            ],
            Expanded(
              child: Text(
                schedule.title,
                style: TextStyle(
                  color: isCompleted ? Colors.grey : Colors.black,
                ),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (schedule.description.isNotEmpty)
              Text(
                schedule.description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isCompleted ? Colors.grey : Colors.black54,
                ),
              ),
            const SizedBox(height: 4),
            Text(
              schedule.repeatTypeLabel,
              style: TextStyle(
                fontSize: 12,
                color: isCompleted ? Colors.grey : Colors.blue,
              ),
            ),
          ],
        ),
        trailing: schedule.requiresCompletion && !isCompleted
            ? IconButton(
                icon: const Icon(Icons.check),
                color: Colors.green,
                onPressed: () async {
                  await ref.read(scheduleNotifierProvider.notifier).completeSchedule(schedule);
                  if (mounted) {
                    ToastUtils.showSuccess('タスクを完了しました');
                  }
                },
              )
            : null,
      ),
    );
  }
}
