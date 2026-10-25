package dev.lumina.calls

import android.content.Context
import android.util.Log
import androidx.annotation.Keep
import org.telegram.messenger.ApplicationLoader
import org.webrtc.ContextUtils
import org.webrtc.VideoSink

/**
 * One private call in the tgcalls engine (liblumina_calls.so). TDLib does the
 * signaling; this class gets the parameters of CallStateReady, relays the
 * engine's signaling data and reports its state. Method and field names are
 * bound by name from android/calls-engine/src/lumina_calls_jni.cpp.
 */
@Keep
class NativeCall(private val listener: Listener) {
    interface Listener {
        fun onState(state: Int)
        fun onSignalBars(bars: Int)
        fun onAudioLevels(mine: Float, theirs: Float)
        fun onRemoteMedia(audioState: Int, videoState: Int)
        fun onSignaling(data: ByteArray)
        fun onStopped(debugLog: String, ratingSuggested: Boolean)
    }

    /** Native CallHolder*, 0 when not running. Read by the glue. */
    @JvmField
    var nativePtr: Long = 0

    @Keep
    class Config(
        @JvmField val initializationTimeout: Double,
        @JvmField val receiveTimeout: Double,
        /** 0 never, 1 on mobile data, 2 always. */
        @JvmField val dataSaving: Int,
        @JvmField val enableP2p: Boolean,
        @JvmField val enableAec: Boolean,
        @JvmField val enableNs: Boolean,
        @JvmField val enableAgc: Boolean,
        @JvmField val logPath: String,
        @JvmField val statsLogPath: String,
        @JvmField val maxApiLayer: Int,
        @JvmField val customParameters: String,
    )

    /** A server from CallStateReady: WebRTC STUN/TURN (isRtc) or a Telegram reflector. */
    @Keep
    class Endpoint(
        @JvmField val isRtc: Boolean,
        @JvmField val id: Long,
        @JvmField val ipv4: String,
        @JvmField val ipv6: String,
        @JvmField val port: Int,
        /** ENDPOINT_* */
        @JvmField val type: Int,
        @JvmField val peerTag: ByteArray?,
        @JvmField val turn: Boolean,
        @JvmField val tcp: Boolean,
        @JvmField val reflectorId: Int,
        @JvmField val username: String,
        @JvmField val password: String,
    )

    /** SOCKS5 proxy for the call ("Use proxy for calls"). */
    @Keep
    class Proxy(
        @JvmField val host: String,
        @JvmField val port: Int,
        @JvmField val login: String,
        @JvmField val password: String,
    )

    fun begin(
        version: String,
        config: Config,
        endpoints: Array<Endpoint>,
        proxy: Proxy?,
        networkType: Int,
        encryptionKey: ByteArray,
        outgoing: Boolean,
        remoteSink: VideoSink,
        capturer: Long,
        aspectRatio: Float,
        persistentStatePath: String,
    ) {
        check(nativePtr == 0L) { "Call already started" }
        nativePtr = start(
            version, config, endpoints, proxy, networkType, encryptionKey, outgoing, remoteSink, capturer,
            aspectRatio, persistentStatePath,
        )
    }

    /** Ends the call; [Listener.onStopped] follows. */
    fun end() {
        if (nativePtr == 0L) return
        stop()
    }

    private external fun start(
        version: String,
        config: Config,
        endpoints: Array<Endpoint>,
        proxy: Proxy?,
        networkType: Int,
        encryptionKey: ByteArray,
        outgoing: Boolean,
        remoteSink: VideoSink,
        capturer: Long,
        aspectRatio: Float,
        persistentStatePath: String,
    ): Long

    private external fun stop()
    external fun receiveSignaling(data: ByteArray)
    external fun setMuted(muted: Boolean)
    external fun setNetworkType(type: Int)
    external fun setAudioOutputGainControl(enabled: Boolean)
    external fun setEchoCancellationStrength(strength: Int)
    external fun debugInfo(): String?
    external fun lastError(): String?

    /** [type]: CAPTURE_BACK, CAPTURE_FRONT or CAPTURE_SCREEN. */
    external fun setupOutgoingVideo(localSink: VideoSink, type: Int)
    external fun useCapturer(capturer: Long)
    external fun setVideoState(state: Int)
    external fun switchCamera(front: Boolean)
    external fun stopVideo()

    // Called from native threads.
    @Keep private fun onStateUpdated(state: Int) = listener.onState(state)
    @Keep private fun onSignalBarsUpdated(bars: Int) = listener.onSignalBars(bars)
    @Keep private fun onAudioLevels(mine: Float, theirs: Float) = listener.onAudioLevels(mine, theirs)
    @Keep private fun onRemoteMediaState(audio: Int, video: Int) = listener.onRemoteMedia(audio, video)
    @Keep private fun onSignalingData(data: ByteArray) = listener.onSignaling(data)

    @Keep
    private fun onStop(debugLog: String, ratingSuggested: Boolean) {
        nativePtr = 0
        listener.onStopped(debugLog, ratingSuggested)
    }

    companion object {
        private const val TAG = "NativeCall"

        const val STATE_WAIT_INIT = 1
        const val STATE_WAIT_INIT_ACK = 2
        const val STATE_ESTABLISHED = 3
        const val STATE_FAILED = 4
        const val STATE_RECONNECTING = 5

        const val ENDPOINT_INET = 0
        const val ENDPOINT_LAN = 1
        const val ENDPOINT_UDP_RELAY = 2
        const val ENDPOINT_TCP_RELAY = 3

        const val CAPTURE_BACK = 0
        const val CAPTURE_FRONT = 1
        const val CAPTURE_SCREEN = 2

        /** tgcalls VideoState. */
        const val VIDEO_INACTIVE = 0
        const val VIDEO_PAUSED = 1
        const val VIDEO_ACTIVE = 2

        @Volatile
        private var loaded: Boolean? = null

        /**
         * Loads the engine once. False when this build has no
         * liblumina_calls.so (calls are then unavailable, nothing else breaks).
         */
        @JvmStatic
        fun load(context: Context): Boolean {
            loaded?.let { return it }
            synchronized(this) {
                loaded?.let { return it }
                val app = context.applicationContext
                ApplicationLoader.applicationContext = app
                ContextUtils.initialize(app)
                val ok = try {
                    System.loadLibrary("lumina_calls")
                    true
                } catch (e: UnsatisfiedLinkError) {
                    Log.w(TAG, "Calls engine not bundled", e)
                    false
                }
                loaded = ok
                return ok
            }
        }

        /** Protocol versions for CallProtocol.libraryVersions, newest last. */
        @JvmStatic external fun versions(): Array<String>
        @JvmStatic external fun maxLayer(): Int

        /** A capturer for the preview before (or outside) a call. */
        @JvmStatic external fun createCapturer(localSink: VideoSink, type: Int): Long
        @JvmStatic external fun destroyCapturer(capturer: Long)
        @JvmStatic external fun switchCapturerCamera(capturer: Long, front: Boolean)
        @JvmStatic external fun setCapturerState(capturer: Long, state: Int)
    }
}
