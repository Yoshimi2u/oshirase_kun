/// 通知設定モデル
class NotificationSettings {
  final bool morningEnabled;
  final int morningHour;
  final bool eveningEnabled;
  final int eveningHour;

  NotificationSettings({
    required this.morningEnabled,
    required this.morningHour,
    required this.eveningEnabled,
    required this.eveningHour,
  });

  /// デフォルト設定
  factory NotificationSettings.defaultSettings() {
    return NotificationSettings(
      morningEnabled: true,
      morningHour: 8,
      eveningEnabled: true,
      eveningHour: 20,
    );
  }

  /// Firestoreからデータを取得
  factory NotificationSettings.fromFirestore(Map<String, dynamic> data) {
    return NotificationSettings(
      morningEnabled: data['morningEnabled'] as bool? ?? true,
      morningHour: data['morningHour'] as int? ?? 8,
      eveningEnabled: data['eveningEnabled'] as bool? ?? true,
      eveningHour: data['eveningHour'] as int? ?? 20,
    );
  }

  /// Firestoreに保存する形式に変換
  Map<String, dynamic> toFirestore() {
    return {
      'morningEnabled': morningEnabled,
      'morningHour': morningHour,
      'eveningEnabled': eveningEnabled,
      'eveningHour': eveningHour,
    };
  }

  /// コピーを作成
  NotificationSettings copyWith({
    bool? morningEnabled,
    int? morningHour,
    bool? eveningEnabled,
    int? eveningHour,
  }) {
    return NotificationSettings(
      morningEnabled: morningEnabled ?? this.morningEnabled,
      morningHour: morningHour ?? this.morningHour,
      eveningEnabled: eveningEnabled ?? this.eveningEnabled,
      eveningHour: eveningHour ?? this.eveningHour,
    );
  }
}
