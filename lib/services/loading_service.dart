import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/global_loading_overlay.dart';

/// 参照不要でどこからでも使えるグローバルローディング制御
class LoadingService {
  static ProviderContainer? _container;

  /// MaterialApp.builder 等の上位コンテキストから一度だけ初期化
  static void initFromContext(BuildContext context) {
    if (_container != null) return; // 既に初期化済み
    try {
      _container = ProviderScope.containerOf(context, listen: false);
    } catch (_) {
      // ProviderScopeの外では初期化不可
    }
  }

  static bool get isReady => _container != null;

  static void show({String? message}) {
    final c = _container;
    if (c == null) return;
    final current = c.read(globalLoadingProvider);
    c.read(globalLoadingProvider.notifier).state =
        current.copyWith(requested: true, message: message, showSuccess: false);
  }

  static Future<void> hide({bool withSuccess = false}) async {
    final c = _container;
    if (c == null) return;
    if (withSuccess) {
      final cur = c.read(globalLoadingProvider);
      c.read(globalLoadingProvider.notifier).state = cur.copyWith(showSuccess: true);
      await Future.delayed(const Duration(milliseconds: kGlobalLoadingSuccessHoldMs));
    }
    final cur = c.read(globalLoadingProvider);
    c.read(globalLoadingProvider.notifier).state = cur.copyWith(requested: false);
  }
}
