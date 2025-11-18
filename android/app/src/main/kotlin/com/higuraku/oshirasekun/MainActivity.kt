package com.higuraku.oshirasekun

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.WindowManager
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // FCM通知チャネルの作成
        createNotificationChannel()
        
        // 広告表示に配慮したエッジ ツー エッジ表示設定
        configureSystemUI()
    }
    
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager = getSystemService(NotificationManager::class.java)
            
            // デフォルトの通知チャンネル
            val defaultChannelId = "default_channel"
            val defaultChannelName = "お知らせ"
            val defaultChannel = NotificationChannel(
                defaultChannelId,
                defaultChannelName,
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "タスクのお知らせ通知"
                enableVibration(true)
                enableLights(true)
            }
            notificationManager.createNotificationChannel(defaultChannel)
            
            // グループタスク完了通知チャンネル
            val groupChannelId = "group_notification_channel"
            val groupChannelName = "グループタスク"
            val groupChannel = NotificationChannel(
                groupChannelId,
                groupChannelName,
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "グループメンバーのタスク完了通知"
                enableVibration(true)
                enableLights(true)
            }
            notificationManager.createNotificationChannel(groupChannel)
        }
    }
    
    private fun configureSystemUI() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // Android 11+ (API 30+) での対応
            window.setDecorFitsSystemWindows(false)
            
            val controller = WindowInsetsControllerCompat(window, window.decorView)
            
            // 広告表示のためシステムバーは隠さない
            // controller.hide(WindowInsetsCompat.Type.systemBars()) // この行をコメントアウト
            
            // システムバーの外観を調整
            controller.isAppearanceLightStatusBars = true
            controller.isAppearanceLightNavigationBars = true
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            // Android 6+ (API 23+) での対応
            // 広告表示に影響しないよう、フルスクリーンフラグは使用しない
            window.decorView.systemUiVisibility = (
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                or View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
            )
        }
        
        // ステータスバーを半透明に設定（完全透明だと広告に影響する場合がある）
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            window.statusBarColor = android.graphics.Color.parseColor("#80000000") // 半透明の黒
            window.navigationBarColor = android.graphics.Color.parseColor("#80000000") // 半透明の黒
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                window.attributes.layoutInDisplayCutoutMode = 
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }
        
        // 広告表示のため、適度なシステムUI設定
        WindowCompat.setDecorFitsSystemWindows(window, true) // trueに変更
    }
}
