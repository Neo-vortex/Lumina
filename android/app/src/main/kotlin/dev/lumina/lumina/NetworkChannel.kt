package dev.lumina.lumina

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel

/**
 * "dev.lumina/network": the active connection as "none", "wifi", "mobile",
 * "roaming" or "other", sent on listen and on every change. Auto-download
 * picks its policy from it.
 */
class NetworkChannel(context: Context, messenger: BinaryMessenger) : EventChannel.StreamHandler {
    private val connectivity = context.getSystemService(ConnectivityManager::class.java)
    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var callback: ConnectivityManager.NetworkCallback? = null

    init {
        EventChannel(messenger, "dev.lumina/network").setStreamHandler(this)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
        events.success(describe(connectivity.getNetworkCapabilities(connectivity.activeNetwork)))
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) = send(describe(caps))

            override fun onLost(network: Network) = send("none")
        }
        callback = cb
        // The Handler overload needs API 26; callbacks come on a system thread.
        connectivity.registerDefaultNetworkCallback(cb)
    }

    override fun onCancel(arguments: Any?) {
        callback?.let { runCatching { connectivity.unregisterNetworkCallback(it) } }
        callback = null
        sink = null
    }

    private fun send(type: String) {
        main.post { sink?.success(type) }
    }

    private fun describe(caps: NetworkCapabilities?): String = when {
        caps == null -> "none"
        caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "wifi"
        caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) ->
            if (caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_ROAMING)) "mobile" else "roaming"
        else -> "other"
    }
}
