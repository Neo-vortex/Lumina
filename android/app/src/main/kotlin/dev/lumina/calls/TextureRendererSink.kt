package dev.lumina.calls

import android.os.Handler
import android.os.Looper
import io.flutter.view.TextureRegistry
import org.telegram.messenger.voip.VideoCapturerDevice
import org.webrtc.EglBase
import org.webrtc.EglRenderer
import org.webrtc.GlRectDrawer
import org.webrtc.VideoFrame
import org.webrtc.VideoSink

/**
 * Draws WebRTC video frames into a Flutter texture (shown by a Texture
 * widget in the call screen). One per stream: the other side's video and
 * the local camera preview. Reports the frame size so Dart can lay out the
 * aspect ratio.
 */
class TextureRendererSink(
    textures: TextureRegistry,
    name: String,
    private val onSize: (width: Int, height: Int) -> Unit,
) : VideoSink {
    private val main = Handler(Looper.getMainLooper())
    private val producer = textures.createSurfaceProducer()
    private val renderer = EglRenderer(name)
    private var width = 0
    private var height = 0
    private var hasSurface = false

    val textureId: Long get() = producer.id()

    init {
        renderer.init(VideoCapturerDevice.getEglBase().eglBaseContext, EglBase.CONFIG_PLAIN, GlRectDrawer())
        producer.setCallback(object : TextureRegistry.SurfaceProducer.Callback {
            // The surface is recreated after the app was in the background.
            override fun onSurfaceAvailable() = attach()

            override fun onSurfaceCleanup() = detach()
        })
        producer.setSize(640, 360)
        attach()
    }

    private fun attach() {
        if (hasSurface) return
        renderer.createEglSurface(producer.surface)
        hasSurface = true
    }

    private fun detach() {
        if (!hasSurface) return
        hasSurface = false
        renderer.releaseEglSurface({}, false)
    }

    override fun onFrame(frame: VideoFrame) {
        val w = frame.rotatedWidth
        val h = frame.rotatedHeight
        if (w != width || h != height) {
            width = w
            height = h
            main.post {
                // A new buffer size needs a new surface.
                detach()
                producer.setSize(w, h)
                attach()
                onSize(w, h)
            }
        }
        renderer.onFrame(frame)
    }

    fun setMirror(mirror: Boolean) = renderer.setMirror(mirror)

    /** Blank the texture (video turned off, call over). */
    fun clear() {
        renderer.clearImage()
        width = 0
        height = 0
    }

    fun release() {
        renderer.release()
        producer.release()
    }
}
