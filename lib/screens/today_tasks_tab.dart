import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/schedule_instance.dart';
import '../providers/task_provider.dart' show todayTasksStreamProvider;
import '../widgets/inline_banner_ad.dart';
import '../services/ad_manager.dart';
import 'widgets/schedule_list_widgets.dart';

/// 今日のタスクタブ
class TodayTasksTab extends ConsumerStatefulWidget {
  const TodayTasksTab({super.key});

  @override
  ConsumerState<TodayTasksTab> createState() => _TodayTasksTabState();
}

class _TodayTasksTabState extends ConsumerState<TodayTasksTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixinのために必要
    final todayAsync = ref.watch(todayTasksStreamProvider);

    return todayAsync.when(
      data: (allTasks) {
        if (allTasks.isEmpty) {
          return ListView(
            padding: const EdgeInsets.all(8),
            children: [
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.5,
                child: Center(
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
                ),
              ),
              // インラインバナー広告
              InlineBannerAd(adUnitId: AdManager.inlineBannerAdUnitId),
            ],
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
              SectionHeader(
                title: '遅延中 (${overdueTasks.length}件)',
                color: Colors.red,
              ),
              ...overdueTasks.map((task) => TaskCard(
                    task: task,
                    showCompleteButton: true,
                    showDateInfo: false,
                  )),
              const SizedBox(height: 16),
            ],
            if (pendingTasks.isNotEmpty) ...[
              SectionHeader(
                title: '未完了 (${pendingTasks.length}件)',
                color: Colors.blue,
              ),
              ...pendingTasks.map((task) => TaskCard(
                    task: task,
                    showCompleteButton: true,
                    showDateInfo: false,
                  )),
              const SizedBox(height: 16),
            ],
            // インラインバナー広告（未完了と完了の間）
            InlineBannerAd(adUnitId: AdManager.inlineBannerAdUnitId),
            if (completedTasks.isNotEmpty) ...[
              SectionHeader(
                title: '完了済み (${completedTasks.length}件)',
                color: Colors.green,
              ),
              ...completedTasks.map((task) => TaskCard(
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
      error: (e, st) => ErrorView(error: e),
    );
  }
}
