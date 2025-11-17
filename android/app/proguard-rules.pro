# Flutter関連の保護設定
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Play Core関連の保護設定（Optional - 使用していない場合は無視される）
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }

# AdMob関連の保護設定
-keep class com.google.android.gms.ads.** { *; }
-keep class com.google.ads.** { *; }

# SQLite関連の保護設定
-keep class com.tekartik.sqflite.** { *; }

# その他の重要なクラス
-keepattributes *Annotation*
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
