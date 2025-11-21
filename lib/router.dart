import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'services/analytics_service.dart';
import 'screens/schedule_list_screen.dart';
import 'screens/schedule_form_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/calendar_screen.dart';
import 'screens/group_screen.dart';
import 'screens/account_screen.dart';

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
      '/schedule/create': '予定作成',
      '/schedule/edit': '予定編集',
      '/calendar': 'カレンダー',
      '/settings': '設定',
      '/groups': 'グループ管理',
      '/account': 'アカウント設定',
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

final GoRouter router = GoRouter(
  initialLocation: '/',
  observers: [AnalyticsRouteObserver()],
  routes: [
    GoRoute(
      path: '/',
      pageBuilder: (context, state) => _buildPageWithoutAnimation(
        const ScheduleListScreen(),
      ),
    ),
    GoRoute(
      path: '/schedule/create',
      pageBuilder: (context, state) => _buildPageWithAnimation(
        const ScheduleFormScreen(),
      ),
    ),
    GoRoute(
      path: '/schedule/edit/:id',
      pageBuilder: (context, state) {
        final id = state.pathParameters['id'];
        final taskId = state.uri.queryParameters['taskId'];
        final initialDateStr = state.uri.queryParameters['initialDate'];
        DateTime? initialDate;
        if (initialDateStr != null) {
          try {
            initialDate = DateTime.parse(initialDateStr);
          } catch (e) {
            // パース失敗時はnullのまま
          }
        }
        return _buildPageWithAnimation(
          ScheduleFormScreen(
            scheduleId: id,
            initialDate: initialDate,
            taskId: taskId,
          ),
        );
      },
    ),
    GoRoute(
      path: '/calendar',
      pageBuilder: (context, state) => _buildPageWithAnimation(
        const CalendarScreen(),
      ),
    ),
    GoRoute(
      path: '/settings',
      pageBuilder: (context, state) => _buildPageWithAnimation(
        const SettingsScreen(),
      ),
    ),
    GoRoute(
      path: '/groups',
      pageBuilder: (context, state) => _buildPageWithAnimation(
        const GroupScreen(),
      ),
    ),
    GoRoute(
      path: '/account',
      pageBuilder: (context, state) => _buildPageWithAnimation(
        const AccountScreen(),
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
