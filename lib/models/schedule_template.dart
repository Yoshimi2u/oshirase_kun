import 'package:cloud_firestore/cloud_firestore.dart';

/// 繰り返しタイプの列挙型
enum RepeatType {
  none, // 繰り返しなし
  daily, // 毎日
  customWeekly, // 曜日指定
  monthly, // 毎月
  monthlyLastDay, // 毎月末日
  custom, // カスタム（〇日ごと）
}

/// 予定テンプレート（繰り返し設定を保持する親要素）
class ScheduleTemplate {
  final String id;
  final String userId;
  final String title;
  final String description;
  final RepeatType repeatType;
  final int? repeatInterval; // カスタム繰り返しの間隔（日数）
  final List<int>? selectedWeekdays; // 選択された曜日リスト（1=月曜, 7=日曜）
  final int? monthlyDay; // 毎月の指定日（1〜28）
  final bool requiresCompletion; // 完了必須フラグ（カスタムのみ）
  final bool isActive; // テンプレートの有効/無効

  // グループ予定用フィールド
  final String? groupId;
  final bool isGroupSchedule;

  final DateTime createdAt;
  final DateTime updatedAt;

  ScheduleTemplate({
    required this.id,
    required this.userId,
    required this.title,
    required this.description,
    this.repeatType = RepeatType.none,
    this.repeatInterval,
    this.selectedWeekdays,
    this.monthlyDay,
    this.requiresCompletion = false,
    this.isActive = true,
    this.groupId,
    this.isGroupSchedule = false,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Firestoreドキュメントから ScheduleTemplate オブジェクトを作成
  factory ScheduleTemplate.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ScheduleTemplate(
      id: doc.id,
      userId: data['userId'] ?? '',
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      repeatType: RepeatType.values.firstWhere(
        (e) => e.toString() == data['repeatType'],
        orElse: () => RepeatType.none,
      ),
      repeatInterval: data['repeatInterval'],
      selectedWeekdays: (data['selectedWeekdays'] as List<dynamic>?)?.map((e) => e as int).toList(),
      monthlyDay: data['monthlyDay'],
      requiresCompletion: data['requiresCompletion'] ?? false,
      isActive: data['isActive'] ?? true,
      groupId: data['groupId'],
      isGroupSchedule: data['isGroupSchedule'] ?? false,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
    );
  }

  /// Firestore に保存するためのマップに変換
  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'title': title,
      'description': description,
      'repeatType': repeatType.toString(),
      'repeatInterval': repeatInterval,
      'selectedWeekdays': selectedWeekdays,
      'monthlyDay': monthlyDay,
      'requiresCompletion': requiresCompletion,
      'isActive': isActive,
      'groupId': groupId,
      'isGroupSchedule': isGroupSchedule,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  /// コピーを作成（一部のフィールドを変更可能）
  ScheduleTemplate copyWith({
    String? id,
    String? userId,
    String? title,
    String? description,
    RepeatType? repeatType,
    int? repeatInterval,
    List<int>? selectedWeekdays,
    int? monthlyDay,
    bool? requiresCompletion,
    bool? isActive,
    String? groupId,
    bool? isGroupSchedule,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ScheduleTemplate(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      description: description ?? this.description,
      repeatType: repeatType ?? this.repeatType,
      repeatInterval: repeatInterval ?? this.repeatInterval,
      selectedWeekdays: selectedWeekdays ?? this.selectedWeekdays,
      monthlyDay: monthlyDay ?? this.monthlyDay,
      requiresCompletion: requiresCompletion ?? this.requiresCompletion,
      isActive: isActive ?? this.isActive,
      groupId: groupId ?? this.groupId,
      isGroupSchedule: isGroupSchedule ?? this.isGroupSchedule,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// 繰り返しタイプのラベルを取得
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
        return '毎月${monthlyDay ?? 1}日';
      case RepeatType.monthlyLastDay:
        return '毎月末日';
      case RepeatType.custom:
        return '$repeatInterval日ごと';
    }
  }

  /// 次回のタスク予定日を計算
  DateTime calculateNextTaskDate(DateTime? lastCompletedDate) {
    final baseDate = lastCompletedDate ?? DateTime.now();

    switch (repeatType) {
      case RepeatType.none:
        // 繰り返しなしの場合は今日
        return DateTime(baseDate.year, baseDate.month, baseDate.day);

      case RepeatType.daily:
        return DateTime(
          baseDate.year,
          baseDate.month,
          baseDate.day + 1,
        );

      case RepeatType.customWeekly:
        // 曜日指定
        if (selectedWeekdays == null || selectedWeekdays!.isEmpty) {
          return DateTime(baseDate.year, baseDate.month, baseDate.day + 1);
        }
        return _findNextWeekday(baseDate, selectedWeekdays!);

      case RepeatType.monthly:
        // monthlyDayが指定されている場合はその日を使用
        final targetDay = monthlyDay ?? baseDate.day;
        final day = targetDay > 28 ? 28 : targetDay;

        int nextMonth = baseDate.month + 1;
        int nextYear = baseDate.year;
        if (nextMonth > 12) {
          nextMonth = 1;
          nextYear++;
        }

        return DateTime(nextYear, nextMonth, day);

      case RepeatType.monthlyLastDay:
        // 翌月の月末を計算
        int nextMonth = baseDate.month + 1;
        int nextYear = baseDate.year;
        if (nextMonth > 12) {
          nextMonth = 1;
          nextYear++;
        }

        // 翌月の末日を取得（翌々月の0日 = 翌月の末日）
        final lastDayOfNextMonth = DateTime(nextYear, nextMonth + 1, 0);
        return DateTime(lastDayOfNextMonth.year, lastDayOfNextMonth.month, lastDayOfNextMonth.day);

      case RepeatType.custom:
        if (repeatInterval == null || repeatInterval! <= 0) {
          return DateTime(baseDate.year, baseDate.month, baseDate.day + 1);
        }
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
      if (weekdays.contains(nextDate.weekday)) {
        return nextDate;
      }
      nextDate = nextDate.add(const Duration(days: 1));
    }

    // 見つからない場合は翌日を返す（フォールバック）
    return DateTime(baseDate.year, baseDate.month, baseDate.day + 1);
  }

  /// 翌月末までのタスク日付リストを生成
  /// カスタム（完了必須あり）の場合は初回のみ生成
  List<DateTime> generateTaskDatesUntilNextMonthEnd([DateTime? startDate]) {
    final baseDate = startDate ?? DateTime.now();
    final List<DateTime> dates = [];

    // カスタム（完了必須あり）の場合は初回のみ
    if (repeatType == RepeatType.custom && requiresCompletion) {
      // 開始日を使用
      final startDay = DateTime(baseDate.year, baseDate.month, baseDate.day);
      dates.add(startDay);
      return dates;
    }

    // 繰り返しなしの場合は初回のみ
    if (repeatType == RepeatType.none) {
      // 開始日を使用
      final startDay = DateTime(baseDate.year, baseDate.month, baseDate.day);
      dates.add(startDay);
      return dates;
    }

    // 翌月末日を計算
    final nextMonth = baseDate.month == 12 ? 1 : baseDate.month + 1;
    final nextMonthYear = baseDate.month == 12 ? baseDate.year + 1 : baseDate.year;
    final endOfNextMonth = DateTime(nextMonthYear, nextMonth + 1, 0); // 次の月の0日 = 翌月末

    // 初回日付を計算
    final today = DateTime(baseDate.year, baseDate.month, baseDate.day);
    DateTime currentDate;

    switch (repeatType) {
      case RepeatType.daily:
        // 毎日: 今日から開始
        currentDate = today;
        break;

      case RepeatType.customWeekly:
        // 曜日指定: 今日が該当曜日なら今日、そうでなければ次の該当曜日
        if (selectedWeekdays != null && selectedWeekdays!.contains(today.weekday)) {
          currentDate = today;
        } else {
          currentDate = calculateNextTaskDate(today.add(const Duration(days: -1)));
        }
        break;

      case RepeatType.monthly:
        // 毎月: monthlyDayが指定されている場合、今月または来月のその日から
        final targetDay = monthlyDay ?? today.day;
        final day = targetDay > 28 ? 28 : targetDay;

        if (day >= today.day) {
          // 今月のその日がまだ来ていないか今日なら今月から
          currentDate = DateTime(today.year, today.month, day);
        } else {
          // もう過ぎていれば来月から
          final nextMonth = today.month == 12 ? 1 : today.month + 1;
          final nextYear = today.month == 12 ? today.year + 1 : today.year;
          currentDate = DateTime(nextYear, nextMonth, day);
        }
        break;

      case RepeatType.monthlyLastDay:
        // 毎月末日: 今月の末日がまだ来ていないか今日なら今月の末日、過ぎていれば来月の末日
        final lastDayOfThisMonth = DateTime(today.year, today.month + 1, 0);

        if (lastDayOfThisMonth.day >= today.day) {
          currentDate = DateTime(lastDayOfThisMonth.year, lastDayOfThisMonth.month, lastDayOfThisMonth.day);
        } else {
          // 来月の末日
          final lastDayOfNextMonth = DateTime(today.year, today.month + 2, 0);
          currentDate = DateTime(lastDayOfNextMonth.year, lastDayOfNextMonth.month, lastDayOfNextMonth.day);
        }
        break;

      case RepeatType.custom:
        // カスタム: 今日から開始
        currentDate = today;
        break;

      case RepeatType.none:
        // 繰り返しなし: calculateNextTaskDateで処理されるので到達しないが、念のため
        currentDate = today;
        break;
    }

    // 翌月末まで生成
    while (currentDate.isBefore(endOfNextMonth) || currentDate.isAtSameMomentAs(endOfNextMonth)) {
      dates.add(currentDate);

      // 次の日付を計算
      currentDate = calculateNextTaskDate(currentDate);

      // 無限ループ防止（1年以上先になったら中断）
      if (dates.length > 365) {
        break;
      }
    }

    return dates;
  }
}
