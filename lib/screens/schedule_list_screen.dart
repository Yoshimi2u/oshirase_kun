import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/schedule.dart';
import '../providers/schedule_provider.dart';
import '../providers/group_provider.dart';
import 'package:go_router/go_router.dart';
import 'calendar_screen.dart';

/// 予定一覧画面（タブ表示）
class ScheduleListScreen extends ConsumerStatefulWidget {
  const ScheduleListScreen({super.key});

  @override
  ConsumerState<ScheduleListScreen> createState() => _ScheduleListScreenState();
}

class _ScheduleListScreenState extends ConsumerState<ScheduleListScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('お知らせ君'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: '今日のタスク', icon: Icon(Icons.today)),
            Tab(text: '予定一覧', icon: Icon(Icons.list)),
            Tab(text: 'カレンダー', icon: Icon(Icons.calendar_month)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              context.push('/settings');
            },
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _TodayTasksTab(),
          _AllSchedulesTab(),
          CalendarScreen(),
        ],
      ),
      floatingActionButton: _tabController.index != 2
          ? FloatingActionButton.extended(
              onPressed: () {
                context.push('/schedule/create');
              },
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text(
                '予定を追加',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            )
          : null,
    );
  }
}

/// 今日のタスクタブ
class _TodayTasksTab extends ConsumerWidget {
  const _TodayTasksTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todayAsync = ref.watch(todaySchedulesStreamProvider);
    final overdueAsync = ref.watch(overdueSchedulesStreamProvider);
    final completedAsync = ref.watch(todayCompletedSchedulesStreamProvider);

    return todayAsync.when(
      data: (todayTasks) {
        return overdueAsync.when(
          data: (overdueTasks) {
            return completedAsync.when(
              data: (completedTasks) {
                final allTasks = [...overdueTasks, ...todayTasks, ...completedTasks];

                if (allTasks.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 80,
                          color: Colors.green[300],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '今日のタスクはありません',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView(
                  padding: const EdgeInsets.all(8),
                  children: [
                    if (overdueTasks.isNotEmpty) ...[
                      _SectionHeader(
                        title: '遅延中 (${overdueTasks.length}件)',
                        color: Colors.red,
                      ),
                      ...overdueTasks.map((schedule) => _TaskCard(
                            schedule: schedule,
                            showCompleteButton: true,
                          )),
                      const SizedBox(height: 16),
                    ],
                    if (todayTasks.isNotEmpty) ...[
                      _SectionHeader(
                        title: '今日のタスク (${todayTasks.length}件)',
                        color: Colors.blue,
                      ),
                      ...todayTasks.map((schedule) => _TaskCard(
                            schedule: schedule,
                            showCompleteButton: true,
                          )),
                      const SizedBox(height: 16),
                    ],
                    if (completedTasks.isNotEmpty) ...[
                      _SectionHeader(
                        title: '完了済み (${completedTasks.length}件)',
                        color: Colors.green,
                      ),
                      ...completedTasks.map((schedule) => _TaskCard(
                            schedule: schedule,
                            showCompleteButton: false,
                          )),
                    ],
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => _ErrorView(error: e),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => _ErrorView(error: e),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => _ErrorView(error: e),
    );
  }
}

/// 全予定タブ
class _AllSchedulesTab extends ConsumerWidget {
  const _AllSchedulesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final upcomingAsync = ref.watch(upcomingSchedulesStreamProvider);

    return upcomingAsync.when(
      data: (schedules) {
        if (schedules.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.calendar_today,
                  size: 80,
                  color: Colors.grey[300],
                ),
                const SizedBox(height: 16),
                Text(
                  '予定がありません',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '右下のボタンから予定を追加してください',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          );
        }

        // 日付ごとにグループ化
        final Map<String, List<Schedule>> groupedSchedules = {};
        for (final schedule in schedules) {
          if (schedule.nextScheduledDate != null) {
            final date = schedule.nextScheduledDate!;
            final key = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
            groupedSchedules.putIfAbsent(key, () => []).add(schedule);
          }
        }

        final sortedKeys = groupedSchedules.keys.toList()..sort();

        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: sortedKeys.length,
          itemBuilder: (context, index) {
            final dateKey = sortedKeys[index];
            final schedulesForDate = groupedSchedules[dateKey]!;
            final firstSchedule = schedulesForDate.first;
            final date = firstSchedule.nextScheduledDate!;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DateSectionHeader(date: date, count: schedulesForDate.length),
                ...schedulesForDate.map((schedule) => _TaskCard(
                      schedule: schedule,
                      showCompleteButton: false,
                    )),
                const SizedBox(height: 8),
              ],
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => _ErrorView(error: e),
    );
  }
}

/// 日付セクションヘッダー
class _DateSectionHeader extends StatelessWidget {
  final DateTime date;
  final int count;

  const _DateSectionHeader({
    required this.date,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('M月d日(E)', 'ja_JP');
    final today = DateTime.now();
    final tomorrow = today.add(const Duration(days: 1));

    String label = dateFormat.format(date);
    Color labelColor = Colors.blue;

    // 今日・明日の場合は特別な表示
    if (date.year == today.year && date.month == today.month && date.day == today.day) {
      label = '今日 ${dateFormat.format(date)}';
      labelColor = Colors.orange;
    } else if (date.year == tomorrow.year && date.month == tomorrow.month && date.day == tomorrow.day) {
      label = '明日 ${dateFormat.format(date)}';
      labelColor = Colors.green;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 24,
            decoration: BoxDecoration(
              color: labelColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: labelColor,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: labelColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count件',
              style: TextStyle(
                fontSize: 12,
                color: labelColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// セクションヘッダー
class _SectionHeader extends StatelessWidget {
  final String title;
  final Color color;

  const _SectionHeader({
    required this.title,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 20,
            color: color,
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// タスクカード
class _TaskCard extends ConsumerStatefulWidget {
  final Schedule schedule;
  final bool showCompleteButton;

  const _TaskCard({
    required this.schedule,
    required this.showCompleteButton,
  });

  @override
  ConsumerState<_TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends ConsumerState<_TaskCard> {
  bool _isFirstTapped = false;
  DateTime? _firstTapTime;

  @override
  Widget build(BuildContext context) {
    final status = widget.schedule.getStatus();
    final dateFormat = DateFormat('yyyy年MM月dd日(E)', 'ja_JP');
    final isInactive = !widget.schedule.isActive;

    // 3秒経過したらリセット
    if (_isFirstTapped && _firstTapTime != null) {
      final elapsed = DateTime.now().difference(_firstTapTime!);
      if (elapsed.inSeconds > 3) {
        _isFirstTapped = false;
        _firstTapTime = null;
      }
    }

    return Opacity(
      opacity: isInactive ? 0.5 : 1.0,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        elevation: 2,
        color: isInactive ? Colors.grey[100] : null,
        child: InkWell(
          onTap: () {
            context.push('/schedule/edit/${widget.schedule.id}');
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // ステータスバッジ
                    _StatusBadge(status: status),
                    const SizedBox(width: 8),
                    // グループアイコン
                    if (widget.schedule.isGroupSchedule && widget.schedule.groupId != null) ...[
                      Consumer(
                        builder: (context, ref, child) {
                          final groupAsync = ref.watch(groupProvider(widget.schedule.groupId!));
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
                      const SizedBox(width: 8),
                    ],
                    // タイトル
                    Expanded(
                      child: Text(
                        widget.schedule.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    // 通知アイコン（有効/無効切り替え）
                    InkWell(
                      onTap: () {
                        ref
                            .read(scheduleNotifierProvider.notifier)
                            .toggleActive(widget.schedule.id, !widget.schedule.isActive);
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          widget.schedule.isActive ? Icons.notifications : Icons.notifications_off,
                          size: 20,
                          color: widget.schedule.isActive ? Colors.blue[700] : Colors.grey[400],
                        ),
                      ),
                    ),
                  ],
                ),
                if (widget.schedule.description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    widget.schedule.description,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.event, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      widget.schedule.nextScheduledDate != null
                          ? dateFormat.format(widget.schedule.nextScheduledDate!)
                          : '未設定',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Icon(_getRepeatIcon(widget.schedule.repeatType), size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      widget.schedule.repeatTypeLabel,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
                if (widget.showCompleteButton) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: isInactive
                          ? null
                          : () async {
                              if (!_isFirstTapped) {
                                // 1回目のタップ
                                setState(() {
                                  _isFirstTapped = true;
                                  _firstTapTime = DateTime.now();
                                });

                                // 3秒後に自動でリセット
                                Future.delayed(const Duration(seconds: 3), () {
                                  if (mounted) {
                                    setState(() {
                                      _isFirstTapped = false;
                                      _firstTapTime = null;
                                    });
                                  }
                                });
                              } else {
                                // 2回目のタップ - 完了処理
                                await ref.read(scheduleNotifierProvider.notifier).completeSchedule(widget.schedule);
                                setState(() {
                                  _isFirstTapped = false;
                                  _firstTapTime = null;
                                });
                              }
                            },
                      icon: const Icon(Icons.check),
                      label: Text(_isFirstTapped ? 'もう一度タップで完了' : '2回タップで完了'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isFirstTapped ? Colors.orange : Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ],
            ), // Column
          ), // Padding
        ), // InkWell
      ), // Card
    ); // Opacity
  }

  IconData _getRepeatIcon(RepeatType type) {
    switch (type) {
      case RepeatType.none:
        return Icons.looks_one;
      case RepeatType.daily:
        return Icons.repeat;
      case RepeatType.weekly:
        return Icons.calendar_view_week;
      case RepeatType.monthly:
        return Icons.calendar_month;
      case RepeatType.custom:
        return Icons.sync;
    }
  }
}

/// ステータスバッジ
class _StatusBadge extends StatelessWidget {
  final ScheduleStatus status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;

    switch (status) {
      case ScheduleStatus.pending:
        // 予定の場合は表示しない
        return const SizedBox.shrink();
      case ScheduleStatus.overdue:
        color = Colors.red;
        label = '遅延';
        break;
      case ScheduleStatus.completed:
        color = Colors.green;
        label = '完了';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}

/// エラー表示
class _ErrorView extends StatelessWidget {
  final Object error;

  const _ErrorView({required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            size: 60,
            color: Colors.red,
          ),
          const SizedBox(height: 16),
          Text(
            'エラーが発生しました',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            error.toString(),
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
