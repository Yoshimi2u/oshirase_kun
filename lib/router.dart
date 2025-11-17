import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'services/analytics_service.dart';

// Firebase Analyticsでページ遷移を追跡するNavigatorObserver
class AnalyticsRouteObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _logScreenView(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (newRoute != null) {
      _logScreenView(newRoute);
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (previousRoute != null) {
      _logScreenView(previousRoute);
    }
  }

  void _logScreenView(Route<dynamic> route) {
    if (route.settings.name != null) {
      final screenName = _getScreenName(route.settings.name!);
      AnalyticsService.logScreenView(screenName);
    }
  }

  String _getScreenName(String routeName) {
    final routeScreenNameMap = {
      '/': 'ホーム',
    };

    // パラメータ付きのルートを処理
    for (final entry in routeScreenNameMap.entries) {
      if (routeName.startsWith(entry.key)) {
        return entry.value;
      }
    }

    return routeName; // フォールバック
  }
}

// ホーム画面のプレースホルダー
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ホーム'),
      ),
      body: const Center(
        child: Text('ここにアプリの内容を実装してください'),
      ),
    );
  }
}

final GoRouter router = GoRouter(
  initialLocation: '/',
  observers: [AnalyticsRouteObserver()],
  routes: [
    GoRoute(
      path: '/',
      pageBuilder: (context, state) => _buildPageWithoutAnimation(
        const HomePage(),
      ),
    ),
  ],
  errorBuilder: (context, state) => Scaffold(
    appBar: AppBar(title: const Text('エラー')),
    body: const Center(child: Text('ページが見つかりません')),
  ),
);

CustomTransitionPage<void> _buildPageWithAnimation(Widget page) {
  return CustomTransitionPage<void>(
    child: page,
    transitionDuration: const Duration(milliseconds: 400),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.0, 1.0),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(
            parent: animation,
            curve: Curves.easeInOut,
          ),
        ),
        child: child,
      );
    },
  );
}

CustomTransitionPage<void> _buildPageWithoutAnimation(Widget page) {
  return CustomTransitionPage<void>(
    child: page,
    transitionDuration: Duration.zero,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return child;
    },
  );
}
