import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/schedule_instance.dart';
import '../providers/task_provider.dart'
    show
        todayTasksStreamProvider,
        upcomingTasksProvider,
        extendedUpcomingTasksProvider,
        tasksByDateRangeProvider,
        taskRepositoryProvider,
        currentUserIdProvider,
        DateRangeParams;
import '../providers/schedule_template_provider.dart' as template_provider;
import '../providers/user_profile_provider.dart';
import '../providers/group_provider.dart';
import '../constants/app_spacing.dart';
import '../utils/toast_utils.dart';
import '../widgets/inline_banner_ad.dart';
import '../services/ad_manager.dart';
import 'package:go_router/go_router.dart';
import 'calendar_screen.dart';

/// 予定一覧画面（タブ表示）- 新モデル対応
class ScheduleListScreen extends ConsumerStatefulWidget {
  const ScheduleListScreen({super.key});

  @override
  ConsumerState<ScheduleListScreen> createState() => _ScheduleListScreenState();
}

class _ScheduleListScreenState extends ConsumerState<ScheduleListScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isRefreshing = false;
  bool _refreshCompleted = false;
  Timer? _completedTimer;
  DateTime? _lastRefreshTime;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _completedTimer?.cancel();
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  /// 更新ボタンが押せるかチェック（30秒制限）
  bool _canRefresh() {
    if (_lastRefreshTime == null) return true;
    final now = DateTime.now();
    final difference = now.difference(_lastRefreshTime!);
    return difference.inSeconds >= 30;
  }

  /// 次に更新できるまでの残り秒数
  int _getRemainingSeconds() {
    if (_lastRefreshTime == null) return 0;
    final now = DateTime.now();
    final difference = now.difference(_lastRefreshTime!);
    final remaining = 30 - difference.inSeconds;
    return remaining > 0 ? remaining : 0;
  }

  /// 更新処理
  Future<void> _handleRefresh() async {
    // 30秒制限中の場合はトーストで通知
    if (!_canRefresh()) {
      final remaining = _getRemainingSeconds();
      ToastUtils.showInfo('更新は$remaining秒後に可能です');
      return;
    }

    // 更新中の場合は何もしない
    if (_isRefreshing) return;

    setState(() {
      _isRefreshing = true;
      _refreshCompleted = false;
      _lastRefreshTime = DateTime.now();
    });

    try {
      // 予定一覧タブとカレンダータブの両方を更新
      if (_tabController.index == 1) {
        // 予定一覧タブから更新
        ref.invalidate(upcomingTasksProvider);
        ref.invalidate(tasksByDateRangeProvider);
        await ref.read(upcomingTasksProvider.future);
      } else if (_tabController.index == 2) {
        // カレンダータブから更新
        ref.invalidate(upcomingTasksProvider);
        ref.invalidate(tasksByDateRangeProvider);
        // 現在の月（当月のみ）のデータを取得
        final now = DateTime.now();
        final startDate = DateTime(now.year, now.month, 1);
        final endDate = DateTime(now.year, now.month + 1, 0);
        await ref.read(tasksByDateRangeProvider(
          DateRangeParams(startDate: startDate, endDate: endDate),
        ).future);
      }

      // 更新完了表示
      if (mounted) {
        setState(() {
          _isRefreshing = false;
          _refreshCompleted = true;
        });

        // 1秒後にチェックマークを消す
        _completedTimer?.cancel();
        _completedTimer = Timer(const Duration(seconds: 1), () {
          if (mounted) {
            setState(() {
              _refreshCompleted = false;
            });
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
          _refreshCompleted = false;
        });
      }
    }
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
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      body: Stack(
        children: [
          // ステータスバー領域の背景色
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: MediaQuery.of(context).padding.top, // SafeAreaの高さ
              color: primaryColor,
            ),
          ),
          // メインコンテンツ
          SafeArea(
            child: NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) {
                return [
                  SliverAppBar(
                    title: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(_getActiveTabTitle()),
                    ),
                    titleSpacing: 16,
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    floating: true, // 上スクロールで即座に表示
                    snap: true, // 表示/非表示が滑らかに
                    pinned: false, // 完全に隠れる
                    forceElevated: innerBoxIsScrolled,
                    actions: [
                      // 予定一覧タブまたはカレンダータブの場合は更新ボタンを表示
                      if (_tabController.index == 1 || _tabController.index == 2)
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            IconButton(
                              icon: _refreshCompleted
                                  ? const Icon(Icons.check, color: Colors.white)
                                  : _isRefreshing
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                          ),
                                        )
                                      : const Icon(Icons.refresh),
                              iconSize: 22,
                              tooltip: '更新',
                              onPressed: _isRefreshing || _refreshCompleted ? null : _handleRefresh,
                            ),
                          ],
                        ),
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
                    bottom: TabBar(
                      controller: _tabController,
                      indicatorColor: Colors.white,
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.white70,
                      tabs: const [
                        Tab(text: '今日のタスク', icon: Icon(Icons.today, size: 24)),
                        Tab(text: '予定', icon: Icon(Icons.list, size: 24)),
                        Tab(text: 'カレンダー', icon: Icon(Icons.calendar_month, size: 24)),
                      ],
                    ),
                  ),
                ];
              },
              body: TabBarView(
                controller: _tabController,
                children: const [
                  _TodayTasksTab(),
                  _AllSchedulesTab(),
                  CalendarScreen(),
                ],
              ),
            ),
          ),
          // グローバルローディング表示
          if (_isRefreshing)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: const Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text(
                          '更新中...',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 今日のタスクタブ
class _TodayTasksTab extends ConsumerStatefulWidget {
  const _TodayTasksTab();

  @override
  ConsumerState<_TodayTasksTab> createState() => _TodayTasksTabState();
}

class _TodayTasksTabState extends ConsumerState<_TodayTasksTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixinのために必要
    final todayAsync = ref.watch(todayTasksStreamProvider);

    return todayAsync.when(
      data: (allTasks) {
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

        // タスクをステータスごとに分類
        final overdueTasks = allTasks.where((task) => task.getStatus() == TaskStatus.overdue).toList();
        final pendingTasks = allTasks.where((task) => task.getStatus() == TaskStatus.pending).toList();
        final completedTasks = allTasks.where((task) => task.getStatus() == TaskStatus.completed).toList();

        return ListView(
          padding: const EdgeInsets.all(8),
          children: [
            if (overdueTasks.isNotEmpty) ...[
              _SectionHeader(
                title: '遅延中 (${overdueTasks.length}件)',
                color: Colors.red,
              ),
              ...overdueTasks.map((task) => _TaskCard(
                    task: task,
                    showCompleteButton: true,
                    showDateInfo: false,
                  )),
              const SizedBox(height: 16),
            ],
            if (pendingTasks.isNotEmpty) ...[
              _SectionHeader(
                title: '未完了 (${pendingTasks.length}件)',
                color: Colors.blue,
              ),
              ...pendingTasks.map((task) => _TaskCard(
                    task: task,
                    showCompleteButton: true,
                    showDateInfo: false,
                  )),
              const SizedBox(height: 16),
            ],
            // インラインバナー広告（未完了と完了の間）
            InlineBannerAd(adUnitId: AdManager.inlineBannerAdUnitId),
            if (completedTasks.isNotEmpty) ...[
              _SectionHeader(
                title: '完了済み (${completedTasks.length}件)',
                color: Colors.green,
              ),
              ...completedTasks.map((task) => _TaskCard(
                    task: task,
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
  }
}

/// 全予定タブ（明日以降のタスクを日付別に表示）
class _AllSchedulesTab extends ConsumerStatefulWidget {
  const _AllSchedulesTab();

  @override
  ConsumerState<_AllSchedulesTab> createState() => _AllSchedulesTabState();
}

class _AllSchedulesTabState extends ConsumerState<_AllSchedulesTab> with AutomaticKeepAliveClientMixin {
  bool _showExtended = false;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixinのために必要
    final tasksAsync = _showExtended ? ref.watch(extendedUpcomingTasksProvider) : ref.watch(upcomingTasksProvider);

    return tasksAsync.when(
      data: (tasks) {
        if (tasks.isEmpty) {
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
                  '予定を追加してください',
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
        final Map<String, List<Task>> groupedTasks = {};
        for (final task in tasks) {
          final date = task.scheduledDate;
          final key = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
          groupedTasks.putIfAbsent(key, () => []).add(task);
        }

        final sortedKeys = groupedTasks.keys.toList()..sort();

        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: sortedKeys.length + 2, // +1 for ad, +1 for "Load More" button
          itemBuilder: (context, index) {
            // 3日目の後（index=3）にインライン広告を表示
            if (index == 3 && sortedKeys.length > 3) {
              return InlineBannerAd(adUnitId: AdManager.scheduleInlineBannerAdUnitId);
            }

            // 広告がある場合はindexを調整
            final adjustedIndex = index > 3 && sortedKeys.length > 3 ? index - 1 : index;

            // 最後のアイテムは「もっと見る」ボタン
            if (adjustedIndex == sortedKeys.length) {
              if (_showExtended) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                child: OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _showExtended = true;
                    });
                  },
                  icon: const Icon(Icons.expand_more),
                  label: const Text('もっと見る（翌月末まで）'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              );
            }

            final dateKey = sortedKeys[adjustedIndex];
            final tasksForDate = groupedTasks[dateKey]!;
            final firstTask = tasksForDate.first;
            final date = firstTask.scheduledDate;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DateSectionHeader(date: date, count: tasksForDate.length),
                ...tasksForDate.map((task) => _TaskCard(
                      task: task,
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
  final Task task;
  final bool showCompleteButton;
  final bool showDateInfo;
  final bool isCompleted;

  const _TaskCard({
    required this.task,
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
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.task.getStatus();

    // 3秒経過したらリセット
    if (_isFirstTapped && _firstTapTime != null) {
      final elapsed = DateTime.now().difference(_firstTapTime!);
      if (elapsed.inSeconds > 3) {
        _isFirstTapped = false;
        _firstTapTime = null;
      }
    }

    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.cardMarginHorizontal,
        vertical: AppSpacing.cardMarginVertical,
      ),
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.isCompleted
            ? null
            : () async {
                // テンプレートIDからテンプレートを取得して編集画面へ（taskIdも渡す）
                final templateRepository = ref.read(template_provider.scheduleTemplateRepositoryProvider);
                final template = await templateRepository.getTemplate(widget.task.templateId);
                if (template != null && context.mounted) {
                  context.push('/schedule/edit/${template.id}?taskId=${widget.task.id}');
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
                      // 上部: ステータスバッジとグループバッジ
                      Row(
                        children: [
                          // ステータスバッジ
                          _StatusBadge(status: status, task: widget.task),
                          // グループバッジ
                          if (widget.task.isGroupSchedule && widget.task.groupId != null) ...[
                            if (status == TaskStatus.overdue) const SizedBox(width: AppSpacing.medium),
                            _GroupBadge(groupId: widget.task.groupId!),
                          ],
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      // タイトルと通知アイコン
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.task.title,
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
                          widget.task.isGroupSchedule &&
                          widget.task.completedByMemberId != null) ...[
                        const SizedBox(height: 6),
                        Consumer(
                          builder: (context, ref, child) {
                            final currentUserId = ref.watch(currentUserIdProvider);

                            // 自分が完了した場合
                            if (currentUserId != null && currentUserId == widget.task.completedByMemberId) {
                              return const Row(
                                children: [
                                  Icon(
                                    Icons.check_circle,
                                    size: 14,
                                    color: Colors.green,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'あなたが完了',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.green,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              );
                            }

                            // 他のメンバーが完了した場合
                            return FutureBuilder<String>(
                              future: _getCompletedByMemberName(ref, widget.task.completedByMemberId!),
                              builder: (context, snapshot) {
                                final memberName = snapshot.data ?? '読み込み中...';
                                return Row(
                                  children: [
                                    const Icon(
                                      Icons.person,
                                      size: 14,
                                      color: Colors.green,
                                    ),
                                    const SizedBox(width: AppSpacing.xs),
                                    Text(
                                      '$memberNameさんが完了',
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
                      if (widget.task.description.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.small),
                        Text(
                          widget.task.description,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[700],
                            height: 1.4,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      // 繰り返し情報を表示
                      if (widget.showDateInfo && widget.task.hasRepeat) ...[
                        const SizedBox(height: AppSpacing.large),
                        Row(
                          children: [
                            Icon(Icons.repeat,
                                size: 18,
                                color: Theme.of(context).brightness == Brightness.dark
                                    ? Colors.grey[400]
                                    : Colors.grey[600]),
                            const SizedBox(width: AppSpacing.small),
                            Text(
                              widget.task.repeatDisplayText,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).brightness == Brightness.dark
                                    ? Colors.grey[400]
                                    : Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (widget.showCompleteButton) ...[
                        const SizedBox(height: AppSpacing.large),
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

                                // 既存のタイマーをキャンセル
                                _resetTimer?.cancel();

                                // 3秒後に自動でリセット
                                _resetTimer = Timer(const Duration(seconds: 3), () {
                                  if (mounted) {
                                    setState(() {
                                      _isFirstTapped = false;
                                      _firstTapTime = null;
                                    });
                                  }
                                });
                              } else {
                                // 2回目のタップ - 完了処理
                                _resetTimer?.cancel();
                                final taskRepository = ref.read(taskRepositoryProvider);
                                await taskRepository.completeTask(widget.task.id);
                                if (mounted) {
                                  setState(() {
                                    _isFirstTapped = false;
                                    _firstTapTime = null;
                                  });
                                }
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

  /// 完了者のメンバー名を取得
  Future<String> _getCompletedByMemberName(WidgetRef ref, String memberId) async {
    try {
      final repository = ref.read(userProfileRepositoryProvider);
      final userProfile = await repository.getUserProfile(memberId);
      return userProfile?.displayName ?? 'メンバー';
    } catch (e) {
      return 'メンバー';
    }
  }
}

/// ステータスバッジ
class _StatusBadge extends StatelessWidget {
  final TaskStatus status;
  final Task task;

  const _StatusBadge({
    required this.status,
    required this.task,
  });

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;

    switch (status) {
      case TaskStatus.pending:
        // 予定の場合は表示しない
        return const SizedBox.shrink();
      case TaskStatus.overdue:
        color = Colors.red;
        // 遅延日数を計算
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final scheduledDate = DateTime(
          task.scheduledDate.year,
          task.scheduledDate.month,
          task.scheduledDate.day,
        );
        final delayDays = today.difference(scheduledDate).inDays;
        label = '$delayDays日遅延';
        break;
      case TaskStatus.completed:
        // 完了チップは表示しない（完了者情報で代替）
        return const SizedBox.shrink();
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
