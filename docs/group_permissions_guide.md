# グループ権限機能の実装ガイド

## 📋 権限一覧表

| 操作 | オーナー | 管理者 | メンバー |
|------|---------|--------|---------|
| **グループ管理** |
| グループ設定の更新 | ✅ | ✅ | ❌ |
| グループの削除 | ✅ | ❌ | ❌ |
| メンバーの追加 | ✅ | ✅ | ❌ |
| メンバーの削除 | ✅ 全員 | ✅ メンバーのみ | ❌ |
| メンバーの役割変更 | ✅ | ❌ | ❌ |
| グループからの退出 | ❌ | ✅ | ✅ |
| **タスク管理** |
| タスクの作成 | ✅ | ✅ | ✅ |
| タスクの更新（完了など） | ✅ | ✅ | ✅ |
| タスクの削除 | ✅ | ✅ | ❌ |
| **テンプレート管理** |
| テンプレートの作成 | ✅ | ✅ | ❌ |
| テンプレートの更新 | ✅ | ✅ | ❌ |
| テンプレートの削除 | ✅ | ✅ | ❌ |

### 📌 メンバー削除の詳細ルール

- **オーナー**: 管理者・メンバー全員を退出させられる（オーナー自身は除く）
- **管理者**: メンバーのみ退出させられる（他の管理者やオーナーは不可）
- **メンバー**: 誰も退出させられない（自分の退出のみ可能）

---

## 🔧 実装方法

### 1. 基本的な使い方

```dart
import 'package:oshirase_kun/models/group_with_roles.dart';
import 'package:oshirase_kun/models/group_role.dart';

// グループを取得
final group = await groupRepository.getGroupWithRoles(groupId);
final currentUserId = FirebaseAuth.instance.currentUser!.uid;

// 権限チェック
if (group.canDeleteTask(currentUserId)) {
  // タスク削除処理
  await taskRepository.deleteTask(taskId);
} else {
  // エラー表示
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('タスクを削除する権限がありません')),
  );
}
```

---

### 2. UI での権限チェック

#### ボタンの表示/非表示

```dart
// グループ設定画面
Widget build(BuildContext context) {
  final group = ref.watch(groupProvider(groupId)).value;
  final userId = ref.watch(currentUserIdProvider);
  
  return Column(
    children: [
      // オーナーと管理者のみ表示
      if (group != null && group.canUpdateSettings(userId!))
        ElevatedButton(
          onPressed: () => _updateGroupName(),
          child: Text('グループ名を変更'),
        ),
      
      // オーナーのみ表示
      if (group != null && group.canDelete(userId!))
        ElevatedButton(
          onPressed: () => _deleteGroup(),
          child: Text('グループを削除'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
          ),
        ),
    ],
  );
}
```

#### メニューアイテムの制御

```dart
PopupMenuButton<String>(
  itemBuilder: (context) => [
    // 全員に表示
    PopupMenuItem(
      value: 'view',
      child: Text('グループ詳細'),
    ),
    
    // 全メンバーに表示
    PopupMenuItem(
      value: 'add_task',
      child: Text('タスクを追加'),
    ),
    
    // 管理者・オーナーのみ表示
    if (group.canAddMember(userId))
      PopupMenuItem(
        value: 'invite',
        child: Text('メンバーを招待'),
      ),
    
    // オーナー以外に表示
    if (group.canLeaveGroup(userId))
      PopupMenuItem(
        value: 'leave',
        child: Text('グループから退出'),
      ),
  ],
);
```

---

### 3. Repository での権限チェック

```dart
// group_repository.dart

/// グループ名を更新（権限チェック付き）
Future<void> updateGroupName(String groupId, String userId, String newName) async {
  final group = await getGroupWithRoles(groupId);
  
  if (group == null) {
    throw Exception('グループが見つかりません');
  }
  
  // 権限チェック
  if (!group.canUpdateSettings(userId)) {
    throw Exception('グループ設定を更新する権限がありません');
  }
  
  await _groupsCollection.doc(groupId).update({
    'name': newName,
    'updatedAt': Timestamp.now(),
  });
}

/// メンバーを削除（権限チェック付き）
Future<void> removeMember(String groupId, String requestUserId, String targetUserId) async {
  final group = await getGroupWithRoles(groupId);
  
  if (group == null) {
    throw Exception('グループが見つかりません');
  }
  
  // 詳細な権限チェック（誰が誰を削除できるか）
  if (!group.canRemoveSpecificMember(requestUserId, targetUserId)) {
    final requestRole = group.getRoleForUser(requestUserId);
    final targetRole = group.getRoleForUser(targetUserId);
    
    if (targetUserId == group.ownerId) {
      throw Exception('オーナーは削除できません');
    } else if (requestRole == GroupRole.admin && targetRole == GroupRole.admin) {
      throw Exception('管理者は他の管理者を削除できません');
    } else {
      throw Exception('このメンバーを削除する権限がありません');
    }
  }
  
  // メンバー削除処理
  final updatedRoles = Map<String, GroupRole>.from(group.memberRoles);
  updatedRoles.remove(targetUserId);
  
  await _groupsCollection.doc(groupId).update({
    'memberRoles': updatedRoles.map((k, v) => MapEntry(k, v.toFirestore())),
    'memberIds': updatedRoles.keys.toList(),
    'updatedAt': Timestamp.now(),
  });
}

/// メンバーの役割を変更
Future<void> updateMemberRole(
  String groupId,
  String requestUserId,
  String targetUserId,
  GroupRole newRole,
) async {
  final group = await getGroupWithRoles(groupId);
  
  if (group == null) {
    throw Exception('グループが見つかりません');
  }
  
  // 権限チェック（オーナーのみ）
  if (!group.canChangeRole(requestUserId)) {
    throw Exception('メンバーの役割を変更する権限がありません');
  }
  
  // オーナーの役割は変更できない
  if (targetUserId == group.ownerId) {
    throw Exception('オーナーの役割は変更できません');
  }
  
  // 役割更新
  final updatedRoles = Map<String, GroupRole>.from(group.memberRoles);
  updatedRoles[targetUserId] = newRole;
  
  await _groupsCollection.doc(groupId).update({
    'memberRoles': updatedRoles.map((k, v) => MapEntry(k, v.toFirestore())),
    'updatedAt': Timestamp.now(),
  });
}
```

---

### 4. タスク操作での権限チェック

```dart
// task_repository.dart

/// グループタスクを削除（権限チェック付き）
Future<void> deleteGroupTask(String taskId, String groupId, String userId) async {
  final group = await groupRepository.getGroupWithRoles(groupId);
  
  if (group == null) {
    throw Exception('グループが見つかりません');
  }
  
  // 権限チェック
  if (!group.canDeleteTask(userId)) {
    throw Exception('このタスクを削除する権限がありません');
  }
  
  await _collection.doc(taskId).delete();
}

/// グループタスクを更新（権限チェック付き）
Future<void> updateGroupTask(String taskId, String groupId, String userId, Map<String, dynamic> data) async {
  final group = await groupRepository.getGroupWithRoles(groupId);
  
  if (group == null) {
    throw Exception('グループが見つかりません');
  }
  
  // 権限チェック
  if (!group.canUpdateTask(userId)) {
    throw Exception('このタスクを更新する権限がありません');
  }
  
  await _collection.doc(taskId).update({
    ...data,
    'updatedAt': FieldValue.serverTimestamp(),
  });
}
```

---

## 🎨 UI コンポーネント例

### メンバー一覧画面

```dart
class GroupMembersScreen extends ConsumerWidget {
  final String groupId;
  
  const GroupMembersScreen({required this.groupId});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupAsync = ref.watch(groupWithRolesProvider(groupId));
    final currentUserId = ref.watch(currentUserIdProvider);
    
    return groupAsync.when(
      data: (group) {
        return ListView.builder(
          itemCount: group.memberCount,
          itemBuilder: (context, index) {
            final userId = group.memberIds[index];
            final role = group.getRoleForUser(userId)!;
            
            return ListTile(
              title: Text('ユーザー名'), // 実際にはユーザー情報を取得
              subtitle: Text(role.displayName),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 役割変更ボタン（オーナーのみ）
                  if (group.canChangeRole(currentUserId!) && userId != group.ownerId)
                    IconButton(
                      icon: Icon(Icons.edit),
                      onPressed: () => _showRoleChangeDialog(userId, role),
                    ),
                  
                  // 削除ボタン（詳細な権限チェック）
                  if (group.canRemoveSpecificMember(currentUserId, userId))
                    IconButton(
                      icon: Icon(Icons.remove_circle, color: Colors.red),
                      onPressed: () => _showRemoveConfirmDialog(userId, role),
                    ),
                ],
              ),
            );
          },
        );
      },
      loading: () => Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('エラー: $e')),
    );
  }
}
```

---

## 📊 マイグレーション（既存データの移行）

既存のグループデータを権限システムに移行する方法：

```dart
// migration_service.dart

Future<void> migrateGroupsToRoleSystem() async {
  final snapshot = await FirebaseFirestore.instance
      .collection('groups')
      .get();
  
  final batch = FirebaseFirestore.instance.batch();
  
  for (final doc in snapshot.docs) {
    final data = doc.data();
    final ownerId = data['ownerId'] as String;
    final memberIds = List<String>.from(data['memberIds'] ?? []);
    
    // memberRoles を作成
    final memberRoles = <String, String>{};
    for (final userId in memberIds) {
      if (userId == ownerId) {
        memberRoles[userId] = GroupRole.owner.name;
      } else {
        // 既存メンバーは全員 member に設定
        memberRoles[userId] = GroupRole.member.name;
      }
    }
    
    batch.update(doc.reference, {
      'memberRoles': memberRoles,
    });
  }
  
  await batch.commit();
  print('✅ ${snapshot.docs.length}件のグループを移行しました');
}
```

---

## ⚠️ 注意点

1. **オーナーの扱い**
   - オーナーはグループから退出できない
   - 退出する場合は、他のメンバーにオーナーを譲渡する必要がある

2. **Firestore Rules**
   - クライアント側の権限チェックだけでなく、Firestore Rulesでも保護する

```javascript
// firestore.rules
match /groups/{groupId} {
  // グループの読み取りはメンバーのみ
  allow read: if request.auth != null && 
    request.auth.uid in resource.data.memberIds;
  
  // グループの更新は管理者・オーナーのみ
  allow update: if request.auth != null && 
    (resource.data.memberRoles[request.auth.uid] == 'owner' ||
     resource.data.memberRoles[request.auth.uid] == 'admin');
  
  // グループの削除はオーナーのみ
  allow delete: if request.auth != null && 
    resource.data.ownerId == request.auth.uid;
}
```

3. **後方互換性**
   - `memberIds`フィールドは残しておく（既存のクエリとの互換性）
   - `memberRoles`から自動生成する

---

## 🚀 実装の優先順位

### Phase 1: 基本実装
1. ✅ `GroupRole` enum作成
2. ✅ `GroupPermission` クラス作成
3. ✅ `GroupWithRoles` モデル作成

### Phase 2: Repository拡張
4. `GroupRepository`に権限チェック付きメソッド追加
5. `TaskRepository`に権限チェック追加

### Phase 3: UI実装
6. グループ設定画面で権限に応じたボタン表示
7. メンバー一覧画面で役割管理機能
8. タスク画面で権限チェック

### Phase 4: データ移行
9. 既存グループデータの移行
10. Firestore Rules更新

---

これで権限機能の完全な実装が可能です！🎉
