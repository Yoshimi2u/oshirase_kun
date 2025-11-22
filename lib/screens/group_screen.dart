import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/group.dart';
import '../models/group_with_roles.dart';
import '../models/group_role.dart';
import '../providers/group_provider.dart';
import '../utils/toast_utils.dart';
import '../constants/app_messages.dart';
import '../widgets/app_dialogs.dart';

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
                'グループの読み込みに失敗しました',
                style: TextStyle(color: Colors.grey),
              ),
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
      bottomNavigationBar: _buildBottomActions(context, ref),
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
  Widget _buildBottomActions(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF2C2C2C) : Colors.white,
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
                onPressed: () => _showCreateGroupDialog(context, ref),
                icon: const Icon(Icons.add),
                label: const Text(
                  '新しいグループを作成',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
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
                onPressed: () => _showJoinGroupDialog(context, ref),
                icon: const Icon(Icons.login),
                label: Text(
                  '招待コードで参加',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.blue,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(
                    color: Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.blue,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// グループ作成ダイアログ
  void _showCreateGroupDialog(BuildContext context, WidgetRef ref) async {
    final groupName = await InputDialog.show(
      context,
      title: 'グループを作成',
      label: 'グループ名',
      hint: '例: プロジェクトA、田中家',
      maxLength: 50,
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'グループ名を入力してください';
        }
        return null;
      },
    );

    if (groupName == null || groupName.trim().isEmpty || !context.mounted) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ToastUtils.showError('ユーザーがログインしていません');
      return;
    }

    try {
      final group = await ref.read(groupNotifierProvider.notifier).createGroup(
            name: groupName.trim(),
            ownerId: user.uid,
          );

      if (context.mounted) {
        if (group != null) {
          _showInviteCodeDialog(context, group);
        } else {
          ToastUtils.showError('グループの作成に失敗しました');
        }
      }
    } catch (e) {
      if (context.mounted) {
        ToastUtils.showError('グループの作成に失敗しました');
      }
    }
  }

  /// 招待コード表示ダイアログ
  void _showInviteCodeDialog(BuildContext context, Group group) {
    InviteCodeDialog.show(
      context,
      inviteCode: group.inviteCode,
      onCopy: () => ToastUtils.showSuccess('招待コードをコピーしました'),
    );
  }

  /// グループ参加ダイアログ
  void _showJoinGroupDialog(BuildContext context, WidgetRef ref) async {
    final code = await InputDialog.show(
      context,
      title: 'グループに参加',
      label: '招待コード',
      hint: '6桁のコードを入力',
      maxLength: 6,
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return '招待コードを入力してください';
        }
        if (value.trim().length != 6) {
          return '6桁のコードを入力してください';
        }
        return null;
      },
    );

    if (code == null || code.trim().isEmpty || !context.mounted) return;

    final inviteCode = code.trim().toUpperCase();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ToastUtils.showError('ユーザーがログインしていません');
      return;
    }

    try {
      ToastUtils.showSuccess('グループに参加中...');

      final group = await ref.read(groupNotifierProvider.notifier).joinGroup(
            inviteCode: inviteCode,
            userId: user.uid,
          );

      if (context.mounted) {
        if (group != null) {
          ToastUtils.showSuccess('「${group.name}」に参加しました');
        } else {
          ToastUtils.showError('招待コードが見つかりません');
        }
      }
    } catch (e) {
      if (context.mounted) {
        final errorMessage = e.toString();
        if (errorMessage.contains('既にこのグループ')) {
          ToastUtils.showError('既にこのグループに参加しています');
        } else if (errorMessage.contains('招待コード')) {
          ToastUtils.showError('招待コードが見つかりません');
        } else {
          ToastUtils.showError('グループへの参加に失敗しました');
        }
      }
    }
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
                            color:
                                Theme.of(context).brightness == Brightness.dark ? Colors.blue[300] : Colors.blue[700],
                            fontWeight: FontWeight.w500,
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
                      color: Theme.of(context).brightness == Brightness.dark ? Colors.blue[300] : Colors.blue[700],
                      fontWeight: FontWeight.w500,
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
      builder: (context) => Consumer(
        builder: (context, ref, child) {
          // グループ情報をリアルタイムで監視
          final groupAsync = ref.watch(groupStreamProvider(group.id));

          return groupAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => Center(
              child: Text('エラー: $error'),
            ),
            data: (currentGroup) {
              if (currentGroup == null) {
                return const Center(child: Text('グループが見つかりません'));
              }

              return SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.group),
                      title: Text(currentGroup.name),
                      subtitle: Text(
                        'メンバー: ${currentGroup.memberCount}人',
                        style: TextStyle(
                          color: Theme.of(context).brightness == Brightness.dark ? Colors.blue[300] : Colors.blue[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.people),
                      title: const Text('メンバー一覧'),
                      onTap: () {
                        Navigator.pop(context);
                        _showMembersList(context, ref);
                      },
                    ),
                    if (isOwner)
                      SwitchListTile(
                        secondary: const Icon(Icons.lock_open),
                        title: const Text('新規メンバーの参加を許可'),
                        subtitle: Text(
                          currentGroup.isJoinable ? '招待コードで参加できます' : '参加を一時停止中',
                          style: TextStyle(
                            fontSize: 12,
                            color: currentGroup.isJoinable ? Colors.green : Colors.orange,
                          ),
                        ),
                        value: currentGroup.isJoinable,
                        onChanged: (value) async {
                          final success = await ref.read(groupNotifierProvider.notifier).updateJoinable(
                                groupId: currentGroup.id,
                                isJoinable: value,
                              );

                          if (success) {
                            ToastUtils.showSuccess(
                              value ? '参加を許可しました' : '参加を停止しました',
                            );
                          } else {
                            ToastUtils.showError('設定の更新に失敗しました');
                          }
                        },
                      ),
                    ListTile(
                      leading: const Icon(Icons.exit_to_app),
                      title: const Text('グループから退出'),
                      onTap: () async {
                        if (isOwner) {
                          ToastUtils.showError('オーナーは退出できません。グループを削除してください。');
                          return;
                        }

                        final confirmed = await ConfirmationDialog.show(
                          context,
                          title: 'グループから退出',
                          message: '「${currentGroup.name}」から退出しますか?',
                          icon: Icons.exit_to_app,
                          confirmColor: Colors.orange,
                          confirmText: '退出',
                        );

                        if (confirmed == true && user != null && context.mounted) {
                          final success = await ref
                              .read(groupNotifierProvider.notifier)
                              .leaveGroup(groupId: currentGroup.id, userId: user.uid);

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
                          final confirmed = await DeleteConfirmationDialog.show(
                            context,
                            title: 'グループを削除',
                            message: '「${currentGroup.name}」を削除しますか?',
                            subMessage: 'この操作は取り消せません。\nグループのすべてのデータが削除されます。',
                            confirmText: AppMessages.buttonDelete,
                          );

                          if (confirmed == true && context.mounted) {
                            final success = await ref.read(groupNotifierProvider.notifier).deleteGroup(currentGroup.id);

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
              );
            },
          );
        },
      ),
    );
  }

  /// メンバー一覧を表示
  void _showMembersList(BuildContext context, WidgetRef ref) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => FutureBuilder<GroupWithRoles?>(
          future: ref.read(groupRepositoryProvider).getGroupWithRoles(group.id),
          builder: (context, groupSnapshot) {
            if (!groupSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final groupWithRoles = groupSnapshot.data;
            if (groupWithRoles == null) {
              return const Center(child: Text('グループ情報の取得に失敗しました'));
            }

            return SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Icon(Icons.people),
                        const SizedBox(width: 8),
                        Text(
                          'メンバー一覧 (${groupWithRoles.memberCount}人)',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: groupWithRoles.memberIds.length,
                      itemBuilder: (context, index) {
                        final memberId = groupWithRoles.memberIds[index];
                        final memberRole = groupWithRoles.getRoleForUser(memberId);

                        return FutureBuilder<Map<String, dynamic>?>(
                          future: FirebaseFirestore.instance
                              .collection('users')
                              .doc(memberId)
                              .get()
                              .then((doc) => doc.data()),
                          builder: (context, snapshot) {
                            final displayName = snapshot.data?['displayName'] as String? ?? 'ユーザー';
                            final email = snapshot.data?['email'] as String? ?? '';

                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: _getRoleColor(memberRole),
                                child: Text(
                                  displayName.isNotEmpty ? displayName[0] : 'U',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                              title: Text(
                                displayName,
                                style: const TextStyle(fontWeight: FontWeight.w500),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (email.isNotEmpty) Text(email),
                                  const SizedBox(height: 4),
                                  _buildRoleBadge(memberRole),
                                ],
                              ),
                              trailing: _buildMemberActions(
                                context,
                                ref,
                                groupWithRoles,
                                currentUserId,
                                memberId,
                                memberRole,
                                displayName,
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// 役割に応じた色を返す
  Color _getRoleColor(GroupRole? role) {
    switch (role) {
      case GroupRole.owner:
        return Colors.orange;
      case GroupRole.admin:
        return Colors.purple;
      case GroupRole.member:
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  /// 役割バッジを表示
  Widget _buildRoleBadge(GroupRole? role) {
    if (role == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _getRoleColor(role).withOpacity(0.1),
        border: Border.all(color: _getRoleColor(role)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        role.displayName,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: _getRoleColor(role),
        ),
      ),
    );
  }

  /// メンバーアクション（役割変更・削除）
  Widget? _buildMemberActions(
    BuildContext context,
    WidgetRef ref,
    GroupWithRoles groupWithRoles,
    String currentUserId,
    String targetUserId,
    GroupRole? targetRole,
    String displayName,
  ) {
    // 自分自身には操作ボタンを表示しない
    if (currentUserId == targetUserId) {
      return null;
    }

    final canChangeRole = groupWithRoles.canChangeRole(currentUserId);
    final canRemove = groupWithRoles.canRemoveSpecificMember(currentUserId, targetUserId);

    if (!canChangeRole && !canRemove) {
      return null;
    }

    return Consumer(
      builder: (context, ref, child) {
        return PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (value) async {
            if (value == 'change_role') {
              await _showRoleChangeDialog(
                context,
                ref,
                groupWithRoles.id,
                targetUserId,
                targetRole,
                displayName,
              );
            } else if (value == 'remove') {
              await _showRemoveMemberDialog(
                context,
                ref,
                groupWithRoles.id,
                targetUserId,
                displayName,
              );
            }
          },
          itemBuilder: (context) => [
            if (canChangeRole && targetUserId != groupWithRoles.ownerId)
              const PopupMenuItem(
                value: 'change_role',
                child: Row(
                  children: [
                    Icon(Icons.edit, size: 20),
                    SizedBox(width: 8),
                    Text('役割を変更'),
                  ],
                ),
              ),
            if (canRemove)
              const PopupMenuItem(
                value: 'remove',
                child: Row(
                  children: [
                    Icon(Icons.remove_circle, size: 20, color: Colors.red),
                    SizedBox(width: 8),
                    Text('削除', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  /// 役割変更ダイアログ
  Future<void> _showRoleChangeDialog(
    BuildContext context,
    WidgetRef ref,
    String groupId,
    String targetUserId,
    GroupRole? currentRole,
    String displayName,
  ) async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;

    // showDialog の前に repository インスタンスを取得
    final repository = ref.read(groupRepositoryProvider);

    final newRole = await showDialog<GroupRole>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$displayName の役割を変更'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<GroupRole>(
              title: Text(GroupRole.admin.displayName),
              subtitle: Text(GroupRole.admin.description),
              value: GroupRole.admin,
              groupValue: currentRole,
              onChanged: (value) => Navigator.pop(context, value),
            ),
            RadioListTile<GroupRole>(
              title: Text(GroupRole.member.displayName),
              subtitle: Text(GroupRole.member.description),
              value: GroupRole.member,
              groupValue: currentRole,
              onChanged: (value) => Navigator.pop(context, value),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
        ],
      ),
    );

    if (newRole == null || newRole == currentRole) return;

    if (!context.mounted) return;

    try {
      await repository.updateMemberRole(
        groupId: groupId,
        requestUserId: currentUserId,
        targetUserId: targetUserId,
        newRole: newRole,
      );

      if (context.mounted) {
        ToastUtils.showSuccess('役割を変更しました');
        Navigator.pop(context); // メンバー一覧を閉じて再表示
        _showMembersList(context, ref);
      }
    } catch (e) {
      if (context.mounted) {
        ToastUtils.showError(AppMessages.errorGroupRoleChangeFailed);
      }
    }
  }

  /// メンバー削除確認ダイアログ
  Future<void> _showRemoveMemberDialog(
    BuildContext context,
    WidgetRef ref,
    String groupId,
    String targetUserId,
    String displayName,
  ) async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;

    // showDialog の前に repository インスタンスを取得
    final repository = ref.read(groupRepositoryProvider);

    final confirmed = await DeleteConfirmationDialog.show(
      context,
      title: 'メンバーを削除',
      message: '$displayName をグループから削除しますか？',
      subMessage: 'この操作は取り消せません。',
      confirmText: '削除',
    );

    if (confirmed != true) return;

    if (!context.mounted) return;

    try {
      await repository.removeMemberWithPermission(
        groupId: groupId,
        requestUserId: currentUserId,
        targetUserId: targetUserId,
      );

      if (context.mounted) {
        ToastUtils.showSuccess('メンバーを削除しました');
        Navigator.pop(context); // メンバー一覧を閉じて再表示
        _showMembersList(context, ref);
      }
    } catch (e) {
      if (context.mounted) {
        ToastUtils.showError(AppMessages.errorGroupMemberDeleteFailed);
      }
    }
  }
}
