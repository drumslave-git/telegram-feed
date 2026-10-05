package dev.telegramfeed.push_runner

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import org.json.JSONObject

/**
 * Debug builds only: queues a push as FCM would, so a run can be watched without
 * Telegram. `adb shell am broadcast -a dev.telegramfeed.push_runner.DEBUG_PUSH
 * -p <package> [--es payload <json>]`.
 */
class DebugPushReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val payload = intent.getStringExtra("payload") ?: "{}"
        PushQueue.add(context.applicationContext, JSONObject().put("push", payload).toString())
    }
}
