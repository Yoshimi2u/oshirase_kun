import 'package:cloud_firestore/cloud_firestore.dart';

/// 完了履歴を管理するモデルクラス
class CompletionHistory {
  final String id; // ドキュメントID
  final String scheduleId; // 関連するスケジュールID
  final String userId; // タスクを所有するユーザーID
  final DateTime completedDate; // 完了日
  final String? completedByMemberId; // 完了したメンバーのUID（グループタスク用）
  final String? completedByMemberName; // 完了したメンバーの名前（グループタスク用）
  final String? groupId; // グループID（グループタスク用）
  final String scheduleTitle; // タスクのタイトル（参照用）
  final DateTime createdAt; // 作成日時

  CompletionHistory({
    required this.id,
    required this.scheduleId,
    required this.userId,
    required this.completedDate,
    this.completedByMemberId,
    this.completedByMemberName,
    this.groupId,
    required this.scheduleTitle,
    required this.createdAt,
  });

  /// Firestoreドキュメントから CompletionHistory オブジェクトを作成
  factory CompletionHistory.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CompletionHistory(
      id: doc.id,
      scheduleId: data['scheduleId'] ?? '',
      userId: data['userId'] ?? '',
      completedDate: (data['completedDate'] as Timestamp).toDate(),
      completedByMemberId: data['completedByMemberId'],
      completedByMemberName: data['completedByMemberName'],
      groupId: data['groupId'],
      scheduleTitle: data['scheduleTitle'] ?? '',
      createdAt: (data['createdAt'] as Timestamp).toDate(),
    );
  }

  /// Firestore に保存するためのマップに変換
  Map<String, dynamic> toFirestore() {
    return {
      'scheduleId': scheduleId,
      'userId': userId,
      'completedDate': Timestamp.fromDate(completedDate),
      'completedByMemberId': completedByMemberId,
      'completedByMemberName': completedByMemberName,
      'groupId': groupId,
      'scheduleTitle': scheduleTitle,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  /// コピーを作成
  CompletionHistory copyWith({
    String? id,
    String? scheduleId,
    String? userId,
    DateTime? completedDate,
    String? completedByMemberId,
    String? completedByMemberName,
    String? groupId,
    String? scheduleTitle,
    DateTime? createdAt,
  }) {
    return CompletionHistory(
      id: id ?? this.id,
      scheduleId: scheduleId ?? this.scheduleId,
      userId: userId ?? this.userId,
      completedDate: completedDate ?? this.completedDate,
      completedByMemberId: completedByMemberId ?? this.completedByMemberId,
      completedByMemberName: completedByMemberName ?? this.completedByMemberName,
      groupId: groupId ?? this.groupId,
      scheduleTitle: scheduleTitle ?? this.scheduleTitle,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
