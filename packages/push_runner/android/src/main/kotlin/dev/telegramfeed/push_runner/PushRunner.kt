package dev.telegramfeed.push_runner

import io.flutter.embedding.engine.FlutterEngine

/** The app's hook into the engines of runs: it adds its own channels to each. */
object PushRunner {
    interface Engines {
        fun created(engine: FlutterEngine)

        fun destroyed(engine: FlutterEngine)
    }

    @JvmStatic
    var engines: Engines? = null
}
