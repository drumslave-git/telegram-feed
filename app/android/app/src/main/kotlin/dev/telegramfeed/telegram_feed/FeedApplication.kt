package dev.telegramfeed.telegram_feed

import android.app.Application
import dev.telegramfeed.push_runner.PushRunner
import io.flutter.embedding.engine.FlutterEngine

/**
 * Gives the engine of a push run, where the notifications are made and read-aloud runs
 * while the app is closed, the app's own channels. Android starts a run without an
 * activity, so this is done here, not in [MainActivity].
 */
class FeedApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        PushRunner.engines = object : PushRunner.Engines {
            private val installed = mutableMapOf<FlutterEngine, List<() -> Unit>>()

            override fun created(engine: FlutterEngine) {
                val messenger = engine.dartExecutor.binaryMessenger
                val app = this@FeedApplication
                val keys = ReadAloudKeys(app, messenger)
                val badge = LauncherBadge(app, messenger)
                val pictures = NotificationPictures(app, messenger)
                installed[engine] = listOf(keys::dispose, badge::dispose, pictures::dispose)
            }

            override fun destroyed(engine: FlutterEngine) {
                installed.remove(engine)?.forEach { it() }
            }
        }
    }
}
