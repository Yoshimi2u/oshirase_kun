import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'services/ad_manager.dart';
import 'services/ad_free_manager.dart';
import 'router.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
// import 'firebase_options.dart'; // 新しいプロジェクトで flutterfire configure を実行して生成してください
import 'services/auth_service.dart';
import 'services/analytics_service.dart';
import 'widgets/global_loading_overlay.dart';
import 'services/loading_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase初期化
  // 注: firebase_options.dart を flutterfire configure で生成した後、
  // 以下のコメントを解除してください
  /*
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Firebase Analytics初期化
    FirebaseAnalytics analytics = FirebaseAnalytics.instance;
    await analytics.setAnalyticsCollectionEnabled(true);

    if (kDebugMode) {
      print('Firebase Analytics初期化成功');
    }
  } catch (e) {
    if (kDebugMode) {
      print('Firebase初期化エラー: $e');
    }
  }

  // Firebase Authentication 匿名認証
  try {
    final initialUser = await FirebaseAuth.instance.authStateChanges().first;
    if (initialUser == null) {
      await AuthService.signInAnonymouslyIfNeeded();
    }
  } catch (e) {
    if (kDebugMode) {
      print('匿名認証エラー: $e');
    }
  }
  */

  // App Tracking Transparency 許可リクエスト（iOSのみ）
  try {
    final status = await AppTrackingTransparency.trackingAuthorizationStatus;
    if (status == TrackingStatus.notDetermined) {
      await AppTrackingTransparency.requestTrackingAuthorization();
    }
  } catch (e) {
    // iOS以外のプラットフォームでは無視
  }

  // 画面の向きを縦固定に設定
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Mobile Ads SDKを初期化
  try {
    await AdManager.initialize();
  } catch (e) {
    debugPrint('広告SDK初期化エラー: $e');
  }

  // 広告非表示管理を初期化
  try {
    await AdFreeManager.initialize();
  } catch (e) {
    debugPrint('広告非表示管理初期化エラー: $e');
  }

  // システムUIの設定
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
    systemNavigationBarDividerColor: Colors.transparent,
  ));

  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );

  // アプリ起動後にAnalyticsイベントを送信
  WidgetsBinding.instance.addPostFrameCallback((_) {
    AnalyticsService.logAppOpen();
  });
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AdFreeManager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: router,
      title: 'Flutter App Template',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.light(
          primary: Colors.blue,
          onPrimary: Colors.white,
          primaryContainer: Colors.blue.shade100,
          secondary: Colors.green,
          onSecondary: Colors.white,
          surface: Colors.white,
          onSurface: Colors.black,
        ),
      ),
      builder: (context, child) {
        LoadingService.initFromContext(context);
        final base = child ?? const SizedBox.shrink();
        return Stack(
          children: [
            base,
            const GlobalLoadingOverlay(),
          ],
        );
      },
    );
  }
}
