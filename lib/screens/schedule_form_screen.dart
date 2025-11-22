import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../models/schedule_template.dart';
import '../models/schedule_instance.dart';
import '../models/group.dart';
import '../models/group_role.dart';
import '../providers/schedule_template_provider.dart' as template_provider;
import '../providers/task_provider.dart';
import '../providers/group_provider.dart';
import '../providers/auth_provider.dart';
import '../utils/toast_utils.dart';
import '../services/loading_service.dart';
import '../constants/app_messages.dart';
import '../widgets/app_dialogs.dart';

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
  final _scrollController = ScrollController();
  final _titleKey = GlobalKey();
  final _weekdayKey = GlobalKey();
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

  // 編集権限フラグ（グループメンバーの場合はfalse）
  bool _canEdit = true;

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
      final userId = ref.read(currentUserIdProvider);

      if (userId != null) {
        final repository = ref.read(template_provider.scheduleTemplateRepositoryProvider);
        final template = await repository.getTemplate(widget.scheduleId!);

        if (template != null && mounted) {
          // グループテンプレートの場合、編集権限をチェック
          bool canEdit = true;
          if (template.isGroupSchedule && template.groupId != null) {
            final groupRepository = ref.read(groupRepositoryProvider);
            final groupWithRoles = await groupRepository.getGroupWithRoles(template.groupId!);
            if (groupWithRoles != null) {
              // オーナーまたは管理者のみ編集可能
              final userRole = groupWithRoles.memberRoles[userId];
              canEdit = userRole == GroupRole.owner || userRole == GroupRole.admin;
            }
          }

          setState(() {
            // 既存テンプレートを保存（selectedWeekdaysはコピーして保存）
            _existingTemplate = template.copyWith(
              selectedWeekdays: template.selectedWeekdays != null ? List<int>.from(template.selectedWeekdays!) : null,
            );
            _titleController.text = template.title;
            _descriptionController.text = template.description;
            _repeatType = template.repeatType;
            _customDays = template.repeatInterval ?? 1;
            _selectedWeekdays = template.selectedWeekdays != null ? List<int>.from(template.selectedWeekdays!) : [];
            _monthlyDay = template.monthlyDay ?? 1;
            _requiresCompletion = template.requiresCompletion;
            _isGroupSchedule = template.isGroupSchedule;
            _selectedGroupId = template.groupId;
            _canEdit = canEdit;
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
    _scrollController.dispose();
    super.dispose();
  }

  /// エラーがあるウィジェットまでスクロール
  void _scrollToError() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // タイトルが空の場合
      if (_titleController.text.isEmpty && _titleKey.currentContext != null) {
        Scrollable.ensureVisible(
          _titleKey.currentContext!,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
        return;
      }

      // 毎週で曜日が未選択の場合
      if (_repeatType == RepeatType.customWeekly && _selectedWeekdays.isEmpty && _weekdayKey.currentContext != null) {
        Scrollable.ensureVisible(
          _weekdayKey.currentContext!,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
        return;
      }
    });
  }

  /// 曜日リストが等しいかチェック
  bool _areWeekdaysEqual(List<int>? list1, List<int>? list2) {
    if (list1 == null && list2 == null) return true;
    if (list1 == null || list2 == null) return false;
    if (list1.length != list2.length) return false;

    final sorted1 = List<int>.from(list1)..sort();
    final sorted2 = List<int>.from(list2)..sort();

    for (int i = 0; i < sorted1.length; i++) {
      if (sorted1[i] != sorted2[i]) return false;
    }
    return true;
  }

  Future<void> _saveSchedule() async {
    if (!_formKey.currentState!.validate()) {
      _scrollToError();
      return;
    }

    // 毎週を選択した場合、曜日が1つも選択されていないかチェック
    if (_repeatType == RepeatType.customWeekly && _selectedWeekdays.isEmpty) {
      ToastUtils.showError('曜日を1つ以上選択してください');
      _scrollToError();
      return;
    }

    final userId = ref.read(currentUserIdProvider);
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

        // 繰り返しなしとカスタムの場合は初回タスクのみ手動作成
        if (template.repeatType == RepeatType.none || template.repeatType == RepeatType.custom) {
          final task = Task(
            id: '',
            userId: userId,
            templateId: templateId,
            title: template.title,
            description: template.description,
            scheduledDate: _startDate,
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
        } else {
          // その他の繰り返しタイプは新しいテンプレート用のCloud Functionを呼び出し
          final functions = FirebaseFunctions.instanceFor(region: 'asia-northeast1');
          final callable = functions.httpsCallable('generateTasksForTemplate');
          await callable.call({'templateId': templateId});
        }

        ToastUtils.showSuccess('予定を作成しました');
      } else {
        // 更新
        await templateRepository.updateTemplateWithPermission(template, userId);

        // 繰り返し設定が変更されたかチェック
        final repeatTypeChanged = _existingTemplate?.repeatType != template.repeatType;
        final intervalChanged = _existingTemplate?.repeatInterval != template.repeatInterval;
        final weekdaysChanged = !_areWeekdaysEqual(_existingTemplate?.selectedWeekdays, template.selectedWeekdays);
        final monthlyDayChanged = _existingTemplate?.monthlyDay != template.monthlyDay;

        final repeatSettingsChanged = repeatTypeChanged || intervalChanged || weekdaysChanged || monthlyDayChanged;

        if (kDebugMode) {
          print('🔍 繰り返し設定変更チェック:');
          print(
              '  - repeatType: ${_existingTemplate?.repeatType} -> ${template.repeatType} (changed: $repeatTypeChanged)');
          print(
              '  - interval: ${_existingTemplate?.repeatInterval} -> ${template.repeatInterval} (changed: $intervalChanged)');
          print(
              '  - weekdays: ${_existingTemplate?.selectedWeekdays} -> ${template.selectedWeekdays} (changed: $weekdaysChanged)');
          print(
              '  - monthlyDay: ${_existingTemplate?.monthlyDay} -> ${template.monthlyDay} (changed: $monthlyDayChanged)');
          print('  - 総合判定: $repeatSettingsChanged');
        }

        // 繰り返しなしとカスタムの場合
        if (template.repeatType == RepeatType.none || template.repeatType == RepeatType.custom) {
          // 既存の未完了タスクを削除
          await taskRepository.deleteIncompleteTasksByTemplateId(widget.scheduleId!, userId);

          // 新しい日付でタスクを作成
          final task = Task(
            id: '',
            userId: userId,
            templateId: widget.scheduleId!,
            title: template.title,
            description: template.description,
            scheduledDate: _startDate,
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
        } else {
          // その他の繰り返しタイプ（毎日、毎週、毎月など）
          if (repeatSettingsChanged) {
            // 繰り返し設定が変更された場合のみ、既存タスクを削除して再生成
            await taskRepository.deleteIncompleteTasksByTemplateId(widget.scheduleId!, userId);

            final functions = FirebaseFunctions.instanceFor(region: 'asia-northeast1');
            final callable = functions.httpsCallable('generateTasksForTemplate');
            await callable.call({'templateId': widget.scheduleId!});
          } else {
            // 繰り返し設定が変更されていない場合は、既存タスクのタイトルと説明のみ更新
            await taskRepository.updateIncompleteTasksTitleAndDescription(
              widget.scheduleId!,
              template.title,
              template.description,
            );
          }
        }

        ToastUtils.showSuccess('予定を更新しました');
      }

      // グローバルローディング非表示（成功）
      await LoadingService.hide(withSuccess: true);

      // 予定一覧とカレンダーの両方を更新
      ref.invalidate(tomorrowTasksProvider);
      ref.invalidate(upcomingTasksProvider);
      ref.invalidate(tasksByDateRangeProvider);

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
    // すべての場合で全タスク削除を実行
    await _deleteAllTasks();
  }

  /// すべてのタスクを削除（テンプレート + 全タスク）
  Future<void> _deleteAllTasks() async {
    final confirmed = await DeleteConfirmationDialog.show(
      context,
      title: '予定を削除',
      message: 'この操作は取り消せません。',
      subMessage: 'すべての関連タスクが削除されます。',
      confirmText: AppMessages.buttonDelete,
    );

    if (confirmed == true && widget.scheduleId != null) {
      // グローバルローディング表示
      LoadingService.show();

      try {
        final userId = ref.read(currentUserIdProvider);
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

        // 予定一覧とカレンダーの両方を更新
        ref.invalidate(tomorrowTasksProvider);
        ref.invalidate(upcomingTasksProvider);
        ref.invalidate(tasksByDateRangeProvider);

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
              color: Colors.red,
              onPressed: _canEdit ? _deleteSchedule : null,
            ),
        ],
      ),
      body: GestureDetector(
        onTap: () {
          // 画面タップでキーボードを閉じる
          FocusScope.of(context).unfocus();
        },
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // タイトル入力
              TextFormField(
                key: _titleKey,
                controller: _titleController,
                enabled: _canEdit,
                decoration: const InputDecoration(
                  labelText: 'タイトル',
                  hintText: '例: 薬を飲む',
                  border: OutlineInputBorder(),
                  counterText: '', // 文字数カウンターを非表示
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
                  counterText: '', // 文字数カウンターを非表示
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
              const SizedBox(height: 16),

              // グループ予定設定
              Card(
                child: Column(
                  children: [
                    SwitchListTile(
                      value: _isGroupSchedule,
                      onChanged: _canEdit
                          ? (value) {
                              setState(() {
                                _isGroupSchedule = value;
                                if (!value) {
                                  _selectedGroupId = null;
                                }
                              });
                            }
                          : null,
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

                              // 現在のユーザーIDを取得
                              final currentUserId = ref.watch(currentUserIdProvider);

                              if (currentUserId == null) {
                                return const Padding(
                                  padding: EdgeInsets.all(16.0),
                                  child: Text(
                                    'ユーザー情報の取得に失敗しました',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                );
                              }

                              // テンプレート作成権限があるグループを非同期でフィルタ
                              return FutureBuilder<List<Group>>(
                                future: Future.wait(
                                  groups.map((group) async {
                                    final groupRepository = ref.read(groupRepositoryProvider);
                                    final groupWithRoles = await groupRepository.getGroupWithRoles(group.id);
                                    if (groupWithRoles != null) {
                                      final userRole = groupWithRoles.memberRoles[currentUserId];
                                      if (userRole == GroupRole.owner || userRole == GroupRole.admin) {
                                        return group;
                                      }
                                    }
                                    return null;
                                  }),
                                ).then((results) => results.whereType<Group>().toList()),
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState == ConnectionState.waiting) {
                                    return const Padding(
                                      padding: EdgeInsets.all(16.0),
                                      child: Center(child: CircularProgressIndicator()),
                                    );
                                  }

                                  final creatableGroups = snapshot.data ?? [];

                                  if (creatableGroups.isEmpty) {
                                    return const Padding(
                                      padding: EdgeInsets.all(16.0),
                                      child: Text(
                                        'グループ予定を作成できるグループがありません\n※オーナーまたは管理者のみが繰り返し予定を作成できます',
                                        style: TextStyle(color: Colors.grey),
                                        textAlign: TextAlign.center,
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
                                      items: creatableGroups.map((group) {
                                        return DropdownMenuItem(
                                          value: group.id,
                                          child: Text(group.name),
                                        );
                                      }).toList(),
                                      onChanged: _canEdit
                                          ? (value) {
                                              setState(() {
                                                _selectedGroupId = value;
                                              });
                                            }
                                          : null,
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
                    ListTile(
                      leading: Radio<RepeatType>(
                        value: RepeatType.none,
                        groupValue: _repeatType,
                        onChanged: _canEdit
                            ? (value) {
                                setState(() {
                                  _repeatType = value!;
                                });
                              }
                            : null,
                      ),
                      title: const Text('繰り返しなし'),
                      onTap: null, // タップ無効化
                    ),
                    ListTile(
                      leading: Radio<RepeatType>(
                        value: RepeatType.daily,
                        groupValue: _repeatType,
                        onChanged: _canEdit
                            ? (value) {
                                setState(() {
                                  _repeatType = value!;
                                });
                              }
                            : null,
                      ),
                      title: const Text('毎日'),
                      onTap: null, // タップ無効化
                    ),
                    // 曜日指定
                    ListTile(
                      leading: Radio<RepeatType>(
                        value: RepeatType.customWeekly,
                        groupValue: _repeatType,
                        onChanged: _canEdit
                            ? (value) {
                                setState(() {
                                  _repeatType = value!;
                                  if (_selectedWeekdays.isEmpty) {
                                    // 初期値として火曜日を設定
                                    _selectedWeekdays = [2];
                                  }
                                });
                              }
                            : null,
                      ),
                      title: const Text('毎週'),
                      onTap: null, // タップ無効化
                    ),
                    if (_repeatType == RepeatType.customWeekly)
                      Padding(
                        key: _weekdayKey,
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
                                    onSelected: _canEdit
                                        ? (selected) {
                                            setState(() {
                                              if (selected) {
                                                _selectedWeekdays.add(i);
                                                _selectedWeekdays.sort();
                                              } else {
                                                _selectedWeekdays.remove(i);
                                              }
                                            });
                                          }
                                        : null,
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ListTile(
                      leading: Radio<RepeatType>(
                        value: RepeatType.monthly,
                        groupValue: _repeatType,
                        onChanged: _canEdit
                            ? (value) {
                                setState(() {
                                  _repeatType = value!;
                                });
                              }
                            : null,
                      ),
                      title: Row(
                        children: [
                          const Text('毎月 '),
                          SizedBox(
                            width: 60,
                            child: TextFormField(
                              initialValue: _monthlyDay.toString(),
                              enabled: _canEdit,
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.done,
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
                              onFieldSubmitted: (_) {
                                FocusScope.of(context).unfocus();
                              },
                            ),
                          ),
                          const Text(' 日（最大28日）'),
                        ],
                      ),
                      onTap: null, // タップ無効化
                    ),
                    ListTile(
                      leading: Radio<RepeatType>(
                        value: RepeatType.monthlyLastDay,
                        groupValue: _repeatType,
                        onChanged: _canEdit
                            ? (value) {
                                setState(() {
                                  _repeatType = value!;
                                });
                              }
                            : null,
                      ),
                      title: const Text('毎月末日'),
                      onTap: null, // タップ無効化
                    ),
                    ListTile(
                      leading: Radio<RepeatType>(
                        value: RepeatType.custom,
                        groupValue: _repeatType,
                        onChanged: _canEdit
                            ? (value) {
                                setState(() {
                                  _repeatType = value!;
                                  // カスタムは常に完了必須
                                  _requiresCompletion = true;
                                });
                              }
                            : null,
                      ),
                      title: Row(
                        children: [
                          SizedBox(
                            width: 60,
                            child: TextFormField(
                              initialValue: _customDays.toString(),
                              enabled: _canEdit,
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.done,
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
                                    // 1〜365の範囲に制限
                                    _customDays = days.clamp(1, 365);
                                  });
                                }
                              },
                              onFieldSubmitted: (_) {
                                FocusScope.of(context).unfocus();
                              },
                            ),
                          ),
                          const Text(' 日ごと（最大365日）'),
                        ],
                      ),
                      onTap: null, // タップ無効化
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // カスタム繰り返しの説明（完了必須固定）
              if (_repeatType == RepeatType.custom)
                Card(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.blue.shade900.withOpacity(0.3)
                      : Colors.blue.shade50,
                  child: ListTile(
                    leading: Icon(
                      Icons.info_outline,
                      color: Theme.of(context).brightness == Brightness.dark ? Colors.blue.shade200 : Colors.blue,
                    ),
                    title: Text(
                      '完了後に次の予定を自動作成',
                      style: TextStyle(
                        color: Theme.of(context).brightness == Brightness.dark ? Colors.blue.shade100 : null,
                      ),
                    ),
                    subtitle: Text(
                      'このタスクを完了すると、設定した日数後に次のタスクが自動的に作成されます。',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).brightness == Brightness.dark ? Colors.grey.shade300 : null,
                      ),
                    ),
                  ),
                ),
              if (_repeatType == RepeatType.custom) const SizedBox(height: 16),

              // 開始日選択（繰り返しなしとカスタムの場合のみ表示）
              if (_repeatType == RepeatType.none || _repeatType == RepeatType.custom)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.event),
                    title: const Text('日付'),
                    subtitle: Text(
                      '${_startDate.year}年${_startDate.month}月${_startDate.day}日',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: _canEdit
                        ? () async {
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
                          }
                        : null,
                  ),
                ),
              if (_repeatType == RepeatType.none || _repeatType == RepeatType.custom) const SizedBox(height: 16),
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
                            'このグループ予定は閲覧のみです。\n編集はオーナーのみが行えます。',
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
                  onPressed: _canEdit ? _saveSchedule : null,
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
      ),
    );
  }
}
