import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/completion_history.dart';
import '../repositories/completion_history_repository.dart';

/// CompletionHistoryRepository のプロバイダー
final completionHistoryRepositoryProvider = Provider<CompletionHistoryRepository>((ref) {
  return CompletionHistoryRepository();
});

/// 特定の日の完了履歴を取得するStreamProvider
final completionHistoriesByDateProvider =
    StreamProvider.autoDispose.family<List<CompletionHistory>, DateTime>((ref, date) {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    return Stream.value([]);
  }

  final repository = ref.watch(completionHistoryRepositoryProvider);
  return repository.getCompletionHistoriesByDateStream(user.uid, date);
});

/// 特定のスケジュールの完了履歴を取得するStreamProvider
final completionHistoriesByScheduleProvider =
    StreamProvider.autoDispose.family<List<CompletionHistory>, String>((ref, scheduleId) {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    return Stream.value([]);
  }

  final repository = ref.watch(completionHistoryRepositoryProvider);
  return repository.getCompletionHistoriesStream(user.uid, scheduleId);
});

/// 全完了履歴を取得するStreamProvider
final allCompletionHistoriesProvider = StreamProvider.autoDispose<List<CompletionHistory>>((ref) {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    return Stream.value([]);
  }

  final repository = ref.watch(completionHistoryRepositoryProvider);
  return repository.getAllCompletionHistoriesStream(user.uid);
});
