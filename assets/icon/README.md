# アプリアイコン設定

## 必要なファイル

このディレクトリに以下のファイルを配置してください：

### 必須
- `app_icon.png`: アプリアイコン画像（iOS用、推奨サイズ: 1024x1024px）
- `foreground.png`: Adaptive Icon前景画像（Android用、透過PNG推奨、1024x1024px）

### オプション
- 背景色は`pubspec.yaml`で`#ffffff`（白）に設定済み
- 背景画像を使う場合は`background.png`を配置し、`pubspec.yaml`を編集

## アイコン生成手順

1. **アイコン画像を準備**
   - `app_icon.png`: iOS用のアイコン（1024x1024px）
   - `foreground.png`: Android Adaptive Icon用の前景画像（1024x1024px、透過PNG推奨）
   - `assets/icon/` ディレクトリに配置

2. **パッケージをインストール**
   ```bash
   flutter pub get
   ```

3. **アイコンを生成**
   ```bash
   flutter pub run flutter_launcher_icons
   ```

4. **確認**
   - Android: `android/app/src/main/res/` 配下にアイコンが生成される
   - iOS: `ios/Runner/Assets.xcassets/AppIcon.appiconset/` にアイコンが生成される

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

## 参考

- [flutter_launcher_icons](https://pub.dev/packages/flutter_launcher_icons)
- [Android Adaptive Icons](https://developer.android.com/guide/practices/ui_guidelines/icon_design_adaptive)
- [iOS App Icons](https://developer.apple.com/design/human-interface-guidelines/app-icons)
