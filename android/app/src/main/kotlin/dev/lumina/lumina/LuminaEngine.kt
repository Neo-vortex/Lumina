package dev.lumina.lumina

import android.content.Context
import android.os.Looper
import dev.lumina.calls.CallChannel
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * The one Flutter engine of the process (Dart + TDLib). It outlives the
 * activity, so something other than the UI can start it: a call dialed in
 * the Phone app with Lumina's calling account boots it headless, and the
 * activity attaches to it later.
 */
object LuminaEngine {
    private const val ID = "lumina"

    /** The call channel of the running engine. */
    @Volatile var calls: CallChannel? = null
        private set

    /** Main thread only. */
    fun ensure(context: Context): FlutterEngine {
        check(Looper.myLooper() == Looper.getMainLooper()) { "LuminaEngine.ensure off the main thread" }
        FlutterEngineCache.getInstance().get(ID)?.let { return it }
        val app = context.applicationContext
        val engine = FlutterEngine(app)
        calls = CallChannel(app, engine.dartExecutor.binaryMessenger)
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(app)
        loader.ensureInitializationComplete(app, null)
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "main"),
        )
        FlutterEngineCache.getInstance().put(ID, engine)
        return engine
    }

    fun isRunning(): Boolean = FlutterEngineCache.getInstance().contains(ID)
}
