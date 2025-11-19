import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Firebase Cloud Messaging（FCM）を管理するサービスクラス
class FCMService {
  static final FCMService _instance = FCMService._internal();
  factory FCMService() => _instance;
  FCMService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _initialized = false;
  String? _currentToken;
  String? _currentUserId;
  bool _listenersSetup = false;

  /// FCMサービスを初期化
  Future<void> initialize(String userId) async {
    // 同じユーザーで既に初期化済みの場合はスキップ
    if (_initialized && _currentUserId == userId) return;

    // 異なるユーザーの場合は再初期化
    if (_currentUserId != null && _currentUserId != userId) {
      if (kDebugMode) {
        print('[FCMService] ユーザー変更を検出: $_currentUserId -> $userId');
      }
      _initialized = false;
      _currentToken = null;
    }

    _currentUserId = userId;

    try {
      // 通知権限をリクエスト
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (kDebugMode) {
        print('[FCMService] 通知権限: ${settings.authorizationStatus}');
      }

      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        // iOSの場合、APNSトークンが設定されるのを待つ
        if (defaultTargetPlatform == TargetPlatform.iOS) {
          // 最大5秒間、APNSトークンの設定を待つ
          for (int i = 0; i < 5; i++) {
            await Future.delayed(const Duration(seconds: 1));
            try {
              final apnsToken = await _messaging.getAPNSToken();
              if (apnsToken != null) {
                if (kDebugMode) {
                  print('[FCMService] APNSトークン取得成功');
                }
                break;
              }
            } catch (e) {
              if (kDebugMode) {
                print('[FCMService] APNSトークン確認エラー: $e');
              }
            }
          }
        }

        // FCMトークンを取得
        try {
          _currentToken = await _messaging.getToken();
          if (kDebugMode) {
            if (_currentToken != null) {
              print('[FCMService] FCMトークン取得成功: ${_currentToken!.substring(0, 20)}...');
            } else {
              print('[FCMService] FCMトークンがnullです');
            }
          }
        } catch (e) {
          if (kDebugMode) {
            print('[FCMService] FCMトークン取得エラー: $e');
          }
        }

        if (kDebugMode) {
          print('----------------------------------------');
        }

        // トークンをFirestoreに保存
        if (_currentToken != null) {
          await _saveTokenToFirestore(userId, _currentToken!);
        } else if (kDebugMode) {
          print('[FCMService] FCMトークンがnullのため、Firestoreへの保存をスキップ');
        }

        // リスナーは一度だけ設定
        if (!_listenersSetup) {
          // トークンの更新を監視
          _messaging.onTokenRefresh.listen((newToken) {
            _currentToken = newToken;
            if (kDebugMode) {
              print('[FCMService] FCMトークン更新: ${newToken.substring(0, 20)}...');
            }
            if (_currentUserId != null) {
              _saveTokenToFirestore(_currentUserId!, newToken);
            }
          });

          // フォアグラウンドメッセージの処理
          FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

          _listenersSetup = true;
          if (kDebugMode) {
            print('[FCMService] リスナー設定完了');
          }
        }

        if (defaultTargetPlatform == TargetPlatform.iOS && _currentToken == null) {
          _retryTokenFetch(userId);
        }

        _initialized = true;
      } else {
        if (kDebugMode) {
          print('[FCMService] 通知権限が拒否されました');
        }
        _initialized = true;
      }
    } catch (e) {
      if (kDebugMode) {
        print('[FCMService] 初期化エラー: $e');
      }
      // エラーが発生しても続行（FCMが使えないだけでアプリは動作する）
      _initialized = true;
    }
  }

  /// FCMトークンをFirestoreに保存
  Future<void> _saveTokenToFirestore(String userId, String token) async {
    try {
      await _firestore.collection('users').doc(userId).set({
        'fcmToken': token,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (kDebugMode) {
        print('[FCMService] FCMトークンをFirestoreに保存しました');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[FCMService] FCMトークン保存エラー: $e');
      }
    }
  }

  /// FCMトークン取得のリトライ（iOSでAPNSトークンが遅延設定される場合）
  Future<void> _retryTokenFetch(String userId) async {
    final retryDelays = [5, 10, 20];

    for (final delay in retryDelays) {
      await Future.delayed(Duration(seconds: delay));

      if (_currentToken != null) break;

      try {
        final token = await _messaging.getToken();
        if (token != null) {
          _currentToken = token;
          await _saveTokenToFirestore(userId, token);
          if (kDebugMode) {
            print('[FCMService] トークン再取得成功');
          }
          break;
        }
      } catch (e) {
        if (kDebugMode) {
          print('[FCMService] トークン再取得エラー: $e');
        }
      }
    }
  }

  /// フォアグラウンドでメッセージを受信したときの処理
  void _handleForegroundMessage(RemoteMessage message) {
    if (kDebugMode) {
      print('[FCMService] フォアグラウンドメッセージ受信:');
      print('  タイトル: ${message.notification?.title}');
      print('  本文: ${message.notification?.body}');
      print('  データ: ${message.data}');
    }

    // 必要に応じてローカル通知を表示
    // または画面更新などの処理を実行
  }

  /// 現在のFCMトークンを取得
  String? get currentToken => _currentToken;

  /// 通知権限の状態を取得（プラットフォーム対応版）
  Future<AuthorizationStatus> getPermissionStatus() async {
    final settings = await _messaging.getNotificationSettings();
    return settings.authorizationStatus;
  }

  /// 通知が有効かどうかを判定（プラットフォーム対応）
  /// iOS: 権限の状態を確認
  /// Android: FCMトークンの有無を確認（Android 12以下は常にtrue、Android 13+は権限も考慮）
  Future<bool> isNotificationEnabled() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        // iOSの場合は権限の状態を確認
        final settings = await _messaging.getNotificationSettings();
        return settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional;
      } else {
        // Androidの場合はFCMトークンの有無で判定
        // Android 12以下: 通知は常に有効（トークンが取得できる）
        // Android 13+: 権限が必要だが、トークンの有無で実質的な状態を判定
        final token = await _messaging.getToken();
        return token != null && token.isNotEmpty;
      }
    } catch (e) {
      if (kDebugMode) {
        print('[FCMService] 通知有効状態の確認エラー: $e');
      }
      return false;
    }
  }

  /// FCMトークンを削除（ログアウト時など）
  Future<void> deleteToken(String userId) async {
    try {
      await _messaging.deleteToken();
      await _firestore.collection('users').doc(userId).update({
        'fcmToken': FieldValue.delete(),
      });

      _currentToken = null;
      _currentUserId = null;
      _initialized = false;

      if (kDebugMode) {
        print('[FCMService] FCMトークンを削除しました');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[FCMService] FCMトークン削除エラー: $e');
      }
    }
  }
}

/// バックグラウンドメッセージハンドラー（main.dartで使用）
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (kDebugMode) {
    print('[FCMService] バックグラウンドメッセージ受信:');
    print('  タイトル: ${message.notification?.title}');
    print('  本文: ${message.notification?.body}');
    print('  データ: ${message.data}');
  }
}
