package dev.telegramfeed.telegram_feed

import android.app.NotificationManager
import android.app.PictureInPictureParams
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.provider.Settings
import android.util.Rational
import androidx.annotation.RequiresApi
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // Picture-in-picture: Dart arms it while a video plays in the viewer or the mini player
    // (system_pip.dart); leaving the app then turns the activity into the floating window.
    private var pipChannel: MethodChannel? = null
    private var pipArmed = false
    private var pipAspect = Rational(16, 9)

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
        pipChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tf/pip").also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "arm" -> {
                        pipArmed = call.argument<Boolean>("enabled") == true && pipSupported()
                        pipAspect = aspect(
                            call.argument<Int>("width") ?: 16,
                            call.argument<Int>("height") ?: 9,
                        )
                        // From Android 12 the system enters by itself, also on the home gesture.
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && pipSupported()) {
                            setPictureInPictureParams(pipParams())
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun pipSupported() =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    /** Android accepts window shapes between 1:2.39 and 2.39:1 only. */
    private fun aspect(width: Int, height: Int): Rational {
        if (width <= 0 || height <= 0) return Rational(16, 9)
        val ratio = width.toDouble() / height
        return when {
            ratio > 2.39 -> Rational(239, 100)
            ratio < 1 / 2.39 -> Rational(100, 239)
            else -> Rational(width, height)
        }
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun pipParams(): PictureInPictureParams {
        val builder = PictureInPictureParams.Builder().setAspectRatio(pipAspect)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) builder.setAutoEnterEnabled(pipArmed)
        return builder.build()
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (pipArmed && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            Build.VERSION.SDK_INT < Build.VERSION_CODES.S
        ) {
            enterPictureInPictureMode(pipParams())
        }
    }

    override fun onPictureInPictureModeChanged(isInPip: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPip, newConfig)
        pipChannel?.invokeMethod("pipChanged", isInPip)
    }
}
