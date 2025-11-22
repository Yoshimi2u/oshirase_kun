import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/schedule_instance.dart';
import '../models/group_role.dart';
import '../constants/app_messages.dart';

/// タスク（個別の予定インスタンス）のCRUD操作を管理するリポジトリクラス
class TaskRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collectionName = 'tasks';

  /// コレクション参照を取得
  CollectionReference get _collection => _firestore.collection(_collectionName);

  /// タスクを作成
  Future<String> createTask(Task task) async {
    try {
      final docRef = _collection.doc();
      final taskWithId = task.copyWith(id: docRef.id);
      await docRef.set(taskWithId.toFirestore());
      return docRef.id;
    } catch (e) {
      throw Exception('タスクの作成に失敗しました: $e');
    }
  }

  /// 複数のタスクを一括作成
  Future<List<String>> createTasks(List<Task> tasks) async {
    try {
      final batch = _firestore.batch();
      final ids = <String>[];

      for (final task in tasks) {
        final docRef = _collection.doc();
        final taskWithId = task.copyWith(id: docRef.id);
        batch.set(docRef, taskWithId.toFirestore());
        ids.add(docRef.id);
      }

      await batch.commit();
      return ids;
    } catch (e) {
      throw Exception('タスクの一括作成に失敗しました: $e');
    }
  }

  /// タスクを更新
  Future<void> updateTask(Task task) async {
    try {
      // updatedAtを現在時刻に更新
      final updatedTask = task.copyWith(updatedAt: DateTime.now());

      await _collection.doc(updatedTask.id).set(
            updatedTask.toFirestore(),
            SetOptions(merge: true),
          );
    } catch (e) {
      throw Exception('タスクの更新に失敗しました: $e');
    }
  }

  /// 権限チェック付きタスク更新
  Future<void> updateTaskWithPermission(Task task, String userId) async {
    try {
      // グループタスクの場合は権限チェック
      if (task.groupId != null) {
        final groupDoc = await FirebaseFirestore.instance.collection('groups').doc(task.groupId).get();

        if (!groupDoc.exists) {
          throw Exception(AppMessages.errorGroupNotFound);
        }

        final memberRoles = groupDoc.data()?['memberRoles'] as Map<String, dynamic>?;
        final roleString = memberRoles?[userId] as String?;

        if (roleString == null) {
          throw Exception(AppMessages.errorNotGroupMember);
        }

        final role = GroupRoleExtension.fromFirestore(roleString);
        if (!GroupPermission.canUpdateTask(role)) {
          throw Exception(AppMessages.errorNoUpdateTaskPermission);
        }
      } else {
        // 個人タスクの場合は作成者のみ更新可能
        if (task.userId != userId) {
          throw Exception(AppMessages.errorOnlyOwnTask);
        }
      }

      await updateTask(task);
    } catch (e) {
      if (e.toString().contains('Exception:')) {
        rethrow;
      }
      throw Exception('${AppMessages.errorTaskUpdateFailed}: $e');
    }
  }

  /// タスクを完了する
  Future<void> completeTask(String taskId, {String? completedByMemberId}) async {
    try {
      // タスクを取得
      final taskDoc = await _collection.doc(taskId).get();
      if (!taskDoc.exists) {
        throw Exception('タスクが見つかりません');
      }

      final taskData = taskDoc.data() as Map<String, dynamic>;
      final templateId = taskData['templateId'] as String?;

      // タスクを完了
      await _collection.doc(taskId).update({
        'completedAt': FieldValue.serverTimestamp(),
        'completedByMemberId': completedByMemberId,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // テンプレートの requiresCompletion をチェック
      if (templateId != null) {
        final templateDoc = await FirebaseFirestore.instance.collection('schedule_templates').doc(templateId).get();

        if (templateDoc.exists) {
          final templateData = templateDoc.data();
          final requiresCompletion = templateData?['requiresCompletion'] as bool?;
          final repeatType = templateData?['repeatType'] as String?;

          // requiresCompletion=true かつ CUSTOM の場合、次のタスクを生成
          if (requiresCompletion == true && repeatType == 'custom') {
            await _generateNextTask(templateData!, templateId, taskData);
          }
        }
      }
    } catch (e) {
      throw Exception('${AppMessages.errorTaskCompleteFailed}: $e');
    }
  }

  /// 次のタスクを生成（完了後繰り返し用）
  Future<void> _generateNextTask(
    Map<String, dynamic> templateData,
    String templateId,
    Map<String, dynamic> completedTaskData,
  ) async {
    try {
      // 完了したタスクの scheduledDate を基準に次のタスク日を計算
      final completedDate = (completedTaskData['scheduledDate'] as Timestamp).toDate();
      final repeatInterval = templateData['repeatInterval'] as int? ?? 1;

      // repeatInterval 日後を次のタスク日とする
      final nextTaskDate = DateTime(
        completedDate.year,
        completedDate.month,
        completedDate.day + repeatInterval,
      );

      // グループタスクの場合はテンプレートのuserIdを使用、個人タスクの場合は完了したタスクのuserIdを使用
      final isGroupSchedule = completedTaskData['isGroupSchedule'] ?? false;
      final userId = isGroupSchedule ? templateData['userId'] : completedTaskData['userId'];

      // 次のタスクを作成
      await _collection.add({
        'userId': userId,
        'groupId': completedTaskData['groupId'],
        'templateId': templateId,
        'title': templateData['title'],
        'description': templateData['description'] ?? '',
        'scheduledDate': Timestamp.fromDate(nextTaskDate),
        'completedAt': null,
        'completedByMemberId': null,
        'isGroupSchedule': isGroupSchedule,
        'isDeleted': false,
        'repeatType': templateData['repeatType'],
        'weekdays': templateData['selectedWeekdays'],
        'monthlyDay': null,
        'repeatInterval': repeatInterval,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (kDebugMode) {
        print('[TaskRepository] 次のタスクを生成: template=$templateId, date=${nextTaskDate.toString()}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[TaskRepository] 次のタスク生成エラー: $e');
      }
      // エラーが発生してもタスク完了自体は成功させる
    }
  }

  /// タスクの完了を解除する
  Future<void> uncompleteTask(String taskId) async {
    try {
      await _collection.doc(taskId).update({
        'completedAt': null,
        'completedByMemberId': null,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('${AppMessages.errorTaskUncompleteFailed}: $e');
    }
  }

  /// タスクを削除
  Future<void> deleteTask(String taskId) async {
    try {
      await _collection.doc(taskId).delete();
    } catch (e) {
      throw Exception('${AppMessages.errorTaskDeleteFailed}: $e');
    }
  }

  /// タスクを論理削除（isDeletedフラグを立てる）
  Future<void> logicalDeleteTask(String taskId) async {
    try {
      await _collection.doc(taskId).update({
        'isDeleted': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('${AppMessages.errorTaskDeleteFailed}: $e');
    }
  }

  /// 権限チェック付きタスク削除
  Future<void> deleteTaskWithPermission(String taskId, String userId) async {
    try {
      // タスクを取得して権限チェック
      final taskDoc = await _collection.doc(taskId).get();

      if (!taskDoc.exists) {
        throw Exception(AppMessages.errorTaskNotFound);
      }

      final taskData = taskDoc.data() as Map<String, dynamic>;
      final groupId = taskData['groupId'] as String?;

      if (groupId != null) {
        // グループタスクの場合は権限チェック
        final groupDoc = await FirebaseFirestore.instance.collection('groups').doc(groupId).get();

        if (!groupDoc.exists) {
          throw Exception(AppMessages.errorGroupNotFound);
        }

        final memberRoles = groupDoc.data()?['memberRoles'] as Map<String, dynamic>?;
        final roleString = memberRoles?[userId] as String?;

        if (roleString == null) {
          throw Exception(AppMessages.errorNotGroupMember);
        }

        final role = GroupRoleExtension.fromFirestore(roleString);
        if (!GroupPermission.canDeleteTask(role)) {
          throw Exception(AppMessages.errorNoDeleteTaskPermission);
        }
      } else {
        // 個人タスクの場合は作成者のみ削除可能
        final taskUserId = taskData['userId'] as String?;
        if (taskUserId != userId) {
          throw Exception(AppMessages.errorOnlyOwnTask);
        }
      }

      await logicalDeleteTask(taskId);
    } catch (e) {
      if (e.toString().contains('Exception:')) {
        rethrow;
      }
      throw Exception('${AppMessages.errorTaskDeleteFailed}: $e');
    }
  }

  /// テンプレートに紐づく全タスクを削除
  Future<void> deleteTasksByTemplateId(String templateId, String userId) async {
    if (kDebugMode) {
      print('🗑️ [deleteTasksByTemplateId] START: templateId=$templateId, userId=$userId');
    }

    try {
      // templateIdのみでクエリ（グループタスクも含めて削除）
      final querySnapshot = await _collection.where('templateId', isEqualTo: templateId).get();

      if (kDebugMode) {
        print('🗑️ [deleteTasksByTemplateId] Found ${querySnapshot.docs.length} tasks for templateId: $templateId');
        for (final doc in querySnapshot.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final scheduledDate = (data['scheduledDate'] as Timestamp?)?.toDate();
          final isDeleted = data['isDeleted'] ?? false;
          print('  📋 Task: ${doc.id}, scheduledDate: $scheduledDate, isDeleted: $isDeleted');
        }
      }

      if (querySnapshot.docs.isNotEmpty) {
        // 最初のタスクから権限チェック（全て同じグループまたは個人タスク）
        final firstTaskData = querySnapshot.docs.first.data() as Map<String, dynamic>;
        final groupId = firstTaskData['groupId'] as String?;

        if (groupId != null) {
          // グループタスクの場合は権限チェック
          final groupDoc = await FirebaseFirestore.instance.collection('groups').doc(groupId).get();

          if (!groupDoc.exists) {
            throw Exception(AppMessages.errorGroupNotFound);
          }

          final memberRoles = groupDoc.data()?['memberRoles'] as Map<String, dynamic>?;
          final roleString = memberRoles?[userId] as String?;

          if (roleString == null) {
            throw Exception(AppMessages.errorNotGroupMember);
          }

          final role = GroupRoleExtension.fromFirestore(roleString);
          if (!GroupPermission.canDeleteTemplate(role)) {
            throw Exception(AppMessages.errorNoDeleteTemplatePermission);
          }
        } else {
          // 個人タスクの場合は作成者のみ削除可能
          final taskUserId = firstTaskData['userId'] as String?;
          if (taskUserId != userId) {
            throw Exception(AppMessages.errorOnlyOwnSchedule);
          }
        }
      }

      // タスクを物理削除
      final batch = _firestore.batch();
      for (final doc in querySnapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      if (kDebugMode) {
        print('✅ [deleteTasksByTemplateId] Successfully deleted all tasks for templateId: $templateId');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ [deleteTasksByTemplateId] Error deleting tasks: $e');
      }
      if (e.toString().contains('Exception:')) {
        rethrow;
      }
      throw Exception(AppMessages.errorTasksDeleteByTemplateFailed);
    }
  }

  /// テンプレートに紐づく未完了タスクのみ削除
  Future<void> deleteIncompleteTasksByTemplateId(String templateId, String userId) async {
    try {
      // templateIdのみでクエリ（グループタスクも含めて削除）
      final querySnapshot =
          await _collection.where('templateId', isEqualTo: templateId).where('completedAt', isNull: true).get();

      // タスクを1件ずつ削除
      for (final doc in querySnapshot.docs) {
        await doc.reference.delete();
      }
    } catch (e) {
      throw Exception('未完了タスクの削除に失敗しました: $e');
    }
  }

  /// テンプレートに紐づく未完了タスクの繰り返し情報を更新
  Future<void> updateIncompleteTasksRepeatInfo(
    String templateId,
    String repeatType,
    List<int>? weekdays,
    int? repeatInterval,
    int? monthlyDay,
  ) async {
    try {
      // templateIdの未完了タスクを取得
      final querySnapshot =
          await _collection.where('templateId', isEqualTo: templateId).where('completedAt', isNull: true).get();

      // バッチで更新
      final batch = _firestore.batch();
      for (final doc in querySnapshot.docs) {
        batch.update(doc.reference, {
          'repeatType': repeatType,
          'weekdays': weekdays,
          'repeatInterval': repeatInterval,
          'monthlyDay': monthlyDay,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
    } catch (e) {
      throw Exception('タスクの繰り返し情報更新に失敗しました: $e');
    }
  }

  /// テンプレートに紐づく未完了タスクのタイトルと説明を更新
  Future<void> updateIncompleteTasksTitleAndDescription(
    String templateId,
    String title,
    String description,
  ) async {
    try {
      // templateIdの未完了タスクを取得
      final querySnapshot =
          await _collection.where('templateId', isEqualTo: templateId).where('completedAt', isNull: true).get();

      // バッチで更新
      final batch = _firestore.batch();
      for (final doc in querySnapshot.docs) {
        batch.update(doc.reference, {
          'title': title,
          'description': description,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
    } catch (e) {
      throw Exception('タスクのタイトルと説明の更新に失敗しました: $e');
    }
  }

  /// タスクを取得
  Future<Task?> getTask(String taskId) async {
    try {
      final doc = await _collection.doc(taskId).get();
      if (!doc.exists) {
        return null;
      }
      return Task.fromFirestore(doc);
    } catch (e) {
      throw Exception('タスクの取得に失敗しました: $e');
    }
  }

  /// 今日のタスク一覧を取得
  Future<List<Task>> getTodayTasks(String userId) async {
    try {
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final endOfDay = DateTime(today.year, today.month, today.day, 23, 59, 59, 999);

      final querySnapshot = await _collection
          .where('userId', isEqualTo: userId)
          .where('isDeleted', isEqualTo: false)
          .where('scheduledDate', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('scheduledDate', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
          .orderBy('scheduledDate')
          .get();

      return querySnapshot.docs.map((doc) => Task.fromFirestore(doc)).toList();
    } catch (e) {
      throw Exception('今日のタスク一覧の取得に失敗しました: $e');
    }
  }

  /// 指定日のタスク一覧を取得
  Future<List<Task>> getTasksByDate(String userId, DateTime date) async {
    try {
      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59);

      final querySnapshot = await _collection
          .where('userId', isEqualTo: userId)
          .where('isDeleted', isEqualTo: false)
          .where('scheduledDate', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('scheduledDate', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
          .orderBy('scheduledDate')
          .get();

      return querySnapshot.docs.map((doc) => Task.fromFirestore(doc)).toList();
    } catch (e) {
      throw Exception('指定日のタスク一覧の取得に失敗しました: $e');
    }
  }

  /// 期間内のタスク一覧を取得
  Future<List<Task>> getTasksByDateRange(String userId, DateTime startDate, DateTime endDate) async {
    try {
      final startOfDay = DateTime(startDate.year, startDate.month, startDate.day);
      final endOfDay = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);

      final querySnapshot = await _collection
          .where('userId', isEqualTo: userId)
          .where('isDeleted', isEqualTo: false)
          .where('scheduledDate', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('scheduledDate', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
          .orderBy('scheduledDate')
          .get();

      return querySnapshot.docs.map((doc) => Task.fromFirestore(doc)).toList();
    } catch (e) {
      throw Exception('期間内のタスク一覧の取得に失敗しました: $e');
    }
  }

  /// 未完了のタスク一覧を取得
  Future<List<Task>> getIncompleteTasks(String userId) async {
    try {
      final querySnapshot = await _collection
          .where('userId', isEqualTo: userId)
          .where('isDeleted', isEqualTo: false)
          .where('completedAt', isNull: true)
          .orderBy('scheduledDate')
          .get();

      return querySnapshot.docs.map((doc) => Task.fromFirestore(doc)).toList();
    } catch (e) {
      throw Exception('未完了タスク一覧の取得に失敗しました: $e');
    }
  }

  /// 期限切れのタスク一覧を取得
  Future<List<Task>> getOverdueTasks(String userId) async {
    try {
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);

      final querySnapshot = await _collection
          .where('userId', isEqualTo: userId)
          .where('isDeleted', isEqualTo: false)
          .where('completedAt', isNull: true)
          .where('scheduledDate', isLessThan: Timestamp.fromDate(startOfDay))
          .orderBy('scheduledDate')
          .get();

      return querySnapshot.docs.map((doc) => Task.fromFirestore(doc)).toList();
    } catch (e) {
      throw Exception('期限切れタスク一覧の取得に失敗しました: $e');
    }
  }

  /// テンプレートに紐づくタスク一覧を取得
  Future<List<Task>> getTasksByTemplateId(String templateId) async {
    try {
      final querySnapshot = await _collection
          .where('templateId', isEqualTo: templateId)
          .where('isDeleted', isEqualTo: false)
          .orderBy('scheduledDate', descending: true)
          .get();

      return querySnapshot.docs.map((doc) => Task.fromFirestore(doc)).toList();
    } catch (e) {
      throw Exception('テンプレートに紐づくタスクの取得に失敗しました: $e');
    }
  }

  /// グループのタスク一覧を取得
  Future<List<Task>> getGroupTasks(String groupId) async {
    try {
      final querySnapshot = await _collection
          .where('groupId', isEqualTo: groupId)
          .where('isDeleted', isEqualTo: false)
          .orderBy('scheduledDate')
          .get();

      return querySnapshot.docs.map((doc) => Task.fromFirestore(doc)).toList();
    } catch (e) {
      throw Exception('グループタスクの取得に失敗しました: $e');
    }
  }

  /// 今日のタスクをリアルタイムで監視
  Stream<List<Task>> watchTodayTasks(String userId) {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = DateTime(today.year, today.month, today.day, 23, 59, 59, 999);

    // パフォーマンス最適化: 過去30日分のみ取得（それ以前の未完了タスクは非表示）
    final thirtyDaysAgo = startOfDay.subtract(const Duration(days: 30));

    return _collection
        .where('userId', isEqualTo: userId)
        .where('isDeleted', isEqualTo: false)
        .where('scheduledDate', isGreaterThanOrEqualTo: Timestamp.fromDate(thirtyDaysAgo))
        .where('scheduledDate', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
        .orderBy('scheduledDate')
        .snapshots()
        .map((snapshot) {
      // 今日のタスク + 過去の未完了タスクのみフィルタ
      return snapshot.docs.map((doc) => Task.fromFirestore(doc)).where((task) {
        final taskDate = task.scheduledDate;
        // 今日のタスク（0:00:00 〜 23:59:59.999）
        if (taskDate.isAtSameMomentAs(startOfDay) ||
            (taskDate.isAfter(startOfDay) && taskDate.isBefore(endOfDay.add(const Duration(milliseconds: 1))))) {
          return true;
        }
        // 過去のタスクは未完了のみ含める
        if (taskDate.isBefore(startOfDay)) {
          return !task.isCompleted;
        }
        return false;
      }).toList();
    });
  }

  /// 指定日のタスクをリアルタイムで監視
  Stream<List<Task>> watchTasksByDate(String userId, DateTime date) {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59);

    return _collection
        .where('userId', isEqualTo: userId)
        .where('isDeleted', isEqualTo: false)
        .where('scheduledDate', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('scheduledDate', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
        .orderBy('scheduledDate')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => Task.fromFirestore(doc)).toList());
  }

  /// グループタスクをリアルタイムで監視（今日と過去30日分）
  Stream<List<Task>> watchGroupTasks(String groupId) {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);

    // パフォーマンス最適化: 過去30日～未来のタスクを取得
    final thirtyDaysAgo = startOfDay.subtract(const Duration(days: 30));

    return _collection
        .where('groupId', isEqualTo: groupId)
        .where('isDeleted', isEqualTo: false)
        .where('isGroupSchedule', isEqualTo: true)
        .where('scheduledDate', isGreaterThanOrEqualTo: Timestamp.fromDate(thirtyDaysAgo))
        .orderBy('scheduledDate')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => Task.fromFirestore(doc)).toList());
  }

  /// 期間内のタスクをリアルタイムで監視
  Stream<List<Task>> watchTasksByDateRange(String userId, DateTime startDate, DateTime endDate) {
    final startOfDay = DateTime(startDate.year, startDate.month, startDate.day);
    final endOfDay = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);

    return _collection
        .where('userId', isEqualTo: userId)
        .where('isDeleted', isEqualTo: false)
        .where('scheduledDate', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('scheduledDate', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
        .orderBy('scheduledDate')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => Task.fromFirestore(doc)).toList());
  }

  /// グループタスクを期間指定で一度だけ取得（Future版）
  Future<List<Task>> getGroupTasksByDateRange(
    String groupId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    final startOfDay = DateTime(startDate.year, startDate.month, startDate.day);
    final endOfDay = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);

    final snapshot = await _collection
        .where('groupId', isEqualTo: groupId)
        .where('isDeleted', isEqualTo: false)
        .where('isGroupSchedule', isEqualTo: true)
        .where('scheduledDate', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('scheduledDate', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
        .orderBy('scheduledDate')
        .get();

    return snapshot.docs.map((doc) => Task.fromFirestore(doc)).toList();
  }
}
