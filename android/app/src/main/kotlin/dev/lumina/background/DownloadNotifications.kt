package dev.lumina.background

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * "dev.lumina/downloads": one quiet ongoing "Downloading" notification with
 * Pause all, and a "Downloaded" one per finished file (tap opens Lumina,
 * which opens the file). Events go back on "dev.lumina/downloads/events".
 */
class DownloadNotifications(private val context: Context, messenger: BinaryMessenger) {
    private val main = Handler(Looper.getMainLooper())
    private var events: EventChannel.EventSink? = null

    init {
        instance = this
        MethodChannel(messenger, "dev.lumina/downloads").setMethodCallHandler { c, r ->
            when (c.method) {
                "progress" -> {
                    progress((c.argument<Number>("count") ?: 0).toInt(), (c.argument<Number>("percent") ?: 0).toInt())
                    r.success(null)
                }
                "clearProgress" -> {
                    NotificationManagerCompat.from(context).cancel(PROGRESS_ID)
                    r.success(null)
                }
                "completed" -> {
                    completed(
                        (c.argument<Number>("id") ?: 0).toInt(),
                        c.argument<String>("name") ?: "",
                        c.argument<String>("path") ?: "",
                    )
                    r.success(null)
                }
                else -> r.notImplemented()
            }
        }
        EventChannel(messenger, "dev.lumina/downloads/events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                events = sink
                synchronized(pending) {
                    pending.forEach(sink::success)
                    pending.clear()
                }
            }

            override fun onCancel(arguments: Any?) {
                events = null
            }
        })
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = context.getSystemService(NotificationManager::class.java)
        if (nm.getNotificationChannel(CHANNEL) == null) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL, "Downloads", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "Download progress and finished files"
                },
            )
        }
    }

    private fun canPost(): Boolean = NotificationManagerCompat.from(context).areNotificationsEnabled()

    private fun progress(count: Int, percent: Int) {
        if (!canPost()) return
        ensureChannel()
        val pause = PendingIntent.getBroadcast(
            context,
            PROGRESS_ID,
            Intent(context, ActionReceiver::class.java).setAction(ACTION_PAUSE_ALL),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val n = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(if (count == 1) "Downloading 1 file" else "Downloading $count files")
            .setContentText("$percent%")
            .setProgress(100, percent, false)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setContentIntent(openApp(null, PROGRESS_ID))
            .addAction(0, "Pause all", pause)
            .build()
        try {
            NotificationManagerCompat.from(context).notify(PROGRESS_ID, n)
        } catch (_: SecurityException) {
            // POST_NOTIFICATIONS was revoked.
        }
    }

    private fun completed(id: Int, name: String, path: String) {
        if (!canPost()) return
        ensureChannel()
        val requestId = COMPLETED_BASE + (id % 1000)
        val n = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle("Downloaded")
            .setContentText(name)
            .setAutoCancel(true)
            .setContentIntent(openApp(path, requestId))
            .build()
        try {
            NotificationManagerCompat.from(context).notify(requestId, n)
        } catch (_: SecurityException) {
            // POST_NOTIFICATIONS was revoked.
        }
    }

    private fun openApp(path: String?, requestCode: Int): PendingIntent? {
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: return null
        launch.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        if (!path.isNullOrEmpty()) launch.putExtra(EXTRA_OPEN_DOWNLOAD, path)
        return PendingIntent.getActivity(
            context,
            requestCode,
            launch,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    private fun emit(event: String) = main.post {
        val sink = events
        if (sink != null) sink.success(event) else synchronized(pending) { pending.add(event) }
    }

    /** "Pause all" from the notification. */
    class ActionReceiver : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action == ACTION_PAUSE_ALL) instance?.emit("pauseAll")
        }
    }

    companion object {
        const val CHANNEL = "downloads"
        const val EXTRA_OPEN_DOWNLOAD = "dev.lumina.OPEN_DOWNLOAD"
        private const val ACTION_PAUSE_ALL = "dev.lumina.downloads.PAUSE_ALL"
        private const val PROGRESS_ID = 4100
        private const val COMPLETED_BASE = 4200
        private val pending = mutableListOf<String>()

        @Volatile private var instance: DownloadNotifications? = null

        /** A tapped "Downloaded" notification: Dart opens the file. */
        fun openDownload(path: String) {
            val i = instance
            if (i != null) i.emit("open:$path") else synchronized(pending) { pending.add("open:$path") }
        }
    }
}
