package dev.telegramfeed.telegram_feed

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.drawable.Icon
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.IBinder
import android.os.SystemClock
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The voice message or the music that plays, as Android shows it (now_playing.dart): a media
 * notification with the player's buttons, the same player on the lock screen, and a media
 * session, which the headset's buttons reach. While the sound plays, [PlaybackService] keeps
 * the app in the foreground, so Android lets it play on with the screen off; paused, the
 * notification stays and can be swiped away, which stops the player.
 */
object NowPlaying {
    private const val CHANNEL = "tf/nowPlaying"
    private const val NOTIFICATION_CHANNEL = "playback"
    private const val ID = 0x706c6179
    private const val TAG = "NowPlaying"
    const val ACTION_PLAY = "dev.telegramfeed.playback.PLAY"
    const val ACTION_PAUSE = "dev.telegramfeed.playback.PAUSE"
    const val ACTION_NEXT = "dev.telegramfeed.playback.NEXT"
    const val ACTION_PREVIOUS = "dev.telegramfeed.playback.PREVIOUS"
    const val ACTION_STOP = "dev.telegramfeed.playback.STOP"

    /** What Dart said last: the track, where it is, and the words of the buttons. */
    private class Shown(
        val title: String,
        val artist: String,
        val playing: Boolean,
        val positionMs: Long,
        val durationMs: Long,
        val speed: Float,
        /** The track stands among others: previous and next are offered. */
        val skips: Boolean,
        val channelName: String,
        val play: String,
        val pause: String,
        val previous: String,
        val next: String,
    )

    private var app: Context? = null
    private var messenger: BinaryMessenger? = null
    private var channel: MethodChannel? = null
    private var session: MediaSession? = null
    private var shown: Shown? = null
    private var service: PlaybackService? = null

    /** The service was asked for and has not come up yet. */
    private var starting = false

    fun attach(context: Context, messenger: BinaryMessenger) {
        app = context.applicationContext
        this.messenger = messenger
        channel = MethodChannel(messenger, CHANNEL).also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "show" -> {
                        show(call)
                        result.success(null)
                    }
                    "hide" -> {
                        hide()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    /** The engine goes away, and the player with it. An engine that came after it stays. */
    fun detach(messenger: BinaryMessenger) {
        if (this.messenger !== messenger) return
        hide()
        channel?.setMethodCallHandler(null)
        channel = null
        this.messenger = null
    }

    private fun tell(what: String, argument: Any? = null) {
        channel?.invokeMethod(what, argument)
    }

    /** The lock screen's player, the notification's own buttons on Android 13, a headset. */
    private val callback = object : MediaSession.Callback() {
        override fun onPlay() = tell("play")
        override fun onPause() = tell("pause")
        override fun onSkipToNext() = tell("next")
        override fun onSkipToPrevious() = tell("previous")
        override fun onStop() = tell("stop")
        override fun onSeekTo(pos: Long) = tell("seek", pos)
    }

    /** A button of the notification, or the notification swiped away. */
    fun onAction(context: Context, action: String?) {
        if (channel == null) {
            // The app was closed, and this notification outlived it.
            context.getSystemService(NotificationManager::class.java).cancel(ID)
            return
        }
        when (action) {
            ACTION_PLAY -> tell("play")
            ACTION_PAUSE -> tell("pause")
            ACTION_NEXT -> tell("next")
            ACTION_PREVIOUS -> tell("previous")
            ACTION_STOP -> tell("stop")
        }
    }

    private fun show(call: MethodCall) {
        val context = app ?: return
        val now = Shown(
            title = call.argument<String>("title") ?: "",
            artist = call.argument<String>("artist") ?: "",
            playing = call.argument<Boolean>("playing") == true,
            positionMs = (call.argument<Number>("position") ?: 0).toLong(),
            durationMs = (call.argument<Number>("duration") ?: 0).toLong(),
            speed = (call.argument<Number>("speed") ?: 1).toFloat(),
            skips = call.argument<Boolean>("skips") == true,
            channelName = call.argument<String>("channelName") ?: "Playback",
            play = call.argument<String>("play") ?: "Play",
            pause = call.argument<String>("pause") ?: "Pause",
            previous = call.argument<String>("previous") ?: "Previous",
            next = call.argument<String>("next") ?: "Next",
        )
        shown = now
        val session = session ?: MediaSession(context, "playback").also {
            it.setCallback(callback)
            session = it
        }
        session.setMetadata(
            MediaMetadata.Builder()
                .putString(MediaMetadata.METADATA_KEY_TITLE, now.title)
                .putString(MediaMetadata.METADATA_KEY_ARTIST, now.artist)
                .putLong(
                    MediaMetadata.METADATA_KEY_DURATION,
                    if (now.durationMs > 0) now.durationMs else -1,
                )
                .build(),
        )
        var actions = PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or
            PlaybackState.ACTION_PLAY_PAUSE or PlaybackState.ACTION_STOP or
            PlaybackState.ACTION_SEEK_TO
        if (now.skips) {
            actions = actions or PlaybackState.ACTION_SKIP_TO_NEXT or
                PlaybackState.ACTION_SKIP_TO_PREVIOUS
        }
        session.setPlaybackState(
            PlaybackState.Builder()
                .setActions(actions)
                .setState(
                    if (now.playing) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED,
                    now.positionMs,
                    now.speed,
                    SystemClock.elapsedRealtime(),
                )
                .build(),
        )
        session.isActive = true
        val notification = notification(context, session, now)
        val running = service
        if (!now.playing) {
            // Paused: the notification stays without the service, so it can be swiped away.
            running?.leave(remove = false)
            service = null
            context.getSystemService(NotificationManager::class.java).notify(ID, notification)
        } else if (running != null) {
            running.enter(ID, notification)
        } else if (!starting) {
            starting = true
            try {
                val intent = Intent(context, PlaybackService::class.java)
                context.startForegroundService(intent)
            } catch (e: IllegalStateException) {
                // Android refuses a foreground service to an app it counts as in the
                // background: the sound plays on for as long as the app lives.
                Log.w(TAG, "no foreground service: $e")
                starting = false
                context.getSystemService(NotificationManager::class.java)
                    .notify(ID, notification)
            }
        }
    }

    /** The service is up. Android wants its notification at once, whatever happened since. */
    fun started(started: PlaybackService) {
        starting = false
        val context = app
        val session = session
        val now = shown
        if (context == null || session == null || now == null) {
            // Stopped meanwhile.
            started.enter(ID, placeholder(started))
            started.leave(remove = true)
            return
        }
        started.enter(ID, notification(context, session, now))
        if (now.playing) {
            service = started
        } else {
            started.leave(remove = false)
            context.getSystemService(NotificationManager::class.java)
                .notify(ID, notification(context, session, now))
        }
    }

    fun stopped(stopped: PlaybackService) {
        if (service === stopped) service = null
    }

    private fun hide() {
        shown = null
        session?.let {
            it.isActive = false
            it.release()
        }
        session = null
        service?.leave(remove = true)
        service = null
        app?.getSystemService(NotificationManager::class.java)?.cancel(ID)
    }

    private fun builder(context: Context, channelName: String?): Notification.Builder {
        val manager = context.getSystemService(NotificationManager::class.java)
        if (channelName != null || manager.getNotificationChannel(NOTIFICATION_CHANNEL) == null) {
            // Made again with the same id, a channel takes the new name and keeps the rest.
            manager.createNotificationChannel(
                NotificationChannel(
                    NOTIFICATION_CHANNEL,
                    channelName ?: "Playback",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply { setShowBadge(false) },
            )
        }
        return Notification.Builder(context, NOTIFICATION_CHANNEL)
    }

    private fun placeholder(context: Context): Notification =
        builder(context, null).setSmallIcon(R.drawable.ic_stat_feed).build()

    private fun tap(context: Context, action: String): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            action.hashCode(),
            Intent(context, PlaybackReceiver::class.java).setAction(action),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    private fun button(context: Context, icon: Int, label: String, action: String) =
        Notification.Action.Builder(
            Icon.createWithResource(context, icon),
            label,
            tap(context, action),
        ).build()

    private fun notification(context: Context, session: MediaSession, now: Shown): Notification {
        val buttons = buildList {
            if (now.skips) {
                add(
                    button(
                        context,
                        android.R.drawable.ic_media_previous,
                        now.previous,
                        ACTION_PREVIOUS,
                    ),
                )
            }
            add(
                if (now.playing) {
                    button(context, android.R.drawable.ic_media_pause, now.pause, ACTION_PAUSE)
                } else {
                    button(context, android.R.drawable.ic_media_play, now.play, ACTION_PLAY)
                },
            )
            if (now.skips) {
                add(button(context, android.R.drawable.ic_media_next, now.next, ACTION_NEXT))
            }
        }
        val open = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val builder = builder(context, now.channelName)
            .setSmallIcon(R.drawable.ic_stat_feed)
            .setContentTitle(now.title)
            .setContentText(now.artist.ifEmpty { null })
            // Shown on the lock screen as it is: its owner started it.
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setCategory(Notification.CATEGORY_TRANSPORT)
            .setShowWhen(false)
            .setOnlyAlertOnce(true)
            .setOngoing(now.playing)
            .setDeleteIntent(tap(context, ACTION_STOP))
            .setStyle(
                Notification.MediaStyle()
                    .setMediaSession(session.sessionToken)
                    .setShowActionsInCompactView(*IntArray(buttons.size) { it }),
            )
        if (open != null) {
            builder.setContentIntent(
                PendingIntent.getActivity(
                    context,
                    0,
                    open,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                ),
            )
        }
        buttons.forEach { builder.addAction(it) }
        return builder.build()
    }
}

/** In the foreground while a voice message or music plays ([NowPlaying]). */
class PlaybackService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        NowPlaying.started(this)
        return START_NOT_STICKY
    }

    fun enter(id: Int, notification: Notification) {
        try {
            startForeground(id, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        } catch (e: IllegalStateException) {
            // Refused to an app Android counts as in the background: the notification is
            // shown without the service.
            Log.w("NowPlaying", "not in the foreground: $e")
            getSystemService(NotificationManager::class.java).notify(id, notification)
        }
    }

    /** Out of the foreground and gone; the notification goes with it, or stays behind. */
    fun leave(remove: Boolean) {
        stopForeground(if (remove) STOP_FOREGROUND_REMOVE else STOP_FOREGROUND_DETACH)
        stopSelf()
    }

    override fun onDestroy() {
        NowPlaying.stopped(this)
        super.onDestroy()
    }
}

/** The buttons of the player's notification. */
class PlaybackReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) =
        NowPlaying.onAction(context, intent.action)
}
