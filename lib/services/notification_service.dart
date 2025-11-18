import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:flutter/foundation.dart';

/// ローカル通知を管理するサービスクラス
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  // 固定の通知ID
  static const int morningNotificationId = 0;
  static const int eveningNotificationId = 1;

  /// 通知サービスを初期化
  Future<void> initialize() async {
    if (_initialized) return;

    // タイムゾーンデータを初期化
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Tokyo'));

    // Android初期化設定
    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS初期化設定
    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    // 初期化設定を統合
    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    // 通知プラグインを初期化
    await _notificationsPlugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    _initialized = true;
    if (kDebugMode) {
      print('[NotificationService] 初期化完了');
    }
  }

  /// 通知がタップされたときの処理
  void _onNotificationTapped(NotificationResponse response) {
    if (kDebugMode) {
      print('[NotificationService] 通知がタップされました: ${response.payload}');
    }
    // 必要に応じて画面遷移などの処理を追加
  }

  /// 通知権限をリクエスト
  Future<bool> requestPermission() async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final result = await _notificationsPlugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
      return result ?? false;
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      final androidImplementation =
          _notificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final result = await androidImplementation?.requestNotificationsPermission();
      return result ?? false;
    }
    return true;
  }

  /// 朝と夜の通知をスケジュール
  /// todayTaskCount: 今日のタスク数
  /// overdueTaskCount: 遅延タスク数
  Future<void> scheduleTwiceDaily({
    required DateTime morningTime,
    required DateTime eveningTime,
    required bool morningEnabled,
    required bool eveningEnabled,
    required int todayTaskCount,
    required int overdueTaskCount,
  }) async {
    // 既存の通知をキャンセル
    await _notificationsPlugin.cancel(morningNotificationId);
    await _notificationsPlugin.cancel(eveningNotificationId);

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'daily_task_channel',
      '毎日のタスク通知',
      channelDescription: '今日のタスク一覧を通知します',
      importance: Importance.high,
      priority: Priority.high,
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails();

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // 朝の通知をスケジュール
    if (morningEnabled) {
      final now = tz.TZDateTime.now(tz.local);
      var scheduledDate = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        morningTime.hour,
        morningTime.minute,
      );

      if (scheduledDate.isBefore(now)) {
        scheduledDate = scheduledDate.add(const Duration(days: 1));
      }

      final totalCount = todayTaskCount + overdueTaskCount;
      final title = totalCount > 0 ? '今日のタスク' : 'お知らせ君';
      String body;
      if (overdueTaskCount > 0 && todayTaskCount > 0) {
        body = '遅延: $overdueTaskCount件、今日: $todayTaskCount件';
      } else if (overdueTaskCount > 0) {
        body = '遅延タスクが$overdueTaskCount件あります';
      } else if (todayTaskCount > 0) {
        body = '今日は$todayTaskCount件のタスクがあります';
      } else {
        body = '今日のタスクはありません';
      }

      await _notificationsPlugin.zonedSchedule(
        morningNotificationId,
        title,
        body,
        scheduledDate,
        notificationDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );

      if (kDebugMode) {
        print('[NotificationService] 朝の通知をスケジュール: ${morningTime.hour}:${morningTime.minute}');
      }
    }

    // 夜の通知をスケジュール
    if (eveningEnabled) {
      final now = tz.TZDateTime.now(tz.local);
      var scheduledDate = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        eveningTime.hour,
        eveningTime.minute,
      );

      if (scheduledDate.isBefore(now)) {
        scheduledDate = scheduledDate.add(const Duration(days: 1));
      }

      final totalCount = todayTaskCount + overdueTaskCount;
      final title = totalCount > 0 ? '今日のタスク確認' : 'お知らせ君';
      String body;
      if (totalCount > 0) {
        body = '未完了のタスクが${totalCount}件あります';
      } else {
        body = '今日のタスクは完了しました';
      }

      await _notificationsPlugin.zonedSchedule(
        eveningNotificationId,
        title,
        body,
        scheduledDate,
        notificationDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );

      if (kDebugMode) {
        print('[NotificationService] 夜の通知をスケジュール: ${eveningTime.hour}:${eveningTime.minute}');
      }
    }
  }

  /// 通知をキャンセル
  Future<void> cancelNotification(int id) async {
    await _notificationsPlugin.cancel(id);
    if (kDebugMode) {
      print('[NotificationService] 通知をキャンセル: ID=$id');
    }
  }

  /// すべての通知をキャンセル
  Future<void> cancelAllNotifications() async {
    await _notificationsPlugin.cancelAll();
    if (kDebugMode) {
      print('[NotificationService] すべての通知をキャンセル');
    }
  }

  /// スケジュールされている通知の一覧を取得
  Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    return await _notificationsPlugin.pendingNotificationRequests();
  }
}
