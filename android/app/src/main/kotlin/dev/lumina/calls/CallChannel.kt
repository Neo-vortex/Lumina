package dev.lumina.calls

import android.Manifest
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.NoiseSuppressor
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import org.telegram.messenger.voip.VideoCapturerDevice
import org.telegram.messenger.voip.VoIPService
import java.io.File

/**
 * "dev.lumina/calls": the Dart CallEngine (lib/features/calls/data/
 * call_engine.dart) over [NativeCall]. One call at a time. While a call
 * runs, audio is in communication mode with focus held.
 */
class CallChannel(
    private val context: Context,
    messenger: BinaryMessenger,
    private val textures: TextureRegistry,
) : NativeCall.Listener, CallTelecom.Listener {
    private val main = Handler(Looper.getMainLooper())
    private val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var events: EventChannel.EventSink? = null
    private var call: NativeCall? = null
    private var focus: AudioFocusRequest? = null
    private var previousMode = AudioManager.MODE_NORMAL
    private var ringtone: Ringtone? = null
    private var vibrating = false

    /** A notification action that arrived before Dart listened. */
    private var pendingAction: String? = null

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(c: Context, intent: Intent) {
            when (intent.action) {
                CallService.ACTION_HANG_UP -> onNotificationAction("hangup")
                CallService.ACTION_DECLINE -> onNotificationAction("decline")
            }
        }
    }

    // ---- Video ------------------------------------------------------------

    /** The other side's video and our camera preview, as Flutter textures. */
    private var remote: TextureRendererSink? = null
    private var local: TextureRendererSink? = null

    /** Camera capturer made before the call started (video calls), 0 if none. */
    private var preCapturer = 0L

    /** setupOutgoingVideo ran (the capturer exists; later on/off is a state change). */
    private var cameraSetUp = false
    private var front = true
    private var screenSharing = false
    private var cameraWasOn = false

    private fun remoteRenderer() = remote ?: TextureRendererSink(textures, "remote") { w, h ->
        emit(mapOf("type" to "videoSize", "which" to "remote", "width" to w, "height" to h))
    }.also { remote = it }

    private fun localRenderer() = local ?: TextureRendererSink(textures, "local") { w, h ->
        emit(mapOf("type" to "videoSize", "which" to "local", "width" to w, "height" to h))
    }.also { local = it }

    private fun cameraAllowed() =
        context.checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED

    init {
        ScreenPip.context = context
        // Capture events from the vendored VideoCapturerDevice.
        VoIPService.setSharedInstance(
            VoIPService(object : VoIPService.Events {
                override fun onScreenCaptureStopped() {
                    main.post { if (screenSharing) stopScreenShare(byUser = false) }
                }

                override fun onCameraFirstFrame() {}

                override fun onCameraSwitched(front: Boolean) {
                    this@CallChannel.front = front
                    local?.setMirror(front)
                    emit(mapOf("type" to "cameraSwitched", "front" to front))
                }
            }),
        )
        MethodChannel(messenger, "dev.lumina/calls").setMethodCallHandler { c, r -> handle(c, r) }
        EventChannel(messenger, "dev.lumina/calls/events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                events = sink
                pendingAction?.let { sink.success(mapOf("type" to "systemAction", "action" to it)) }
                pendingAction = null
            }

            override fun onCancel(arguments: Any?) {
                events = null
            }
        })
        val filter = IntentFilter().apply {
            addAction(CallService.ACTION_HANG_UP)
            addAction(CallService.ACTION_DECLINE)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            context.registerReceiver(receiver, filter)
        }
    }

    /** "open", "accept", "decline" or "hangup", from a call notification. */
    fun onNotificationAction(action: String) {
        if (action == "decline" || action == "accept") stopRinging()
        val sink = events
        if (sink == null) pendingAction = action else sink.success(mapOf("type" to "systemAction", "action" to action))
    }

    // ---- Telecom (CallTelecom) ----------------------------------------------

    private val telecomSupported = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O

    override fun onTelecomAction(action: String) {
        main.post { onNotificationAction(action) }
    }

    override fun onShowIncomingUi() {
        main.post { emit(mapOf("type" to "showIncomingUi")) }
    }

    override fun onDialerCall(number: String) = emit(mapOf("type" to "dialerCall", "number" to number))

    override fun onAudioRoute(route: String) = emit(mapOf("type" to "audioRoute", "route" to route))

    private fun telecomConnected() = telecomSupported && CallTelecom.connection != null

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
            "telecomRegister" -> {
                if (telecomSupported) {
                    CallTelecom.listener = this
                    CallTelecom.register(context, c.argument<Boolean>("provider") ?: false)
                }
                r.success(telecomSupported)
            }
            // A number the Phone app dialed before Dart was up (headless start).
            "takeDialerCall" -> {
                val number = if (telecomSupported) CallTelecom.pendingDialerNumber else null
                if (telecomSupported) CallTelecom.pendingDialerNumber = null
                r.success(number)
            }
            "telecomProviderEnabled" -> r.success(telecomSupported && CallTelecom.providerEnabled(context))
            // Opens the Phone app's calling accounts settings (to turn Lumina's on).
            "openCallingAccounts" -> r.success(
                try {
                    context.startActivity(
                        Intent(android.telecom.TelecomManager.ACTION_CHANGE_PHONE_ACCOUNTS)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                    )
                    true
                } catch (e: Exception) {
                    false
                },
            )
            "telecomReportIncoming", "telecomReportOutgoing" -> {
                if (!telecomSupported) return r.success(false)
                val callId = (c.argument<Number>("callId") ?: 0).toLong()
                val name = c.argument<String>("name") ?: "Call"
                val video = c.argument<Boolean>("video") ?: false
                val provider = c.argument<Boolean>("provider") ?: false
                r.success(
                    if (c.method == "telecomReportIncoming") CallTelecom.reportIncoming(context, callId, name, video, provider)
                    else CallTelecom.reportOutgoing(context, callId, name, video, provider),
                )
            }
            "telecomState" -> {
                if (telecomSupported) CallTelecom.setState(c.argument<String>("state") ?: "", c.argument<String>("reason"))
                r.success(null)
            }
            "ring" -> {
                ring(c.argument<String>("title") ?: "Call", c.argument<Boolean>("video") ?: false)
                r.success(null)
            }
            "stopRinging" -> {
                stopRinging()
                r.success(null)
            }
            // The ongoing-call notification and foreground service.
            "showOngoing" -> r.success(
                CallService.start(
                    context,
                    c.argument<String>("title") ?: "Call",
                    c.argument<String>("text") ?: "Ongoing call",
                    c.argument<Boolean>("video") ?: false,
                ),
            )
            "hideOngoing" -> {
                CallService.stop(context)
                r.success(null)
            }
            "videoTextures" -> r.success(
                mapOf("remote" to remoteRenderer().textureId, "local" to localRenderer().textureId),
            )
            "startVideo" -> r.success(startVideo(c.argument<Boolean>("front") ?: true))
            "stopVideo" -> {
                stopVideo()
                r.success(null)
            }
            "switchCamera" -> {
                switchCamera(c.arguments as Boolean)
                r.success(null)
            }
            // Dart asked for the MediaProjection permission first (system channel).
            "startScreenShare" -> startScreenShare(
                camera = c.argument<Boolean>("camera") ?: false,
                corner = c.argument<Int>("corner") ?: ScreenPip.BOTTOM_RIGHT,
                result = r,
            )
            "stopScreenShare" -> {
                stopScreenShare(byUser = true)
                r.success(null)
            }
            "setPipCorner" -> {
                ScreenPip.corner = c.arguments as Int
                r.success(null)
            }
            "setSpeaker" -> {
                setSpeaker(c.arguments as Boolean)
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
        // A video call starts with the front camera on, as in Telegram.
        if (args["video"] == true && cameraAllowed() && preCapturer == 0L) {
            front = true
            localRenderer().setMirror(true)
            preCapturer = NativeCall.createCapturer(localRenderer(), NativeCall.CAPTURE_FRONT)
            cameraSetUp = preCapturer != 0L
        }
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
                remoteSink = remoteRenderer(),
                capturer = preCapturer,
                aspectRatio = 0f,
                persistentStatePath = File(context.cacheDir, "calls_persistent_state.json").absolutePath,
            )
        } catch (e: Exception) {
            leaveCallAudio()
            resetVideo()
            throw e
        }
        call = native
    }

    /** Camera on (or back on). False without the camera permission or a call. */
    private fun startVideo(front: Boolean): Boolean {
        val c = call ?: return false
        if (!cameraAllowed()) return false
        CallService.start(context, video = true)
        this.front = front
        localRenderer().setMirror(front)
        if (!cameraSetUp) {
            c.setupOutgoingVideo(localRenderer(), if (front) NativeCall.CAPTURE_FRONT else NativeCall.CAPTURE_BACK)
            cameraSetUp = true
        } else {
            c.setVideoState(NativeCall.VIDEO_ACTIVE)
        }
        return true
    }

    private fun stopVideo() {
        call?.setVideoState(NativeCall.VIDEO_INACTIVE)
        local?.clear()
    }

    private fun switchCamera(front: Boolean) {
        if (screenSharing) {
            ScreenPip.switchCamera(front)
            return
        }
        this.front = front
        call?.switchCamera(front)
        local?.setMirror(front)
    }

    /**
     * Screen sharing, optionally with the camera bubble. Android 14 wants
     * the service in the foreground as mediaProjection before capture
     * starts, so this waits for it.
     */
    private fun startScreenShare(camera: Boolean, corner: Int, result: MethodChannel.Result) {
        val c = call ?: return result.success(false)
        if (VideoCapturerDevice.mediaProjectionPermissionResultData == null) return result.success(false)
        ScreenPip.enabled = camera
        ScreenPip.corner = corner
        ScreenPip.front = front
        cameraWasOn = cameraSetUp
        // The camera can't feed the call and the bubble at once.
        if (cameraSetUp) c.setVideoState(NativeCall.VIDEO_INACTIVE)
        CallService.start(context, video = camera || cameraSetUp, screen = true)
        val deadline = System.currentTimeMillis() + 3000
        fun go() {
            if (!CallService.screenReady && System.currentTimeMillis() < deadline) {
                main.postDelayed(::go, 50)
                return
            }
            if (!CallService.screenReady) return result.success(false)
            screenSharing = true
            localRenderer().setMirror(false)
            c.setupOutgoingVideo(localRenderer(), NativeCall.CAPTURE_SCREEN)
            result.success(true)
        }
        go()
    }

    private fun stopScreenShare(byUser: Boolean) {
        val c = call
        if (!screenSharing) return
        screenSharing = false
        // Stops the screen capturer (and the bubble's camera with it).
        c?.setVideoState(NativeCall.VIDEO_INACTIVE)
        VideoCapturerDevice.mediaProjectionPermissionResultData = null
        if (c != null && cameraWasOn) {
            localRenderer().setMirror(front)
            c.setupOutgoingVideo(localRenderer(), if (front) NativeCall.CAPTURE_FRONT else NativeCall.CAPTURE_BACK)
        } else {
            local?.clear()
        }
        CallService.start(context, video = cameraWasOn, screen = false)
        emit(mapOf("type" to "screenShareStopped", "byUser" to byUser))
    }

    private fun resetVideo() {
        if (preCapturer != 0L) NativeCall.destroyCapturer(preCapturer)
        preCapturer = 0
        cameraSetUp = false
        screenSharing = false
        cameraWasOn = false
        ScreenPip.enabled = false
        VideoCapturerDevice.mediaProjectionPermissionResultData = null
        remote?.clear()
        local?.clear()
    }

    @Suppress("DEPRECATION")
    private fun ring(title: String, video: Boolean) {
        stopRinging()
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(CallService.INCOMING_ID, CallService.incoming(context, title, video))
        if (audio.ringerMode == AudioManager.RINGER_MODE_NORMAL) {
            ringtone = RingtoneManager.getRingtone(context, RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE))?.apply {
                audioAttributes = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) isLooping = true
                play()
            }
        }
        if (audio.ringerMode != AudioManager.RINGER_MODE_SILENT) {
            val vibrator = context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            val pattern = longArrayOf(0, 700, 1000)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator.vibrate(VibrationEffect.createWaveform(pattern, 0))
            } else {
                vibrator.vibrate(pattern, 0)
            }
            vibrating = true
        }
    }

    private fun stopRinging() {
        ringtone?.stop()
        ringtone = null
        if (vibrating) {
            (context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator).cancel()
            vibrating = false
        }
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(CallService.INCOMING_ID)
    }

    @Suppress("DEPRECATION")
    private fun setSpeaker(on: Boolean) {
        // With a Telecom connection, Telecom owns the route.
        if (telecomConnected() && CallTelecom.setRoute(if (on) "speaker" else "earpiece")) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (on) {
                audio.availableCommunicationDevices
                    .firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
                    ?.let { audio.setCommunicationDevice(it) }
            } else {
                audio.clearCommunicationDevice()
            }
        } else {
            audio.isSpeakerphoneOn = on
        }
    }

    @Suppress("DEPRECATION")
    private fun enterCallAudio() {
        previousMode = audio.mode
        // Telecom sets the mode for its (VoIP) connections.
        if (!telecomConnected()) audio.mode = AudioManager.MODE_IN_COMMUNICATION
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
        setSpeaker(false)
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
            resetVideo()
            CallService.stop(context)
            events?.success(mapOf("type" to "stopped", "debugLog" to debugLog, "ratingSuggested" to ratingSuggested))
        }
    }

    companion object {
        /** Intent extra on MainActivity: which call notification opened it. */
        const val EXTRA_CALL_ACTION = "lumina.callAction"
    }
}
