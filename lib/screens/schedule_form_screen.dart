import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/schedule_template.dart';
import '../models/schedule_instance.dart';
import '../providers/schedule_template_provider.dart' as template_provider;
import '../providers/task_provider.dart';
import '../providers/group_provider.dart';
import '../utils/toast_utils.dart';
import '../services/loading_service.dart';
import '../constants/app_messages.dart';

/// 予定登録・編集画面（新モデル: ScheduleTemplate + Task）
class ScheduleFormScreen extends ConsumerStatefulWidget {
  final String? scheduleId; // templateId
  final DateTime? initialDate;
  final String? taskId; // 削除対象のタスクID（オプション）

  const ScheduleFormScreen({
    this.scheduleId,
    this.initialDate,
    this.taskId,
    super.key,
  });

  @override
  ConsumerState<ScheduleFormScreen> createState() => _ScheduleFormScreenState();
}

class _ScheduleFormScreenState extends ConsumerState<ScheduleFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  DateTime _startDate = DateTime.now();
  RepeatType _repeatType = RepeatType.none;
  int _customDays = 1;
  List<int> _selectedWeekdays = []; // 選択された曜日リスト
  int _monthlyDay = 1; // 毎月の指定日（1〜28）
  bool _requiresCompletion = false; // カスタム（何日ごと）用の完了必須フラグ
  bool _isLoading = true;

  // グループ予定関連
  bool _isGroupSchedule = false;
  String? _selectedGroupId;

  // 既存のテンプレート（更新時に使用）
  ScheduleTemplate? _existingTemplate;

  // 選択されたタスク（削除用）
  Task? _selectedTask;

  @override
  void initState() {
    super.initState();
    // initialDateが指定されている場合は、それを開始日として設定
    if (widget.initialDate != null) {
      _startDate = widget.initialDate!;
    }
    _loadSchedule();
  }

  Future<void> _loadSchedule() async {
    if (widget.scheduleId != null) {
      final userId = ref.read(template_provider.currentUserIdProvider);

      if (userId != null) {
        final repository = ref.read(template_provider.scheduleTemplateRepositoryProvider);
        final template = await repository.getTemplate(widget.scheduleId!);

        // タスク情報を読み込む（taskIdが指定されている場合）
        if (widget.taskId != null) {
          final taskRepository = ref.read(taskRepositoryProvider);
          _selectedTask = await taskRepository.getTask(widget.taskId!);
        }

        if (template != null && mounted) {
          setState(() {
            _existingTemplate = template; // 既存テンプレートを保存
            _titleController.text = template.title;
            _descriptionController.text = template.description;
            _repeatType = template.repeatType;
            _customDays = template.repeatInterval ?? 1;
            _selectedWeekdays = template.selectedWeekdays ?? [];
            _monthlyDay = template.monthlyDay ?? 1;
            _requiresCompletion = template.requiresCompletion;
            _isGroupSchedule = template.isGroupSchedule;
            _selectedGroupId = template.groupId;
            _isLoading = false;
          });
          return;
        }
      }
    }
    setState(() {
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _saveSchedule() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // 毎週を選択した場合、曜日が1つも選択されていないかチェック
    if (_repeatType == RepeatType.customWeekly && _selectedWeekdays.isEmpty) {
      ToastUtils.showError('曜日を1つ以上選択してください');
      return;
    }

    final userId = ref.read(template_provider.currentUserIdProvider);
    if (userId == null) {
      ToastUtils.showError('ユーザーIDが取得できませんでした');
      return;
    }

    // グローバルローディング表示
    LoadingService.show(message: '予定を作成中...');

    try {
      final now = DateTime.now();

      // テンプレートを作成
      final template = ScheduleTemplate(
        id: widget.scheduleId ?? '',
        userId: userId,
        title: _titleController.text,
        description: _descriptionController.text,
        repeatType: _repeatType,
        repeatInterval: _repeatType == RepeatType.custom ? _customDays : null,
        selectedWeekdays:
            _repeatType == RepeatType.customWeekly && _selectedWeekdays.isNotEmpty ? _selectedWeekdays : null,
        monthlyDay: _repeatType == RepeatType.monthly ? _monthlyDay : null,
        requiresCompletion: _repeatType == RepeatType.custom ? _requiresCompletion : false,
        isActive: true,
        isGroupSchedule: _isGroupSchedule,
        groupId: _isGroupSchedule ? _selectedGroupId : null,
        createdAt: _existingTemplate?.createdAt ?? now, // 更新時は既存のcreatedAtを使用
        updatedAt: now,
      );

      final templateRepository = ref.read(template_provider.scheduleTemplateRepositoryProvider);
      final taskRepository = ref.read(taskRepositoryProvider);

      if (widget.scheduleId == null) {
        // 新規作成
        final templateId = await templateRepository.createTemplateWithPermission(template, userId);

        // 翌月末までのタスクを一括作成（カスタム完了必須は初回のみ）
        // 開始日を指定してタスク生成
        final taskDates = template.generateTaskDatesUntilNextMonthEnd(_startDate);

        for (final taskDate in taskDates) {
          final task = Task(
            id: '',
            userId: userId,
            templateId: templateId,
            title: template.title,
            description: template.description,
            scheduledDate: taskDate,
            completedAt: null,
            completedByMemberId: null,
            groupId: template.groupId,
            isGroupSchedule: template.isGroupSchedule,
            repeatType: template.repeatType.name,
            weekdays: template.selectedWeekdays,
            repeatInterval: template.repeatInterval,
            monthlyDay: template.monthlyDay,
            createdAt: now,
            updatedAt: now,
          );
          await taskRepository.createTask(task);
        }

        ToastUtils.showSuccess('予定を作成しました');
      } else {
        // 更新
        await templateRepository.updateTemplateWithPermission(template, userId);

        // 既存の未完了タスクのみ削除（完了済みタスクは保持）
        await taskRepository.deleteIncompleteTasksByTemplateId(widget.scheduleId!, userId);

        // 新しい設定で翌月末までのタスクを再生成
        // 開始日を指定してタスク生成
        final taskDates = template.generateTaskDatesUntilNextMonthEnd(_startDate);

        for (final taskDate in taskDates) {
          final task = Task(
            id: '',
            userId: userId,
            templateId: widget.scheduleId!,
            title: template.title,
            description: template.description,
            scheduledDate: taskDate,
            completedAt: null,
            completedByMemberId: null,
            groupId: template.groupId,
            isGroupSchedule: template.isGroupSchedule,
            repeatType: template.repeatType.name,
            weekdays: template.selectedWeekdays,
            repeatInterval: template.repeatInterval,
            monthlyDay: template.monthlyDay,
            createdAt: now,
            updatedAt: now,
          );
          await taskRepository.createTask(task);
        }

        ToastUtils.showSuccess('予定を更新しました');
      }

      // グローバルローディング非表示（成功）
      await LoadingService.hide(withSuccess: true);

      if (mounted) {
        context.pop();
      }
    } catch (e) {
      // グローバルローディング非表示（失敗）
      await LoadingService.hide();

      if (mounted) {
        ToastUtils.showError(AppMessages.errorScheduleSaveFailed);
      }
    }
  }

  Future<void> _deleteSchedule() async {
    // 繰り返し設定がある場合は削除オプションを選択
    if (_existingTemplate?.repeatType != null && _existingTemplate!.repeatType != RepeatType.none) {
      final deleteOption = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text(AppMessages.deleteMethodTitle),
          content: const Text(AppMessages.deleteMethodMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text(AppMessages.buttonCancel),
            ),
            // タスクが選択されている場合のみ「このタスクのみ」を表示
            if (_selectedTask != null)
              TextButton(
                onPressed: () => Navigator.pop(context, 'single'),
                style: TextButton.styleFrom(foregroundColor: Colors.orange),
                child: const Text(AppMessages.buttonThisTaskOnly),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'future'),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text(AppMessages.buttonFutureAll),
            ),
          ],
        ),
      );

      if (deleteOption == null) return;

      if (deleteOption == 'single') {
        await _deleteSingleTask();
      } else if (deleteOption == 'future') {
        await _deleteFutureTasks();
      }
    } else {
      // 繰り返し設定がない場合は通常削除
      await _deleteAllTasks();
    }
  }

  /// このタスクのみ削除
  Future<void> _deleteSingleTask() async {
    if (_selectedTask == null) {
      if (mounted) {
        ToastUtils.showError(AppMessages.errorTaskNotSelected);
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AppMessages.confirmationTitle),
        content: Text('${DateFormat('M月d日').format(_selectedTask!.scheduledDate)}のタスクを削除しますか?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(AppMessages.buttonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            child: const Text(AppMessages.buttonDelete),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      LoadingService.show();

      try {
        final taskRepository = ref.read(taskRepositoryProvider);
        final userId = FirebaseAuth.instance.currentUser?.uid;

        if (userId == null) {
          throw Exception('ユーザー情報が取得できません');
        }

        await taskRepository.deleteTaskWithPermission(_selectedTask!.id, userId);

        await LoadingService.hide(withSuccess: true);

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
  }

  /// 今後のタスクのみ削除（テンプレートとタスクを削除）
  Future<void> _deleteFutureTasks() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AppMessages.confirmationTitle),
        content: const Text(AppMessages.deleteFutureTasksConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(AppMessages.buttonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text(AppMessages.buttonDelete),
          ),
        ],
      ),
    );

    if (confirmed == true && widget.scheduleId != null) {
      LoadingService.show();

      try {
        final userId = ref.read(template_provider.currentUserIdProvider);
        if (userId == null) {
          throw Exception('ユーザーIDが取得できませんでした');
        }

        final taskRepository = ref.read(taskRepositoryProvider);
        final templateRepository = ref.read(template_provider.scheduleTemplateRepositoryProvider);
        final tomorrow = DateTime.now().add(const Duration(days: 1));

        // 明日以降の未完了タスクを削除
        await taskRepository.deleteFutureIncompleteTasksByTemplateId(
          widget.scheduleId!,
          userId,
          tomorrow,
        );

        // テンプレートも削除
        await templateRepository.deleteTemplate(widget.scheduleId!);

        await LoadingService.hide(withSuccess: true);

        if (mounted) {
          ToastUtils.showSuccess(AppMessages.deleteFutureTasksSuccess);
          context.pop();
        }
      } catch (e) {
        await LoadingService.hide();

        if (mounted) {
          ToastUtils.showError(AppMessages.deleteFailed);
        }
      }
    }
  }

  /// すべてのタスクを削除（テンプレート + 全タスク）
  Future<void> _deleteAllTasks() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AppMessages.confirmationTitle),
        content: const Text(AppMessages.deleteScheduleConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(AppMessages.buttonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text(AppMessages.buttonDelete),
          ),
        ],
      ),
    );

    if (confirmed == true && widget.scheduleId != null) {
      // グローバルローディング表示
      LoadingService.show();

      try {
        final userId = ref.read(template_provider.currentUserIdProvider);
        if (userId == null) {
          throw Exception('ユーザーIDが取得できませんでした');
        }

        final templateRepository = ref.read(template_provider.scheduleTemplateRepositoryProvider);
        final taskRepository = ref.read(taskRepositoryProvider);

        // 先に関連するタスクを全て削除（テンプレートが存在する間に削除）
        await taskRepository.deleteTasksByTemplateId(widget.scheduleId!, userId);

        // その後、テンプレートを削除（論理削除）
        await templateRepository.deleteTemplate(widget.scheduleId!);

        // グローバルローディング非表示（成功）
        await LoadingService.hide(withSuccess: true);

        if (mounted) {
          ToastUtils.showSuccess(AppMessages.deleteSuccess);
          context.pop();
        }
      } catch (e) {
        // グローバルローディング非表示（失敗）
        await LoadingService.hide();

        if (mounted) {
          ToastUtils.showError(AppMessages.deleteFailed);
        }
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
        title: Text(widget.scheduleId == null ? '予定を追加' : '予定を編集'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          if (widget.scheduleId != null)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _deleteSchedule,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // タイトル入力
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'タイトル',
                hintText: '例: 薬を飲む',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'タイトルを入力してください';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // 説明入力
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: '説明（任意）',
                hintText: '詳細な説明を入力',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),

            // グループ予定設定
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    value: _isGroupSchedule,
                    onChanged: (value) {
                      setState(() {
                        _isGroupSchedule = value;
                        if (!value) {
                          _selectedGroupId = null;
                        }
                      });
                    },
                    title: const Text('グループ予定'),
                    subtitle: Text(
                      _isGroupSchedule ? '全員の予定として作成されます' : '個人の予定として作成されます',
                    ),
                    secondary: Icon(
                      _isGroupSchedule ? Icons.group : Icons.person,
                      color: _isGroupSchedule ? Colors.blue : Colors.grey,
                    ),
                  ),
                  if (_isGroupSchedule) ...[
                    const Divider(height: 1),
                    Consumer(
                      builder: (context, ref, child) {
                        final groupsAsync = ref.watch(userGroupsStreamProvider);

                        return groupsAsync.when(
                          loading: () => const Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                          error: (error, stack) => const Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Column(
                              children: [
                                Icon(Icons.error_outline, color: Colors.red, size: 32),
                                SizedBox(height: 8),
                                Text(
                                  'グループの読み込みに失敗しました',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                          data: (groups) {
                            if (groups.isEmpty) {
                              return Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  children: [
                                    const Text(
                                      'グループがありません',
                                      style: TextStyle(color: Colors.grey),
                                    ),
                                    const SizedBox(height: 8),
                                    ElevatedButton.icon(
                                      onPressed: () {
                                        context.push('/groups');
                                      },
                                      icon: const Icon(Icons.add),
                                      label: const Text('グループを作成'),
                                    ),
                                  ],
                                ),
                              );
                            }

                            return Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: DropdownButtonFormField<String>(
                                value: _selectedGroupId,
                                decoration: const InputDecoration(
                                  labelText: 'グループを選択',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.group),
                                ),
                                items: groups.map((group) {
                                  return DropdownMenuItem(
                                    value: group.id,
                                    child: Text(group.name),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  setState(() {
                                    _selectedGroupId = value;
                                  });
                                },
                                validator: (value) {
                                  if (_isGroupSchedule && (value == null || value.isEmpty)) {
                                    return 'グループを選択してください';
                                  }
                                  return null;
                                },
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 繰り返し設定
            Card(
              child: Column(
                children: [
                  const ListTile(
                    leading: Icon(Icons.repeat),
                    title: Text('繰り返し設定'),
                  ),
                  const Divider(height: 1),
                  RadioListTile<RepeatType>(
                    title: const Text('繰り返しなし'),
                    value: RepeatType.none,
                    groupValue: _repeatType,
                    onChanged: (value) {
                      setState(() {
                        _repeatType = value!;
                      });
                    },
                  ),
                  RadioListTile<RepeatType>(
                    title: const Text('毎日'),
                    value: RepeatType.daily,
                    groupValue: _repeatType,
                    onChanged: (value) {
                      setState(() {
                        _repeatType = value!;
                      });
                    },
                  ),
                  // 曜日指定
                  RadioListTile<RepeatType>(
                    title: const Text('毎週'),
                    value: RepeatType.customWeekly,
                    groupValue: _repeatType,
                    onChanged: (value) {
                      setState(() {
                        _repeatType = value!;
                        if (_selectedWeekdays.isEmpty) {
                          // 初期値として火曜日を設定
                          _selectedWeekdays = [2];
                        }
                      });
                    },
                  ),
                  if (_repeatType == RepeatType.customWeekly)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(left: 16, bottom: 8),
                            child: Text(
                              '曜日を選択',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                          Wrap(
                            spacing: 8,
                            children: [
                              for (int i = 1; i <= 7; i++)
                                FilterChip(
                                  label: Text(['月', '火', '水', '木', '金', '土', '日'][i - 1]),
                                  selected: _selectedWeekdays.contains(i),
                                  showCheckmark: false,
                                  onSelected: (selected) {
                                    setState(() {
                                      if (selected) {
                                        _selectedWeekdays.add(i);
                                        _selectedWeekdays.sort();
                                      } else {
                                        _selectedWeekdays.remove(i);
                                      }
                                    });
                                  },
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  RadioListTile<RepeatType>(
                    title: Row(
                      children: [
                        const Text('毎月 '),
                        SizedBox(
                          width: 60,
                          child: TextFormField(
                            initialValue: _monthlyDay.toString(),
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                            ),
                            onChanged: (value) {
                              final day = int.tryParse(value) ?? 1;
                              setState(() {
                                // 1〜28の範囲に制限
                                _monthlyDay = day.clamp(1, 28);
                              });
                            },
                          ),
                        ),
                        const Text(' 日（最大28日）'),
                      ],
                    ),
                    value: RepeatType.monthly,
                    groupValue: _repeatType,
                    onChanged: (value) {
                      setState(() {
                        _repeatType = value!;
                      });
                    },
                  ),
                  RadioListTile<RepeatType>(
                    title: Row(
                      children: [
                        SizedBox(
                          width: 60,
                          child: TextFormField(
                            initialValue: _customDays.toString(),
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                            ),
                            onChanged: (value) {
                              final days = int.tryParse(value);
                              if (days != null && days > 0) {
                                setState(() {
                                  _customDays = days;
                                });
                              }
                            },
                          ),
                        ),
                        const Text(' 日ごと'),
                      ],
                    ),
                    value: RepeatType.custom,
                    groupValue: _repeatType,
                    onChanged: (value) {
                      setState(() {
                        _repeatType = value!;
                      });
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 完了必須フラグ（カスタム（何日ごと）の場合のみ表示）
            if (_repeatType == RepeatType.custom)
              Card(
                child: SwitchListTile(
                  secondary: const Icon(Icons.flag),
                  title: const Text('完了必須'),
                  subtitle: const Text(
                    '有効：完了後に次の予定を作成\n無効：指定日数ごとに自動作成',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: _requiresCompletion,
                  onChanged: (value) {
                    setState(() {
                      _requiresCompletion = value;
                    });
                  },
                ),
              ),
            if (_repeatType == RepeatType.custom) const SizedBox(height: 16),

            // 開始日選択（繰り返しなしとカスタムの場合のみ表示）
            if (_repeatType == RepeatType.none || _repeatType == RepeatType.custom)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.event),
                  title: const Text('開始日'),
                  subtitle: Text(
                    '${_startDate.year}年${_startDate.month}月${_startDate.day}日',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _startDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                      locale: const Locale('ja', 'JP'),
                    );
                    if (picked != null) {
                      setState(() {
                        _startDate = picked;
                      });
                    }
                  },
                ),
              ),
            if (_repeatType == RepeatType.none || _repeatType == RepeatType.custom) const SizedBox(height: 16),
            const SizedBox(height: 24),

            // 保存ボタン
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saveSchedule,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  widget.scheduleId == null ? '予定を作成' : '予定を更新',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
