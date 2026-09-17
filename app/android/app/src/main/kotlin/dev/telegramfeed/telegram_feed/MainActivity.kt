package dev.telegramfeed.telegram_feed

import android.app.NotificationManager
import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Do-not-disturb bypass for the urgent channel needs notification policy access, which
        // only a Settings screen can grant; flutter_local_notifications has no API for that.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tf/notifications")
            .setMethodCallHandler { call, result ->
                val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
                when (call.method) {
                    "isPolicyAccessGranted" -> result.success(nm.isNotificationPolicyAccessGranted)
                    "openPolicyAccessSettings" -> {
                        startActivity(Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
