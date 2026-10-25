/*
 * Lumina stand-in for Telegram-Android's Instance (constants only), used by
 * the vendored VideoCapturerDevice. GPL-3.0-or-later, see docs/DECISIONS.md D14.
 */
package org.telegram.messenger.voip;

public final class Instance {
    public static final int VIDEO_STATE_INACTIVE = 0;
    public static final int VIDEO_STATE_PAUSED = 1;
    public static final int VIDEO_STATE_ACTIVE = 2;

    private Instance() {}
}
