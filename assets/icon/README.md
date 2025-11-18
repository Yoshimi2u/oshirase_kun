# アプリアイコン設定

## 必要なファイル

このディレクトリに以下のファイルを配置してください：

### アプリアイコン
- `app_icon.png`: アプリアイコン画像（iOS用、推奨サイズ: 1024x1024px）
- `foreground.png`: Adaptive Icon前景画像（Android用、透過PNG推奨、1024x1024px）
- `background.png`: Adaptive Icon背景画像（Android用、1024x1024px）

### スプラッシュスクリーン
- `splash_icon.png`: スプラッシュ画面のアイコン（推奨サイズ: 1024x1024px、透過PNG可）
- `splash_icon_dark.png`: ダークモード用スプラッシュアイコン（オプション）

## アイコン・スプラッシュ生成手順

### 1. 画像を準備
- `app_icon.png`: iOS用のアイコン（1024x1024px）
- `foreground.png`: Android Adaptive Icon用の前景画像（1024x1024px、透過PNG推奨）
- `background.png`: Android Adaptive Icon用の背景画像（1024x1024px）
- `splash_icon.png`: スプラッシュスクリーン用アイコン（1024x1024px、透過PNG可）
- すべて `assets/icon/` ディレクトリに配置

### 2. パッケージをインストール
```bash
flutter pub get
```

### 3. アプリアイコンを生成
```bash
flutter pub run flutter_launcher_icons
```

### 4. スプラッシュスクリーンを生成
```bash
flutter pub run flutter_native_splash:create
```

### 5. 確認
- **Android**: `android/app/src/main/res/` 配下にアイコンとスプラッシュが生成される
- **iOS**: `ios/Runner/Assets.xcassets/` にアイコンとスプラッシュが生成される

## Adaptive Icon（Android）について

現在の設定:
- **前景画像**: `assets/icon/foreground.png`（透過PNG推奨）
- **背景色**: 白（`#ffffff`）

### 背景画像を使用する場合

`pubspec.yaml` の設定を以下のように変更：

```yaml
flutter_launcher_icons:
  android: true
  ios: true
  image_path: "assets/icon/app_icon.png"
  adaptive_icon_foreground: "assets/icon/foreground.png"
  adaptive_icon_background: "assets/icon/background.png"  # 画像パスに変更
```

### Adaptive Iconのデザインガイドライン

- **前景画像**: 中央の66%のエリアにロゴを配置（外側はトリミングされる可能性あり）
- **安全エリア**: 中央の丸形エリア（直径の約75%）内にメインコンテンツを配置
- **透過**: 前景画像は透過PNGを使用し、背景が見えるようにする

## スプラッシュスクリーン設定

### 現在の設定
- **背景色**: 白（`#ffffff`）
- **画像**: `assets/icon/splash_icon.png`
- **配置**: 中央配置
- **全画面表示**: 有効

### カスタマイズ方法

#### 背景色を変更
`pubspec.yaml`の`flutter_native_splash`セクション：
```yaml
color: "#007AFF"  # お好みの色に変更
```

#### ダークモード対応
```yaml
color_dark: "#000000"
image_dark: assets/icon/splash_icon_dark.png
```

#### Android 12+の専用設定
```yaml
android_12:
  image: assets/icon/splash_icon.png
  color: "#ffffff"
  icon_background_color: "#ffffff"  # アイコン背景色を指定
```

### デザインのポイント
- スプラッシュアイコンは**シンプルなロゴ**がおすすめ
- 透過PNGを使用すると背景色が見える
- Android 12+では中央のアイコンサイズに制限があるため、シンプルなデザインが推奨
- iOS・Androidで同じ画像を使用可能

## トラブルシューティング

### スプラッシュが表示されない場合
```bash
# クリーンビルド
flutter clean
flutter pub get
flutter pub run flutter_native_splash:create
flutter run
```

### アイコンが更新されない場合
```bash
# アプリをアンインストールして再インストール
flutter clean
flutter pub run flutter_launcher_icons
flutter run
```

## 参考

- [flutter_launcher_icons](https://pub.dev/packages/flutter_launcher_icons)
- [Android Adaptive Icons](https://developer.android.com/guide/practices/ui_guidelines/icon_design_adaptive)
- [iOS App Icons](https://developer.apple.com/design/human-interface-guidelines/app-icons)
