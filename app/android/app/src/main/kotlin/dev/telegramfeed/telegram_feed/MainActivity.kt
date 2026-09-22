package dev.telegramfeed.telegram_feed

import android.app.NotificationManager
import android.app.PictureInPictureParams
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.media.RingtoneManager
import android.net.Uri
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.content.res.Configuration
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import java.io.File
import android.util.Rational
import androidx.annotation.RequiresApi
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // Picture-in-picture: Dart arms it while a video plays in the viewer or the mini player
    // (system_pip.dart); leaving the app then turns the activity into the floating window.
    private var pipChannel: MethodChannel? = null

    /** Waiting for the system sound picker (H-33). */
    private var soundPick: MethodChannel.Result? = null
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
                    // The system's own sound picker (H-33): an empty answer means the
                    // default, and a cancelled picker answers with what was there before.
                    "pickSound" -> {
                        if (soundPick != null) {
                            result.error("busy", "a picker is already open", null)
                        } else {
                            soundPick = result
                            val current = call.argument<String>("current")
                            val intent = Intent(RingtoneManager.ACTION_RINGTONE_PICKER).apply {
                                putExtra(
                                    RingtoneManager.EXTRA_RINGTONE_TYPE,
                                    RingtoneManager.TYPE_NOTIFICATION,
                                )
                                putExtra(RingtoneManager.EXTRA_RINGTONE_TITLE, "Notification sound")
                                putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT, true)
                                putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT, false)
                                putExtra(
                                    RingtoneManager.EXTRA_RINGTONE_EXISTING_URI,
                                    if (current.isNullOrEmpty()) null else Uri.parse(current),
                                )
                            }
                            startActivityForResult(intent, SOUND_PICK_REQUEST)
                        }
                    }
                    // Android's own name of a sound the picker returned, as its list shows it.
                    "soundTitle" -> {
                        val uri = call.argument<String>("uri")
                        val title = try {
                            if (uri.isNullOrEmpty()) null
                            else RingtoneManager.getRingtone(this, Uri.parse(uri))?.getTitle(this)
                        } catch (e: Exception) {
                            null
                        }
                        result.success(title)
                    }
                    // False when the user turned the app's notifications off in Android.
                    "areNotificationsEnabled" -> result.success(nm.areNotificationsEnabled())
                    // Android's settings page of the app's notifications, where each channel,
                    // the foreground service's included, can be turned off.
                    "openAppSettings" -> {
                        startActivity(
                            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName),
                        )
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        // A fresh start of the app, for settings that decide where the core runs. Dart has
        // already stopped the core, so TDLib is closed when RestartActivity ends this process.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tf/app")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "restart" -> {
                        result.success(null)
                        startActivity(
                            Intent(this, RestartActivity::class.java)
                                .putExtra(RestartActivity.EXTRA_PID, android.os.Process.myPid())
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                        )
                    }
                    else -> result.notImplemented()
                }
            }
        // Saving a picture or a video where the gallery looks for it (H-23). MediaStore
        // needs no permission for what the app itself writes since Android 10, which is the
        // oldest version this app runs on.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tf/gallery")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "save" -> {
                        val path = call.argument<String>("path")
                        val name = call.argument<String>("name")
                        val mime = call.argument<String>("mimeType") ?: "image/jpeg"
                        if (path == null || name == null) {
                            result.error("args", "path and name are required", null)
                        } else {
                            try {
                                result.success(saveToGallery(File(path), name, mime))
                            } catch (e: Exception) {
                                result.error("save", e.message, null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        // What the phone is on, for the automatic downloads of H-24.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tf/network")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "type" -> result.success(networkType())
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

    /**
     * "wifi", "mobile", "roaming" or "none": metered connections count as mobile, mobile data
     * on a network abroad as roaming.
     */
    private fun networkType(): String {
        val cm = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager
        val network = cm.activeNetwork ?: return "none"
        val caps = cm.getNetworkCapabilities(network) ?: return "none"
        if (!caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) return "none"
        val unmetered = caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
        return when {
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) && unmetered -> "wifi"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "wifi"
            unmetered -> "wifi"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) && roaming(cm, caps) ->
                "roaming"
            else -> "mobile"
        }
    }

    private fun roaming(cm: ConnectivityManager, caps: NetworkCapabilities): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_ROAMING)
        } else {
            @Suppress("DEPRECATION")
            cm.activeNetworkInfo?.isRoaming == true
        }

    /** Copies the file into Pictures/TG Feed (or Movies) and answers with its uri. */
    private fun saveToGallery(file: File, name: String, mime: String): String {
        val video = mime.startsWith("video")
        val collection = if (video) {
            MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        } else {
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        }
        val folder = if (video) Environment.DIRECTORY_MOVIES else Environment.DIRECTORY_PICTURES
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, "$folder/TG Feed")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = contentResolver.insert(collection, values)
            ?: throw IllegalStateException("the gallery refused the file")
        contentResolver.openOutputStream(uri).use { out ->
            checkNotNull(out) { "the gallery gave no stream" }
            file.inputStream().use { it.copyTo(out) }
        }
        values.clear()
        values.put(MediaStore.MediaColumns.IS_PENDING, 0)
        contentResolver.update(uri, values, null, null)
        return uri.toString()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != SOUND_PICK_REQUEST) return
        val pending = soundPick ?: return
        soundPick = null
        val uri = data?.getParcelableExtra<Uri>(RingtoneManager.EXTRA_RINGTONE_PICKED_URI)
        pending.success(uri?.toString() ?: "")
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

    private companion object {
        const val SOUND_PICK_REQUEST = 7301
    }
}
