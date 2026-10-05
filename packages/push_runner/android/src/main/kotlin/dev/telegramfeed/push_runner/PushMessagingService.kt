package dev.telegramfeed.push_runner

import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import org.json.JSONObject

/** Telegram's pushes arrive here and wait for a run; so does a new token. */
class PushMessagingService : FirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage) {
        // TDLib's processPushNotification takes the message's data with these added.
        val payload = JSONObject()
        for ((key, value) in message.data) payload.put(key, value)
        payload.put("google.sent_time", message.sentTime)
        message.notification?.sound?.let { payload.put("google.notification.sound", it) }
        PushQueue.add(applicationContext, JSONObject().put("push", payload.toString()).toString())
    }

    override fun onNewToken(token: String) {
        PushQueue.add(applicationContext, JSONObject().put("register", true).toString())
    }
}
