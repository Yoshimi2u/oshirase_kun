import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'services/ad_manager.dart';
import 'services/ad_free_manager.dart';
import 'services/fcm_service.dart';
import 'router.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'services/analytics_service.dart';
import 'widgets/global_loading_overlay.dart';
import 'widgets/global_banner_ad.dart';
import 'services/loading_service.dart';
import 'providers/theme_provider.dart';

/// バックグラウンドメッセージハンドラー（トップレベル関数として定義）
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (kDebugMode) {
    print('[FCM] バックグラウンドメッセージ受信:');
    print('  タイトル: ${message.notification?.title}');
    print('  本文: ${message.notification?.body}');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 日付フォーマットのロケールデータを初期化
  await initializeDateFormatting('ja_JP', null);

  // Firebase初期化
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

  // バックグラウンドメッセージハンドラーを設定
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

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

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeFCM();
  }

  /// FCMを初期化
  Future<void> _initializeFCM() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final fcmService = FCMService();
        await fcmService.initialize(user.uid);
        if (kDebugMode) {
          print('[MyApp] FCM初期化完了');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('[MyApp] FCM初期化エラー: $e');
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AdFreeManager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      routerConfig: router,
      title: 'お知らせ君',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ja', 'JP'),
      ],
      themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.light(
          primary: Colors.blue,
          onPrimary: Colors.white,
          primaryContainer: Colors.blue.shade100,
          secondary: Colors.green,
          onSecondary: Colors.white,
          surface: const Color(0xFFFAFAFA),
          onSurface: Colors.black,
          surfaceContainerHighest: Colors.white,
          outline: Colors.grey.shade300,
        ),
        cardTheme: CardThemeData(
          elevation: 1,
          color: Colors.white,
          shadowColor: Colors.black.withOpacity(0.1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade200, width: 1),
          ),
        ),
        dividerTheme: DividerThemeData(
          color: Colors.grey.shade300,
          thickness: 1,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.dark(
          primary: Colors.blue.shade300,
          onPrimary: Colors.black,
          primaryContainer: Colors.blue.shade700,
          secondary: Colors.green.shade300,
          onSecondary: Colors.black,
          surface: const Color(0xFF1E1E1E),
          onSurface: Colors.white,
          surfaceContainerHighest: const Color(0xFF2C2C2C),
          outline: Colors.grey.shade600,
        ),
        cardTheme: const CardThemeData(
          elevation: 2,
          color: Color(0xFF2C2C2C),
        ),
        dividerTheme: DividerThemeData(
          color: Colors.grey.shade700,
          thickness: 1,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E1E1E),
          elevation: 0,
          iconTheme: IconThemeData(color: Colors.white),
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      builder: (context, child) {
        LoadingService.initFromContext(context);
        final base = child ?? const SizedBox.shrink();
        return Stack(
          children: [
            GlobalBannerAd(child: base),
            const GlobalLoadingOverlay(),
          ],
        );
      },
    );
  }
}
