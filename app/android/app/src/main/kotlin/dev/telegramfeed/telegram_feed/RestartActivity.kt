package dev.telegramfeed.telegram_feed

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.os.Process

/**
 * Starts the app afresh. It runs in a process of its own (":restart"), so it outlives the
 * app's process: it ends that one, whose core Dart has already closed, launches the app,
 * and goes away itself.
 */
class RestartActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val pid = intent.getIntExtra(EXTRA_PID, -1)
        if (pid > 0) Process.killProcess(pid)
        packageManager.getLaunchIntentForPackage(packageName)?.component?.let {
            startActivity(Intent.makeRestartActivityTask(it))
        }
        finish()
        Runtime.getRuntime().exit(0)
    }

    companion object {
        const val EXTRA_PID = "pid"
    }
}
