package dev.telegramfeed.telegram_feed

import android.app.Application
import com.pravera.flutter_foreground_task.FlutterForegroundTaskLifecycleListener
import com.pravera.flutter_foreground_task.FlutterForegroundTaskPlugin
import com.pravera.flutter_foreground_task.FlutterForegroundTaskStarter
import io.flutter.embedding.engine.FlutterEngine

/**
 * Gives the foreground service's Flutter engine, where read-aloud runs, the app's own
 * channels. Android starts that service without an activity after a reboot or an update, so
 * this is done for every engine the service makes, not in [MainActivity].
 */
class FeedApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        FlutterForegroundTaskPlugin.addTaskLifecycleListener(
            object : FlutterForegroundTaskLifecycleListener {
                private var keys: ReadAloudKeys? = null

                override fun onEngineCreate(flutterEngine: FlutterEngine?) {
                    keys?.dispose()
                    keys = flutterEngine?.let {
                        ReadAloudKeys(this@FeedApplication, it.dartExecutor.binaryMessenger)
                    }
                }

                override fun onTaskStart(starter: FlutterForegroundTaskStarter) {}

                override fun onTaskRepeatEvent() {}

                override fun onTaskDestroy() {}

                override fun onEngineWillDestroy() {
                    keys?.dispose()
                    keys = null
                }
            },
        )
    }
}
