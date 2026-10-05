package dev.telegramfeed.push_runner

import android.content.Context
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

/**
 * A run: an engine of its own runs the app's `pushMain`, which hosts the core and the
 * alerts (or hands the push to the app's core when the app is up) and says `done` when
 * nothing is left to do. Expedited work: from Android 12 on it shows no notification.
 */
class PushWorker(context: Context, params: WorkerParameters) :
    CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        val context = applicationContext
        if (PushQueue.isEmpty(context)) {
            PushQueue.started(null)
            PushQueue.ended(context)
            return Result.success()
        }
        val done = CompletableDeferred<Unit>()
        var engine: FlutterEngine? = null
        var plugin: PushRunnerPlugin? = null
        try {
            withContext(Dispatchers.Main) {
                val loader = FlutterInjector.instance().flutterLoader()
                loader.startInitialization(context)
                loader.ensureInitializationComplete(context, null)
                val e = FlutterEngine(context)
                engine = e
                PushRunner.engines?.created(e)
                val p = e.plugins.get(PushRunnerPlugin::class.java) as PushRunnerPlugin
                plugin = p
                p.run = done
                PushQueue.started(p)
                Log.i(TAG, "run starts")
                e.dartExecutor.executeDartEntrypoint(
                    DartExecutor.DartEntrypoint(loader.findAppBundlePath(), ENTRY_POINT),
                )
            }
            if (withTimeoutOrNull(RUN_LIMIT_MS) { done.await() } == null) {
                Log.w(TAG, "run over its time")
            }
        } finally {
            withContext(NonCancellable + Dispatchers.Main) {
                if (!done.isCompleted) {
                    // Stopped by Android or over its time: the core hands TDLib back first.
                    plugin?.stop()
                    withTimeoutOrNull(STOP_GRACE_MS) { done.await() }
                }
                PushQueue.ended(context)
                engine?.let {
                    PushRunner.engines?.destroyed(it)
                    it.destroy()
                }
                Log.i(TAG, "run ends")
            }
        }
        return Result.success()
    }

    companion object {
        private const val WORK = "push-run"
        private const val ENTRY_POINT = "pushMain"

        /** WorkManager stops a job at ten minutes. */
        private const val RUN_LIMIT_MS = 9 * 60 * 1000L
        private const val STOP_GRACE_MS = 15_000L

        fun enqueue(context: Context) {
            val request = OneTimeWorkRequestBuilder<PushWorker>()
                .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
                .build()
            WorkManager.getInstance(context)
                .enqueueUniqueWork(WORK, ExistingWorkPolicy.APPEND_OR_REPLACE, request)
        }
    }
}
