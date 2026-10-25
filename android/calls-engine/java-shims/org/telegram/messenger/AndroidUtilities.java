/*
 * Lumina stand-in for a Telegram-Android helper, so the vendored org.webrtc
 * and VideoCapturerDevice code (GPL v2 or later, see docs/DECISIONS.md D14)
 * builds without the rest of Telegram's app. Only the members that code
 * calls exist. GPL-3.0-or-later.
 */
package org.telegram.messenger;

import android.os.Handler;
import android.os.Looper;

public final class AndroidUtilities {
    private static final Handler main = new Handler(Looper.getMainLooper());

    private AndroidUtilities() {}

    public static void runOnUIThread(Runnable r) {
        runOnUIThread(r, 0);
    }

    public static void runOnUIThread(Runnable r, long delay) {
        if (delay == 0 && Looper.myLooper() == Looper.getMainLooper()) {
            r.run();
        } else {
            main.postDelayed(r, delay);
        }
    }

    public static void cancelRunOnUIThread(Runnable r) {
        main.removeCallbacks(r);
    }
}
