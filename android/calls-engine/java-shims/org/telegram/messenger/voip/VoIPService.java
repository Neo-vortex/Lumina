/*
 * Lumina stand-in for Telegram-Android's VoIPService: the vendored
 * VideoCapturerDevice reports capture events through it. Lumina's call
 * service installs an instance that forwards them. GPL-3.0-or-later, see
 * docs/DECISIONS.md D14.
 */
package org.telegram.messenger.voip;

public final class VoIPService {
    public interface Events {
        /** The user (or the system) ended screen sharing. */
        void onScreenCaptureStopped();

        void onCameraFirstFrame();

        void onCameraSwitched(boolean front);
    }

    private static volatile VoIPService shared;
    private final Events events;

    public VoIPService(Events events) {
        this.events = events;
    }

    public static VoIPService getSharedInstance() {
        return shared;
    }

    /** Null clears it (call ended). */
    public static void setSharedInstance(VoIPService service) {
        shared = service;
    }

    public void stopScreenCapture() {
        events.onScreenCaptureStopped();
    }

    public void onCameraFirstFrameAvailable() {
        events.onCameraFirstFrame();
    }

    public void setSwitchingCamera(boolean switching, boolean front) {
        if (!switching) events.onCameraSwitched(front);
    }
}
