package dev.telegramfeed.telegram_feed

import android.app.Application
import com.pravera.flutter_foreground_task.FlutterForegroundTaskLifecycleListener
import com.pravera.flutter_foreground_task.FlutterForegroundTaskPlugin
import com.pravera.flutter_foreground_task.FlutterForegroundTaskStarter
import dev.telegramfeed.push_runner.PushRunner
import io.flutter.embedding.engine.FlutterEngine

/**
 * Gives the engines that run without an activity the app's own channels: the foreground
 * service's (instant rules), which Android starts by itself after a reboot or an update,
 * and a push run's. Read-aloud runs there and the notifications are made there, so this
 * is done for every such engine, not in [MainActivity].
 */
class FeedApplication : Application() {
    private val installed = mutableMapOf<FlutterEngine, List<() -> Unit>>()

    private fun install(engine: FlutterEngine) {
        val messenger = engine.dartExecutor.binaryMessenger
        val keys = ReadAloudKeys(this, messenger)
        val badge = LauncherBadge(this, messenger)
        val pictures = NotificationPictures(this, messenger)
        installed[engine] = listOf(keys::dispose, badge::dispose, pictures::dispose)
    }

    private fun uninstall(engine: FlutterEngine) {
        installed.remove(engine)?.forEach { it() }
    }

    override fun onCreate() {
        super.onCreate()
        PushRunner.engines = object : PushRunner.Engines {
            override fun created(engine: FlutterEngine) = install(engine)

            override fun destroyed(engine: FlutterEngine) = uninstall(engine)
        }
        FlutterForegroundTaskPlugin.addTaskLifecycleListener(
            object : FlutterForegroundTaskLifecycleListener {
                private var engine: FlutterEngine? = null

                override fun onEngineCreate(flutterEngine: FlutterEngine?) {
                    engine?.let(::uninstall)
                    engine = flutterEngine?.also(::install)
                }

                override fun onTaskStart(starter: FlutterForegroundTaskStarter) {}

                override fun onTaskRepeatEvent() {}

                override fun onTaskDestroy() {}

                override fun onEngineWillDestroy() {
                    engine?.let(::uninstall)
                    engine = null
                }
            },
        )
    }
}
