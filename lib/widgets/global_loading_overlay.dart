import 'dart:async';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// 完了表示の保持時間（ミリ秒）
const int kGlobalLoadingSuccessHoldMs = 1200;

// 状態: 表示要求/実表示/メッセージ/完了演出
class GlobalLoadingState {
  final bool requested; // API側から表示要求があるか
  final bool visible; // 実際に描画しているか（遅延/最小表示のため）
  final String? message; // 任意のメッセージ
  final bool showSuccess; // 完了チェック表示

  const GlobalLoadingState({
    required this.requested,
    required this.visible,
    this.message,
    this.showSuccess = false,
  });

  GlobalLoadingState copyWith({
    bool? requested,
    bool? visible,
    String? message,
    bool? showSuccess,
  }) =>
      GlobalLoadingState(
        requested: requested ?? this.requested,
        visible: visible ?? this.visible,
        message: message ?? this.message,
        showSuccess: showSuccess ?? this.showSuccess,
      );
}

final globalLoadingProvider =
    StateProvider<GlobalLoadingState>((ref) => const GlobalLoadingState(requested: false, visible: false));

class GlobalLoadingOverlay extends ConsumerStatefulWidget {
  const GlobalLoadingOverlay({Key? key}) : super(key: key);

  @override
  ConsumerState<GlobalLoadingOverlay> createState() => _GlobalLoadingOverlayState();
}

class _GlobalLoadingOverlayState extends ConsumerState<GlobalLoadingOverlay> {
  Timer? _delayTimer;
  Timer? _minTimer;
  DateTime? _visibleSince;
  static const _delayMs = 300; // 300msより短い処理は表示しない
  static const _minVisibleMs = 500; // 一度表示したら最低500msは見せる
  ProviderSubscription<GlobalLoadingState>? _subscription;

  @override
  void initState() {
    super.initState();
    // 毎ビルドでの再登録を避けるため、リスナーは初期化時に一度だけ登録
    _subscription = ref.listenManual<GlobalLoadingState>(globalLoadingProvider, (prev, next) {
      // 成功表示がONになったが、まだ不可視の場合は即座に可視化して成功カードを見せる
      if (next.showSuccess && !(prev?.showSuccess ?? false) && !next.visible) {
        _delayTimer?.cancel();
        _visibleSince = DateTime.now();
        // 最小表示タイマーを開始
        _minTimer?.cancel();
        _minTimer = Timer(const Duration(milliseconds: _minVisibleMs), () {});
        final cur = ref.read(globalLoadingProvider);
        if (!cur.visible) {
          ref.read(globalLoadingProvider.notifier).state = cur.copyWith(visible: true);
        }
      }

      // 表示要求ON
      if (next.requested && !(prev?.requested ?? false)) {
        _delayTimer?.cancel();
        _delayTimer = Timer(const Duration(milliseconds: _delayMs), () {
          // まだ要求が生きている場合のみ可視化
          final cur = ref.read(globalLoadingProvider);
          if (cur.requested) {
            _visibleSince = DateTime.now();
            ref.read(globalLoadingProvider.notifier).state = cur.copyWith(visible: true);
            _minTimer?.cancel();
            _minTimer = Timer(const Duration(milliseconds: _minVisibleMs), () {});
          }
        });
      }

      // 表示要求OFF
      if (!next.requested && (prev?.requested ?? false)) {
        // 遅延中は何も表示していないので即終了
        if (_delayTimer?.isActive ?? false) {
          _delayTimer?.cancel();
          _visibleSince = null;
          final cur = ref.read(globalLoadingProvider);
          ref.read(globalLoadingProvider.notifier).state =
              cur.copyWith(visible: false, showSuccess: false, message: null);
          return;
        }

        // 既に可視なら、最小表示時間を満たすまで待ってから閉じる
        final since = _visibleSince;
        if (since != null) {
          final elapsed = DateTime.now().difference(since).inMilliseconds;
          final remain = (_minVisibleMs - elapsed).clamp(0, _minVisibleMs);
          if (remain > 0) {
            _minTimer?.cancel();
            _minTimer = Timer(Duration(milliseconds: remain), () {
              _visibleSince = null;
              final cur = ref.read(globalLoadingProvider);
              ref.read(globalLoadingProvider.notifier).state =
                  cur.copyWith(visible: false, showSuccess: false, message: null);
            });
          } else {
            _visibleSince = null;
            final cur = ref.read(globalLoadingProvider);
            ref.read(globalLoadingProvider.notifier).state =
                cur.copyWith(visible: false, showSuccess: false, message: null);
          }
        } else {
          // 念のため非表示
          final cur = ref.read(globalLoadingProvider);
          ref.read(globalLoadingProvider.notifier).state =
              cur.copyWith(visible: false, showSuccess: false, message: null);
        }
      }
    });
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _minTimer?.cancel();
    _subscription?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(globalLoadingProvider);
    if (!state.visible) return const SizedBox.shrink();

    return Stack(
      children: [
        // 半透明+ブラーの背景
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 6.0, sigmaY: 6.0),
            child: Container(color: Colors.black.withOpacity(0.3)),
          ),
        ),
        // 中央のカード
        Center(
          child: Semantics(
            label: '読み込み中',
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) {
                final fade = FadeTransition(opacity: animation, child: child);
                return ScaleTransition(scale: animation, child: fade);
              },
              child: state.showSuccess ? _buildSuccessCard(context) : _buildLoadingCard(context, state.message),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingCard(BuildContext context, String? message) {
    final theme = Theme.of(context);
    final spinner = Theme.of(context).platform == TargetPlatform.iOS
        ? const CupertinoActivityIndicator(radius: 14)
        : const CircularProgressIndicator(strokeWidth: 3);

    return Container(
      key: const ValueKey('loading'),
      constraints: const BoxConstraints(minWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 18, offset: const Offset(0, 8)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          spinner,
          const SizedBox(width: 16),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('処理中…', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              if (message != null && message.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(message, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessCard(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('success'),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 18, offset: const Offset(0, 8)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, color: Colors.green[400], size: 24),
          const SizedBox(width: 12),
          Text('完了', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// ローディング表示（メッセージ任意）
void showGlobalLoading(WidgetRef ref, {String? message}) {
  final current = ref.read(globalLoadingProvider);
  // 表示要求ON、メッセージ更新、成功表示はOFF
  ref.read(globalLoadingProvider.notifier).state =
      current.copyWith(requested: true, message: message, showSuccess: false);
}

/// ローディング非表示（完了演出あり）
Future<void> hideGlobalLoading(WidgetRef ref, {bool withSuccess = false}) async {
  if (withSuccess) {
    // 成功演出を一瞬出してから閉じる
    final current = ref.read(globalLoadingProvider);
    ref.read(globalLoadingProvider.notifier).state = current.copyWith(showSuccess: true);
    await Future.delayed(const Duration(milliseconds: kGlobalLoadingSuccessHoldMs));
  }
  final current = ref.read(globalLoadingProvider);
  ref.read(globalLoadingProvider.notifier).state = current.copyWith(requested: false);
}
