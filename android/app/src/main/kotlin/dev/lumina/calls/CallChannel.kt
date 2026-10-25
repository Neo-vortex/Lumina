package dev.lumina.calls

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.NoiseSuppressor
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.webrtc.VideoSink
import java.io.File

/**
 * "dev.lumina/calls": the Dart CallEngine (lib/features/calls/data/
 * call_engine.dart) over [NativeCall]. One call at a time. While a call
 * runs, audio is in communication mode with focus held.
 */
class CallChannel(private val context: Context, messenger: BinaryMessenger) : NativeCall.Listener {
    private val main = Handler(Looper.getMainLooper())
    private val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var events: EventChannel.EventSink? = null
    private var call: NativeCall? = null
    private var focus: AudioFocusRequest? = null
    private var previousMode = AudioManager.MODE_NORMAL

    // Video frames are dropped until the video phase adds renderers.
    private val noVideo = VideoSink { }

    init {
        MethodChannel(messenger, "dev.lumina/calls").setMethodCallHandler { c, r -> handle(c, r) }
        EventChannel(messenger, "dev.lumina/calls/events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                events = sink
            }

            override fun onCancel(arguments: Any?) {
                events = null
            }
        })
    }

    private fun handle(c: MethodCall, r: MethodChannel.Result) {
        when (c.method) {
            "available" -> r.success(NativeCall.load(context))
            "capabilities" -> {
                if (!NativeCall.load(context)) return r.success(null)
                r.success(
                    mapOf(
                        "versions" to NativeCall.versions().toList(),
                        "maxLayer" to NativeCall.maxLayer(),
                        "deviceAec" to runCatching { AcousticEchoCanceler.isAvailable() }.getOrDefault(false),
                        "deviceNs" to runCatching { NoiseSuppressor.isAvailable() }.getOrDefault(false),
                    ),
                )
            }
            "start" -> try {
                start(c.arguments as Map<*, *>)
                r.success(null)
            } catch (e: Exception) {
                r.error("start_failed", e.message, null)
            }
            "receiveSignaling" -> {
                call?.receiveSignaling(c.arguments as ByteArray)
                r.success(null)
            }
            "setMuted" -> {
                call?.setMuted(c.arguments as Boolean)
                r.success(null)
            }
            "stop" -> {
                val running = call
                if (running == null) {
                    emit(mapOf("type" to "stopped", "debugLog" to "", "ratingSuggested" to false))
                } else {
                    running.end()
                }
                r.success(null)
            }
            else -> r.notImplemented()
        }
    }

    private fun start(args: Map<*, *>) {
        check(NativeCall.load(context)) { "Calls engine not bundled" }
        check(call == null) { "A call is already running" }
        check(context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            "Microphone permission is needed for calls"
        }
        val endpoints = (args["endpoints"] as List<*>).map { e ->
            e as Map<*, *>
            NativeCall.Endpoint(
                isRtc = e["isRtc"] as Boolean,
                id = (e["id"] as Number).toLong(),
                ipv4 = e["ipv4"] as String,
                ipv6 = e["ipv6"] as String,
                port = (e["port"] as Number).toInt(),
                type = if (e["tcp"] == true) NativeCall.ENDPOINT_TCP_RELAY else NativeCall.ENDPOINT_UDP_RELAY,
                peerTag = e["peerTag"] as ByteArray?,
                turn = e["turn"] as Boolean,
                tcp = e["tcp"] as Boolean,
                reflectorId = (e["reflectorId"] as Number).toInt(),
                username = e["username"] as String,
                password = e["password"] as String,
            )
        }.toTypedArray()
        val proxy = (args["proxy"] as Map<*, *>?)?.let {
            NativeCall.Proxy(it["host"] as String, (it["port"] as Number).toInt(), it["login"] as String, it["password"] as String)
        }
        val logs = File(context.cacheDir, "calls").apply { mkdirs() }
        val config = NativeCall.Config(
            initializationTimeout = (args["initializationTimeout"] as Number).toDouble(),
            receiveTimeout = (args["receiveTimeout"] as Number).toDouble(),
            dataSaving = 0,
            enableP2p = args["allowP2p"] as Boolean,
            enableAec = args["enableAec"] as Boolean,
            enableNs = args["enableNs"] as Boolean,
            enableAgc = true,
            logPath = File(logs, "call.log").absolutePath,
            statsLogPath = File(logs, "call_stats.log").absolutePath,
            maxApiLayer = (args["maxLayer"] as Number).toInt(),
            customParameters = args["customParameters"] as String,
        )
        enterCallAudio()
        val native = NativeCall(this)
        try {
            native.begin(
                version = args["version"] as String,
                config = config,
                endpoints = endpoints,
                proxy = proxy,
                networkType = networkType(),
                encryptionKey = args["encryptionKey"] as ByteArray,
                outgoing = args["outgoing"] as Boolean,
                remoteSink = noVideo,
                capturer = 0,
                aspectRatio = 0f,
                persistentStatePath = File(context.cacheDir, "calls_persistent_state.json").absolutePath,
            )
        } catch (e: Exception) {
            leaveCallAudio()
            throw e
        }
        call = native
    }

    @Suppress("DEPRECATION")
    private fun enterCallAudio() {
        previousMode = audio.mode
        audio.mode = AudioManager.MODE_IN_COMMUNICATION
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focus = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build(),
                )
                .build()
                .also { audio.requestAudioFocus(it) }
        } else {
            audio.requestAudioFocus(null, AudioManager.STREAM_VOICE_CALL, AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
        }
    }

    @Suppress("DEPRECATION")
    private fun leaveCallAudio() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focus?.let { audio.abandonAudioFocusRequest(it) }
            focus = null
        } else {
            audio.abandonAudioFocus(null)
        }
        audio.mode = previousMode
    }

    /** Telegram's NET_TYPE_* numbering. */
    private fun networkType(): Int {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val caps = cm.getNetworkCapabilities(cm.activeNetwork) ?: return 0
        return when {
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> 6
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> 7
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> 11
            else -> 0
        }
    }

    private fun emit(event: Map<String, Any?>) {
        main.post { events?.success(event) }
    }

    override fun onState(state: Int) = emit(mapOf("type" to "state", "value" to state))
    override fun onSignalBars(bars: Int) = emit(mapOf("type" to "signalBars", "value" to bars))
    override fun onAudioLevels(mine: Float, theirs: Float) =
        emit(mapOf("type" to "audioLevels", "mine" to mine.toDouble(), "theirs" to theirs.toDouble()))
    override fun onRemoteMedia(audioState: Int, videoState: Int) =
        emit(mapOf("type" to "remoteMedia", "audio" to audioState, "video" to videoState))
    override fun onSignaling(data: ByteArray) = emit(mapOf("type" to "signaling", "data" to data))

    override fun onStopped(debugLog: String, ratingSuggested: Boolean) {
        main.post {
            call = null
            leaveCallAudio()
            events?.success(mapOf("type" to "stopped", "debugLog" to debugLog, "ratingSuggested" to ratingSuggested))
        }
    }
}
