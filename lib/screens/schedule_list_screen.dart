import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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

  String _getActiveTabTitle() {
    switch (_tabController.index) {
      case 0:
        return '今日のタスク';
      case 1:
        return '予定一覧';
      case 2:
        return 'カレンダー';
      default:
        return 'お知らせ君';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Align(
          alignment: Alignment.centerLeft,
          child: Text(_getActiveTabTitle()),
        ),
        titleSpacing: 16,
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: '今日のタスク', icon: Icon(Icons.today, size: 24)),
            Tab(text: '予定一覧', icon: Icon(Icons.list, size: 24)),
            Tab(text: 'カレンダー', icon: Icon(Icons.calendar_month, size: 24)),
          ],
        ),
        actions: [
          // 全てのタブで予定追加ボタンを表示
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: TextButton.icon(
                icon: const Icon(Icons.add, size: 20, color: Colors.white),
                label: const Text(
                  '追加',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () {
                  context.push('/schedule/create');
                },
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            iconSize: 22,
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
                            showDateInfo: false,
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
                            showDateInfo: false,
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
                            showDateInfo: false,
                            isCompleted: true,
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
                      showDateInfo: true,
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
  final bool showDateInfo;
  final bool isCompleted;

  const _TaskCard({
    required this.schedule,
    required this.showCompleteButton,
    this.showDateInfo = true,
    this.isCompleted = false,
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

    // 3秒経過したらリセット
    if (_isFirstTapped && _firstTapTime != null) {
      final elapsed = DateTime.now().difference(_firstTapTime!);
      if (elapsed.inSeconds > 3) {
        _isFirstTapped = false;
        _firstTapTime = null;
      }
    }

    // ステータスに応じた左アクセントバーの色を取得
    Color getAccentColor() {
      // 完了済みの場合は緑
      if (widget.isCompleted) {
        return Colors.green;
      }

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
        onTap: widget.isCompleted
            ? null
            : () {
                // nextScheduledDateがある場合はクエリパラメータとして渡す
                final uri = Uri(
                  path: '/schedule/edit/${widget.schedule.id}',
                  queryParameters: widget.schedule.nextScheduledDate != null
                      ? {'initialDate': widget.schedule.nextScheduledDate!.toIso8601String()}
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
                      // 上部: ステータスバッジのみ
                      Row(
                        children: [
                          // ステータスバッジ
                          _StatusBadge(status: status, schedule: widget.schedule),
                        ],
                      ),
                      // グループバッジ（設定されている場合）
                      if (widget.schedule.isGroupSchedule && widget.schedule.groupId != null) ...[
                        const SizedBox(height: 6),
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
                      ],
                      const SizedBox(height: 8),
                      // タイトルと通知アイコン
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.schedule.title,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                      // グループタスク完了者表示
                      if (widget.isCompleted &&
                          widget.schedule.isGroupSchedule &&
                          widget.schedule.completedByMemberId != null) ...[
                        const SizedBox(height: 6),
                        Consumer(
                          builder: (context, ref, child) {
                            return FutureBuilder<String>(
                              future: _getCompletedByMemberName(ref, widget.schedule.completedByMemberId!),
                              builder: (context, snapshot) {
                                final memberName = snapshot.data ?? '読み込み中...';
                                return Row(
                                  children: [
                                    const Icon(
                                      Icons.person,
                                      size: 14,
                                      color: Colors.green,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${memberName}さんが完了',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.green,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                        ),
                      ],
                      if (widget.schedule.description.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          widget.schedule.description,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[700],
                            height: 1.4,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      // 日付と繰り返し情報
                      if (widget.showDateInfo) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Icon(Icons.event,
                                size: 18,
                                color: Theme.of(context).brightness == Brightness.dark
                                    ? Colors.grey[300]
                                    : Colors.grey[800]),
                            const SizedBox(width: 6),
                            Text(
                              widget.schedule.nextScheduledDate != null
                                  ? dateFormat.format(widget.schedule.nextScheduledDate!)
                                  : '未設定',
                              style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(context).brightness == Brightness.dark
                                    ? Colors.grey[300]
                                    : Colors.grey[800],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Icon(_getRepeatIcon(widget.schedule.repeatType),
                                size: 18,
                                color: Theme.of(context).brightness == Brightness.dark
                                    ? Colors.grey[300]
                                    : Colors.grey[800]),
                            const SizedBox(width: 6),
                            Text(
                              widget.schedule.repeatTypeLabel,
                              style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(context).brightness == Brightness.dark
                                    ? Colors.grey[300]
                                    : Colors.grey[800],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (widget.showCompleteButton) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () async {
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

  /// 完了者のメンバー名を取得
  Future<String> _getCompletedByMemberName(WidgetRef ref, String memberId) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(memberId).get();
      if (doc.exists) {
        final data = doc.data();
        return data?['displayName'] as String? ?? 'メンバー';
      }
      return 'メンバー';
    } catch (e) {
      return 'メンバー';
    }
  }
}

/// ステータスバッジ
class _StatusBadge extends StatelessWidget {
  final ScheduleStatus status;
  final Schedule schedule;

  const _StatusBadge({
    required this.status,
    required this.schedule,
  });

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
        // 遅延日数を計算
        if (schedule.nextScheduledDate != null) {
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final scheduledDate = DateTime(
            schedule.nextScheduledDate!.year,
            schedule.nextScheduledDate!.month,
            schedule.nextScheduledDate!.day,
          );
          final delayDays = today.difference(scheduledDate).inDays;
          label = '${delayDays}日遅延';
        } else {
          label = '遅延';
        }
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
