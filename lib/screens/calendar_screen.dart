import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../models/schedule_instance.dart';
import '../providers/task_provider.dart';
import '../providers/schedule_template_provider.dart' as template_provider;
import '../providers/group_provider.dart';
import '../constants/app_spacing.dart';
import '../constants/app_messages.dart';

/// カレンダー画面 - 新モデル対応
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> with AutomaticKeepAliveClientMixin {
  late DateTime _focusedDay;
  late DateTime _selectedDay;
  CalendarFormat _calendarFormat = CalendarFormat.month;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _focusedDay = DateTime.now();
    _selectedDay = DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixinのために必要
    // カレンダーの表示範囲（当月のみ）のタスクを取得
    final startDate = DateTime(_focusedDay.year, _focusedDay.month, 1);
    final endDate = DateTime(_focusedDay.year, _focusedDay.month + 1, 0);

    final tasksAsync = ref.watch(
      tasksByDateRangeProvider(
        DateRangeParams(startDate: startDate, endDate: endDate),
      ),
    );

    return tasksAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red),
            SizedBox(height: AppSpacing.xxl),
            Text(
              AppMessages.errorGeneric,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: AppSpacing.medium),
            Text(
              AppMessages.taskLoadError,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
      data: (tasks) => Column(
        children: [
          _buildCalendar(tasks),
          const Divider(height: 1),
          Expanded(
            child: _buildScheduleList(tasks),
          ),
        ],
      ),
    );
  }

  /// カレンダーウィジェット
  Widget _buildCalendar(List<Task> tasks) {
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
        markersMaxCount: 1, // マーカーは1つのみ（数字表示用）
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
      // カスタムビルダーでタスク数を表示
      calendarBuilders: CalendarBuilders(
        markerBuilder: (context, date, events) {
          if (events.isEmpty) return null;

          return Positioned(
            top: 2,
            right: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${events.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
        },
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
        setState(() {
          _focusedDay = focusedDay;
        });
      },
      eventLoader: (day) {
        return _getEventsForDay(day, tasks);
      },
    );
  }

  /// 指定日のイベントを取得（新モデル対応）
  List<Task> _getEventsForDay(DateTime day, List<Task> tasks) {
    final targetDate = DateTime(day.year, day.month, day.day);
    return tasks.where((task) {
      final taskDate = DateTime(
        task.scheduledDate.year,
        task.scheduledDate.month,
        task.scheduledDate.day,
      );
      return isSameDay(taskDate, targetDate);
    }).toList();
  }

  /// 選択日のタスクリスト（新モデル対応）
  Widget _buildScheduleList(List<Task> tasks) {
    // 選択日のタスクをフィルタリング
    final selectedDayTasks = tasks.where((task) {
      final taskDate = DateTime(
        task.scheduledDate.year,
        task.scheduledDate.month,
        task.scheduledDate.day,
      );
      return isSameDay(taskDate, _selectedDay);
    }).toList();

    // 完了済みと未完了に分類
    final incompleteTasks = selectedDayTasks.where((task) => task.completedAt == null).toList();
    final completedTasks = selectedDayTasks.where((task) => task.completedAt != null).toList();

    final dateFormat = DateFormat('M月d日(E)', 'ja_JP');

    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Text(
              dateFormat.format(_selectedDay),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (selectedDayTasks.isEmpty)
            const Expanded(
              child: Center(
                child: Text(
                  AppMessages.noTasksToday,
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
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
                children: [
                  // 未完了タスク
                  if (incompleteTasks.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.only(bottom: AppSpacing.medium),
                      child: Text(
                        '未完了',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                    ),
                    ...incompleteTasks.map((task) => _buildTaskCard(task)),
                  ],

                  // 完了済みタスク
                  if (completedTasks.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xxl),
                    const Padding(
                      padding: EdgeInsets.only(bottom: AppSpacing.medium),
                      child: Text(
                        '完了済み',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ),
                    ...completedTasks.map((task) => _buildTaskCard(task)),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// タスクカード（新モデル対応）
  Widget _buildTaskCard(Task task) {
    final isCompleted = task.completedAt != null;

    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.cardMarginHorizontal,
        vertical: AppSpacing.cardMarginVertical,
      ),
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: isCompleted
            ? null // 完了済みタスクは編集不可
            : () async {
                // テンプレートIDからテンプレート情報を取得して編集画面へ（taskIdも渡す）
                final templateRepository = ref.read(template_provider.scheduleTemplateRepositoryProvider);
                final template = await templateRepository.getTemplate(task.templateId);

                if (template != null) {
                  if (!mounted) return;
                  final uri = Uri(
                    path: '/schedule/edit/${task.templateId}',
                    queryParameters: {
                      'initialDate': task.scheduledDate.toIso8601String(),
                      'taskId': task.id,
                    },
                  );
                  context.push(uri.toString());
                }
              },
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // メインコンテンツ
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.cardPadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // グループタスク表示
                      if (task.isGroupSchedule && task.groupId != null) ...[
                        _GroupBadge(groupId: task.groupId!),
                        const SizedBox(height: AppSpacing.medium),
                      ],
                      // タイトル
                      Text(
                        task.title,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          height: 1.3,
                          color: isCompleted ? Colors.grey : null,
                          decoration: isCompleted ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      if (task.description.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.small),
                        Text(
                          task.description,
                          style: TextStyle(
                            fontSize: 14,
                            color: isCompleted ? Colors.grey : Colors.grey[700],
                            height: 1.4,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      // 完了日時表示（完了済みの場合）
                      if (isCompleted && task.completedAt != null) ...[
                        const SizedBox(height: AppSpacing.medium),
                        Row(
                          children: [
                            const Icon(Icons.check_circle, size: 16, color: Colors.green),
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              '完了: ${DateFormat('HH:mm', 'ja_JP').format(task.completedAt!)}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.green,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                      // 繰り返し情報を表示
                      if (task.hasRepeat)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.medium),
                          child: Row(
                            children: [
                              Icon(Icons.repeat,
                                  size: 16,
                                  color: Theme.of(context).brightness == Brightness.dark
                                      ? Colors.grey[400]
                                      : Colors.grey[600]),
                              const SizedBox(width: AppSpacing.xs),
                              Text(
                                task.repeatDisplayText,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).brightness == Brightness.dark
                                      ? Colors.grey[400]
                                      : Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
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
}

/// グループバッジ
class _GroupBadge extends ConsumerWidget {
  final String groupId;

  const _GroupBadge({required this.groupId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupAsync = ref.watch(groupProvider(groupId));

    return groupAsync.when(
      data: (group) {
        if (group == null) {
          return Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.small,
              vertical: AppSpacing.xxs,
            ),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.group, size: 16, color: Colors.blue[700]),
                const SizedBox(width: AppSpacing.xxs),
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
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.small,
            vertical: AppSpacing.xxs,
          ),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.group, size: 16, color: Colors.blue[700]),
              const SizedBox(width: AppSpacing.xxs),
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
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.small,
          vertical: AppSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: Colors.blue.withOpacity(0.1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.group, size: 16, color: Colors.blue[700]),
            const SizedBox(width: AppSpacing.xxs),
            Text(
              '読み込み中...',
              style: TextStyle(
                fontSize: 11,
                color: Colors.blue[700],
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
      error: (error, stack) => Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.small,
          vertical: AppSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: Colors.blue.withOpacity(0.1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.group, size: 16, color: Colors.blue[700]),
            const SizedBox(width: AppSpacing.xxs),
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
  }
}
