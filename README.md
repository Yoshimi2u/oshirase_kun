# Flutter App Template

Firebase連携とAdMob広告を含む、Flutterアプリケーションの汎用テンプレートです。

## 主な機能

### 共通機能
- Firebase連携（Analytics、Auth、Firestore、Storage、Functions、Remote Config）
- AdMob広告統合（バナー広告、広告非表示管理）
- Firebase Analytics イベントトラッキング
- 匿名認証
- Riverpod状態管理
- GoRouterによるナビゲーション
- グローバルローディング表示
- iOS App Tracking Transparency (ATT) 対応

### 保持されているサービス
- `services/ad_manager.dart` - AdMob広告の初期化と管理
- `services/ad_free_manager.dart` - 広告非表示機能の管理
- `services/ad_diagnostic_service.dart` - 広告診断サービス（開発時のみ）
- `services/analytics_service.dart` - Firebase Analyticsのラッパー
- `services/auth_service.dart` - Firebase Authentication管理
- `services/loading_service.dart` - グローバルローディング管理

## セットアップ

### 1. 依存関係のインストール
```bash
flutter pub get
```

### 2. Firebase設定
1. Firebase Consoleで新しいプロジェクトを作成
2. iOS/Androidアプリを追加
3. `google-services.json`（Android）と`GoogleService-Info.plist`（iOS）をダウンロード
4. 各プラットフォームの適切なディレクトリに配置
5. Firebase CLIを使用して`firebase_options.dart`を生成:
```bash
flutterfire configure
```

### 3. AdMob設定
1. AdMob アカウントを作成
2. アプリを登録してApp IDを取得
3. `android/app/src/main/AndroidManifest.xml`と`ios/Runner/Info.plist`にApp IDを設定
4. `services/ad_manager.dart`内の広告ユニットIDを更新

### 4. パッケージ名とアプリ名の変更
- `pubspec.yaml`の`name`を変更
- Android: `android/app/build.gradle`の`applicationId`を変更
- iOS: Xcodeでバンドル識別子を変更
- `lib/main.dart`のアプリタイトルを変更

## プロジェクト構造

```
lib/
├── main.dart                 # アプリケーションのエントリーポイント
├── router.dart               # GoRouterの設定
├── firebase_options.dart     # Firebase設定（自動生成）
├── constants/                # 定数定義
├── db/                       # データベース関連
├── provider/                 # Riverpod プロバイダー
├── services/                 # ビジネスロジックとサービス
├── utils/                    # ユーティリティ関数
└── widgets/                  # 再利用可能なウィジェット
```

## 使い方

### 画面の追加
1. 画面ウィジェットを作成
2. `router.dart`にルートを追加

### Firebaseサービスの利用
```dart
// Analytics
AnalyticsService.logEvent('event_name', parameters: {'key': 'value'});

// Firestore
FirebaseFirestore.instance.collection('users').doc(userId).get();
```

### 広告の表示
`widgets/banner_ad_widget.dart`を使用してバナー広告を表示できます。

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

## 注意事項

- Firebaseプロジェクトの設定ファイルは含まれていません。各自で設定してください
- AdMob App IDと広告ユニットIDは、実際の値に置き換える必要があります
- iOS用のApp Store IDは`version_checker.dart`などで使用される場合があります

## ライセンス

このテンプレートは自由に使用・改変できます。

