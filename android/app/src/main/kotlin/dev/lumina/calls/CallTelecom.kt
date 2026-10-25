// Telecom self-managed calls need Android 8 (API 26). Every entry point is
// guarded: CallChannel checks the version before calling in, the public
// functions below return early, and the services are only bound by Telecom
// for accounts registered on API 26+.
@file:SuppressLint("NewApi")

package dev.lumina.calls

import android.annotation.SuppressLint

import android.content.ComponentName
import android.content.Context
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.telecom.CallAudioState
import android.telecom.Connection
import android.telecom.ConnectionRequest
import android.telecom.ConnectionService
import android.telecom.DisconnectCause
import android.telecom.PhoneAccount
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import android.telecom.VideoProfile
import android.util.Log
import dev.lumina.lumina.R

/**
 * Lumina calls in Android's Telecom framework, so the system treats them
 * like phone calls: Bluetooth / car / watch controls, audio routing, other
 * calls put on hold, and the Phone app's call history.
 *
 * Two modes (owner's choice, both):
 * - **self-managed** (default): Lumina shows its own call UI and Telecom
 *   knows about the call.
 * - **calling account** (opt-in): a managed PhoneAccount the user enables in
 *   the Phone app; the dialer then shows its own in-call screen, and calls
 *   placed from the dialer with this account become Lumina calls.
 *
 * Telecom asks for decisions through [Listener] (CallChannel forwards them to
 * Dart); Dart reports progress back with [setState].
 */
object CallTelecom {
    private const val TAG = "CallTelecom"
    const val SCHEME = "lumina"
    private const val EXTRA_CALL_ID = "lumina.callId"
    private const val EXTRA_NAME = "lumina.name"

    interface Listener {
        /** accept, decline, hangup, hold, unhold. */
        fun onTelecomAction(action: String)

        /** Telecom wants Lumina's incoming-call UI (self-managed). */
        fun onShowIncomingUi()

        /** The Phone app dialed [number] with Lumina's calling account. */
        fun onDialerCall(number: String)

        fun onAudioRoute(route: String)
    }

    @Volatile var listener: Listener? = null

    /** A dialer call that arrived before Dart was listening. */
    @Volatile var pendingDialerNumber: String? = null

    /** The call's Connection, if Telecom accepted it. */
    @Volatile var connection: LuminaConnection? = null
        private set

    private fun telecom(context: Context) = context.getSystemService(Context.TELECOM_SERVICE) as TelecomManager

    fun selfManagedHandle(context: Context) =
        PhoneAccountHandle(ComponentName(context, SelfManagedCallService::class.java), "lumina")

    fun providerHandle(context: Context) =
        PhoneAccountHandle(ComponentName(context, CallProviderService::class.java), "lumina-provider")

    private val supported = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O

    /** Registers the self-managed account, and the calling account when [provider] is on. */
    fun register(context: Context, provider: Boolean) {
        if (!supported) return
        val tm = telecom(context)
        val icon = Icon.createWithResource(context, R.mipmap.ic_launcher)
        val selfManaged = PhoneAccount.builder(selfManagedHandle(context), "Lumina")
            .setCapabilities(
                PhoneAccount.CAPABILITY_SELF_MANAGED or PhoneAccount.CAPABILITY_VIDEO_CALLING or
                    PhoneAccount.CAPABILITY_SUPPORTS_VIDEO_CALLING,
            )
            .setIcon(icon)
            .addSupportedUriScheme(SCHEME)
            .setExtras(Bundle().apply {
                // Self-managed calls show in the Phone app's history (Android 11+).
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) putBoolean(PhoneAccount.EXTRA_LOG_SELF_MANAGED_CALLS, true)
            })
            .build()
        try {
            tm.registerPhoneAccount(selfManaged)
            if (provider) {
                tm.registerPhoneAccount(
                    PhoneAccount.builder(providerHandle(context), "Lumina")
                        .setCapabilities(PhoneAccount.CAPABILITY_CALL_PROVIDER or PhoneAccount.CAPABILITY_VIDEO_CALLING)
                        .setIcon(icon)
                        .setShortDescription("Telegram calls through Lumina")
                        .addSupportedUriScheme(PhoneAccount.SCHEME_TEL)
                        .addSupportedUriScheme(SCHEME)
                        .build(),
                )
            } else {
                tm.unregisterPhoneAccount(providerHandle(context))
            }
        } catch (e: Exception) {
            Log.w(TAG, "Could not register phone accounts", e)
        }
    }

    /** True when the user turned Lumina's calling account on in the Phone app. */
    fun providerEnabled(context: Context): Boolean = supported && try {
        telecom(context).getPhoneAccount(providerHandle(context))?.isEnabled == true
    } catch (e: SecurityException) {
        false
    }

    private fun handleFor(context: Context, useProvider: Boolean) =
        if (useProvider && providerEnabled(context)) providerHandle(context) else selfManagedHandle(context)

    private fun extras(callId: Long, name: String) = Bundle().apply {
        putLong(EXTRA_CALL_ID, callId)
        putString(EXTRA_NAME, name)
    }

    /** Hands an incoming call to Telecom. False when it refused (use the notification path). */
    fun reportIncoming(context: Context, callId: Long, name: String, video: Boolean, useProvider: Boolean): Boolean = supported && try {
        val handle = handleFor(context, useProvider)
        val tm = telecom(context)
        if (handle == selfManagedHandle(context) && !tm.isIncomingCallPermitted(handle)) {
            false
        } else {
            tm.addNewIncomingCall(handle, Bundle().apply {
                putBundle(TelecomManager.EXTRA_INCOMING_CALL_EXTRAS, extras(callId, name))
                putParcelable(TelecomManager.EXTRA_INCOMING_CALL_ADDRESS, Uri.fromParts(SCHEME, callId.toString(), null))
                if (video) putInt(TelecomManager.EXTRA_INCOMING_VIDEO_STATE, VideoProfile.STATE_BIDIRECTIONAL)
            })
            true
        }
    } catch (e: Exception) {
        Log.w(TAG, "addNewIncomingCall failed", e)
        false
    }

    /** Tells Telecom about an outgoing call Lumina is making. */
    fun reportOutgoing(context: Context, callId: Long, name: String, video: Boolean, useProvider: Boolean): Boolean = supported && try {
        val handle = handleFor(context, useProvider)
        val tm = telecom(context)
        if (handle == selfManagedHandle(context) && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P &&
            !tm.isOutgoingCallPermitted(handle)
        ) {
            false
        } else {
            tm.placeCall(Uri.fromParts(SCHEME, callId.toString(), null), Bundle().apply {
                putParcelable(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, handle)
                putBundle(TelecomManager.EXTRA_OUTGOING_CALL_EXTRAS, extras(callId, name))
                if (video) putInt(TelecomManager.EXTRA_START_CALL_WITH_VIDEO_STATE, VideoProfile.STATE_BIDIRECTIONAL)
            })
            true
        }
    } catch (e: SecurityException) {
        // placeCall on a managed account needs CALL_PHONE on some versions.
        Log.w(TAG, "placeCall refused", e)
        false
    } catch (e: Exception) {
        Log.w(TAG, "placeCall failed", e)
        false
    }

    /**
     * Progress from Dart: ringing, dialing, connecting, active, held, or
     * ended with a reason (local, remote, missed, rejected, busy, error).
     */
    fun setState(state: String, reason: String? = null) {
        val c = connection ?: return
        when (state) {
            "dialing" -> c.setDialing()
            "ringing" -> c.setRinging()
            "active" -> c.setActive()
            "held" -> c.setOnHold()
            "ended" -> {
                c.setDisconnected(
                    DisconnectCause(
                        when (reason) {
                            "remote" -> DisconnectCause.REMOTE
                            "missed" -> DisconnectCause.MISSED
                            "rejected" -> DisconnectCause.REJECTED
                            "busy" -> DisconnectCause.BUSY
                            "error" -> DisconnectCause.ERROR
                            else -> DisconnectCause.LOCAL
                        },
                    ),
                )
                c.destroy()
                connection = null
            }
        }
    }

    /** speaker, earpiece, bluetooth, headset. */
    @Suppress("DEPRECATION")
    fun setRoute(route: String): Boolean {
        val c = connection ?: return false
        c.setAudioRoute(
            when (route) {
                "speaker" -> CallAudioState.ROUTE_SPEAKER
                "bluetooth" -> CallAudioState.ROUTE_BLUETOOTH
                "headset" -> CallAudioState.ROUTE_WIRED_HEADSET
                else -> CallAudioState.ROUTE_EARPIECE
            },
        )
        return true
    }

    internal fun attach(c: LuminaConnection) {
        connection?.let {
            it.setDisconnected(DisconnectCause(DisconnectCause.OTHER))
            it.destroy()
        }
        connection = c
    }

    internal fun detach(c: LuminaConnection) {
        if (connection === c) connection = null
    }

    /** One Lumina call as Telecom sees it. */
    class LuminaConnection(selfManaged: Boolean, name: String?, address: Uri?) : Connection() {
        init {
            if (selfManaged) connectionProperties = PROPERTY_SELF_MANAGED
            connectionCapabilities = CAPABILITY_MUTE or CAPABILITY_HOLD or CAPABILITY_SUPPORT_HOLD
            audioModeIsVoip = true
            if (address != null) setAddress(address, TelecomManager.PRESENTATION_ALLOWED)
            if (name != null) setCallerDisplayName(name, TelecomManager.PRESENTATION_ALLOWED)
        }

        override fun onShowIncomingCallUi() {
            listener?.onShowIncomingUi()
        }

        override fun onAnswer() = act("accept")
        override fun onAnswer(videoState: Int) = act("accept")
        override fun onReject() = act("decline")
        override fun onDisconnect() = act("hangup")
        override fun onAbort() = act("hangup")
        override fun onHold() {
            setOnHold()
            act("hold")
        }

        override fun onUnhold() {
            setActive()
            act("unhold")
        }

        @Deprecated("Deprecated in Java")
        override fun onCallAudioStateChanged(state: CallAudioState) {
            listener?.onAudioRoute(
                when (state.route) {
                    CallAudioState.ROUTE_SPEAKER -> "speaker"
                    CallAudioState.ROUTE_BLUETOOTH -> "bluetooth"
                    CallAudioState.ROUTE_WIRED_HEADSET -> "headset"
                    else -> "earpiece"
                },
            )
        }

        private fun act(action: String) {
            listener?.onTelecomAction(action)
        }
    }

    /** Shared by both ConnectionServices. */
    abstract class Base(private val selfManaged: Boolean) : ConnectionService() {
        override fun onCreateIncomingConnection(account: PhoneAccountHandle?, request: ConnectionRequest): Connection {
            val extras = request.extras?.getBundle(TelecomManager.EXTRA_INCOMING_CALL_EXTRAS) ?: request.extras
            val c = LuminaConnection(selfManaged, extras?.getString(EXTRA_NAME), request.address)
            c.setRinging()
            attach(c)
            return c
        }

        override fun onCreateIncomingConnectionFailed(account: PhoneAccountHandle?, request: ConnectionRequest) {
            // Lumina rings with its own notification instead.
            listener?.onShowIncomingUi()
        }

        override fun onCreateOutgoingConnection(account: PhoneAccountHandle?, request: ConnectionRequest): Connection {
            val address = request.address
            val c = LuminaConnection(
                selfManaged,
                request.extras?.getBundle(TelecomManager.EXTRA_OUTGOING_CALL_EXTRAS)?.getString(EXTRA_NAME)
                    ?: request.extras?.getString(EXTRA_NAME),
                address,
            )
            c.setDialing()
            attach(c)
            // A number dialed in the Phone app with Lumina's calling account.
            if (address != null && address.scheme == PhoneAccount.SCHEME_TEL) {
                val number = address.schemeSpecificPart
                val l = listener
                if (l != null) {
                    l.onDialerCall(number)
                } else {
                    // Lumina isn't running: boot the engine without UI. Dart
                    // picks the number up (takeDialerCall) once TDLib is ready;
                    // the Phone app shows "dialing" meanwhile.
                    pendingDialerNumber = number
                    dev.lumina.lumina.LuminaEngine.ensure(this)
                }
            }
            return c
        }

        override fun onCreateOutgoingConnectionFailed(account: PhoneAccountHandle?, request: ConnectionRequest) {
            Log.w(TAG, "Telecom refused the outgoing call")
        }
    }
}

/** The always-on self-managed account. */
class SelfManagedCallService : CallTelecom.Base(selfManaged = true)

/** The opt-in calling account shown in the Phone app. */
class CallProviderService : CallTelecom.Base(selfManaged = false)
