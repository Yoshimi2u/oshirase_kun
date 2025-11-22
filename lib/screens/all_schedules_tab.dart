import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/schedule_instance.dart';
import '../providers/task_provider.dart';
import '../constants/app_spacing.dart';
import 'widgets/schedule_list_widgets.dart';

/// 全予定タブ（明日以降のタスクを日付別に表示）
class AllSchedulesTab extends ConsumerStatefulWidget {
  const AllSchedulesTab({super.key});

  @override
  ConsumerState<AllSchedulesTab> createState() => _AllSchedulesTabState();
}

class _AllSchedulesTabState extends ConsumerState<AllSchedulesTab> with AutomaticKeepAliveClientMixin {
  bool _showMore = false; // もっと見るフラグ（初期は明日のみ）

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixinのために必要

    // 常に明日と1週間分の両方を取得
    final tomorrowTasksAsync = ref.watch(tomorrowTasksProvider);
    final upcomingTasksAsync = ref.watch(upcomingTasksProvider);

    return tomorrowTasksAsync.when(
      data: (tomorrowTasks) {
        // 明日のタスク部分を構築
        final tomorrowSection = Column(
          children: [
            if (tomorrowTasks.isEmpty)
              _buildEmptyTaskCard()
            else ...[
              // 明日の日付ヘッダーを1回だけ表示
              DateSectionHeader(
                date: tomorrowTasks.first.scheduledDate,
                count: tomorrowTasks.length,
              ),
              // 全タスクを表示
              ...tomorrowTasks.map((task) => TaskCard(
                    task: task,
                    showCompleteButton: false,
                    showDateInfo: true,
                  )),
              const SizedBox(height: 8),
            ],
          ],
        );

        // 明日のみ表示の場合
        if (!_showMore) {
          return ListView(
            padding: const EdgeInsets.all(8),
            children: [
              tomorrowSection,
              _buildShowMoreButton(),
            ],
          );
        }

        // 1週間分表示の場合
        return upcomingTasksAsync.when(
          data: (upcomingTasks) {
            // 明日以降のタスク（明日を除く）
            final tomorrow = DateTime.now().add(const Duration(days: 1));
            final tomorrowDate = DateTime(tomorrow.year, tomorrow.month, tomorrow.day);
            final dayAfterTomorrow = tomorrowDate.add(const Duration(days: 1));

            final afterTomorrowTasks = upcomingTasks.where((task) {
              // 明後日0:00:00以降のタスクのみ
              return task.scheduledDate.isAtSameMomentAs(dayAfterTomorrow) ||
                  task.scheduledDate.isAfter(dayAfterTomorrow);
            }).toList();

            if (afterTomorrowTasks.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(8),
                children: [
                  tomorrowSection,
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        '明日以降の予定がありません',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[500],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }

            // 日付ごとにグループ化
            final Map<String, List<Task>> groupedTasks = {};
            for (final task in afterTomorrowTasks) {
              final date = task.scheduledDate;
              final key =
                  '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
              groupedTasks.putIfAbsent(key, () => []).add(task);
            }

            final sortedKeys = groupedTasks.keys.toList()..sort();

            return ListView(
              padding: const EdgeInsets.all(8),
              children: [
                tomorrowSection,
                ...sortedKeys.map((dateKey) {
                  final tasksForDate = groupedTasks[dateKey]!;
                  final date = tasksForDate.first.scheduledDate;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DateSectionHeader(date: date, count: tasksForDate.length),
                      ...tasksForDate.map((task) => TaskCard(
                            task: task,
                            showCompleteButton: false,
                            showDateInfo: true,
                          )),
                      const SizedBox(height: 8),
                    ],
                  );
                }),
              ],
            );
          },
          loading: () => ListView(
            padding: const EdgeInsets.all(8),
            children: [
              tomorrowSection,
              const Center(child: CircularProgressIndicator()),
            ],
          ),
          error: (e, st) => ListView(
            padding: const EdgeInsets.all(8),
            children: [
              tomorrowSection,
              ErrorView(error: e),
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => ErrorView(error: e),
    );
  }

  /// タスクがない場合のカード表示
  Widget _buildEmptyTaskCard() {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.cardMarginHorizontal,
        vertical: AppSpacing.cardMarginVertical,
      ),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  size: 20,
                  color: Colors.grey[400],
                ),
                const SizedBox(width: 8),
                Text(
                  DateFormat('M月d日(E)', 'ja_JP').format(tomorrow),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                '予定がありません',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[500],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// もっと見るボタン
  Widget _buildShowMoreButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: OutlinedButton.icon(
        onPressed: () {
          setState(() {
            _showMore = true;
          });
        },
        icon: const Icon(Icons.expand_more),
        label: const Text('もっと見る（1週間分）'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
}
