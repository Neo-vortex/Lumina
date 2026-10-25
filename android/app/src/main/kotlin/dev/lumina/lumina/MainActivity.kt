package dev.lumina.lumina

import android.app.ActivityManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Geocoder
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.StatFs
import android.provider.AlarmClock
import android.provider.CalendarContract
import android.provider.Settings
import dev.lumina.calls.CallChannel
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * Hosts the "dev.lumina/system" channel: streaming asset extraction for the
 * bundled models, storage/RAM facts, the battery-optimisation prompt and
 * the system intents used by AI actions (calendar, alarm, timer, note).
 */
class MainActivity : FlutterActivity() {
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var calls: CallChannel? = null

    // The engine lives in LuminaEngine so calls (and a call dialed from the
    // Phone app) can run without this activity.
    override fun provideFlutterEngine(context: Context): FlutterEngine = LuminaEngine.ensure(context)

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        super.cleanUpFlutterEngine(flutterEngine)
        // The system channel's handler points at this activity.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.lumina/system").setMethodCallHandler(null)
        calls = null
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleCallIntent(intent)
    }

    /** Opened from a call notification: show over the lock screen and pass on Accept / Decline. */
    private fun handleCallIntent(intent: Intent?) {
        val action = intent?.getStringExtra(CallChannel.EXTRA_CALL_ACTION) ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }
        intent.removeExtra(CallChannel.EXTRA_CALL_ACTION)
        calls?.onNotificationAction(action)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.lumina/system")
            .setMethodCallHandler { call, result -> handle(call, result) }
        calls = LuminaEngine.calls
        handleCallIntent(intent)
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "copyAsset" -> {
                val asset = call.argument<String>("asset")!!
                val dest = call.argument<String>("dest")!!
                io.execute {
                    try {
                        val key = FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(asset)
                        val target = File(dest)
                        target.parentFile?.mkdirs()
                        val partial = File("$dest.part")
                        var copied = 0L
                        assets.open(key).use { input ->
                            partial.outputStream().use { output ->
                                val buffer = ByteArray(1 shl 20)
                                while (true) {
                                    val n = input.read(buffer)
                                    if (n < 0) break
                                    output.write(buffer, 0, n)
                                    copied += n
                                }
                            }
                        }
                        partial.renameTo(target)
                        main.post { result.success(copied) }
                    } catch (e: Exception) {
                        main.post { result.error("copy_failed", e.message, null) }
                    }
                }
            }
            "currentLocation" -> withLocationPermission(result) { locate(result) }
            "currentPosition" -> position(result)
            "liveLocationStart" -> {
                val begin = { granted: Boolean -> result.success(granted && LiveLocationService.start(this)) }
                if (hasLocation() || call.argument<Boolean>("ask") != true) begin(hasLocation())
                else requestLive(begin)
            }
            // names: microphone, camera, notifications. Returns name -> granted.
            "requestPermissions" -> {
                val wanted = (call.arguments as List<*>).mapNotNull { name ->
                    when (name) {
                        "microphone" -> android.Manifest.permission.RECORD_AUDIO
                        "camera" -> android.Manifest.permission.CAMERA
                        "notifications" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            android.Manifest.permission.POST_NOTIFICATIONS
                        } else {
                            null
                        }
                        else -> null
                    }?.let { name as String to it }
                }
                fun report() = result.success(
                    (call.arguments as List<*>).associate { name ->
                        val perm = wanted.firstOrNull { it.first == name }?.second
                        name to (perm == null || checkSelfPermission(perm) == PackageManager.PERMISSION_GRANTED)
                    },
                )
                val missing = wanted.map { it.second }.filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
                if (missing.isEmpty()) return report()
                pendingPermissions?.invoke()
                pendingPermissions = { report() }
                requestPermissions(missing.toTypedArray(), PERMISSIONS_REQUEST)
            }
            "liveLocationStop" -> {
                LiveLocationService.stop(this)
                result.success(null)
            }
            "freeSpace" -> {
                val path = call.argument<String>("path") ?: filesDir.path
                result.success(StatFs(path).availableBytes)
            }
            "totalRam" -> {
                val info = ActivityManager.MemoryInfo()
                (getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).getMemoryInfo(info)
                result.success(info.totalMem)
            }
            "isIgnoringBatteryOptimizations" -> {
                val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                result.success(pm.isIgnoringBatteryOptimizations(packageName))
            }
            "openBatterySettings" -> result.success(start(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)))
            "insertCalendarEvent" -> {
                val intent = Intent(Intent.ACTION_INSERT)
                    .setData(CalendarContract.Events.CONTENT_URI)
                    .putExtra(CalendarContract.Events.TITLE, call.argument<String>("title"))
                    .putExtra(CalendarContract.Events.DESCRIPTION, call.argument<String>("description"))
                    .putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, call.argument<Number>("begin")!!.toLong())
                    .putExtra(CalendarContract.EXTRA_EVENT_END_TIME, call.argument<Number>("end")!!.toLong())
                    .putExtra(CalendarContract.EXTRA_EVENT_ALL_DAY, call.argument<Boolean>("allDay") ?: false)
                call.argument<String>("location")?.let { intent.putExtra(CalendarContract.Events.EVENT_LOCATION, it) }
                if (call.argument<Boolean>("reminder") == true) {
                    intent.putExtra(CalendarContract.Events.HAS_ALARM, true)
                }
                result.success(start(intent))
            }
            "setAlarm" -> {
                val intent = Intent(AlarmClock.ACTION_SET_ALARM)
                    .putExtra(AlarmClock.EXTRA_HOUR, call.argument<Int>("hour")!!)
                    .putExtra(AlarmClock.EXTRA_MINUTES, call.argument<Int>("minutes")!!)
                    .putExtra(AlarmClock.EXTRA_MESSAGE, call.argument<String>("message") ?: "")
                    .putExtra(AlarmClock.EXTRA_SKIP_UI, false)
                result.success(start(intent))
            }
            "setTimer" -> {
                val intent = Intent(AlarmClock.ACTION_SET_TIMER)
                    .putExtra(AlarmClock.EXTRA_LENGTH, call.argument<Int>("seconds")!!)
                    .putExtra(AlarmClock.EXTRA_MESSAGE, call.argument<String>("message") ?: "")
                    .putExtra(AlarmClock.EXTRA_SKIP_UI, false)
                result.success(start(intent))
            }
            "createNote" -> {
                val title = call.argument<String>("title") ?: ""
                val text = call.argument<String>("text") ?: ""
                val note = Intent("com.google.android.gms.actions.CREATE_NOTE")
                    .setType("text/plain")
                    .putExtra(Intent.EXTRA_SUBJECT, title)
                    .putExtra(Intent.EXTRA_TEXT, text)
                if (start(note)) {
                    result.success(true)
                } else {
                    val share = Intent(Intent.ACTION_SEND)
                        .setType("text/plain")
                        .putExtra(Intent.EXTRA_SUBJECT, title)
                        .putExtra(Intent.EXTRA_TEXT, if (title.isEmpty()) text else "$title\n\n$text")
                    result.success(start(Intent.createChooser(share, "Save note with…")))
                }
            }
            "openUrl" -> result.success(start(Intent(Intent.ACTION_VIEW, Uri.parse(call.argument<String>("url")))))
            "sdkInt" -> result.success(Build.VERSION.SDK_INT)
            else -> result.notImplemented()
        }
    }

    // ---- Location (story location tags) ------------------------------------

    private var pendingLocation: (() -> Unit)? = null
    private var pendingLocationResult: MethodChannel.Result? = null

    private fun withLocationPermission(result: MethodChannel.Result, then: () -> Unit) {
        val perm = android.Manifest.permission.ACCESS_COARSE_LOCATION
        if (checkSelfPermission(perm) == PackageManager.PERMISSION_GRANTED) return then()
        pendingLocation = then
        pendingLocationResult = result
        requestPermissions(arrayOf(perm), LOCATION_REQUEST)
    }

    private var pendingLive: ((Boolean) -> Unit)? = null
    private var pendingPermissions: (() -> Unit)? = null

    private fun hasLocation() = listOf(
        android.Manifest.permission.ACCESS_FINE_LOCATION,
        android.Manifest.permission.ACCESS_COARSE_LOCATION,
    ).any { checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }

    /** Live location asks for precise location (the user may still pick approximate) and notifications. */
    private fun requestLive(then: (Boolean) -> Unit) {
        pendingLive?.invoke(false)
        pendingLive = then
        val perms = mutableListOf(
            android.Manifest.permission.ACCESS_FINE_LOCATION,
            android.Manifest.permission.ACCESS_COARSE_LOCATION,
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) perms += android.Manifest.permission.POST_NOTIFICATIONS
        requestPermissions(perms.toTypedArray(), LIVE_REQUEST)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSIONS_REQUEST) {
            val then = pendingPermissions
            pendingPermissions = null
            then?.invoke()
            return
        }
        if (requestCode == LIVE_REQUEST) {
            val then = pendingLive
            pendingLive = null
            then?.invoke(hasLocation())
            return
        }
        if (requestCode != LOCATION_REQUEST) return
        val then = pendingLocation
        val result = pendingLocationResult
        pendingLocation = null
        pendingLocationResult = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) then?.invoke() else result?.success(null)
    }

    @Suppress("MissingPermission", "DEPRECATION")
    private fun locate(result: MethodChannel.Result) {
        val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val known = lm.getProviders(true).mapNotNull { runCatching { lm.getLastKnownLocation(it) }.getOrNull() }
            .maxByOrNull { it.time }
        val fresh = known != null && System.currentTimeMillis() - known.time < 30 * 60 * 1000
        if (fresh || Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return describe(known, result)
        val provider = if (lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) LocationManager.NETWORK_PROVIDER
        else LocationManager.GPS_PROVIDER
        var done = false
        val timeout = Runnable { if (!done) { done = true; describe(known, result) } }
        main.postDelayed(timeout, 8000)
        lm.getCurrentLocation(provider, null, mainExecutor) { loc ->
            if (!done) { done = true; main.removeCallbacks(timeout); describe(loc ?: known, result) }
        }
    }

    /** A fresh fix for live locations: GPS when precise access is granted, no geocoding, never prompts. */
    @Suppress("MissingPermission", "DEPRECATION")
    private fun position(result: MethodChannel.Result) {
        if (!hasLocation()) return result.success(null)
        val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val fine = checkSelfPermission(android.Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        val known = lm.getProviders(true).mapNotNull { runCatching { lm.getLastKnownLocation(it) }.getOrNull() }
            .maxByOrNull { it.time }
        fun reply(loc: Location?) = result.success(
            loc?.let { mapOf("latitude" to it.latitude, "longitude" to it.longitude, "accuracy" to it.accuracy.toDouble()) },
        )
        val recent = known != null && System.currentTimeMillis() - known.time < 30 * 1000
        if (recent) return reply(known)
        val provider = when {
            fine && lm.isProviderEnabled(LocationManager.GPS_PROVIDER) -> LocationManager.GPS_PROVIDER
            lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER) -> LocationManager.NETWORK_PROVIDER
            else -> return reply(known)
        }
        var done = false
        val timeout = Runnable { if (!done) { done = true; reply(known) } }
        main.postDelayed(timeout, 20000)
        val got = { loc: Location? -> if (!done) { done = true; main.removeCallbacks(timeout); reply(loc ?: known) } }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            lm.getCurrentLocation(provider, null, mainExecutor) { got(it) }
        } else {
            lm.requestSingleUpdate(provider, LocationListener { got(it) }, Looper.getMainLooper())
        }
    }

    /** Coordinates plus a best-effort place name from the system geocoder. */
    @Suppress("DEPRECATION")
    private fun describe(loc: Location?, result: MethodChannel.Result) {
        if (loc == null) return result.success(null)
        io.execute {
            val name = runCatching {
                Geocoder(this).getFromLocation(loc.latitude, loc.longitude, 1)?.firstOrNull()?.let {
                    listOfNotNull(it.featureName?.takeIf { f -> f != it.subThoroughfare }, it.locality ?: it.subAdminArea)
                        .distinct().joinToString(", ")
                }
            }.getOrNull().orEmpty()
            main.post { result.success(mapOf("latitude" to loc.latitude, "longitude" to loc.longitude, "name" to name)) }
        }
    }

    private fun start(intent: Intent): Boolean = try {
        startActivity(intent)
        true
    } catch (e: ActivityNotFoundException) {
        false
    }

    companion object {
        private const val LOCATION_REQUEST = 4107
        private const val LIVE_REQUEST = 4109
        private const val PERMISSIONS_REQUEST = 4110
    }
}
