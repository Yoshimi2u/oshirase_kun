import 'package:cloud_firestore/cloud_firestore.dart';

/// タスクステータスの列挙型
enum TaskStatus {
  pending, // 未完了（期限内）
  overdue, // 遅延
  completed, // 完了済み
}

/// 個別タスク（予定テンプレートから生成される実際のタスク）
class Task {
  final String id;
  final String userId;
  final String templateId; // 親テンプレートへの参照
  final String title; // テンプレートから継承
  final String description; // テンプレートから継承
  final DateTime scheduledDate; // この個別タスクの予定日
  final DateTime? completedAt; // 完了日時
  final String? completedByMemberId; // 完了したメンバーのUID（グループ予定用）

  // グループ予定用フィールド
  final String? groupId;
  final bool isGroupSchedule;

  // 繰り返し情報（表示用にテンプレートから埋め込み）
  final String repeatType; // 'none', 'daily', 'weekly', 'monthly', 'customWeekly', 'custom'
  final List<int>? weekdays; // 週の繰り返しの場合 [1,2,3,4,5,6,7]
  final int? repeatInterval; // カスタム繰り返しの場合の日数
  final int? monthlyDay; // 毎月の指定日（1〜28）

  final DateTime createdAt;
  final DateTime updatedAt;

  Task({
    required this.id,
    required this.userId,
    required this.templateId,
    required this.title,
    required this.description,
    required this.scheduledDate,
    this.completedAt,
    this.completedByMemberId,
    this.groupId,
    this.isGroupSchedule = false,
    this.repeatType = 'none',
    this.weekdays,
    this.repeatInterval,
    this.monthlyDay,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Firestoreドキュメントから Task オブジェクトを作成
  factory Task.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Task(
      id: doc.id,
      userId: data['userId'] ?? '',
      templateId: data['templateId'] ?? '',
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      scheduledDate: (data['scheduledDate'] as Timestamp).toDate(),
      completedAt: data['completedAt'] != null ? (data['completedAt'] as Timestamp).toDate() : null,
      completedByMemberId: data['completedByMemberId'],
      groupId: data['groupId'],
      isGroupSchedule: data['isGroupSchedule'] ?? false,
      repeatType: data['repeatType'] ?? 'none',
      weekdays: data['weekdays'] != null ? List<int>.from(data['weekdays']) : null,
      repeatInterval: data['repeatInterval'],
      monthlyDay: data['monthlyDay'],
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
    );
  }

  /// Firestore に保存するためのマップに変換
  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'templateId': templateId,
      'title': title,
      'description': description,
      'scheduledDate': Timestamp.fromDate(scheduledDate),
      'completedAt': completedAt != null ? Timestamp.fromDate(completedAt!) : null,
      'completedByMemberId': completedByMemberId,
      'groupId': groupId,
      'isGroupSchedule': isGroupSchedule,
      'repeatType': repeatType,
      'weekdays': weekdays,
      'repeatInterval': repeatInterval,
      'monthlyDay': monthlyDay,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  /// コピーを作成（一部のフィールドを変更可能）
  Task copyWith({
    String? id,
    String? userId,
    String? templateId,
    String? title,
    String? description,
    DateTime? scheduledDate,
    DateTime? completedAt,
    String? completedByMemberId,
    String? groupId,
    bool? isGroupSchedule,
    String? repeatType,
    List<int>? weekdays,
    int? repeatInterval,
    int? monthlyDay,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Task(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      templateId: templateId ?? this.templateId,
      title: title ?? this.title,
      description: description ?? this.description,
      scheduledDate: scheduledDate ?? this.scheduledDate,
      completedAt: completedAt ?? this.completedAt,
      completedByMemberId: completedByMemberId ?? this.completedByMemberId,
      groupId: groupId ?? this.groupId,
      isGroupSchedule: isGroupSchedule ?? this.isGroupSchedule,
      repeatType: repeatType ?? this.repeatType,
      weekdays: weekdays ?? this.weekdays,
      repeatInterval: repeatInterval ?? this.repeatInterval,
      monthlyDay: monthlyDay ?? this.monthlyDay,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// 現在のステータスを取得
  TaskStatus getStatus() {
    if (completedAt != null) {
      return TaskStatus.completed;
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final scheduled = DateTime(
      scheduledDate.year,
      scheduledDate.month,
      scheduledDate.day,
    );

    if (scheduled.isBefore(today)) {
      return TaskStatus.overdue;
    }

    return TaskStatus.pending;
  }

  /// ステータスのラベルを取得
  String get statusLabel {
    switch (getStatus()) {
      case TaskStatus.pending:
        return '予定';
      case TaskStatus.overdue:
        return '遅延';
      case TaskStatus.completed:
        return '完了済み';
    }
  }

  /// 今日のタスクかどうか
  bool get isToday {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final scheduled = DateTime(
      scheduledDate.year,
      scheduledDate.month,
      scheduledDate.day,
    );
    return scheduled.isAtSameMomentAs(today);
  }

  /// 完了済みかどうか
  bool get isCompleted => completedAt != null;

  /// 繰り返し情報の表示テキストを取得
  String get repeatDisplayText {
    switch (repeatType) {
      case 'daily':
        return '毎日';
      case 'customWeekly':
        if (weekdays == null || weekdays!.isEmpty) return '毎週';
        final dayNames = ['月', '火', '水', '木', '金', '土', '日'];
        final selectedDays = weekdays!.map((day) => dayNames[day - 1]).join('・');
        return '毎週$selectedDays';
      case 'monthly':
        if (monthlyDay == null || monthlyDay! < 1 || monthlyDay! > 28) return '毎月';
        return '毎月${monthlyDay}日';
      case 'monthlyLastDay':
        return '毎月末日';
      case 'custom':
        if (repeatInterval == null || repeatInterval! <= 1) return '';
        return '$repeatInterval日ごと';
      case 'none':
      default:
        return '';
    }
  }

  /// 繰り返し設定があるかどうか
  bool get hasRepeat => repeatType != 'none';
}
