package dev.lumina.lumina

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.os.Process

/**
 * Restarts Lumina in a fresh process (switching servers: TDLib reads
 * LUMINA_SERVER once per process). Runs in its own ":restart" process,
 * started while Lumina is in front, so Android lets it launch Lumina again;
 * an alarm-based relaunch is blocked as a background activity start.
 */
class RestartActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val mainPid = intent.getIntExtra(EXTRA_PID, -1)
        if (mainPid > 0) Process.killProcess(mainPid)
        val launch = packageManager.getLaunchIntentForPackage(packageName)!!
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
        startActivity(launch)
        finish()
        Runtime.getRuntime().exit(0)
    }

    companion object {
        const val EXTRA_PID = "main_pid"
    }
}
