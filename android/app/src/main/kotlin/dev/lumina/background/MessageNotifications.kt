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
import androidx.core.app.Person
import androidx.core.app.RemoteInput
import dev.lumina.lumina.MainActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * "dev.lumina/notifications": Dart's notification center (built on TDLib's
 * notification groups) shows chats as MessagingStyle notifications here;
 * Reply / Mark as read come back as events, also when Lumina wasn't running
 * ([ActionReceiver] boots the engine and queues them).
 */
class MessageNotifications(private val context: Context, messenger: BinaryMessenger) {
    private val main = Handler(Looper.getMainLooper())
    private var events: EventChannel.EventSink? = null

    init {
        instance = this
        MethodChannel(messenger, "dev.lumina/notifications").setMethodCallHandler { c, r -> handle(c, r) }
        EventChannel(messenger, "dev.lumina/notifications/events").setStreamHandler(object : EventChannel.StreamHandler {
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

    private fun handle(c: MethodCall, r: MethodChannel.Result) {
        when (c.method) {
            "show" -> {
                show(c.arguments as Map<*, *>)
                r.success(null)
            }
            "cancel" -> {
                NotificationManagerCompat.from(context).cancel(TAG, (c.arguments as Number).toInt())
                r.success(null)
            }
            "cancelAll" -> {
                val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    nm.activeNotifications.filter { it.tag == TAG }.forEach { nm.cancel(TAG, it.id) }
                }
                r.success(null)
            }
            "setBackgroundMode" -> {
                Background.apply(context, c.arguments as String)
                r.success(null)
            }
            "backgroundMode" -> r.success(Background.mode(context))
            else -> r.notImplemented()
        }
    }

    /**
     * A chat's unread messages: id (TDLib group id), chatId, title, isGroup,
     * silent, messages [{sender, text, date (ms), outgoing}].
     */
    private fun show(n: Map<*, *>) {
        channel(context)
        val id = (n["id"] as Number).toInt()
        val chatId = (n["chatId"] as Number).toLong()
        val me = Person.Builder().setName("You").build()
        val style = NotificationCompat.MessagingStyle(me)
            .setConversationTitle(if (n["isGroup"] == true) n["title"] as String else null)
            .setGroupConversation(n["isGroup"] == true)
        for (m in n["messages"] as List<*>) {
            m as Map<*, *>
            val sender = if (m["outgoing"] == true) null else Person.Builder().setName(m["sender"] as String).build()
            style.addMessage(m["text"] as String, (m["date"] as Number).toLong(), sender)
        }
        val reply = NotificationCompat.Action.Builder(
            android.R.drawable.ic_menu_send,
            "Reply",
            action(ACTION_REPLY, id, chatId),
        )
            .addRemoteInput(RemoteInput.Builder(KEY_TEXT).setLabel("Message").build())
            .setSemanticAction(NotificationCompat.Action.SEMANTIC_ACTION_REPLY)
            .setShowsUserInterface(false)
            .build()
        val read = NotificationCompat.Action.Builder(
            android.R.drawable.ic_menu_view,
            "Mark as read",
            action(ACTION_READ, id, chatId),
        )
            .setSemanticAction(NotificationCompat.Action.SEMANTIC_ACTION_MARK_AS_READ)
            .setShowsUserInterface(false)
            .build()
        val open = PendingIntent.getActivity(
            context,
            id,
            Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                .putExtra(EXTRA_OPEN_CHAT, chatId),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val notification = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(android.R.drawable.stat_notify_chat)
            .setStyle(style)
            .setContentIntent(open)
            .setAutoCancel(true)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setSilent(n["silent"] == true)
            .setOnlyAlertOnce(n["alert"] != true)
            .addAction(reply)
            .addAction(read)
            .build()
        try {
            NotificationManagerCompat.from(context).notify(TAG, id, notification)
        } catch (e: SecurityException) {
            // Notifications not allowed (Android 13+ permission).
        }
    }

    private fun action(action: String, id: Int, chatId: Long): PendingIntent = PendingIntent.getBroadcast(
        context,
        id * 2 + if (action == ACTION_REPLY) 0 else 1,
        Intent(context, ActionReceiver::class.java)
            .setAction(action)
            .putExtra(EXTRA_GROUP, id)
            .putExtra(EXTRA_CHAT, chatId),
        // Replies need a mutable intent for the typed text.
        (if (action == ACTION_REPLY) PendingIntent.FLAG_MUTABLE else PendingIntent.FLAG_IMMUTABLE) or
            PendingIntent.FLAG_UPDATE_CURRENT,
    )

    internal fun deliver(event: Map<String, Any?>) {
        main.post {
            val sink = events
            if (sink != null) sink.success(event) else synchronized(pending) { pending += event }
        }
    }

    /** Reply / Mark as read from a notification. */
    class ActionReceiver : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val group = intent.getIntExtra(EXTRA_GROUP, 0)
            val chatId = intent.getLongExtra(EXTRA_CHAT, 0)
            val event = when (intent.action) {
                ACTION_REPLY -> {
                    val text = RemoteInput.getResultsFromIntent(intent)?.getCharSequence(KEY_TEXT)?.toString()
                    if (text.isNullOrBlank()) return
                    mapOf("type" to "reply", "chatId" to chatId, "groupId" to group, "text" to text)
                }
                ACTION_READ -> mapOf("type" to "read", "chatId" to chatId, "groupId" to group)
                else -> return
            }
            // Clear it now; TDLib removes the group once the message is read.
            NotificationManagerCompat.from(context).cancel(TAG, group)
            val result = goAsync()
            Background.ensureEngine(context)
            val target = instance
            if (target != null) target.deliver(event) else synchronized(pending) { pending += event }
            result.finish()
        }
    }

    companion object {
        private const val TAG = "lumina.chat"
        private const val CHANNEL = "messages"
        private const val ACTION_REPLY = "dev.lumina.notifications.REPLY"
        private const val ACTION_READ = "dev.lumina.notifications.READ"
        private const val KEY_TEXT = "text"
        private const val EXTRA_GROUP = "group"
        private const val EXTRA_CHAT = "chat"

        /** MainActivity extra: open this chat. */
        const val EXTRA_OPEN_CHAT = "lumina.openChat"

        @Volatile private var instance: MessageNotifications? = null

        /** Actions that arrived before Dart listened. */
        private val pending = mutableListOf<Map<String, Any?>>()

        fun channel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL, "Messages", NotificationManager.IMPORTANCE_HIGH).apply {
                    description = "New messages"
                },
            )
        }

        /** A notification tap asked to open a chat (MainActivity forwards it). */
        fun openChat(chatId: Long) {
            val event = mapOf("type" to "open", "chatId" to chatId)
            val target = instance
            if (target != null) target.deliver(event) else synchronized(pending) { pending += event }
        }
    }
}
