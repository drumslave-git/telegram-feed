package dev.telegramfeed.push_runner

import android.content.Context
import android.util.Log
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging

/** The FCM token of this install. */
internal object PushToken {
    /**
     * Answers the token, or null: a build without a Firebase project of its own (no
     * `google-services.json`, so no FirebaseApp) or a phone without Google Play services.
     */
    fun get(context: Context, answer: (String?) -> Unit) {
        if (FirebaseApp.getApps(context).isEmpty()) {
            answer(null)
            return
        }
        try {
            FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
                if (!task.isSuccessful) Log.w(TAG, "no FCM token: ${task.exception}")
                answer(if (task.isSuccessful) task.result else null)
            }
        } catch (e: Exception) {
            Log.w(TAG, "no FCM token: $e")
            answer(null)
        }
    }
}

internal const val TAG = "push"
