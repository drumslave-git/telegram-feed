package dev.telegramfeed.telegram_feed

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.util.Log
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * The pictures of a channel's notification (notification_pictures.dart). "avatar" cuts the
 * channel's photo round, as Android draws the face of a conversation as it is given, and
 * returns the file; "share" returns a content uri of a post's picture that the
 * notification shade may read. Both answer null for a file they can do nothing with.
 */
class NotificationPictures(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, CHANNEL)

    init {
        channel.setMethodCallHandler { call, result ->
            val path = call.arguments as? String
            when (call.method) {
                "avatar" -> result.success(path?.let(::avatar))
                "share" -> result.success(path?.let(::share))
                else -> result.notImplemented()
            }
        }
    }

    private fun avatar(path: String): String? = try {
        val source = File(path)
        val dir = File(context.cacheDir, "notify").apply { mkdirs() }
        val prefix = "avatar_${path.hashCode().toUInt()}_"
        val round = File(dir, "$prefix${source.lastModified()}.png")
        if (!round.exists()) {
            // The photo changed: the round picture of the old one goes.
            dir.listFiles { f -> f.name.startsWith(prefix) }?.forEach { it.delete() }
            val photo = BitmapFactory.decodeFile(path)
            if (photo == null) {
                null
            } else {
                val size = minOf(photo.width, photo.height)
                val cut = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
                val canvas = Canvas(cut)
                val paint = Paint(Paint.ANTI_ALIAS_FLAG)
                canvas.drawCircle(size / 2f, size / 2f, size / 2f, paint)
                paint.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
                canvas.drawBitmap(
                    photo,
                    (size - photo.width) / 2f,
                    (size - photo.height) / 2f,
                    paint,
                )
                round.outputStream().use { cut.compress(Bitmap.CompressFormat.PNG, 100, it) }
                round.path
            }
        } else {
            round.path
        }
    } catch (e: Exception) {
        Log.w(TAG, "avatar: $e")
        null
    }

    private fun share(path: String): String? = try {
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", File(path))
        // Android hands the shade the pictures of a notification by itself from Android 9;
        // before that, and on phones whose shade is asked on its own, it is given here.
        context.grantUriPermission(
            "com.android.systemui",
            uri,
            Intent.FLAG_GRANT_READ_URI_PERMISSION,
        )
        uri.toString()
    } catch (e: Exception) {
        Log.w(TAG, "share: $e")
        null
    }

    /** The engine goes away. */
    fun dispose() = channel.setMethodCallHandler(null)

    private companion object {
        const val CHANNEL = "tf/notificationPictures"
        const val TAG = "NotificationPictures"
    }
}
