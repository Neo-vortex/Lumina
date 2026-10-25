/*
 * Lumina stand-in for a Telegram-Android helper, so the vendored org.webrtc
 * and VideoCapturerDevice code (GPL v2 or later, see docs/DECISIONS.md D14)
 * builds without the rest of Telegram's app. Only the members that code
 * calls exist. GPL-3.0-or-later.
 */
package org.telegram.messenger;

public final class SharedConfig {
    /** Telegram's debug switch for the system echo canceller / noise suppressor. */
    public static boolean disableVoiceAudioEffects = false;

    private SharedConfig() {}
}
