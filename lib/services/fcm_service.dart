import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
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

  /// FCMサービスを初期化
  Future<void> initialize(String userId) async {
    if (_initialized) return;

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
        // iOSの場合、APNSトークンが設定されるのを待つ（ベストエフォート）
        if (defaultTargetPlatform == TargetPlatform.iOS) {
          if (kDebugMode) {
            print('[FCMService] iOS環境: APNSトークンの確認');
          }

          // 最大10秒間、APNSトークンの設定を待つ
          for (int i = 0; i < 10; i++) {
            await Future.delayed(const Duration(seconds: 1));
            try {
              final apnsToken = await _messaging.getAPNSToken();
              if (apnsToken != null) {
                if (kDebugMode) {
                  print('[FCMService] APNSトークン取得成功: ${apnsToken.substring(0, 10)}...');
                }
                break;
              } else if (kDebugMode) {
                print('[FCMService] APNSトークン待機中... (${i + 1}/10)');
              }
            } catch (e) {
              if (kDebugMode) {
                print('[FCMService] APNSトークン確認エラー: $e');
              }
            }
          }

          // 最終確認
          final finalApnsToken = await _messaging.getAPNSToken();
          if (finalApnsToken == null) {
            if (kDebugMode) {
              print('[FCMService] 警告: APNSトークンがnullですが、処理を続行します');
              print('[FCMService] バックグラウンドでAPNSトークンが設定される可能性があります');
            }
          }
        }

        // FCMトークンを取得（APNSトークンがnullでも試行）
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
          // APNSトークンが設定されていない場合のエラーは無視して続行
        }

        // トークンをFirestoreに保存
        if (_currentToken != null) {
          await _saveTokenToFirestore(userId, _currentToken!);
        } else if (kDebugMode) {
          print('[FCMService] FCMトークンがnullのため、Firestoreへの保存をスキップ');
        }

        // トークンの更新を監視
        _messaging.onTokenRefresh.listen((newToken) {
          _currentToken = newToken;
          if (kDebugMode) {
            print('[FCMService] FCMトークン更新: ${newToken.substring(0, 20)}...');
          }
          _saveTokenToFirestore(userId, newToken);
        });

        // iOSの場合、APNSトークンが後から設定される可能性があるため
        // 定期的にFCMトークンの再取得を試みる
        if (defaultTargetPlatform == TargetPlatform.iOS && _currentToken == null) {
          if (kDebugMode) {
            print('[FCMService] iOS: バックグラウンドでトークン取得を継続');
          }
          _retryTokenFetch(userId);
        }

        // フォアグラウンドメッセージの処理
        FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

        // バックグラウンドメッセージの処理は main.dart で設定
        // FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

        _initialized = true;
        if (kDebugMode) {
          print('[FCMService] 初期化完了');
        }
      } else {
        if (kDebugMode) {
          print('[FCMService] 通知権限が拒否されました');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('[FCMService] 初期化エラー: $e');
      }
      // エラーが発生しても続行（FCMが使えないだけでアプリは動作する）
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
    // 5秒後、10秒後、20秒後にリトライ
    final retryDelays = [5, 10, 20];

    for (final delay in retryDelays) {
      await Future.delayed(Duration(seconds: delay));

      if (_currentToken != null) {
        // すでにトークンが取得できていればリトライ不要
        break;
      }

      try {
        if (kDebugMode) {
          print('[FCMService] トークン再取得試行 (${delay}秒後)');
        }

        final token = await _messaging.getToken();
        if (token != null) {
          _currentToken = token;
          await _saveTokenToFirestore(userId, token);
          if (kDebugMode) {
            print('[FCMService] トークン再取得成功: ${token.substring(0, 20)}...');
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

  /// FCMトークンを削除（ログアウト時など）
  Future<void> deleteToken(String userId) async {
    try {
      await _messaging.deleteToken();
      await _firestore.collection('users').doc(userId).update({
        'fcmToken': FieldValue.delete(),
      });

      _currentToken = null;

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
