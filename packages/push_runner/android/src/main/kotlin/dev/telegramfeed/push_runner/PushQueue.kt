package dev.telegramfeed.push_runner

import android.content.Context
import android.os.Handler
import android.os.Looper
import org.json.JSONArray

/**
 * What waits for a run: pushes, buttons pressed while nothing ran, a token to register.
 * Kept in shared preferences, so a run that starts in a new process finds it. While a
 * run goes on in this process it is told of each new item; otherwise one is asked of
 * WorkManager.
 */
internal object PushQueue {
    private const val PREFS = "push_runner"
    private const val KEY = "queue"
    private val lock = Any()
    private val main = Handler(Looper.getMainLooper())

    /** The plugin of the engine whose run goes on in this process. */
    private var running: PushRunnerPlugin? = null

    /** A run was asked of WorkManager and has not started yet. */
    private var asked = false

    fun add(context: Context, item: String) {
        synchronized(lock) {
            save(context, load(context) + item)
            val run = running
            if (run != null) {
                main.post { run.queued() }
            } else if (!asked) {
                asked = true
                PushWorker.enqueue(context)
            }
        }
    }

    fun take(context: Context): List<String> = synchronized(lock) {
        load(context).also { save(context, emptyList()) }
    }

    fun isEmpty(context: Context): Boolean = synchronized(lock) { load(context).isEmpty() }

    /** A run starts, hosted by [plugin]'s engine; null for a run with nothing to do. */
    fun started(plugin: PushRunnerPlugin?) {
        synchronized(lock) {
            asked = false
            running = plugin
        }
    }

    /** The run is over; what came after its last look at the queue gets a run of its own. */
    fun ended(context: Context) {
        synchronized(lock) {
            running = null
            if (load(context).isNotEmpty() && !asked) {
                asked = true
                PushWorker.enqueue(context)
            }
        }
    }

    private fun load(context: Context): List<String> {
        val raw = prefs(context).getString(KEY, null) ?: return emptyList()
        val array = JSONArray(raw)
        return List(array.length()) { array.getString(it) }
    }

    private fun save(context: Context, items: List<String>) {
        prefs(context).edit().putString(KEY, JSONArray(items).toString()).commit()
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
