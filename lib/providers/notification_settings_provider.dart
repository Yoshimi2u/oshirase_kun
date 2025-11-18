import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/notification_settings.dart';
import '../repositories/notification_settings_repository.dart';

/// NotificationSettingsRepository のプロバイダー
final notificationSettingsRepositoryProvider = Provider<NotificationSettingsRepository>((ref) {
  return NotificationSettingsRepository();
});

/// 現在のユーザーIDを取得するプロバイダー
final currentUserIdProvider = Provider<String?>((ref) {
  final user = FirebaseAuth.instance.currentUser;
  return user?.uid;
});

/// 通知設定を管理するStateNotifierProvider
final notificationSettingsProvider =
    StateNotifierProvider<NotificationSettingsNotifier, AsyncValue<NotificationSettings>>((ref) {
  final repository = ref.watch(notificationSettingsRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);
  return NotificationSettingsNotifier(repository, userId);
});

class NotificationSettingsNotifier extends StateNotifier<AsyncValue<NotificationSettings>> {
  final NotificationSettingsRepository _repository;
  final String? _userId;

  NotificationSettingsNotifier(this._repository, this._userId) : super(const AsyncValue.loading()) {
    loadSettings();
  }

  /// 設定を読み込み
  Future<void> loadSettings() async {
    if (_userId == null) {
      state = AsyncValue.data(NotificationSettings.defaultSettings());
      return;
    }

    state = const AsyncValue.loading();
    try {
      final settings = await _repository.getSettings(_userId!);
      state = AsyncValue.data(settings);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// 設定を保存
  Future<void> saveSettings(NotificationSettings settings) async {
    if (_userId == null) return;

    state = const AsyncValue.loading();
    try {
      await _repository.saveSettings(_userId!, settings);
      state = AsyncValue.data(settings);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// 朝の通知時刻を更新
  Future<void> updateMorningHour(int hour) async {
    final currentSettings = state.value;
    if (currentSettings == null || _userId == null) return;

    state = const AsyncValue.loading();
    try {
      final newSettings = currentSettings.copyWith(morningHour: hour);
      await _repository.saveSettings(_userId!, newSettings);
      state = AsyncValue.data(newSettings);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// 夜の通知時刻を更新
  Future<void> updateEveningHour(int hour) async {
    final currentSettings = state.value;
    if (currentSettings == null || _userId == null) return;

    state = const AsyncValue.loading();
    try {
      final newSettings = currentSettings.copyWith(eveningHour: hour);
      await _repository.saveSettings(_userId!, newSettings);
      state = AsyncValue.data(newSettings);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// 朝の通知の有効/無効を切り替え
  Future<void> toggleMorningEnabled(bool enabled) async {
    final currentSettings = state.value;
    if (currentSettings == null || _userId == null) return;

    state = const AsyncValue.loading();
    try {
      final newSettings = currentSettings.copyWith(morningEnabled: enabled);
      await _repository.saveSettings(_userId!, newSettings);
      state = AsyncValue.data(newSettings);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// 夜の通知の有効/無効を切り替え
  Future<void> toggleEveningEnabled(bool enabled) async {
    final currentSettings = state.value;
    if (currentSettings == null || _userId == null) return;

    state = const AsyncValue.loading();
    try {
      final newSettings = currentSettings.copyWith(eveningEnabled: enabled);
      await _repository.saveSettings(_userId!, newSettings);
      state = AsyncValue.data(newSettings);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}
