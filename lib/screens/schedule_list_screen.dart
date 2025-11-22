import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/task_provider.dart' show upcomingTasksProvider, tomorrowTasksProvider, tasksByDateRangeProvider;
import '../utils/toast_utils.dart';
import '../widgets/global_loading_overlay.dart';
import 'package:go_router/go_router.dart';
import 'calendar_screen.dart';
import 'today_tasks_tab.dart';
import 'all_schedules_tab.dart';

/// 予定一覧画面（タブ表示）- 新モデル対応
class ScheduleListScreen extends ConsumerStatefulWidget {
  const ScheduleListScreen({super.key});

  @override
  ConsumerState<ScheduleListScreen> createState() => _ScheduleListScreenState();
}

class _ScheduleListScreenState extends ConsumerState<ScheduleListScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
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

    // 更新中かチェック
    final loadingState = ref.read(globalLoadingProvider);
    if (loadingState.requested) return;

    _lastRefreshTime = DateTime.now();
    showGlobalLoading(ref, message: 'データを更新しています');

    try {
      // ローディング表示が確実に見えるように少し待機（300ms遅延対策）
      await Future.delayed(const Duration(milliseconds: 400));

      // 予定一覧タブとカレンダータブの両方を更新
      if (_tabController.index == 1) {
        // 予定一覧タブから更新
        ref.invalidate(tomorrowTasksProvider);
        ref.invalidate(upcomingTasksProvider);
        ref.invalidate(tasksByDateRangeProvider);
        // データ取得を待つ
        await ref.read(tomorrowTasksProvider.future);
        await ref.read(upcomingTasksProvider.future);
      } else if (_tabController.index == 2) {
        // カレンダータブから更新 - 全てのキャッシュを無効化
        ref.invalidate(tomorrowTasksProvider);
        ref.invalidate(upcomingTasksProvider);
        ref.invalidate(tasksByDateRangeProvider);
      }

      // 完了演出付きでローディングを閉じる
      await hideGlobalLoading(ref, withSuccess: true);
    } catch (e) {
      // エラー時はローディングを閉じる
      await hideGlobalLoading(ref, withSuccess: false);
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
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          iconSize: 22,
                          tooltip: '更新',
                          onPressed: _handleRefresh,
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
                  TodayTasksTab(),
                  AllSchedulesTab(),
                  CalendarScreen(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
