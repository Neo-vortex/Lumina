/*
 * Lumina stand-in for a Telegram-Android helper, so the vendored org.webrtc
 * and VideoCapturerDevice code (GPL v2 or later, see docs/DECISIONS.md D14)
 * builds without the rest of Telegram's app. Only the members that code
 * calls exist. GPL-3.0-or-later.
 */
package org.telegram.messenger;

import android.util.Log;

public final class FileLog {
    private static final String TAG = "LuminaCalls";

    private FileLog() {}

    public static void d(String message) {
        Log.d(TAG, message);
    }

    public static void e(String message) {
        Log.e(TAG, message);
    }

    public static void e(Throwable e) {
        Log.e(TAG, "", e);
    }

    public static void e(String message, Throwable e) {
        Log.e(TAG, message, e);
    }
}
