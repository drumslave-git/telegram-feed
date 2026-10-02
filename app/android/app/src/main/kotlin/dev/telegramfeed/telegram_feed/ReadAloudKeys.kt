package dev.telegramfeed.telegram_feed

import android.content.Context
import android.media.AudioManager
import android.media.VolumeProvider
import android.media.session.MediaSession
import android.media.session.PlaybackState
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Volume down stops read-aloud, also with the screen off or locked (read_aloud_keys.dart).
 * Android gives the volume keys to the media session that plays; this one plays "remotely",
 * through a volume provider of its own, so volume down reaches the service host instead of
 * lowering the volume, and volume up raises the media volume as it would have anyway. The
 * session also receives a headset's pause and stop while it is held, which stop read-aloud
 * too. Dart holds it only while a post is read or waits, so the keys work as usual otherwise.
 */
class ReadAloudKeys(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, CHANNEL)
    private val audio = context.getSystemService(AudioManager::class.java)
    private var session: MediaSession? = null

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "watch" -> {
                    if (call.arguments == true) hold() else release()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun stop() = channel.invokeMethod("stop", null)

    private fun hold() {
        if (session != null) return
        session = MediaSession(context, "read-aloud").apply {
            setPlaybackToRemote(volume())
            setCallback(object : MediaSession.Callback() {
                override fun onPause() = stop()
                override fun onStop() = stop()
            })
            // Android hands the keys to an active session that plays.
            setPlaybackState(
                PlaybackState.Builder()
                    .setActions(
                        PlaybackState.ACTION_PAUSE or PlaybackState.ACTION_PLAY_PAUSE or
                            PlaybackState.ACTION_STOP,
                    )
                    .setState(
                        PlaybackState.STATE_PLAYING,
                        PlaybackState.PLAYBACK_POSITION_UNKNOWN,
                        1f,
                    )
                    .build(),
            )
            isActive = true
        }
    }

    /** Mirrors the media volume, which the speech is played at. */
    private fun volume(): VolumeProvider {
        val stream = AudioManager.STREAM_MUSIC
        return object : VolumeProvider(
            VOLUME_CONTROL_ABSOLUTE,
            audio.getStreamMaxVolume(stream),
            audio.getStreamVolume(stream),
        ) {
            override fun onAdjustVolume(direction: Int) {
                // A key's release arrives as 0.
                if (direction < 0) {
                    stop()
                } else if (direction > 0) {
                    audio.adjustStreamVolume(
                        stream,
                        AudioManager.ADJUST_RAISE,
                        AudioManager.FLAG_SHOW_UI,
                    )
                    currentVolume = audio.getStreamVolume(stream)
                }
            }

            override fun onSetVolumeTo(volume: Int) {
                audio.setStreamVolume(stream, volume, 0)
                currentVolume = audio.getStreamVolume(stream)
            }
        }
    }

    private fun release() {
        session?.release()
        session = null
    }

    /** The engine goes away. */
    fun dispose() {
        release()
        channel.setMethodCallHandler(null)
    }

    private companion object {
        const val CHANNEL = "tf/readAloudKeys"
    }
}
