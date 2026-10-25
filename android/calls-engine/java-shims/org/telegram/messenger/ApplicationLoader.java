/*
 * Lumina stand-in for a Telegram-Android helper, so the vendored org.webrtc
 * and VideoCapturerDevice code (GPL v2 or later, see docs/DECISIONS.md D14)
 * builds without the rest of Telegram's app. Only the members that code
 * calls exist. GPL-3.0-or-later.
 */
package org.telegram.messenger;

import android.annotation.SuppressLint;
import android.content.Context;

public final class ApplicationLoader {
    /** Set by dev.lumina.calls.CallEngine before the engine is used. */
    @SuppressLint("StaticFieldLeak")
    public static volatile Context applicationContext;

    private ApplicationLoader() {}
}
