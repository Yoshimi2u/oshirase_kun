import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/notification_settings.dart';
import '../repositories/notification_settings_repository.dart';
import 'schedule_provider.dart'; // currentUserIdProviderをインポート

/// 通知設定リポジトリのプロバイダー
final notificationSettingsRepositoryProvider = Provider<NotificationSettingsRepository>((ref) {
  return NotificationSettingsRepository();
});

/// 通知設定のStreamProvider
final notificationSettingsProvider = StreamProvider<NotificationSettings>((ref) {
  final userIdAsync = ref.watch(currentUserIdProvider);
  final repository = ref.watch(notificationSettingsRepositoryProvider);

  return userIdAsync.when(
    data: (userId) {
      if (userId == null) {
        return Stream.value(NotificationSettings.defaultSettings());
      }
      return repository.watchSettings(userId);
    },
    loading: () => Stream.value(NotificationSettings.defaultSettings()),
    error: (_, __) => Stream.value(NotificationSettings.defaultSettings()),
  );
});

/// 通知設定の変更を管理するNotifier
class NotificationSettingsNotifier extends StateNotifier<AsyncValue<NotificationSettings>> {
  final NotificationSettingsRepository _repository;
  final String? _userId;

  NotificationSettingsNotifier(this._repository, this._userId) : super(const AsyncValue.loading()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    if (_userId == null) {
      state = AsyncValue.data(NotificationSettings.defaultSettings());
      return;
    }

    try {
      final settings = await _repository.getSettings(_userId!);
      state = AsyncValue.data(settings);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  /// 朝の通知の有効/無効を切り替え
  Future<void> toggleMorningEnabled(bool enabled) async {
    if (_userId == null) return;

    try {
      await _repository.toggleMorningEnabled(_userId!, enabled);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  /// 朝の通知時刻を更新
  Future<void> updateMorningHour(int hour) async {
    if (_userId == null) return;

    try {
      await _repository.updateMorningHour(_userId!, hour);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  /// 夜の通知の有効/無効を切り替え
  Future<void> toggleEveningEnabled(bool enabled) async {
    if (_userId == null) return;

    try {
      await _repository.toggleEveningEnabled(_userId!, enabled);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  /// 夜の通知時刻を更新
  Future<void> updateEveningHour(int hour) async {
    if (_userId == null) return;

    try {
      await _repository.updateEveningHour(_userId!, hour);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }
}

/// NotificationSettingsNotifierのプロバイダー
final notificationSettingsNotifierProvider =
    StateNotifierProvider<NotificationSettingsNotifier, AsyncValue<NotificationSettings>>((ref) {
  final repository = ref.watch(notificationSettingsRepositoryProvider);
  final userIdAsync = ref.watch(currentUserIdProvider);
  final userId = userIdAsync.maybeWhen(
    data: (id) => id,
    orElse: () => null,
  );
  return NotificationSettingsNotifier(repository, userId);
});
