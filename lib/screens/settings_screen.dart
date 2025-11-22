import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/notification_settings.dart';
import '../providers/notification_settings_provider.dart';
import '../providers/user_profile_provider.dart';
import '../providers/theme_provider.dart';
import '../utils/toast_utils.dart';
import '../services/fcm_service.dart';
import '../widgets/app_dialogs.dart';

/// 設定画面
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(notificationSettingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('設定'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red),
              SizedBox(height: 16),
              Text(
                'エラーが発生しました',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                '設定の読み込みに失敗しました',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
        data: (settings) => _buildSettingsList(context, ref, settings),
      ),
    );
  }

  Widget _buildSettingsList(BuildContext context, WidgetRef ref, NotificationSettings settings) {
    final userProfileAsync = ref.watch(userProfileStreamProvider);

    return ListView(
      children: [
        // ユーザー名設定
        Card(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: userProfileAsync.when(
            loading: () => const ListTile(
              leading: Icon(Icons.person, color: Colors.blue),
              title: Text('読み込み中...'),
            ),
            error: (error, stack) => const ListTile(
              leading: Icon(Icons.person, color: Colors.red),
              title: Text('エラー'),
              subtitle: Text('ユーザー情報の読み込みに失敗しました'),
            ),
            data: (profile) => ListTile(
              leading: const Icon(Icons.person, color: Colors.blue),
              title: const Text(
                'ユーザー名',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                profile?.displayName ?? 'ユーザー',
                style: const TextStyle(fontSize: 16),
              ),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => _editDisplayName(context, ref, profile?.displayName ?? 'ユーザー'),
            ),
          ),
        ),

        // グループ管理
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            leading: const Icon(Icons.group, color: Colors.blue),
            title: const Text(
              'グループ管理',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            subtitle: const Text('グループで予定を共有'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              context.push('/groups');
            },
          ),
        ),

        // アカウント設定
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            leading: const Icon(Icons.account_circle, color: Colors.blue),
            title: const Text(
              'アカウント設定',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            subtitle: const Text('サインイン・アカウント管理'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              context.push('/account');
            },
          ),
        ),

        // ダークモード設定
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SwitchListTile(
            value: ref.watch(themeModeProvider),
            onChanged: (value) {
              ref.read(themeModeProvider.notifier).setThemeMode(value);
              ToastUtils.showSuccess(value ? 'ダークモードを有効にしました' : 'ライトモードを有効にしました');
            },
            title: const Text(
              'ダークモード',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            secondary: const Icon(Icons.dark_mode, color: Colors.indigo),
          ),
        ),

        // 通知権限チェック用のFutureBuilder（プラットフォーム対応版）
        FutureBuilder<bool>(
          future: FCMService().isNotificationEnabled(),
          builder: (context, snapshot) {
            final isNotificationEnabled = snapshot.data ?? true; // デフォルトはtrue（読み込み中は通知設定を表示）

            // 通知が無効の場合、誘導カードを表示
            if (!isNotificationEnabled) {
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: Colors.orange[50],
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.notifications_off,
                        size: 48,
                        color: Colors.orange,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '通知が無効になっています',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        defaultTargetPlatform == TargetPlatform.iOS
                            ? '通知を受け取るには、iOSの設定から\n通知を許可してください'
                            : '通知を受け取るには、設定から\n通知を許可してください',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[700],
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.settings),
                        label: Text(
                          defaultTargetPlatform == TargetPlatform.iOS ? 'iOSの設定を開く' : 'Androidの設定を開く',
                        ),
                        onPressed: () async {
                          final message = defaultTargetPlatform == TargetPlatform.iOS
                              ? '設定 > お知らせ君 > 通知 から許可してください'
                              : '設定 > アプリ > お知らせ君 > 通知 から許可してください';
                          ToastUtils.showInfo(message);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            // 通知が有効な場合、朝と夜の通知設定を表示
            return Column(
              children: [
                // 朝の通知設定
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    children: [
                      SwitchListTile(
                        value: settings.morningEnabled,
                        onChanged: (value) {
                          ref.read(notificationSettingsNotifierProvider.notifier).toggleMorningEnabled(value);
                        },
                        title: const Text(
                          '朝の通知',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        secondary: const Icon(Icons.wb_sunny, color: Colors.orange),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        enabled: settings.morningEnabled,
                        leading: const Icon(Icons.access_time),
                        title: const Text('通知時刻'),
                        subtitle: Text(
                          '${settings.morningHour.toString().padLeft(2, '0')}:00',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: settings.morningEnabled ? Colors.blue : Colors.grey,
                          ),
                        ),
                        trailing: settings.morningEnabled ? const Icon(Icons.arrow_forward_ios, size: 16) : null,
                        onTap: settings.morningEnabled
                            ? () => _selectMorningHour(context, ref, settings.morningHour)
                            : null,
                      ),
                    ],
                  ),
                ),

                // 夜の通知設定
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    children: [
                      SwitchListTile(
                        value: settings.eveningEnabled,
                        onChanged: (value) {
                          ref.read(notificationSettingsNotifierProvider.notifier).toggleEveningEnabled(value);
                        },
                        title: const Text(
                          '夜の通知',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        secondary: const Icon(Icons.nightlight_round, color: Colors.indigo),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        enabled: settings.eveningEnabled,
                        leading: const Icon(Icons.access_time),
                        title: const Text('通知時刻'),
                        subtitle: Text(
                          '${settings.eveningHour.toString().padLeft(2, '0')}:00',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: settings.eveningEnabled ? Colors.blue : Colors.grey,
                          ),
                        ),
                        trailing: settings.eveningEnabled ? const Icon(Icons.arrow_forward_ios, size: 16) : null,
                        onTap: settings.eveningEnabled
                            ? () => _selectEveningHour(context, ref, settings.eveningHour)
                            : null,
                      ),
                    ],
                  ),
                ),

                // 説明
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    '通知は毎日指定した時刻に、その日のタスクと未完了タスクの件数をお知らせします。',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  /// 朝の通知時刻（時）を選択
  Future<void> _selectMorningHour(BuildContext context, WidgetRef ref, int currentHour) async {
    final int? picked = await showDialog<int>(
      context: context,
      builder: (context) => _HourPickerDialog(
        initialHour: currentHour,
        minHour: 0,
        maxHour: 11,
      ),
    );

    if (picked != null) {
      await ref.read(notificationSettingsNotifierProvider.notifier).updateMorningHour(picked);
    }
  }

  /// 夜の通知時刻（時）を選択
  Future<void> _selectEveningHour(BuildContext context, WidgetRef ref, int currentHour) async {
    final int? picked = await showDialog<int>(
      context: context,
      builder: (context) => _HourPickerDialog(
        initialHour: currentHour,
        minHour: 12,
        maxHour: 23,
      ),
    );

    if (picked != null) {
      await ref.read(notificationSettingsNotifierProvider.notifier).updateEveningHour(picked);
    }
  }

  /// 表示名を編集
  Future<void> _editDisplayName(BuildContext context, WidgetRef ref, String currentName) async {
    final newName = await InputDialog.show(
      context,
      title: '表示名の変更',
      label: '表示名',
      hint: '新しい表示名',
      initialValue: currentName,
      maxLength: 50,
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return '表示名を入力してください';
        }
        if (value.trim().length > 50) {
          return '表示名は50文字以内で入力してください';
        }
        return null;
      },
    );

    if (newName != null && newName.isNotEmpty && context.mounted) {
      try {
        await ref.read(userProfileNotifierProvider.notifier).updateDisplayName(newName);
        if (context.mounted) {
          ToastUtils.showSuccess('ユーザー名を更新しました');
        }
      } catch (e) {
        if (context.mounted) {
          ToastUtils.showError('ユーザー名の更新に失敗しました');
        }
      }
    }
  }
}

/// 時刻（時）選択ダイアログ
class _HourPickerDialog extends StatelessWidget {
  final int initialHour;
  final int minHour;
  final int maxHour;

  const _HourPickerDialog({
    required this.initialHour,
    this.minHour = 0,
    this.maxHour = 23,
  });

  @override
  Widget build(BuildContext context) {
    final hours = List.generate(maxHour - minHour + 1, (index) => minHour + index);

    return AlertDialog(
      title: const Text('通知時刻を選択'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: ListView.builder(
          itemCount: hours.length,
          itemBuilder: (context, index) {
            final hour = hours[index];
            final isSelected = hour == initialHour;
            return ListTile(
              title: Text(
                '${hour.toString().padLeft(2, '0')}:00',
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? Colors.blue : null,
                ),
              ),
              selected: isSelected,
              onTap: () => Navigator.of(context).pop(hour),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
      ],
    );
  }
}

/// 表示名編集ダイアログ
class _DisplayNameDialog extends StatefulWidget {
  final String currentName;

  const _DisplayNameDialog({required this.currentName});

  @override
  State<_DisplayNameDialog> createState() => _DisplayNameDialogState();
}

class _DisplayNameDialogState extends State<_DisplayNameDialog> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('ユーザー名を設定'),
      content: TextField(
        controller: _controller,
        decoration: const InputDecoration(
          labelText: 'ユーザー名',
          hintText: '例: 田中太郎',
          border: OutlineInputBorder(),
        ),
        maxLength: 20,
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        TextButton(
          onPressed: () {
            final name = _controller.text.trim();
            if (name.isNotEmpty) {
              Navigator.pop(context, name);
            }
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
