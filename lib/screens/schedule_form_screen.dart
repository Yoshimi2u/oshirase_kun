import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/schedule.dart';
import '../providers/schedule_provider.dart';
import '../providers/group_provider.dart';
import '../utils/toast_utils.dart';

/// 予定登録・編集画面
class ScheduleFormScreen extends ConsumerStatefulWidget {
  final String? scheduleId;
  final DateTime? initialDate;

  const ScheduleFormScreen({this.scheduleId, this.initialDate, super.key});

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
  bool _requiresCompletion = false;
  bool _isLoading = true;

  // グループ予定関連
  bool _isGroupSchedule = false;
  String? _selectedGroupId;

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
      final userIdAsync = ref.read(currentUserIdProvider);
      final userId = userIdAsync.maybeWhen(
        data: (id) => id,
        orElse: () => null,
      );

      if (userId != null) {
        final repository = ref.read(scheduleRepositoryProvider);
        final schedule = await repository.getSchedule(userId, widget.scheduleId!);
        if (schedule != null && mounted) {
          setState(() {
            _titleController.text = schedule.title;
            _descriptionController.text = schedule.description;
            // initialDateが指定されていない場合のみ、既存データの開始日を使用
            if (widget.initialDate == null) {
              _startDate = schedule.startDate ?? DateTime.now();
            }
            _repeatType = schedule.repeatType;
            _customDays = schedule.repeatInterval ?? 1;
            _requiresCompletion = schedule.requiresCompletion;
            _isGroupSchedule = schedule.isGroupSchedule;
            _selectedGroupId = schedule.groupId;
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

    final now = DateTime.now();

    // 編集時は既存の情報を保持、新規作成時は新しい値を設定
    DateTime? nextScheduledDate;
    DateTime createdAt = now;
    DateTime? lastCompletedDate;
    List<DateTime> completionHistory = [];
    bool isActive = true;

    if (widget.scheduleId == null) {
      // 新規作成時
      nextScheduledDate = _startDate;
    } else {
      // 編集時は既存のスケジュールから取得
      final userIdAsync = ref.read(currentUserIdProvider);
      final userId = userIdAsync.maybeWhen(
        data: (id) => id,
        orElse: () => null,
      );

      if (userId != null) {
        final repository = ref.read(scheduleRepositoryProvider);
        final existingSchedule = await repository.getSchedule(userId, widget.scheduleId!);
        if (existingSchedule != null) {
          // 既存の情報を保持
          createdAt = existingSchedule.createdAt;
          lastCompletedDate = existingSchedule.lastCompletedDate;
          completionHistory = existingSchedule.completionHistory;
          isActive = existingSchedule.isActive;

          // 繰り返し設定または開始日が変更されたかチェック
          final repeatTypeChanged = existingSchedule.repeatType != _repeatType;
          final repeatIntervalChanged =
              _repeatType == RepeatType.custom && existingSchedule.repeatInterval != _customDays;
          final startDateChanged = existingSchedule.startDate == null ||
              existingSchedule.startDate!.year != _startDate.year ||
              existingSchedule.startDate!.month != _startDate.month ||
              existingSchedule.startDate!.day != _startDate.day;

          if (repeatTypeChanged || repeatIntervalChanged || startDateChanged) {
            // 繰り返し設定または開始日が変更された場合はstartDateにリセット
            nextScheduledDate = _startDate;
          } else {
            // 変更されていない場合は既存の値を保持
            nextScheduledDate = existingSchedule.nextScheduledDate;
          }
        }
      }
    }

    final schedule = Schedule(
      id: widget.scheduleId ?? '',
      title: _titleController.text,
      description: _descriptionController.text,
      repeatType: _repeatType,
      repeatInterval: _repeatType == RepeatType.custom ? _customDays : null,
      startDate: _startDate,
      requiresCompletion: _requiresCompletion,
      nextScheduledDate: nextScheduledDate,
      isActive: isActive,
      createdAt: createdAt,
      updatedAt: now,
      lastCompletedDate: lastCompletedDate,
      completionHistory: completionHistory,
      isGroupSchedule: _isGroupSchedule,
      groupId: _isGroupSchedule ? _selectedGroupId : null,
    );

    try {
      if (widget.scheduleId == null) {
        await ref.read(scheduleNotifierProvider.notifier).createSchedule(schedule);
      } else {
        await ref.read(scheduleNotifierProvider.notifier).updateSchedule(schedule);
      }

      if (mounted) {
        ToastUtils.showSuccess(
          widget.scheduleId == null ? '予定を作成しました' : '予定を更新しました',
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ToastUtils.showError('操作に失敗しました: $e');
      }
    }
  }

  Future<void> _deleteSchedule() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('確認'),
        content: const Text('この予定を削除しますか?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('削除'),
          ),
        ],
      ),
    );

    if (confirmed == true && widget.scheduleId != null) {
      try {
        await ref.read(scheduleNotifierProvider.notifier).deleteSchedule(widget.scheduleId!);

        if (mounted) {
          ToastUtils.showSuccess('予定を削除しました');
          context.pop();
        }
      } catch (e) {
        if (mounted) {
          ToastUtils.showError('削除に失敗しました');
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

            // 開始日選択
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
                  RadioListTile<RepeatType>(
                    title: const Text('毎週'),
                    value: RepeatType.weekly,
                    groupValue: _repeatType,
                    onChanged: (value) {
                      setState(() {
                        _repeatType = value!;
                      });
                    },
                  ),
                  RadioListTile<RepeatType>(
                    title: const Text('毎月'),
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
                        const Text('カスタム: '),
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

            // 完了必須フラグ（繰り返し設定が「繰り返しなし」以外の場合のみ表示）
            if (_repeatType != RepeatType.none)
              Card(
                child: SwitchListTile(
                  secondary: const Icon(Icons.flag),
                  title: const Text('完了必須'),
                  subtitle: const Text(
                    '有効にすると、完了するまで次の予定が作成されません',
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
            if (_repeatType != RepeatType.none) const SizedBox(height: 16),
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
