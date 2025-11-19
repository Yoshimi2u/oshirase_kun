import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/completion_history.dart';

/// 完了履歴のCRUD操作を管理するリポジトリクラス
class CompletionHistoryRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collectionName = 'completion_history';

  /// ユーザーIDを基にしたコレクション参照を取得
  CollectionReference _getCollection(String userId) {
    return _firestore.collection('users').doc(userId).collection(_collectionName);
  }

  /// 完了履歴を作成
  Future<String> createCompletionHistory(CompletionHistory history) async {
    try {
      final docRef = _getCollection(history.userId).doc();
      final historyWithId = history.copyWith(id: docRef.id);
      await docRef.set(historyWithId.toFirestore());
      return docRef.id;
    } catch (e) {
      throw Exception('完了履歴の作成に失敗しました: $e');
    }
  }

  /// グループタスクの完了履歴を全メンバーに作成
  Future<void> createGroupCompletionHistory(
    List<String> memberIds,
    CompletionHistory history,
  ) async {
    try {
      final batch = _firestore.batch();

      for (final memberId in memberIds) {
        final docRef = _getCollection(memberId).doc();
        final historyForMember = history.copyWith(
          id: docRef.id,
          userId: memberId,
        );
        batch.set(docRef, historyForMember.toFirestore());
      }

      await batch.commit();
    } catch (e) {
      throw Exception('グループ完了履歴の作成に失敗しました: $e');
    }
  }

  /// 特定のスケジュールの完了履歴を取得
  Stream<List<CompletionHistory>> getCompletionHistoriesStream(
    String userId,
    String scheduleId,
  ) {
    return _getCollection(userId)
        .where('scheduleId', isEqualTo: scheduleId)
        .orderBy('completedDate', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => CompletionHistory.fromFirestore(doc)).toList();
    });
  }

  /// 特定の日の完了履歴を取得
  Stream<List<CompletionHistory>> getCompletionHistoriesByDateStream(
    String userId,
    DateTime date,
  ) {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    return _getCollection(userId)
        .where('completedDate', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('completedDate', isLessThan: Timestamp.fromDate(endOfDay))
        .orderBy('completedDate', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => CompletionHistory.fromFirestore(doc)).toList();
    });
  }

  /// ユーザーの全完了履歴を取得
  Stream<List<CompletionHistory>> getAllCompletionHistoriesStream(
    String userId,
  ) {
    return _getCollection(userId).orderBy('completedDate', descending: true).snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => CompletionHistory.fromFirestore(doc)).toList();
    });
  }

  /// 完了履歴を削除
  Future<void> deleteCompletionHistory(String userId, String historyId) async {
    try {
      await _getCollection(userId).doc(historyId).delete();
    } catch (e) {
      throw Exception('完了履歴の削除に失敗しました: $e');
    }
  }

  /// 特定のスケジュールに関連する全完了履歴を削除
  Future<void> deleteCompletionHistoriesByScheduleId(
    String userId,
    String scheduleId,
  ) async {
    try {
      final snapshot = await _getCollection(userId).where('scheduleId', isEqualTo: scheduleId).get();

      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (e) {
      throw Exception('スケジュールの完了履歴削除に失敗しました: $e');
    }
  }
}
