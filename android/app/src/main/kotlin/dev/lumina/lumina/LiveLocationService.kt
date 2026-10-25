package dev.lumina.lumina

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log

/**
 * Keeps the process in the foreground while a live location is shared, so
 * the Dart side (LiveLocationService) can keep sending fixes with the app in
 * the background. It does no location work itself.
 */
class LiveLocationService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIFICATION_ID, notification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
            } else {
                startForeground(NOTIFICATION_ID, notification())
            }
        } catch (e: Exception) {
            // Android 14+ refuses a location service without location access.
            Log.w(TAG, "Could not start live location service", e)
            stopSelf()
        }
        return START_NOT_STICKY
    }

    // The Flutter engine goes away with the task; nothing left to update.
    override fun onTaskRemoved(rootIntent: Intent?) {
        stopSelf()
    }

    @Suppress("DEPRECATION")
    private fun notification(): Notification {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL, "Live location", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "Shown while you share your live location"
                },
            )
            Notification.Builder(this, CHANNEL)
        } else {
            Notification.Builder(this)
        }
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return builder
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentTitle("Sharing live location")
            .setContentText("Open Lumina to stop sharing")
            .setContentIntent(open)
            .setOngoing(true)
            .build()
    }

    companion object {
        private const val TAG = "LiveLocation"
        private const val CHANNEL = "live_location"
        private const val NOTIFICATION_ID = 4108

        fun start(context: Context): Boolean = try {
            val intent = Intent(context, LiveLocationService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(intent)
            else context.startService(intent)
            true
        } catch (e: Exception) {
            // Background start not allowed (Android 12+).
            Log.w(TAG, "Could not start live location service", e)
            false
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, LiveLocationService::class.java))
        }
    }
}
