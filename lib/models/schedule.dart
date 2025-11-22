import 'package:cloud_firestore/cloud_firestore.dart';

/// 繰り返しタイプの列挙型
enum RepeatType {
  none, // 繰り返しなし
  daily, // 毎日
  customWeekly, // 曜日指定
  monthly, // 毎月
  custom, // カスタム（〇日ごと）
}

/// RepeatType拡張メソッド
extension RepeatTypeExtension on RepeatType {
  /// Firestore保存用の文字列（"customWeekly"形式）
  String get value => name;

  /// 文字列からRepeatTypeを取得
  static RepeatType fromString(String value) {
    return RepeatType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => RepeatType.none,
    );
  }
}

/// タスクステータスの列挙型
enum ScheduleStatus {
  pending, // 未完了（期限内）
  overdue, // 遅延
  completed, // 完了済み
}

/// 予定を管理するモデルクラス
class Schedule {
  final String id;
  final String title;
  final String description;
  final RepeatType repeatType; // 繰り返しタイプ
  final int? repeatInterval; // カスタム繰り返しの間隔（日数）
  final List<int>? selectedWeekdays; // 選択された曜日リスト（1=月曜, 7=日曜）
  final int? monthlyDay; // 毎月の指定日（1〜28）
  final DateTime? startDate; // 最初の予定日（繰り返し開始日）
  final DateTime? endDate; // 繰り返し終了日（任意）
  final bool isActive; // 通知の有効/無効

  // 新しいフィールド
  final DateTime? nextScheduledDate; // 次回予定日
  final DateTime? lastCompletedDate; // 最終完了日
  final bool requiresCompletion; // 完了必須フラグ（true: 完了するまで次の予定を作らない）
  final List<DateTime> completionHistory; // 完了履歴

  // グループ予定用フィールド
  final String? groupId; // 所属グループID（グループ予定の場合のみ）
  final bool isGroupSchedule; // グループ予定フラグ
  final String? completedByMemberId; // 完了したメンバーのUID（グループ予定用）
  final DateTime? groupCompletedAt; // グループ全体の完了日時（グループ予定用）

  final DateTime createdAt;
  final DateTime updatedAt;

  Schedule({
    required this.id,
    required this.title,
    required this.description,
    this.repeatType = RepeatType.none,
    this.repeatInterval,
    this.selectedWeekdays,
    this.monthlyDay,
    this.startDate,
    this.endDate,
    this.isActive = true,
    this.nextScheduledDate,
    this.lastCompletedDate,
    this.requiresCompletion = false,
    this.completionHistory = const [],
    this.groupId,
    this.isGroupSchedule = false,
    this.completedByMemberId,
    this.groupCompletedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Firestoreドキュメントから Schedule オブジェクトを作成
  factory Schedule.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Schedule(
      id: doc.id,
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      repeatType: RepeatTypeExtension.fromString(
        data['repeatType'] ?? 'none',
      ),
      repeatInterval: data['repeatInterval'],
      selectedWeekdays: (data['selectedWeekdays'] as List<dynamic>?)?.map((e) => e as int).toList(),
      monthlyDay: data['monthlyDay'],
      startDate: data['startDate'] != null ? (data['startDate'] as Timestamp).toDate() : null,
      endDate: data['endDate'] != null ? (data['endDate'] as Timestamp).toDate() : null,
      isActive: data['isActive'] ?? true,
      nextScheduledDate: data['nextScheduledDate'] != null ? (data['nextScheduledDate'] as Timestamp).toDate() : null,
      lastCompletedDate: data['lastCompletedDate'] != null ? (data['lastCompletedDate'] as Timestamp).toDate() : null,
      requiresCompletion: data['requiresCompletion'] ?? false,
      completionHistory:
          (data['completionHistory'] as List<dynamic>?)?.map((e) => (e as Timestamp).toDate()).toList() ?? [],
      groupId: data['groupId'],
      isGroupSchedule: data['isGroupSchedule'] ?? false,
      completedByMemberId: data['completedByMemberId'],
      groupCompletedAt: data['groupCompletedAt'] != null ? (data['groupCompletedAt'] as Timestamp).toDate() : null,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
    );
  }

  /// Firestore に保存するためのマップに変換
  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'description': description,
      'repeatType': repeatType.value,
      'repeatInterval': repeatInterval,
      'selectedWeekdays': selectedWeekdays,
      'monthlyDay': monthlyDay,
      'startDate': startDate != null ? Timestamp.fromDate(startDate!) : null,
      'endDate': endDate != null ? Timestamp.fromDate(endDate!) : null,
      'isActive': isActive,
      'nextScheduledDate': nextScheduledDate != null ? Timestamp.fromDate(nextScheduledDate!) : null,
      'lastCompletedDate': lastCompletedDate != null ? Timestamp.fromDate(lastCompletedDate!) : null,
      'requiresCompletion': requiresCompletion,
      'completionHistory': completionHistory.map((date) => Timestamp.fromDate(date)).toList(),
      'groupId': groupId,
      'isGroupSchedule': isGroupSchedule,
      'completedByMemberId': completedByMemberId,
      'groupCompletedAt': groupCompletedAt != null ? Timestamp.fromDate(groupCompletedAt!) : null,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  /// コピーを作成（一部のフィールドを変更可能）
  Schedule copyWith({
    String? id,
    String? title,
    String? description,
    RepeatType? repeatType,
    int? repeatInterval,
    List<int>? selectedWeekdays,
    int? monthlyDay,
    DateTime? startDate,
    DateTime? endDate,
    bool? isActive,
    DateTime? nextScheduledDate,
    DateTime? lastCompletedDate,
    bool? requiresCompletion,
    List<DateTime>? completionHistory,
    String? groupId,
    bool? isGroupSchedule,
    String? completedByMemberId,
    DateTime? groupCompletedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Schedule(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      repeatType: repeatType ?? this.repeatType,
      repeatInterval: repeatInterval ?? this.repeatInterval,
      selectedWeekdays: selectedWeekdays ?? this.selectedWeekdays,
      monthlyDay: monthlyDay ?? this.monthlyDay,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      isActive: isActive ?? this.isActive,
      nextScheduledDate: nextScheduledDate ?? this.nextScheduledDate,
      lastCompletedDate: lastCompletedDate ?? this.lastCompletedDate,
      requiresCompletion: requiresCompletion ?? this.requiresCompletion,
      completionHistory: completionHistory ?? this.completionHistory,
      groupId: groupId ?? this.groupId,
      isGroupSchedule: isGroupSchedule ?? this.isGroupSchedule,
      completedByMemberId: completedByMemberId ?? this.completedByMemberId,
      groupCompletedAt: groupCompletedAt ?? this.groupCompletedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// 現在のステータスを取得
  ScheduleStatus getStatus() {
    if (nextScheduledDate == null) {
      return ScheduleStatus.completed;
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final scheduledDay = DateTime(
      nextScheduledDate!.year,
      nextScheduledDate!.month,
      nextScheduledDate!.day,
    );

    if (scheduledDay.isBefore(today)) {
      return ScheduleStatus.overdue;
    }

    return ScheduleStatus.pending;
  }

  /// ステータスの日本語表示
  String get statusLabel {
    switch (getStatus()) {
      case ScheduleStatus.pending:
        return '予定';
      case ScheduleStatus.overdue:
        return '遅延';
      case ScheduleStatus.completed:
        return '完了済み';
    }
  }

  /// 今日のタスクかどうか
  bool get isToday {
    if (nextScheduledDate == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final scheduledDay = DateTime(
      nextScheduledDate!.year,
      nextScheduledDate!.month,
      nextScheduledDate!.day,
    );
    return scheduledDay.isAtSameMomentAs(today);
  }

  /// 次回予定日を計算
  DateTime? calculateNextScheduledDate() {
    // startDateがない場合は現在の日付を基準にする
    final baseDate = lastCompletedDate ?? startDate ?? DateTime.now();

    switch (repeatType) {
      case RepeatType.none:
        // 繰り返しなしの場合、完了したらnull
        return null;

      case RepeatType.daily:
        return DateTime(
          baseDate.year,
          baseDate.month,
          baseDate.day + 1,
        );

      case RepeatType.customWeekly:
        // 複数曜日指定
        if (selectedWeekdays == null || selectedWeekdays!.isEmpty) return null;
        return _findNextWeekday(baseDate, selectedWeekdays!);

      case RepeatType.monthly:
        // monthlyDayが指定されている場合はその日を使用
        final targetDay = monthlyDay ?? baseDate.day;
        // 28日を超える場合は28日に制限
        final day = targetDay > 28 ? 28 : targetDay;

        // 次の月の同じ日を計算
        int nextMonth = baseDate.month + 1;
        int nextYear = baseDate.year;
        if (nextMonth > 12) {
          nextMonth = 1;
          nextYear++;
        }

        return DateTime(nextYear, nextMonth, day);

      case RepeatType.custom:
        if (repeatInterval == null || repeatInterval! <= 0) return null;
        return DateTime(
          baseDate.year,
          baseDate.month,
          baseDate.day + repeatInterval!,
        );
    }
  }

  /// 指定された曜日リストから次回の日付を検索
  DateTime _findNextWeekday(DateTime baseDate, List<int> weekdays) {
    DateTime nextDate = DateTime(baseDate.year, baseDate.month, baseDate.day + 1);

    // 最大14日先まで検索（2週間分）
    for (int i = 0; i < 14; i++) {
      // DateTime.weekdayは1=月曜, 7=日曜
      if (weekdays.contains(nextDate.weekday)) {
        return nextDate;
      }
      nextDate = nextDate.add(const Duration(days: 1));
    }

    // 見つからない場合は翌日を返す（フォールバック）
    return DateTime(baseDate.year, baseDate.month, baseDate.day + 1);
  }

  /// 繰り返しタイプの日本語表示
  String get repeatTypeLabel {
    switch (repeatType) {
      case RepeatType.none:
        return '繰り返しなし';
      case RepeatType.daily:
        return '毎日';
      case RepeatType.customWeekly:
        if (selectedWeekdays == null || selectedWeekdays!.isEmpty) {
          return '曜日指定';
        }
        final weekdayNames = ['月', '火', '水', '木', '金', '土', '日'];
        final names = selectedWeekdays!.map((day) => weekdayNames[day - 1]).join('・');
        return '毎週（$names）';
      case RepeatType.monthly:
        return '毎月';
      case RepeatType.custom:
        return '$repeatInterval日ごと';
    }
  }
}
