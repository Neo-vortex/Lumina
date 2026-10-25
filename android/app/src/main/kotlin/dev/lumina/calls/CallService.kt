package dev.lumina.calls

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
import dev.lumina.lumina.MainActivity

/**
 * Keeps the process (and the microphone) in the foreground during a call,
 * with an ongoing notification: tap to return, "Hang up" to end. The call
 * itself runs in [CallChannel] / [NativeCall].
 */
class CallService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "Call"
        val text = intent?.getStringExtra(EXTRA_TEXT) ?: "Ongoing call"
        val video = intent?.getBooleanExtra(EXTRA_VIDEO, false) ?: false
        val screen = intent?.getBooleanExtra(EXTRA_SCREEN, false) ?: false
        try {
            val notification = ongoing(this, title, text)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                var type = ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                // A type whose permission is missing would throw and end the call's service.
                if (video && checkSelfPermission(android.Manifest.permission.CAMERA) ==
                    android.content.pm.PackageManager.PERMISSION_GRANTED
                ) {
                    type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
                }
                if (screen) type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
                startForeground(ONGOING_ID, notification, type)
            } else {
                startForeground(ONGOING_ID, notification)
            }
            screenReady = screen
        } catch (e: Exception) {
            Log.w(TAG, "Could not start the call service", e)
            stopSelf()
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        screenReady = false
        super.onDestroy()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // The Flutter engine (and with it the call) goes away with the task.
        stopSelf()
    }

    companion object {
        private const val TAG = "CallService"
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_TEXT = "text"
        private const val EXTRA_VIDEO = "video"
        private const val EXTRA_SCREEN = "screen"

        /** The service runs with the mediaProjection type (screen sharing may start). */
        @Volatile var screenReady = false
            private set

        private var lastTitle = "Call"
        private var lastText = "Ongoing call"
        const val ONGOING_CHANNEL = "calls_ongoing"
        const val INCOMING_CHANNEL = "calls_incoming"
        const val ONGOING_ID = 4201
        const val INCOMING_ID = 4202

        /** Broadcast actions from notification buttons, handled by [CallChannel]. */
        const val ACTION_HANG_UP = "dev.lumina.calls.HANG_UP"
        const val ACTION_DECLINE = "dev.lumina.calls.DECLINE"

        /** Starts the service, or updates its types / text while it runs. */
        fun start(
            context: Context,
            title: String = lastTitle,
            text: String = lastText,
            video: Boolean,
            screen: Boolean = false,
        ): Boolean = try {
            lastTitle = title
            lastText = text
            val intent = Intent(context, CallService::class.java)
                .putExtra(EXTRA_TITLE, title)
                .putExtra(EXTRA_TEXT, text)
                .putExtra(EXTRA_VIDEO, video)
                .putExtra(EXTRA_SCREEN, screen)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(intent)
            else context.startService(intent)
            true
        } catch (e: Exception) {
            Log.w(TAG, "Could not start the call service", e)
            false
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, CallService::class.java))
        }

        fun channels(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(
                NotificationChannel(ONGOING_CHANNEL, "Ongoing calls", NotificationManager.IMPORTANCE_LOW),
            )
            nm.createNotificationChannel(
                NotificationChannel(INCOMING_CHANNEL, "Incoming calls", NotificationManager.IMPORTANCE_HIGH).apply {
                    description = "Rings when someone calls you"
                    // CallChannel plays the ringtone itself (looping, call volume).
                    setSound(null, null)
                    enableVibration(false)
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                },
            )
        }

        fun openApp(context: Context, action: String, requestCode: Int): PendingIntent = PendingIntent.getActivity(
            context,
            requestCode,
            Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK)
                .putExtra(CallChannel.EXTRA_CALL_ACTION, action),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        fun broadcast(context: Context, action: String, requestCode: Int): PendingIntent = PendingIntent.getBroadcast(
            context,
            requestCode,
            Intent(action).setPackage(context.packageName),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        @Suppress("DEPRECATION")
        private fun builder(context: Context, channel: String): Notification.Builder =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(context, channel)
            else Notification.Builder(context)

        fun ongoing(context: Context, title: String, text: String): Notification {
            channels(context)
            return builder(context, ONGOING_CHANNEL)
                .setSmallIcon(android.R.drawable.stat_sys_phone_call)
                .setContentTitle(title)
                .setContentText(text)
                .setContentIntent(openApp(context, "open", 1))
                .setOngoing(true)
                .setCategory(Notification.CATEGORY_CALL)
                .addAction(
                    Notification.Action.Builder(null, "Hang up", broadcast(context, ACTION_HANG_UP, 2)).build(),
                )
                .build()
        }

        @Suppress("DEPRECATION")
        fun incoming(context: Context, title: String, video: Boolean): Notification {
            channels(context)
            val full = openApp(context, "open", 3)
            return builder(context, INCOMING_CHANNEL)
                .setSmallIcon(android.R.drawable.stat_sys_phone_call)
                .setContentTitle(title)
                .setContentText(if (video) "Incoming video call" else "Incoming call")
                .setCategory(Notification.CATEGORY_CALL)
                .setPriority(Notification.PRIORITY_MAX)
                .setOngoing(true)
                .setContentIntent(full)
                .setFullScreenIntent(full, true)
                .addAction(
                    Notification.Action.Builder(null, "Decline", broadcast(context, ACTION_DECLINE, 4)).build(),
                )
                .addAction(Notification.Action.Builder(null, "Answer", openApp(context, "accept", 5)).build())
                .build()
        }
    }
}
