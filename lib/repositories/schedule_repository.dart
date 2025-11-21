import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/schedule.dart';
import '../models/group.dart';
import '../models/completion_history.dart';
import 'completion_history_repository.dart';

/// 予定のCRUD操作を管理するリポジトリクラス
class ScheduleRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collectionName = 'schedules';
  final CompletionHistoryRepository _completionHistoryRepository = CompletionHistoryRepository();

  /// ユーザーIDを基にしたコレクション参照を取得
  CollectionReference _getCollection(String userId) {
    return _firestore.collection('users').doc(userId).collection(_collectionName);
  }

  /// 予定を作成
  Future<String> createSchedule(String userId, Schedule schedule) async {
    try {
      // グループ予定の場合は全メンバーに作成
      if (schedule.isGroupSchedule && schedule.groupId != null) {
        final result = await _createGroupSchedule(userId, schedule);
        return result;
      }

      // 個人予定の作成
      final docRef = _getCollection(userId).doc();
      final scheduleWithId = schedule.copyWith(id: docRef.id);
      await docRef.set(scheduleWithId.toFirestore());
      return docRef.id;
    } catch (e) {
      throw Exception('予定の作成に失敗しました: $e');
    }
  }

  /// グループ予定を作成（全メンバーに作成）
  Future<String> _createGroupSchedule(String userId, Schedule schedule) async {
    // グループ情報を取得
    final groupDoc = await _firestore.collection('groups').doc(schedule.groupId).get();
    if (!groupDoc.exists) {
      throw Exception('グループが見つかりません');
    }

    final group = Group.fromFirestore(groupDoc);

    // IDを生成
    final scheduleId = _getCollection(userId).doc().id;
    final scheduleWithId = schedule.copyWith(id: scheduleId);

    // バッチ処理で全メンバーに予定を作成
    final batch = _firestore.batch();

    for (final memberId in group.memberIds) {
      final memberScheduleRef = _getCollection(memberId).doc(scheduleId);
      final data = scheduleWithId.toFirestore();
      batch.set(memberScheduleRef, data);
    }

    // バッチ実行
    await batch.commit();
    return scheduleId;
  }

  /// 予定を更新
  Future<void> updateSchedule(String userId, Schedule schedule) async {
    try {
      // updatedAtを現在時刻に更新
      final updatedSchedule = schedule.copyWith(updatedAt: DateTime.now());

      // グループ予定の場合は全メンバーの予定を更新
      if (updatedSchedule.isGroupSchedule && updatedSchedule.groupId != null) {
        await _updateGroupSchedule(updatedSchedule);
        return;
      }

      // 個人予定の更新（set with merge を使用）
      await _getCollection(userId).doc(updatedSchedule.id).set(
            updatedSchedule.toFirestore(),
            SetOptions(merge: true),
          );
    } catch (e) {
      throw Exception('予定の更新に失敗しました: $e');
    }
  }

  /// グループ予定を更新（全メンバーの予定を更新）
  Future<void> _updateGroupSchedule(Schedule schedule) async {
    // グループ情報を取得
    final groupDoc = await _firestore.collection('groups').doc(schedule.groupId).get();
    if (!groupDoc.exists) {
      throw Exception('グループが見つかりません');
    }

    final group = Group.fromFirestore(groupDoc);

    // バッチ処理で全メンバーの予定を更新
    final batch = _firestore.batch();

    for (final memberId in group.memberIds) {
      final memberScheduleRef = _getCollection(memberId).doc(schedule.id);
      batch.set(memberScheduleRef, schedule.toFirestore(), SetOptions(merge: true));
    }

    // バッチ実行
    await batch.commit();
  }

  /// 予定を削除
  Future<void> deleteSchedule(String userId, String scheduleId) async {
    try {
      // 削除する予定を取得してグループ予定かチェック
      final schedule = await getSchedule(userId, scheduleId);
      if (schedule != null && schedule.isGroupSchedule && schedule.groupId != null) {
        await _deleteGroupSchedule(schedule);
        return;
      }

      // 個人予定の削除
      await _getCollection(userId).doc(scheduleId).delete();
    } catch (e) {
      throw Exception('予定の削除に失敗しました: $e');
    }
  }

  /// グループ予定を削除（全メンバーの予定を削除）
  Future<void> _deleteGroupSchedule(Schedule schedule) async {
    // グループ情報を取得
    final groupDoc = await _firestore.collection('groups').doc(schedule.groupId).get();
    if (!groupDoc.exists) {
      throw Exception('グループが見つかりません');
    }

    final group = Group.fromFirestore(groupDoc);

    // バッチ処理で全メンバーの予定を削除
    final batch = _firestore.batch();

    for (final memberId in group.memberIds) {
      final memberScheduleRef = _getCollection(memberId).doc(schedule.id);
      batch.delete(memberScheduleRef);
    }

    // バッチ実行
    await batch.commit();
  }

  /// 特定の予定を取得
  Future<Schedule?> getSchedule(String userId, String scheduleId) async {
    try {
      final doc = await _getCollection(userId).doc(scheduleId).get();
      if (doc.exists) {
        return Schedule.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      throw Exception('予定の取得に失敗しました: $e');
    }
  }

  /// すべての予定をストリームで取得
  Stream<List<Schedule>> getSchedulesStream(String userId) {
    return _getCollection(userId).orderBy('createdAt', descending: true).snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => Schedule.fromFirestore(doc)).toList();
    });
  }

  /// アクティブな予定のみを取得
  Stream<List<Schedule>> getActiveSchedulesStream(String userId) {
    return _getCollection(userId)
        .where('isActive', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => Schedule.fromFirestore(doc)).toList();
    });
  }

  /// すべての予定を一度だけ取得
  Future<List<Schedule>> getAllSchedules(String userId) async {
    try {
      final snapshot = await _getCollection(userId).orderBy('createdAt', descending: true).get();
      return snapshot.docs.map((doc) => Schedule.fromFirestore(doc)).toList();
    } catch (e) {
      throw Exception('予定の取得に失敗しました: $e');
    }
  }

  /// 予定を完了する
  Future<void> completeSchedule(String userId, Schedule schedule) async {
    try {
      final now = DateTime.now();
      final completedDate = DateTime(now.year, now.month, now.day);

      // グループ予定の場合は全メンバーの予定を完了
      if (schedule.isGroupSchedule && schedule.groupId != null) {
        await _completeGroupSchedule(userId, schedule, completedDate);
        return;
      }

      // 個人予定の完了処理
      await _completePersonalSchedule(userId, schedule, completedDate);
    } catch (e) {
      throw Exception('予定の完了処理に失敗しました: $e');
    }
  }

  /// 個人予定の完了処理
  Future<void> _completePersonalSchedule(
    String userId,
    Schedule schedule,
    DateTime completedDate,
  ) async {
    // 完了履歴を別コレクションに保存
    final completionHistory = CompletionHistory(
      id: '', // createCompletionHistoryで自動生成
      scheduleId: schedule.id,
      userId: userId,
      completedDate: completedDate,
      completedByMemberId: userId,
      completedByMemberName: null, // 個人タスクなので不要
      groupId: null,
      scheduleTitle: schedule.title,
      createdAt: DateTime.now(),
    );
    await _completionHistoryRepository.createCompletionHistory(completionHistory);

    // 次回予定日を計算
    DateTime? nextDate;
    if (schedule.repeatType == RepeatType.custom) {
      // カスタム（何日ごと）の場合
      if (schedule.requiresCompletion) {
        // 完了必須：完了日から次の予定を計算
        nextDate = schedule.calculateNextScheduledDate();
      } else {
        // 完了不要：元のnextScheduledDateを維持（Cloud Functionsが自動更新）
        nextDate = schedule.nextScheduledDate;
      }
    } else {
      // その他の繰り返しは元のnextScheduledDateを維持（Cloud Functionsが自動更新）
      nextDate = schedule.nextScheduledDate;
    }

    // スケジュールの lastCompletedDate と nextScheduledDate のみ更新
    // completionHistory配列は廃止（後方互換性のため残すが更新しない）
    await _getCollection(userId).doc(schedule.id).update({
      'lastCompletedDate': Timestamp.fromDate(completedDate),
      'nextScheduledDate': nextDate != null ? Timestamp.fromDate(nextDate) : null,
      'updatedAt': Timestamp.now(),
    });
  }

  /// グループ予定の完了処理（全メンバーの予定を完了）
  Future<void> _completeGroupSchedule(
    String userId,
    Schedule schedule,
    DateTime completedDate,
  ) async {
    // グループ情報を取得
    final groupDoc = await _firestore.collection('groups').doc(schedule.groupId).get();
    if (!groupDoc.exists) {
      throw Exception('グループが見つかりません');
    }

    final group = Group.fromFirestore(groupDoc);

    // 完了したユーザーの情報を取得
    final userDoc = await _firestore.collection('users').doc(userId).get();
    final completedByName = userDoc.data()?['displayName'] as String?;

    // 完了履歴を全メンバーに保存
    final completionHistory = CompletionHistory(
      id: '', // createGroupCompletionHistoryで自動生成
      scheduleId: schedule.id,
      userId: '', // メンバーごとに設定される
      completedDate: completedDate,
      completedByMemberId: userId,
      completedByMemberName: completedByName,
      groupId: schedule.groupId,
      scheduleTitle: schedule.title,
      createdAt: DateTime.now(),
    );
    await _completionHistoryRepository.createGroupCompletionHistory(
      group.memberIds,
      completionHistory,
    );

    // 次回予定日を計算
    DateTime? nextDate;
    if (schedule.requiresCompletion) {
      nextDate = schedule.calculateNextScheduledDate();
    } else {
      nextDate = schedule.calculateNextScheduledDate();
    }

    // バッチ処理で全メンバーの予定を更新
    final batch = _firestore.batch();

    // 全メンバーの予定を更新
    for (final memberId in group.memberIds) {
      final memberScheduleRef = _getCollection(memberId).doc(schedule.id);

      batch.update(memberScheduleRef, {
        'lastCompletedDate': Timestamp.fromDate(completedDate),
        'nextScheduledDate': nextDate != null ? Timestamp.fromDate(nextDate) : null,
        'completedByMemberId': userId,
        'groupCompletedAt': Timestamp.fromDate(completedDate),
        'updatedAt': Timestamp.now(),
      });
    }

    // バッチ実行
    await batch.commit();
  }

  /// 今日のタスクを取得
  Stream<List<Schedule>> getTodaySchedulesStream(String userId) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    return _getCollection(userId)
        .where('nextScheduledDate', isGreaterThanOrEqualTo: Timestamp.fromDate(today))
        .where('nextScheduledDate', isLessThan: Timestamp.fromDate(tomorrow))
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => Schedule.fromFirestore(doc)).toList();
    });
  }

  /// 遅延タスクを取得
  Stream<List<Schedule>> getOverdueSchedulesStream(String userId) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return _getCollection(userId)
        .where('nextScheduledDate', isLessThan: Timestamp.fromDate(today))
        .orderBy('nextScheduledDate', descending: false)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => Schedule.fromFirestore(doc)).toList();
    });
  }

  /// 予定済みタスク(今日以降)を取得
  Stream<List<Schedule>> getUpcomingSchedulesStream(String userId) {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));

    return _getCollection(userId)
        .where('nextScheduledDate', isGreaterThanOrEqualTo: Timestamp.fromDate(tomorrow))
        .orderBy('nextScheduledDate', descending: false)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => Schedule.fromFirestore(doc)).toList();
    });
  }

  /// 今日完了したタスクを取得
  Stream<List<Schedule>> getTodayCompletedSchedulesStream(String userId) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    return _getCollection(userId)
        .where('lastCompletedDate', isGreaterThanOrEqualTo: Timestamp.fromDate(today))
        .where('lastCompletedDate', isLessThan: Timestamp.fromDate(tomorrow))
        .orderBy('lastCompletedDate', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => Schedule.fromFirestore(doc)).toList();
    });
  }
}
