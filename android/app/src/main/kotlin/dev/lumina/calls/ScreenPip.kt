package dev.lumina.calls

import android.content.Context
import android.graphics.Matrix
import android.opengl.GLES20
import android.util.Log
import org.telegram.messenger.voip.VideoCapturerDevice
import org.webrtc.Camera1Enumerator
import org.webrtc.Camera2Enumerator
import org.webrtc.CameraEnumerator
import org.webrtc.CameraVideoCapturer
import org.webrtc.CapturerObserver
import org.webrtc.GlGenericDrawer
import org.webrtc.GlRectDrawer
import org.webrtc.GlShader
import org.webrtc.GlTextureFrameBuffer
import org.webrtc.SurfaceTextureHelper
import org.webrtc.TextureBufferImpl
import org.webrtc.VideoFrame
import org.webrtc.VideoFrameDrawer
import org.webrtc.YuvConverter
import java.util.concurrent.atomic.AtomicReference

/**
 * Screen sharing with the camera on top (owner item 21): the other side
 * gets one video track, the screen with a rounded camera square in a
 * corner. The vendored VideoCapturerDevice hands the screen capturer's
 * observer to [wrap] (android/calls-engine/patches/); when the camera is
 * included, a [Compositor] sits between the screen frames and tgcalls.
 */
object ScreenPip {
    const val TOP_LEFT = 0
    const val TOP_RIGHT = 1
    const val BOTTOM_LEFT = 2
    const val BOTTOM_RIGHT = 3

    /** Include the camera in the next / current screen share. */
    @Volatile var enabled = false

    @Volatile var corner = BOTTOM_RIGHT

    /** The square's side as a fraction of the screen's width. */
    @Volatile var size = 0.22f

    @Volatile var front = true

    @Volatile private var active: Compositor? = null

    @Volatile lateinit var context: Context

    /** Called by VideoCapturerDevice for the screen capturer. */
    @JvmStatic
    fun wrap(target: CapturerObserver, screenHelper: SurfaceTextureHelper): CapturerObserver {
        if (!enabled) return target
        return Compositor(target, screenHelper).also { active = it }
    }

    fun switchCamera(front: Boolean) {
        this.front = front
        active?.switchCamera(front)
    }

    internal fun ended(c: Compositor) {
        if (active === c) active = null
    }

    /** Pure geometry, in GL coordinates (origin bottom-left): x, y, side. */
    fun rect(width: Int, height: Int, corner: Int, size: Float): Triple<Int, Int, Int> {
        val side = ((minOf(width, height) * size).toInt().coerceAtLeast(16)) and 1.inv()
        val margin = (minOf(width, height) * 0.03f).toInt()
        val x = if (corner == TOP_LEFT || corner == BOTTOM_LEFT) margin else width - margin - side
        val y = if (corner == BOTTOM_LEFT || corner == BOTTOM_RIGHT) margin else height - margin - side
        return Triple(x, y, side)
    }

    /**
     * Draws each screen frame, then the latest camera frame cropped to a
     * rounded square, into a texture tgcalls encodes. Runs on the screen
     * capturer's GL thread (its SurfaceTextureHelper), which shares the
     * engine's EGL context.
     */
    class Compositor(private val target: CapturerObserver, private val screen: SurfaceTextureHelper) : CapturerObserver {
        private val frameDrawer = VideoFrameDrawer()
        private val plain = GlRectDrawer()
        private val yuv = YuvConverter()
        private val pool = arrayOfNulls<GlTextureFrameBuffer>(3)
        private val busy = BooleanArray(3)
        private val latestCamera = AtomicReference<VideoFrame?>(null)
        private var cameraHelper: SurfaceTextureHelper? = null
        private var camera: CameraVideoCapturer? = null

        // Current bubble, in framebuffer pixels (read by the shader callback).
        private var pipX = 0
        private var pipY = 0
        private var pipSide = 0

        private val rounded = GlGenericDrawer(
            """
            uniform vec4 pipRect;
            uniform float pipRadius;
            void main() {
              vec2 p = gl_FragCoord.xy - pipRect.xy - pipRect.zw * 0.5;
              vec2 q = abs(p) - (pipRect.zw * 0.5 - vec2(pipRadius));
              if (length(max(q, 0.0)) > pipRadius) discard;
              gl_FragColor = sample(tc);
            }
            """.trimIndent(),
            object : GlGenericDrawer.ShaderCallbacks {
                override fun onNewShader(shader: GlShader) {}

                override fun onPrepareShader(
                    shader: GlShader,
                    texMatrix: FloatArray,
                    frameWidth: Int,
                    frameHeight: Int,
                    viewportWidth: Int,
                    viewportHeight: Int,
                ) {
                    GLES20.glUniform4f(
                        shader.getUniformLocation("pipRect"),
                        pipX.toFloat(),
                        pipY.toFloat(),
                        pipSide.toFloat(),
                        pipSide.toFloat(),
                    )
                    GLES20.glUniform1f(shader.getUniformLocation("pipRadius"), pipSide * 0.18f)
                }
            },
        )

        private val cameraObserver = object : CapturerObserver {
            override fun onCapturerStarted(success: Boolean) {}
            override fun onCapturerStopped() {}
            override fun onFrameCaptured(frame: VideoFrame) {
                frame.retain()
                latestCamera.getAndSet(frame)?.release()
            }
        }

        private fun startCamera() {
            val ctx = ScreenPip.context
            val enumerator: CameraEnumerator =
                if (Camera2Enumerator.isSupported(ctx)) Camera2Enumerator(ctx) else Camera1Enumerator(true)
            val name = enumerator.deviceNames.firstOrNull { enumerator.isFrontFacing(it) == front }
                ?: enumerator.deviceNames.firstOrNull()
                ?: return
            val helper = SurfaceTextureHelper.create("PipCamera", VideoCapturerDevice.getEglBase().eglBaseContext)
            val capturer = enumerator.createCapturer(name, null)
            capturer.initialize(helper, ctx, cameraObserver)
            capturer.startCapture(640, 480, 30)
            cameraHelper = helper
            camera = capturer
        }

        fun switchCamera(front: Boolean) {
            val ctx = ScreenPip.context
            val enumerator: CameraEnumerator =
                if (Camera2Enumerator.isSupported(ctx)) Camera2Enumerator(ctx) else Camera1Enumerator(true)
            val name = enumerator.deviceNames.firstOrNull { enumerator.isFrontFacing(it) == front } ?: return
            camera?.switchCamera(null, name)
        }

        private fun stopCamera() {
            try {
                camera?.stopCapture()
            } catch (e: InterruptedException) {
                Thread.currentThread().interrupt()
            }
            camera?.dispose()
            camera = null
            cameraHelper?.dispose()
            cameraHelper = null
            latestCamera.getAndSet(null)?.release()
        }

        override fun onCapturerStarted(success: Boolean) {
            target.onCapturerStarted(success)
            if (success) {
                try {
                    startCamera()
                } catch (e: Exception) {
                    Log.w(TAG, "Camera for the screen-share bubble failed", e)
                }
            }
        }

        override fun onCapturerStopped() {
            stopCamera()
            screen.handler.post {
                for (fb in pool) fb?.release()
                pool.fill(null)
                frameDrawer.release()
                plain.release()
                rounded.release()
                yuv.release()
            }
            ScreenPip.ended(this)
            target.onCapturerStopped()
        }

        override fun onFrameCaptured(frame: VideoFrame) {
            val cam = latestCamera.get()?.also { it.retain() }
            val slot = busy.indexOfFirst { !it }
            if (cam == null || slot < 0) {
                cam?.release()
                target.onFrameCaptured(frame)
                return
            }
            val w = frame.rotatedWidth
            val h = frame.rotatedHeight
            val fb = pool[slot] ?: GlTextureFrameBuffer(GLES20.GL_RGBA).also { pool[slot] = it }
            fb.setSize(w, h)
            GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, fb.frameBufferId)
            frameDrawer.drawFrame(frame, plain, null, 0, 0, w, h, false, false)

            val (x, y, side) = rect(w, h, corner, size)
            pipX = x
            pipY = y
            pipSide = side
            frameDrawer.drawFrame(cam, rounded, squareCrop(cam), x, y, side, side, false, false)
            cam.release()
            GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, 0)
            // The encoder samples this texture from another context.
            GLES20.glFinish()

            busy[slot] = true
            val buffer = TextureBufferImpl(
                w,
                h,
                VideoFrame.TextureBuffer.Type.RGB,
                fb.textureId,
                Matrix(),
                screen.handler,
                yuv,
            ) { screen.handler.post { busy[slot] = false } }
            val out = VideoFrame(buffer, 0, frame.timestampNs)
            target.onFrameCaptured(out)
            out.release()
        }

        /** Shows the centre square of the camera frame. */
        private fun squareCrop(cam: VideoFrame): Matrix {
            val cw = cam.rotatedWidth.toFloat()
            val ch = cam.rotatedHeight.toFloat()
            return Matrix().apply {
                preTranslate(0.5f, 0.5f)
                if (cw > ch) preScale(ch / cw, 1f) else preScale(1f, cw / ch)
                preTranslate(-0.5f, -0.5f)
            }
        }
    }

    private const val TAG = "ScreenPip"
}
