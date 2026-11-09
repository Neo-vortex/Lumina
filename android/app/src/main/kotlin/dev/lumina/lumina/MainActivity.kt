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
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.StatFs
import android.provider.AlarmClock
import android.provider.CalendarContract
import android.provider.Settings
import dev.lumina.background.MessageNotifications
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

    // Flutter keeps "the framework handles back" across activity recreation
    // only for engines found by cached id, and the framework sends it only
    // when it changes. With our long-lived engine a recreated activity would
    // let the system take back and close the app over an open chat, so the
    // last value lives with the engine and is re-applied here.
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setFrameworkHandlesBack(frameworkHandlesBack)
    }

    override fun setFrameworkHandlesBack(frameworkHandlesBack: Boolean) {
        Companion.frameworkHandlesBack = frameworkHandlesBack
        super.setFrameworkHandlesBack(frameworkHandlesBack)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        super.cleanUpFlutterEngine(flutterEngine)
        // The system channel's handler points at this activity.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.lumina/system").setMethodCallHandler(null)
        calls = null
    }

    override fun onResume() {
        super.onResume()
        preferHighestRefreshRate()
    }

    /**
     * Flutter never asks Android for more than the default refresh rate, and
     * many phones (Xiaomi/Poco especially) then hold it at 60 Hz. Prefer the
     * fastest display mode at the current resolution (90/120/144 Hz).
     */
    @Suppress("DEPRECATION")
    private fun preferHighestRefreshRate() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val display = (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) display else windowManager.defaultDisplay) ?: return
        val current = display.mode
        val best = display.supportedModes
            .filter { it.physicalWidth == current.physicalWidth && it.physicalHeight == current.physicalHeight }
            .maxByOrNull { it.refreshRate } ?: return
        if (window.attributes.preferredDisplayModeId == best.modeId) return
        window.attributes = window.attributes.apply { preferredDisplayModeId = best.modeId }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleCallIntent(intent)
    }

    /** Opened from a call notification: show over the lock screen and pass on Accept / Decline. */
    private fun handleCallIntent(intent: Intent?) {
        intent?.getStringExtra(dev.lumina.background.DownloadNotifications.EXTRA_OPEN_DOWNLOAD)?.let {
            intent.removeExtra(dev.lumina.background.DownloadNotifications.EXTRA_OPEN_DOWNLOAD)
            dev.lumina.background.DownloadNotifications.openDownload(it)
        }
        val chat = intent?.getLongExtra(MessageNotifications.EXTRA_OPEN_CHAT, 0) ?: 0
        if (chat != 0L) {
            intent?.removeExtra(MessageNotifications.EXTRA_OPEN_CHAT)
            MessageNotifications.openChat(chat)
        }
        if (intent != null && intent.action == Intent.ACTION_VIEW) {
            intent.data?.let { MessageNotifications.openLink(it.toString()) }
            intent.data = null
        }
        if (intent != null && (intent.action == Intent.ACTION_SEND || intent.action == Intent.ACTION_SEND_MULTIPLE)) {
            // Once only (a recreated activity keeps its intent).
            intent.action = null
            receiveShare(intent)
        }
        val action = intent?.getStringExtra(CallChannel.EXTRA_CALL_ACTION) ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }
        intent.removeExtra(CallChannel.EXTRA_CALL_ACTION)
        calls?.onNotificationAction(action)
    }

    /**
     * Shared from another app: the text and any files. The files are copied
     * into cache/shared_in at once (read access to the other app's URIs ends
     * with this activity), then Dart picks the chat.
     */
    @Suppress("DEPRECATION")
    private fun receiveShare(intent: Intent) {
        val uris = mutableListOf<Uri>()
        if (intent.action == Intent.ACTION_SEND_MULTIPLE) {
            intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)?.let { uris += it }
        } else {
            intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)?.let { uris += it }
        }
        intent.clipData?.let { clip ->
            for (i in 0 until clip.itemCount) clip.getItemAt(i).uri?.let { if (it !in uris) uris += it }
        }
        val text = listOfNotNull(
            intent.getStringExtra(Intent.EXTRA_SUBJECT)?.takeIf { it.isNotBlank() },
            intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()?.takeIf { it.isNotBlank() },
        ).distinct().joinToString("\n")
        val fallbackType = intent.type
        io.execute {
            val dir = File(cacheDir, "shared_in/${System.currentTimeMillis()}").apply { mkdirs() }
            val files = uris.mapIndexedNotNull { i, uri ->
                runCatching {
                    var name: String? = null
                    contentResolver.query(uri, arrayOf(android.provider.OpenableColumns.DISPLAY_NAME), null, null, null)
                        ?.use { c -> if (c.moveToFirst()) name = c.getString(0) }
                    val safe = (name ?: uri.lastPathSegment ?: "shared_$i").replace('/', '_')
                    val out = File(dir, safe)
                    contentResolver.openInputStream(uri)!!.use { input -> out.outputStream().use { input.copyTo(it) } }
                    mapOf(
                        "path" to out.path,
                        "name" to safe,
                        "mime" to (contentResolver.getType(uri) ?: fallbackType ?: "application/octet-stream"),
                    )
                }.getOrNull()
            }
            if (text.isEmpty() && files.isEmpty()) return@execute
            main.post { MessageNotifications.openShare(text, files) }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.lumina/system")
            .setMethodCallHandler { call, result -> handle(call, result) }
        calls = LuminaEngine.calls
        handleCallIntent(intent)
        // Settings → Background decides; the default is "connected".
        dev.lumina.background.Background.resume(applicationContext)
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
            // Screen sharing in a call: the system's "start recording?" prompt.
            "requestScreenCapture" -> {
                pendingScreenCapture?.success(false)
                pendingScreenCapture = result
                val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as android.media.projection.MediaProjectionManager
                startActivityForResult(mpm.createScreenCaptureIntent(), SCREEN_CAPTURE_REQUEST)
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
            // A fresh process: TDLib reads its server (LUMINA_SERVER) once.
            "restartApp" -> {
                result.success(true)
                startActivity(
                    Intent(this, RestartActivity::class.java)
                        .putExtra(RestartActivity.EXTRA_PID, android.os.Process.myPid())
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
            }
            "notificationsEnabled" -> result.success(
                androidx.core.app.NotificationManagerCompat.from(this).areNotificationsEnabled(),
            )
            "openNotificationSettings" -> result.success(
                start(
                    Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                        .putExtra(Settings.EXTRA_APP_PACKAGE, packageName),
                ),
            )
            // Android 14+: without this, an incoming call on a locked phone is
            // only a quiet lock-screen notification, never the call screen.
            "canUseFullScreenIntent" -> result.success(
                Build.VERSION.SDK_INT < 34 ||
                    (getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager)
                        .canUseFullScreenIntent(),
            )
            "openFullScreenIntentSettings" -> result.success(
                Build.VERSION.SDK_INT >= 34 &&
                    start(
                        Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT)
                            .setData(Uri.parse("package:$packageName")),
                    ),
            )
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
            // The phone's own "new contact" screen, prefilled (no permission needed).
            "saveToPhoneContacts" -> {
                val insert = Intent(android.provider.ContactsContract.Intents.Insert.ACTION)
                    .setType(android.provider.ContactsContract.RawContacts.CONTENT_TYPE)
                    .putExtra(android.provider.ContactsContract.Intents.Insert.NAME, call.argument<String>("name") ?: "")
                val phone = call.argument<String>("phone") ?: ""
                if (phone.isNotEmpty()) insert.putExtra(android.provider.ContactsContract.Intents.Insert.PHONE, phone)
                val note = call.argument<String>("note") ?: ""
                if (note.isNotEmpty()) insert.putExtra(android.provider.ContactsContract.Intents.Insert.NOTES, note)
                result.success(start(insert))
            }
            "shareText" -> {
                val share = Intent(Intent.ACTION_SEND)
                    .setType("text/plain")
                    .putExtra(Intent.EXTRA_TEXT, call.argument<String>("text") ?: "")
                result.success(start(Intent.createChooser(share, null)))
            }
            "openLinkSettings" -> {
                val uri = Uri.parse("package:$packageName")
                val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
                    Intent(Settings.ACTION_APP_OPEN_BY_DEFAULT_SETTINGS, uri)
                else Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, uri)
                result.success(start(intent))
            }
            // Android's share sheet for a file: a copy in cache/share goes
            // out through the FileProvider (never the TDLib folders).
            "shareFile" -> {
                val path = call.argument<String>("path")!!
                val mime = call.argument<String>("mime") ?: "*/*"
                val name = call.argument<String>("name") ?: File(path).name
                io.execute {
                    val uri = runCatching {
                        val dir = File(cacheDir, "share").apply { mkdirs() }
                        dir.listFiles()?.forEach { it.delete() }
                        val copy = File(dir, name.replace('/', '_'))
                        File(path).copyTo(copy, overwrite = true)
                        androidx.core.content.FileProvider.getUriForFile(this, "$packageName.share", copy)
                    }.getOrNull()
                    main.post {
                        if (uri == null) return@post result.success(false)
                        val share = Intent(Intent.ACTION_SEND)
                            .setType(mime)
                            .putExtra(Intent.EXTRA_STREAM, uri)
                            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        share.clipData = android.content.ClipData.newRawUri(name, uri)
                        result.success(start(Intent.createChooser(share, null).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)))
                    }
                }
            }
            // Copies a file into the shared gallery (Pictures/Lumina, or
            // Movies/Lumina for videos).
            "saveToGallery" -> {
                val path = call.argument<String>("path")!!
                val mime = call.argument<String>("mime") ?: "image/jpeg"
                val name = call.argument<String>("name") ?: File(path).name
                io.execute {
                    val ok = runCatching {
                        val values = android.content.ContentValues().apply {
                            put(android.provider.MediaStore.MediaColumns.DISPLAY_NAME, name)
                            put(android.provider.MediaStore.MediaColumns.MIME_TYPE, mime)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                put(
                                    android.provider.MediaStore.MediaColumns.RELATIVE_PATH,
                                    if (mime.startsWith("video/")) "Movies/Lumina" else "Pictures/Lumina",
                                )
                            }
                        }
                        val collection = if (mime.startsWith("video/"))
                            android.provider.MediaStore.Video.Media.EXTERNAL_CONTENT_URI
                        else android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                        val uri = contentResolver.insert(collection, values)!!
                        contentResolver.openOutputStream(uri)!!.use { out -> File(path).inputStream().use { it.copyTo(out) } }
                        true
                    }.getOrDefault(false)
                    main.post { result.success(ok) }
                }
            }
            "sdkInt" -> result.success(Build.VERSION.SDK_INT)
            // Silent or vibrate: UI sounds (the send sound) stay quiet.
            "ringerSilent" -> {
                val audio = getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager
                result.success(audio.ringerMode != android.media.AudioManager.RINGER_MODE_NORMAL)
            }
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
    private var pendingScreenCapture: MethodChannel.Result? = null

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != SCREEN_CAPTURE_REQUEST) return
        val ok = resultCode == RESULT_OK && data != null
        // The vendored capturer reads the permission from here.
        org.telegram.messenger.voip.VideoCapturerDevice.mediaProjectionPermissionResultData = if (ok) data else null
        pendingScreenCapture?.success(ok)
        pendingScreenCapture = null
    }

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
        /** Last value the framework sent, for the engine that outlives this activity. */
        private var frameworkHandlesBack = false

        private const val LOCATION_REQUEST = 4107
        private const val LIVE_REQUEST = 4109
        private const val PERMISSIONS_REQUEST = 4110
        private const val SCREEN_CAPTURE_REQUEST = 4111
    }
}
