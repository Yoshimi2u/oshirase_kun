# お知らせ君 (oshirase_kun)

予定を登録して毎日定時に通知を送るシンプルなリマインダーアプリです。

## 主な機能

### 予定管理
- 予定のタイトルと説明を設定
- 通知時刻を自由に設定（デフォルト: 午前5時）
- 繰り返しパターンの選択
  - 繰り返しなし（1回のみ）
  - 毎日
  - 毎週
  - 毎月
  - カスタム（〇日ごと）

### 通知機能
- ローカル通知による定時リマインダー
- 予定ごとにON/OFF切り替え可能
- バックグラウンドでも動作

### データ保存
- Cloud Firestoreによるクラウド保存
- 複数デバイスでの同期に対応
- Firebase Authenticationによる匿名認証

## 技術スタック

- **フレームワーク**: Flutter
- **状態管理**: Riverpod
- **ルーティング**: GoRouter
- **データベース**: Cloud Firestore
- **通知**: flutter_local_notifications
- **認証**: Firebase Authentication
- **広告**: Google AdMob

## セットアップ

### 1. 依存関係のインストール
```bash
flutter pub get
```

### 2. Firebase設定
1. Firebase Consoleで新しいプロジェクトを作成
2. iOS/Androidアプリを追加
3. `google-services.json`（Android）と`GoogleService-Info.plist`（iOS）をダウンロード
4. 各プラットフォームの適切なディレクトリに配置:
   - Android: `android/app/google-services.json`
   - iOS: `ios/Runner/GoogleService-Info.plist`
5. Firebase CLIを使用して`firebase_options.dart`を生成:
```bash
flutterfire configure
```

6. `lib/main.dart`のFirebase初期化コードのコメントを解除

### 3. Firestoreセキュリティルールの設定
Firebase Consoleで以下のセキュリティルールを設定してください:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId}/schedules/{scheduleId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
  }
}
```

### 4. Android通知設定
`android/app/src/main/AndroidManifest.xml`に以下の権限を追加:

```xml
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
<uses-permission android:name="android.permission.USE_EXACT_ALARM"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
```

### 5. iOS通知設定
`ios/Runner/Info.plist`に以下を追加:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>
    <string>remote-notification</string>
</array>
```

### 6. AdMob設定（オプション）
広告を有効にする場合:
1. AdMobアカウントを作成
2. `android/app/src/main/AndroidManifest.xml`と`ios/Runner/Info.plist`にApp IDを設定
3. `lib/services/ad_manager.dart`内の広告ユニットIDを更新

## プロジェクト構造

```
lib/
├── main.dart                          # アプリのエントリーポイント
├── router.dart                        # GoRouterの設定
├── models/
│   └── schedule.dart                  # 予定のデータモデル
├── repositories/
│   └── schedule_repository.dart       # Firestore操作
├── providers/
│   └── schedule_provider.dart         # Riverpod状態管理
├── services/
│   ├── notification_service.dart      # 通知管理
│   ├── ad_manager.dart                # 広告管理
│   ├── ad_free_manager.dart           # 広告非表示管理
│   ├── analytics_service.dart         # Analytics
│   ├── auth_service.dart              # 認証サービス
│   └── loading_service.dart           # ローディング管理
├── screens/
│   ├── schedule_list_screen.dart      # 予定一覧画面
│   └── schedule_form_screen.dart      # 予定登録・編集画面
└── widgets/
    ├── banner_ad_widget.dart          # バナー広告
    └── global_loading_overlay.dart    # ローディング表示
```

## 使い方

### 予定の追加
1. ホーム画面右下の「予定を追加」ボタンをタップ
2. タイトルと説明を入力
3. 通知時刻を設定
4. 繰り返しパターンを選択
5. 「予定を作成」ボタンをタップ

### 予定の編集
1. 予定一覧から編集したい予定をタップ
2. 内容を変更
3. 「予定を更新」ボタンをタップ

### 予定の削除
1. 予定一覧から削除したい予定をタップ
2. 右上のゴミ箱アイコンをタップ
3. 確認ダイアログで「削除」を選択

### 通知のON/OFF
予定一覧画面の各予定カード右側のスイッチで切り替えができます。

## ビルド

### Android
```bash
flutter build apk --release
# または
flutter build appbundle --release
```

### iOS
```bash
flutter build ios --release
```

## トラブルシューティング

### 通知が届かない
- Android 13以降では通知権限の許可が必要です
- 設定アプリでアプリの通知権限を確認してください
- バッテリー最適化の除外設定も確認してください

### Firestoreに接続できない
- `firebase_options.dart`が正しく生成されているか確認
- Firebase Consoleでプロジェクトが有効になっているか確認
- セキュリティルールが正しく設定されているか確認

## ライセンス

このプロジェクトは自由に使用・改変できます。


