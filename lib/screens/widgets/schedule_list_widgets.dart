import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../../models/schedule_instance.dart';
import '../../models/schedule_template.dart';
import '../../providers/task_provider.dart';
import '../../providers/schedule_template_provider.dart' as template_provider;
import '../../providers/user_profile_provider.dart';
import '../../providers/group_provider.dart';
import '../../providers/auth_provider.dart';
import '../../constants/app_spacing.dart';
import '../../widgets/app_dialogs.dart';

/// 日付セクションヘッダー
class DateSectionHeader extends StatelessWidget {
  final DateTime date;
  final int count;

  const DateSectionHeader({
    super.key,
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
class SectionHeader extends StatelessWidget {
  final String title;
  final Color color;

  const SectionHeader({
    super.key,
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
class TaskCard extends ConsumerStatefulWidget {
  final Task task;
  final bool showCompleteButton;
  final bool showDateInfo;
  final bool isCompleted;

  const TaskCard({
    super.key,
    required this.task,
    required this.showCompleteButton,
    this.showDateInfo = true,
    this.isCompleted = false,
  });

  @override
  ConsumerState<TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends ConsumerState<TaskCard> {
  bool _isFirstTapped = false;
  DateTime? _firstTapTime;
  Timer? _resetTimer;

  /// 仮想タスクを実体化（Firestoreに保存）して新しいIDを返す
  Future<String?> _materializeVirtualTask(Task virtualTask) async {
    try {
      final taskRepository = ref.read(taskRepositoryProvider);

      // 仮想タスクを実タスクに変換
      final realTask = virtualTask.copyWith(
        id: '', // 新しいIDを生成させる
        isVirtual: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Firestoreに保存して新しいIDを取得
      final newTaskId = await taskRepository.createTask(realTask);

      // キャッシュをクリアして再読み込み（次のフレームで実行）
      Future.microtask(() {
        if (mounted) {
          ref.invalidate(todayTasksStreamProvider);
          ref.invalidate(upcomingTasksProvider);
          ref.invalidate(tasksByDateRangeProvider);
        }
      });

      return newTaskId;
    } catch (e) {
      // エラーハンドリング
      return null;
    }
  }

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
                // テンプレートIDからテンプレートを取得
                final templateRepository = ref.read(template_provider.scheduleTemplateRepositoryProvider);
                final template = await templateRepository.getTemplate(widget.task.templateId);

                if (template == null || !context.mounted) return;

                // 繰り返し設定がある場合は編集方法を選択（カスタムタイプは除く）
                if (template.repeatType != RepeatType.none && template.repeatType != RepeatType.custom) {
                  final editOption = await EditMethodDialog.show(context);

                  if (editOption == null || !context.mounted) return;

                  // 仮想タスクの場合は実体化してから遷移
                  String taskId = widget.task.id;
                  if (widget.task.isVirtual) {
                    // 仮想タスクを実体化して新しいIDを取得
                    final newId = await _materializeVirtualTask(widget.task);
                    if (newId == null || !context.mounted) return;
                    taskId = newId;
                  }

                  if (editOption == 'single') {
                    // このタスクのみ編集
                    context.push('/task/edit/$taskId');
                  } else {
                    // 今後すべて編集
                    final uri = Uri(
                      path: '/schedule/edit/${template.id}',
                      queryParameters: {
                        'initialDate': widget.task.scheduledDate.toIso8601String(),
                        'taskId': taskId,
                      },
                    );
                    context.push(uri.toString());
                  }
                } else {
                  // 繰り返しなし・カスタムの場合は直接編集画面へ
                  final uri = Uri(
                    path: '/schedule/edit/${template.id}',
                    queryParameters: {
                      'initialDate': widget.task.scheduledDate.toIso8601String(),
                      'taskId': widget.task.id,
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
                      // 上部: ステータスバッジとグループバッジ
                      Row(
                        children: [
                          // ステータスバッジ
                          StatusBadge(status: status, task: widget.task),
                          // グループバッジ
                          if (widget.task.isGroupSchedule && widget.task.groupId != null) ...[
                            if (status == TaskStatus.overdue) const SizedBox(width: AppSpacing.medium),
                            GroupBadge(groupId: widget.task.groupId!),
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
                                final currentUserId = ref.read(currentUserIdProvider);
                                await taskRepository.completeTask(
                                  widget.task.id,
                                  completedByMemberId: widget.task.isGroupSchedule ? currentUserId : null,
                                );
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
class StatusBadge extends StatelessWidget {
  final TaskStatus status;
  final Task task;

  const StatusBadge({
    super.key,
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
class GroupBadge extends ConsumerWidget {
  final String groupId;

  const GroupBadge({super.key, required this.groupId});

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
class ErrorView extends StatelessWidget {
  final Object error;

  const ErrorView({super.key, required this.error});

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
