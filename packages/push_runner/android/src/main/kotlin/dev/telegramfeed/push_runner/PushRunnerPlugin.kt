package dev.telegramfeed.push_runner

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CompletableDeferred

/**
 * The channel `tf/push` on every engine of the app: the FCM token, the queue of what
 * waits for a run, and, on the engine of a run, the word that the run is over.
 */
class PushRunnerPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var context: Context
    private var channel: MethodChannel? = null

    /** Set while this engine hosts a run ([PushWorker]); completed by `done`. */
    internal var run: CompletableDeferred<Unit>? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "tf/push").also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "token" -> PushToken.get(context) { result.success(it) }
            "take" -> result.success(PushQueue.take(context))
            "queue" -> {
                PushQueue.add(context, call.arguments as String)
                result.success(null)
            }
            "done" -> {
                run?.complete(Unit)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /** More waits for the run of this engine. Main thread. */
    internal fun queued() {
        channel?.invokeMethod("queued", null)
    }

    /** Android ends the run of this engine early. Main thread. */
    internal fun stop() {
        channel?.invokeMethod("stop", null)
    }
}
