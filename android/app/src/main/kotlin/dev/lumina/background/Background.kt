package dev.lumina.background

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import dev.lumina.lumina.LuminaEngine
import dev.lumina.lumina.MainActivity
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * How Lumina stays reachable without Firebase (owner item 22):
 * - "connected": [KeepAliveService] holds the engine (Dart + TDLib) so
 *   messages and calls arrive in real time;
 * - "saver": [SyncWorker] boots it every ~15 minutes to fetch messages;
 * - "off": only while the app is open.
 * The mode is mirrored here (native prefs) so boot can act before Dart runs.
 */
object Background {
    private const val TAG = "LuminaBackground"
    private const val PREFS = "lumina_background"
    private const val WORK = "lumina-sync"
    const val CONNECTED = "connected"
    const val SAVER = "saver"
    const val OFF = "off"

    fun mode(context: Context): String =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("mode", CONNECTED) ?: CONNECTED

    /** Stores [mode] and starts / stops the matching worker. */
    fun apply(context: Context, mode: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString("mode", mode).apply()
        val work = WorkManager.getInstance(context)
        when (mode) {
            CONNECTED -> {
                work.cancelUniqueWork(WORK)
                KeepAliveService.start(context)
            }
            SAVER -> {
                KeepAliveService.stop(context)
                work.enqueueUniquePeriodicWork(
                    WORK,
                    ExistingPeriodicWorkPolicy.UPDATE,
                    PeriodicWorkRequestBuilder<SyncWorker>(15, TimeUnit.MINUTES).build(),
                )
            }
            else -> {
                KeepAliveService.stop(context)
                work.cancelUniqueWork(WORK)
            }
        }
    }

    /** After boot or an update: resume the stored mode. */
    fun resume(context: Context) {
        try {
            apply(context, mode(context))
        } catch (e: Exception) {
            Log.w(TAG, "Could not resume background mode", e)
        }
    }

    /** Boots the engine headless (no-op when running). Any thread. */
    fun ensureEngine(context: Context) {
        val app = context.applicationContext
        if (Looper.myLooper() == Looper.getMainLooper()) {
            LuminaEngine.ensure(app)
        } else {
            val done = CountDownLatch(1)
            Handler(Looper.getMainLooper()).post {
                try {
                    LuminaEngine.ensure(app)
                } finally {
                    done.countDown()
                }
            }
            done.await(10, TimeUnit.SECONDS)
        }
    }

    internal fun openApp(context: Context): PendingIntent = PendingIntent.getActivity(
        context,
        10,
        Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )
}

/** Keeps the Telegram connection open: a quiet, permanent notification. */
class KeepAliveService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            val n = notification()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
            } else {
                startForeground(ID, n)
            }
            Background.ensureEngine(this)
        } catch (e: Exception) {
            Log.w("KeepAliveService", "Could not stay in the foreground", e)
            stopSelf()
            return START_NOT_STICKY
        }
        // Android restarts it after killing the process for memory.
        return START_STICKY
    }

    @Suppress("DEPRECATION")
    private fun notification(): Notification {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL, "Connection", NotificationManager.IMPORTANCE_MIN).apply {
                    description = "Keeps Lumina connected for messages and calls (no Google push)"
                    setShowBadge(false)
                },
            )
            Notification.Builder(this, CHANNEL)
        } else {
            Notification.Builder(this).setPriority(Notification.PRIORITY_MIN)
        }
        return builder
            .setSmallIcon(android.R.drawable.stat_notify_sync_noanim)
            .setContentTitle("Lumina is connected")
            .setContentText("Receiving messages and calls")
            .setContentIntent(Background.openApp(this))
            .setOngoing(true)
            .setShowWhen(false)
            .build()
    }

    companion object {
        private const val CHANNEL = "background_connection"
        private const val ID = 4301

        fun start(context: Context) {
            try {
                val intent = Intent(context, KeepAliveService::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(intent)
                else context.startService(intent)
            } catch (e: Exception) {
                // Background start not allowed right now (Android 12+); the
                // next app start or boot tries again.
                Log.w("KeepAliveService", "Start refused", e)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, KeepAliveService::class.java))
        }
    }
}

/** Battery saver: boot the engine, give TDLib time to sync, let it go. */
class SyncWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        val wasRunning = LuminaEngine.isRunning()
        Background.ensureEngine(applicationContext)
        // TDLib reconnects, fetches updates and the notification center posts
        // what's new. A running app needs no extra wait.
        if (!wasRunning) Thread.sleep(SYNC_MS)
        return Result.success()
    }

    companion object {
        private const val SYNC_MS = 60_000L
    }
}

/** Boot / app update: resume the stored background mode. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED -> Background.resume(context)
        }
    }
}
