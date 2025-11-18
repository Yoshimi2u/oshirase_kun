/// 通知設定を管理するモデルクラス
class NotificationSettings {
  final int morningHour; // 朝の通知時刻（0-23）
  final int eveningHour; // 夜の通知時刻（0-23）
  final bool morningEnabled; // 朝の通知を有効にするか
  final bool eveningEnabled; // 夜の通知を有効にするか

  NotificationSettings({
    required this.morningHour,
    required this.eveningHour,
    this.morningEnabled = true,
    this.eveningEnabled = true,
  });

  /// デフォルト設定（朝7時、夜18時）
  factory NotificationSettings.defaultSettings() {
    return NotificationSettings(
      morningHour: 7,
      eveningHour: 18,
      morningEnabled: true,
      eveningEnabled: true,
    );
  }

  /// Firestoreに保存する形式に変換
  Map<String, dynamic> toFirestore() {
    return {
      'morningHour': morningHour,
      'eveningHour': eveningHour,
      'morningEnabled': morningEnabled,
      'eveningEnabled': eveningEnabled,
    };
  }

  /// Firestoreから復元
  factory NotificationSettings.fromFirestore(Map<String, dynamic> data) {
    return NotificationSettings(
      morningHour: data['morningHour'] ?? 7,
      eveningHour: data['eveningHour'] ?? 18,
      morningEnabled: data['morningEnabled'] ?? true,
      eveningEnabled: data['eveningEnabled'] ?? true,
    );
  }

  /// JSON形式に変換（後方互換性のため残す）
  Map<String, dynamic> toJson() => toFirestore();

  /// JSONから復元（後方互換性のため残す）
  factory NotificationSettings.fromJson(Map<String, dynamic> json) => NotificationSettings.fromFirestore(json);

  /// コピーを作成
  NotificationSettings copyWith({
    int? morningHour,
    int? eveningHour,
    bool? morningEnabled,
    bool? eveningEnabled,
  }) {
    return NotificationSettings(
      morningHour: morningHour ?? this.morningHour,
      eveningHour: eveningHour ?? this.eveningHour,
      morningEnabled: morningEnabled ?? this.morningEnabled,
      eveningEnabled: eveningEnabled ?? this.eveningEnabled,
    );
  }
}
