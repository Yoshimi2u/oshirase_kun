import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/group.dart';
import '../providers/group_provider.dart';
import '../utils/toast_utils.dart';

/// グループ管理管理画面
class GroupScreen extends ConsumerWidget {
  const GroupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(userGroupsStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('グループ管理'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: groupsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text('エラーが発生しました\n$error'),
            ],
          ),
        ),
        data: (groups) {
          if (groups.isEmpty) {
            return _buildEmptyState(context);
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: groups.length,
            itemBuilder: (context, index) {
              final group = groups[index];
              return _GroupCard(group: group);
            },
          );
        },
      ),
      bottomNavigationBar: _buildBottomActions(context),
    );
  }

  /// グループがない場合の表示
  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.group_outlined,
            size: 80,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            'グループがありません',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '新しいグループを作成するか\n招待コードで参加してください',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  /// 下部のアクションボタン
  Widget _buildBottomActions(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _showCreateGroupDialog(context),
                icon: const Icon(Icons.add),
                label: const Text('新しいグループを作成'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _showJoinGroupDialog(context),
                icon: const Icon(Icons.login),
                label: const Text('招待コードで参加'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// グループ作成ダイアログ
  void _showCreateGroupDialog(BuildContext context) {
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('グループを作成'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'グループ名',
            hintText: '例: プロジェクトA、田中家',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          Consumer(
            builder: (context, ref, child) {
              return TextButton(
                onPressed: () async {
                  if (nameController.text.trim().isEmpty) {
                    ToastUtils.showError('グループ名を入力してください');
                    return;
                  }

                  final user = FirebaseAuth.instance.currentUser;
                  if (user == null) {
                    ToastUtils.showError('ユーザーがログインしていません');
                    return;
                  }

                  try {
                    final group = await ref.read(groupNotifierProvider.notifier).createGroup(
                          name: nameController.text.trim(),
                          ownerId: user.uid,
                        );

                    if (context.mounted) {
                      Navigator.pop(context);
                      if (group != null) {
                        _showInviteCodeDialog(context, group);
                      } else {
                        ToastUtils.showError('グループの作成に失敗しました');
                      }
                    }
                  } catch (e) {
                    if (context.mounted) {
                      Navigator.pop(context);
                      ToastUtils.showError('グループの作成に失敗しました');
                    }
                  }
                },
                child: const Text('作成'),
              );
            },
          ),
        ],
      ),
    );
  }

  /// 招待コード表示ダイアログ
  void _showInviteCodeDialog(BuildContext context, Group group) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('グループを作成しました'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('招待コード'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                group.inviteCode,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                  color: Colors.blue,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'メンバーにこのコードを共有してください',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: group.inviteCode));
              ToastUtils.showSuccess('招待コードをコピーしました');
            },
            child: const Text('コピー'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  /// グループ参加ダイアログ
  void _showJoinGroupDialog(BuildContext context) {
    final codeController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('グループに参加'),
        content: TextField(
          controller: codeController,
          decoration: const InputDecoration(
            labelText: '招待コード',
            hintText: '6桁のコードを入力',
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.characters,
          maxLength: 6,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          Consumer(
            builder: (context, ref, child) {
              return TextButton(
                onPressed: () async {
                  final code = codeController.text.trim().toUpperCase();

                  if (code.isEmpty || code.length != 6) {
                    ToastUtils.showError('6桁の招待コードを入力してください');
                    return;
                  }

                  final user = FirebaseAuth.instance.currentUser;
                  if (user == null) {
                    ToastUtils.showError('ユーザーがログインしていません');
                    return;
                  }

                  try {
                    final group = await ref.read(groupNotifierProvider.notifier).joinGroup(
                          inviteCode: code,
                          userId: user.uid,
                        );

                    if (context.mounted) {
                      Navigator.pop(context);
                      if (group != null) {
                        ToastUtils.showSuccess('「${group.name}」に参加しました');
                      } else {
                        ToastUtils.showError('グループへの参加に失敗しました');
                      }
                    }
                  } catch (e) {
                    if (context.mounted) {
                      Navigator.pop(context);
                      ToastUtils.showError('グループへの参加に失敗しました');
                    }
                  }
                },
                child: const Text('参加'),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// グループカード
class _GroupCard extends ConsumerWidget {
  final Group group;

  const _GroupCard({required this.group});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = FirebaseAuth.instance.currentUser;
    final isOwner = user != null && group.isOwner(user.uid);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _showGroupDetail(context, ref),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.group, color: Colors.blue, size: 28),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'メンバー: ${group.memberCount}人',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isOwner)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'オーナー',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.vpn_key, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    '招待コード: ${group.inviteCode}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: group.inviteCode));
                      ToastUtils.showSuccess('招待コードをコピーしました');
                    },
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      child: const Icon(Icons.copy, size: 16, color: Colors.blue),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// グループ詳細を表示
  void _showGroupDetail(BuildContext context, WidgetRef ref) {
    final user = FirebaseAuth.instance.currentUser;
    final isOwner = user != null && group.isOwner(user.uid);

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.group),
              title: Text(group.name),
              subtitle: Text('メンバー: ${group.memberCount}人'),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.exit_to_app),
              title: const Text('グループから退出'),
              onTap: () async {
                if (isOwner) {
                  ToastUtils.showError('オーナーは退出できません。グループを削除してください。');
                  return;
                }

                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('確認'),
                    content: Text('「${group.name}」から退出しますか?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('キャンセル'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('退出'),
                      ),
                    ],
                  ),
                );

                if (confirmed == true && user != null && context.mounted) {
                  final success =
                      await ref.read(groupNotifierProvider.notifier).leaveGroup(groupId: group.id, userId: user.uid);

                  if (context.mounted) {
                    Navigator.pop(context);
                    if (success) {
                      ToastUtils.showSuccess('グループから退出しました');
                    }
                  }
                }
              },
            ),
            if (isOwner)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('グループを削除', style: TextStyle(color: Colors.red)),
                onTap: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('確認'),
                      content: Text('「${group.name}」を削除しますか?\nこの操作は取り消せません。'),
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

                  if (confirmed == true && context.mounted) {
                    final success = await ref.read(groupNotifierProvider.notifier).deleteGroup(group.id);

                    if (context.mounted) {
                      Navigator.pop(context);
                      if (success) {
                        ToastUtils.showSuccess('グループを削除しました');
                      }
                    }
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}
