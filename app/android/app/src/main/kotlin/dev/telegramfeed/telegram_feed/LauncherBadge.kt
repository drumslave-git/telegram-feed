package dev.telegramfeed.telegram_feed

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * The number on the app's icon (launcher_badge.dart). Android has no way of its own to set
 * one, so it is handed to the launchers that take it: the badge broadcast that Samsung's,
 * LG's and Sony's home screens listen for, and Huawei's and Honor's badge provider. A home
 * screen that shows no numbers (Pixel's shows a dot for a notification) ignores both.
 */
class LauncherBadge(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, CHANNEL)

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "set" -> {
                    set((call.arguments as? Number)?.toInt() ?: 0)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun set(count: Int) {
        val launcher =
            context.packageManager.getLaunchIntentForPackage(context.packageName)?.component
                ?: return
        Log.i(TAG, "badge $count")
        try {
            val update = Intent(BADGE_COUNT_UPDATE)
                .putExtra("badge_count", count)
                .putExtra("badge_count_package_name", context.packageName)
                .putExtra("badge_count_class_name", launcher.className)
            // Android 8 delivers no broadcast that names no receiver: each one is named.
            for (receiver in context.packageManager.queryBroadcastReceivers(update, 0)) {
                val info = receiver.activityInfo ?: continue
                context.sendBroadcast(
                    Intent(update).setComponent(ComponentName(info.packageName, info.name)),
                )
            }
        } catch (e: Exception) {
            Log.w(TAG, "broadcast: $e")
        }
        try {
            context.contentResolver.call(
                Uri.parse("content://com.huawei.android.launcher.settings/badge/"),
                "change_badge",
                null,
                Bundle().apply {
                    putString("package", context.packageName)
                    putString("class", launcher.className)
                    putInt("badgenumber", count)
                },
            )
        } catch (e: Exception) {
            // No such home screen on this phone.
        }
    }

    /** The engine goes away. */
    fun dispose() = channel.setMethodCallHandler(null)

    private companion object {
        const val CHANNEL = "tf/badge"
        const val TAG = "LauncherBadge"
        const val BADGE_COUNT_UPDATE = "android.intent.action.BADGE_COUNT_UPDATE"
    }
}
