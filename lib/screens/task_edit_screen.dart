import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../models/schedule_instance.dart';
import '../models/group_role.dart';
import '../providers/task_provider.dart';
import '../providers/group_provider.dart';
import '../utils/toast_utils.dart';
import '../services/loading_service.dart';
import '../constants/app_messages.dart';
import '../widgets/app_dialogs.dart';

/// 個別タスク編集画面（このタスクのみを編集）
class TaskEditScreen extends ConsumerStatefulWidget {
  final String taskId;

  const TaskEditScreen({
    required this.taskId,
    super.key,
  });

  @override
  ConsumerState<TaskEditScreen> createState() => _TaskEditScreenState();
}

class _TaskEditScreenState extends ConsumerState<TaskEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  bool _isLoading = true;
  Task? _task;
  bool _canEdit = true; // 編集権限フラグ

  @override
  void initState() {
    super.initState();
    _loadTask();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadTask() async {
    try {
      final taskRepository = ref.read(taskRepositoryProvider);

      // 仮想タスクIDの場合は実体化が必要
      if (widget.taskId.startsWith('virtual_')) {
        // 仮想タスクは読み込めないため、エラーメッセージを表示
        if (mounted) {
          ToastUtils.showError('仮想タスクは編集できません');
          context.pop();
        }
        return;
      }

      final task = await taskRepository.getTask(widget.taskId);

      if (task != null && mounted) {
        // グループタスクの場合、編集権限をチェック
        bool canEdit = true;
        if (task.isGroupSchedule && task.groupId != null) {
          final userId = ref.read(currentUserIdProvider);
          if (userId != null) {
            final groupRepository = ref.read(groupRepositoryProvider);
            final groupWithRoles = await groupRepository.getGroupWithRoles(task.groupId!);
            if (groupWithRoles != null) {
              final userRole = groupWithRoles.memberRoles[userId];
              canEdit = userRole == GroupRole.owner || userRole == GroupRole.admin;
            }
          }
        }

        setState(() {
          _task = task;
          _titleController.text = task.title;
          _descriptionController.text = task.description;
          _canEdit = canEdit;
          _isLoading = false;
        });
      } else {
        if (mounted) {
          ToastUtils.showError(AppMessages.errorTaskNotFound);
          context.pop();
        }
      }
    } catch (e) {
      if (mounted) {
        ToastUtils.showError(AppMessages.taskLoadError);
        context.pop();
      }
    }
  }

  Future<void> _saveTask() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_task == null) return;

    LoadingService.show();

    try {
      final taskRepository = ref.read(taskRepositoryProvider);
      final userId = ref.read(currentUserIdProvider);

      if (userId == null) {
        throw Exception('ユーザー情報が取得できません');
      }

      // タスクを更新
      final updatedTask = _task!.copyWith(
        title: _titleController.text,
        description: _descriptionController.text.isEmpty ? null : _descriptionController.text,
        updatedAt: DateTime.now(),
      );

      await taskRepository.updateTaskWithPermission(updatedTask, userId);

      await LoadingService.hide(withSuccess: true);

      // キャッシュをクリア
      ref.invalidate(todayTasksStreamProvider);
      ref.invalidate(tomorrowTasksProvider);
      ref.invalidate(upcomingTasksProvider);
      ref.invalidate(tasksByDateRangeProvider);

      if (mounted) {
        ToastUtils.showSuccess('タスクを更新しました');
        context.pop();
      }
    } catch (e) {
      await LoadingService.hide();

      if (mounted) {
        ToastUtils.showError(AppMessages.errorTaskUpdateFailed);
      }
    }
  }

  Future<void> _deleteTask() async {
    if (_task == null) return;

    final confirmed = await DeleteConfirmationDialog.show(
      context,
      title: 'タスクを削除',
      message: '${DateFormat('M月d日').format(_task!.scheduledDate)}のタスクを削除しますか?',
      subMessage: '繰り返し予定は残ります。',
      confirmText: AppMessages.buttonDelete,
    );

    if (confirmed != true) return;

    LoadingService.show();

    try {
      final taskRepository = ref.read(taskRepositoryProvider);
      final userId = ref.read(currentUserIdProvider);

      if (userId == null) {
        throw Exception('ユーザー情報が取得できません');
      }

      await taskRepository.deleteTaskWithPermission(_task!.id, userId);

      await LoadingService.hide(withSuccess: true);

      // キャッシュをクリア
      ref.invalidate(todayTasksStreamProvider);
      ref.invalidate(tomorrowTasksProvider);
      ref.invalidate(upcomingTasksProvider);
      ref.invalidate(tasksByDateRangeProvider);

      if (mounted) {
        ToastUtils.showSuccess(AppMessages.deleteTaskSuccess);
        context.pop();
      }
    } catch (e) {
      await LoadingService.hide();

      if (mounted) {
        ToastUtils.showError(AppMessages.deleteFailed);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('タスクを編集'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: GestureDetector(
        onTap: () {
          FocusScope.of(context).unfocus();
        },
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 日付表示
              Card(
                child: ListTile(
                  leading: const Icon(Icons.calendar_today),
                  title: const Text('日付'),
                  subtitle: Text(
                    DateFormat('yyyy年M月d日(E)', 'ja_JP').format(_task!.scheduledDate),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 注意事項
              Card(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.orange.shade900.withOpacity(0.3)
                    : Colors.orange.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.orange.shade300
                            : Colors.orange.shade700,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'このタスクのみを編集します。\n繰り返し設定は変更されません。',
                          style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(context).brightness == Brightness.dark
                                ? Colors.orange.shade200
                                : Colors.orange.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // タイトル入力
              TextFormField(
                controller: _titleController,
                enabled: _canEdit,
                decoration: const InputDecoration(
                  labelText: 'タイトル',
                  hintText: '例: 薬を飲む',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
                maxLength: 50,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) {
                  FocusScope.of(context).unfocus();
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'タイトルを入力してください';
                  }
                  if (value.length > 50) {
                    return 'タイトルは50文字以内で入力してください';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // 説明入力
              TextFormField(
                controller: _descriptionController,
                enabled: _canEdit,
                decoration: const InputDecoration(
                  labelText: '説明（任意）',
                  hintText: '詳細な説明を入力',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
                maxLength: 500,
                maxLines: 3,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) {
                  FocusScope.of(context).unfocus();
                },
                validator: (value) {
                  if (value != null && value.length > 500) {
                    return '説明は500文字以内で入力してください';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),

              // 編集権限がない場合の警告メッセージ
              if (!_canEdit) ...[
                Card(
                  color: Colors.orange.shade50,
                  child: const Padding(
                    padding: EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.orange),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'このグループタスクは閲覧のみです。\n編集はオーナーまたは管理者のみが行えます。',
                            style: TextStyle(color: Colors.orange),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // 保存ボタン
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _canEdit ? _saveTask : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    '保存',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 削除ボタン
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _canEdit ? _deleteTask : null,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text(
                    'このタスクを削除',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
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
