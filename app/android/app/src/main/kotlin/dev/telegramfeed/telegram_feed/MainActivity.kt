package dev.telegramfeed.telegram_feed

import android.app.NotificationManager
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.ActivityNotFoundException
import android.content.BroadcastReceiver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.drawable.Icon
import android.content.pm.PackageManager
import android.media.RingtoneManager
import android.net.Uri
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.content.res.Configuration
import android.os.Environment
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.VibratorManager
import android.provider.MediaStore
import android.provider.Settings
import android.speech.tts.TextToSpeech
import java.io.File
import android.util.Rational
import android.view.WindowManager
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // Picture-in-picture: Dart arms it while a video plays in the viewer or the mini player
    // (system_pip.dart); leaving the app then turns the activity into the floating window.
    private var pipChannel: MethodChannel? = null

    /** Waiting for the system sound picker (H-33). */
    private var soundPick: MethodChannel.Result? = null

    /** Waiting for the speech engine's example sentence. */
    private var sampleText: MethodChannel.Result? = null
    private var pipArmed = false
    private var pipAspect = Rational(16, 9)

    // The floating window's own button: pause while the video plays, play otherwise. Its
    // tap comes back as a broadcast, which is handed on to Dart (`pipAction`).
    private var pipPlaying = false
    private var pipPlayLabel = "Play"
    private var pipPauseLabel = "Pause"
    private var pipReceiverOn = false
    private val pipActionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            pipChannel?.invokeMethod("pipAction", null)
        }
    }

    /** Read-aloud runs in this engine, beside the core (rule_alerts.dart). */
    private var readAloudKeys: ReadAloudKeys? = null

    /** And so are the notifications made, and the unread posts counted. */
    private var notificationPictures: NotificationPictures? = null
    private var launcherBadge: LauncherBadge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        readAloudKeys?.dispose()
        readAloudKeys =
            ReadAloudKeys(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        NowPlaying.attach(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        notificationPictures?.dispose()
        notificationPictures =
            NotificationPictures(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        launcherBadge?.dispose()
        launcherBadge =
            LauncherBadge(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
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
                    // What a push starts is held back by battery optimisation while the
                    // phone sleeps (core_host.dart).
                    "isIgnoringBatteryOptimizations" -> result.success(
                        getSystemService(PowerManager::class.java)
                            .isIgnoringBatteryOptimizations(packageName),
                    )
                    "requestIgnoreBatteryOptimizations" -> {
                        startActivity(
                            Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                                .setData(Uri.parse("package:$packageName")),
                        )
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        // The window and the phone: the lock, the screen kept on, files opened, haptics.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tf/app")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // While the app lock is set, the task switcher shows a blank card and
                    // screenshots are refused (app_lock.dart).
                    "secure" -> {
                        if (call.arguments == true) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        result.success(null)
                    }
                    // While a video plays in the viewer or the mini player (system_pip.dart).
                    "keepScreenOn" -> {
                        if (call.arguments == true) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                        result.success(null)
                    }
                    // A downloaded file, opened in the app the phone has for its kind
                    // (media_view.dart). False when there is none.
                    "openFile" -> {
                        val path = call.argument<String>("path")
                        val mime = call.argument<String>("mime").orEmpty()
                        if (path == null) {
                            result.success(false)
                        } else {
                            try {
                                val uri = FileProvider.getUriForFile(
                                    this,
                                    "$packageName.files",
                                    File(path),
                                )
                                startActivity(
                                    Intent(Intent.ACTION_VIEW)
                                        .setDataAndType(uri, mime.ifEmpty { "*/*" })
                                        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),
                                )
                                result.success(true)
                            } catch (e: ActivityNotFoundException) {
                                result.success(false)
                            } catch (e: IllegalArgumentException) {
                                // A path the provider does not serve.
                                result.success(false)
                            }
                        }
                    }
                    // A vibration longer than any haptic constant (haptics.dart).
                    "buzz" -> {
                        val ms = (call.arguments as? Number)?.toLong() ?: 200L
                        val vibrator =
                            getSystemService(VibratorManager::class.java)?.defaultVibrator
                        if (vibrator == null || !vibrator.hasVibrator()) {
                            result.error("no_vibrator", null, null)
                        } else {
                            vibrator.vibrate(
                                VibrationEffect.createOneShot(
                                    ms,
                                    VibrationEffect.DEFAULT_AMPLITUDE,
                                ),
                            )
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        // Saving a picture or a video where the gallery looks for it (H-23). MediaStore
        // needs no permission for what the app itself writes.
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
                                result.success(
                                    saveToGallery(
                                        File(path),
                                        name,
                                        mime,
                                        call.argument<String>("to") ?: "gallery",
                                    ),
                                )
                            } catch (e: Exception) {
                                result.error("save", e.message, null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        // The speech engine's own example sentence in a language, the one Android's
        // text-to-speech settings play; null when the engine has none.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tf/tts")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "sampleText" -> {
                        val intent = Intent(TextToSpeech.Engine.ACTION_GET_SAMPLE_TEXT)
                            .putExtra("language", call.argument<String>("language") ?: "")
                            .putExtra("country", call.argument<String>("country") ?: "")
                            .putExtra("variant", "")
                        val engine = sampleTextEngine(intent)
                        if (engine == null || sampleText != null) {
                            result.success(null)
                        } else {
                            sampleText = result
                            try {
                                startActivityForResult(
                                    intent.setPackage(engine),
                                    SAMPLE_TEXT_REQUEST,
                                )
                            } catch (e: ActivityNotFoundException) {
                                sampleText = null
                                result.success(null)
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
                        pipPlaying = call.argument<Boolean>("playing") == true
                        pipPlayLabel = call.argument<String>("playLabel") ?: pipPlayLabel
                        pipPauseLabel = call.argument<String>("pauseLabel") ?: pipPauseLabel
                        // The system enters by itself, also on the home gesture; the
                        // parameters carry the window's button, which follows whether the
                        // video plays.
                        if (pipSupported()) {
                            registerPipReceiver()
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
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) && roaming(caps) ->
                "roaming"
            else -> "mobile"
        }
    }

    private fun roaming(caps: NetworkCapabilities): Boolean =
        !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_ROAMING)

    /**
     * Copies the file to where the phone keeps such files and answers with its uri:
     * Pictures or Movies for the gallery, Download for documents, Music for audio.
     */
    private fun saveToGallery(file: File, name: String, mime: String, to: String): String {
        val video = mime.startsWith("video")
        val collection = when (to) {
            "downloads" -> MediaStore.Downloads.EXTERNAL_CONTENT_URI
            "music" -> MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
            else -> if (video) {
                MediaStore.Video.Media.EXTERNAL_CONTENT_URI
            } else {
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            }
        }
        val folder = when (to) {
            "downloads" -> Environment.DIRECTORY_DOWNLOADS
            "music" -> Environment.DIRECTORY_MUSIC
            else -> if (video) Environment.DIRECTORY_MOVIES else Environment.DIRECTORY_PICTURES
        }
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

    /**
     * The engine that speaks: the one chosen in Android's settings, otherwise the first that
     * answers [intent], as TextToSpeech picks the system's own engine then.
     */
    private fun sampleTextEngine(intent: Intent): String? {
        val engines = packageManager.queryIntentActivities(intent, 0)
            .map { it.activityInfo.packageName }
        val chosen = Settings.Secure.getString(contentResolver, "tts_default_synth")
        return if (chosen in engines) chosen else engines.firstOrNull()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        readAloudKeys?.dispose()
        readAloudKeys = null
        NowPlaying.detach(flutterEngine.dartExecutor.binaryMessenger)
        notificationPictures?.dispose()
        notificationPictures = null
        launcherBadge?.dispose()
        launcherBadge = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == SAMPLE_TEXT_REQUEST) {
            val pending = sampleText ?: return
            sampleText = null
            pending.success(
                if (resultCode == TextToSpeech.LANG_AVAILABLE) {
                    data?.getStringExtra(TextToSpeech.Engine.EXTRA_SAMPLE_TEXT)
                } else {
                    null
                },
            )
            return
        }
        if (requestCode != SOUND_PICK_REQUEST) return
        val pending = soundPick ?: return
        soundPick = null
        val uri = data?.getParcelableExtra<Uri>(RingtoneManager.EXTRA_RINGTONE_PICKED_URI)
        pending.success(uri?.toString() ?: "")
    }

    private fun pipSupported() =
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

    private fun pipParams(): PictureInPictureParams =
        PictureInPictureParams.Builder()
            .setAspectRatio(pipAspect)
            .setActions(listOf(pipToggleAction()))
            .setAutoEnterEnabled(pipArmed)
            .build()

    /** Play or pause in the floating window. */
    private fun pipToggleAction(): RemoteAction {
        val tap = PendingIntent.getBroadcast(
            this,
            PIP_TOGGLE_REQUEST,
            Intent(PIP_TOGGLE_ACTION).setPackage(packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val label = if (pipPlaying) pipPauseLabel else pipPlayLabel
        val icon = Icon.createWithResource(
            this,
            if (pipPlaying) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play,
        )
        return RemoteAction(icon, label, label, tap)
    }

    private fun registerPipReceiver() {
        if (pipReceiverOn) return
        ContextCompat.registerReceiver(
            this,
            pipActionReceiver,
            IntentFilter(PIP_TOGGLE_ACTION),
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
        pipReceiverOn = true
    }

    override fun onDestroy() {
        if (pipReceiverOn) {
            unregisterReceiver(pipActionReceiver)
            pipReceiverOn = false
        }
        super.onDestroy()
    }

    override fun onPictureInPictureModeChanged(isInPip: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPip, newConfig)
        pipChannel?.invokeMethod("pipChanged", isInPip)
    }

    private companion object {
        const val SOUND_PICK_REQUEST = 7301
        const val SAMPLE_TEXT_REQUEST = 7302
        const val PIP_TOGGLE_REQUEST = 7303
        const val PIP_TOGGLE_ACTION = "dev.telegramfeed.telegram_feed.PIP_TOGGLE"
    }
}
