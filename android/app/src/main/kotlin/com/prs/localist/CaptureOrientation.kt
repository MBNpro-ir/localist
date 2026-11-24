package com.prs.localist

import android.content.Context
import android.graphics.Matrix
import android.hardware.SensorManager
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.view.OrientationEventListener
import android.view.WindowManager
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.cloudwebrtc.webrtc.FlutterWebRTCPlugin
import com.cloudwebrtc.webrtc.video.LocalVideoTrack
import org.webrtc.JavaI420Buffer
import org.webrtc.TextureBufferImpl
import org.webrtc.VideoFrame
import org.webrtc.YuvHelper
import kotlin.math.abs
import kotlin.math.roundToInt

/** Physical orientation is independent of Android's display/auto-rotate lock. */
object CaptureOrientation {
    private var track: LocalVideoTrack? = null
    private var processor: LocalVideoTrack.ExternalVideoFrameProcessing? = null
    private var listener: OrientationEventListener? = null

    @Synchronized fun set(context: Context, trackId: String?, cameraId: String?, rear: Boolean) {
        clear()
        if (trackId == null) return
        val local = FlutterWebRTCPlugin.sharedSingleton?.getLocalTrack(trackId) as? LocalVideoTrack
            ?: throw IllegalStateException("The active camera track is unavailable")
        val manager = context.getSystemService(CameraManager::class.java)
        val ids = manager.cameraIdList
        val id = cameraId?.takeIf { it in ids }
            ?: cameraId?.let { Regex("^Camera (\\d+)").find(it)?.groupValues?.get(1) }?.takeIf { it in ids }
            ?: ids.firstOrNull { manager.getCameraCharacteristics(it).get(CameraCharacteristics.LENS_FACING) ==
                if (rear) CameraCharacteristics.LENS_FACING_BACK else CameraCharacteristics.LENS_FACING_FRONT }
        val characteristics = id?.let(manager::getCameraCharacteristics)
        val facing = characteristics?.get(CameraCharacteristics.LENS_FACING)
        val front = facing?.let { it == CameraCharacteristics.LENS_FACING_FRONT } ?: !rear
        val sensor = characteristics?.get(CameraCharacteristics.SENSOR_ORIENTATION)
        @Suppress("DEPRECATION")
        val initial = (360 - context.getSystemService(WindowManager::class.java).defaultDisplay.rotation * 90) % 360
        val displayPhysical = {
            @Suppress("DEPRECATION")
            (360 - context.getSystemService(WindowManager::class.java).defaultDisplay.rotation * 90) % 360
        }
        val main = Handler(Looper.getMainLooper())
        val transform = FrameRotation(front, initial, displayPhysical,
            sensorOrientation = sensor,
            followsDevice = facing != CameraCharacteristics.LENS_FACING_EXTERNAL,
            dimensionsChanged = { width, height ->
                main.post {
                    if (track === local) CaptureForegroundService.channel?.invokeMethod(
                        "captureVideoGeometry", mapOf("track" to trackId, "width" to width, "height" to height)
                    )
                }
            },
        ) { message ->
            main.post {
                if (track === local) CaptureForegroundService.channel?.invokeMethod("captureError", message)
            }
        }
        local.addProcessor(transform)
        track = local
        processor = transform
        run {
            listener = object : OrientationEventListener(context.applicationContext, SensorManager.SENSOR_DELAY_NORMAL) {
                override fun onOrientationChanged(orientation: Int) {
                    if (orientation != ORIENTATION_UNKNOWN) transform.update(orientation)
                }
            }.also { if (it.canDetectOrientation()) it.enable() }
        }
    }

    @Synchronized fun clear() {
        listener?.disable()
        listener = null
        processor?.let { track?.removeProcessor(it) }
        track = null
        processor = null
    }

    internal class FrameRotation(
        private val front: Boolean,
        initial: Int,
        private val displayPhysical: () -> Int = { initial },
        private val sensorOrientation: Int? = null,
        private val followsDevice: Boolean = true,
        private val dimensionsChanged: ((Int, Int) -> Unit)? = null,
        private val failure: ((String) -> Unit)? = null,
    ) : LocalVideoTrack.ExternalVideoFrameProcessing {
        @Volatile private var physical = initial
        private var layout: FrameLayout? = null
        private var reported = false

        fun update(degrees: Int) {
            // Hysteresis prevents jitter at the portrait/landscape boundary.
            val distance = abs(degrees - physical).let { minOf(it, 360 - it) }
            if (distance >= 60) physical = ((degrees + 45) / 90 * 90) % 360
        }

        override fun onFrame(frame: VideoFrame): VideoFrame = try {
            process(frame)
        } catch (error: OutOfMemoryError) {
            fail("حافظه برای این کیفیت کافی نیست؛ کیفیت پایین‌تری انتخاب کنید. / Not enough memory for this capture mode.", error)
            frame
        } catch (error: RuntimeException) {
            fail("پردازش دوربین متوقف شد؛ کیفیت یا دوربین دیگری انتخاب کنید. / Camera frame processing failed.", error)
            frame
        }

        private fun fail(message: String, error: Throwable) {
            if (reported) return
            reported = true
            Log.e("LocalistCapture", message, error)
            failure?.invoke(message)
        }

        private fun process(frame: VideoFrame): VideoFrame {
            val pose = physical
            val sign = if (front) -1 else 1
            val rotation = when {
                !followsDevice -> frame.rotation
                sensorOrientation != null -> (sensorOrientation + sign * pose + 360) % 360
                else -> (frame.rotation + sign * (pose - displayPhysical()) + 360) % 360
            }
            val buffer = frame.buffer
            val previous = layout
            val current = if (previous != null &&
                previous.sourceWidth == buffer.width && previous.sourceHeight == buffer.height &&
                previous.rotation == rotation
            ) previous else FrameLayout(buffer.width, buffer.height, rotation).also {
                layout = it
                Log.d("LocalistCapture", "camera pose=$pose rotation=$rotation size=${it.width}x${it.height}")
                if (previous == null || previous.width != it.width || previous.height != it.height) {
                    dimensionsChanged?.invoke(it.width, it.height)
                }
            }
            if (rotation == 0 && !current.needsCrop) return rotatePixels(frame, 0)
            // Sample the upright crop directly on the camera texture. Both the
            // preview and encoder retain the same frame, with no YUV copy here.
            if (buffer is TextureBufferImpl) {
                return VideoFrame(
                    buffer.applyTransformMatrix(current.sampling, current.width, current.height),
                    0, frame.timestampNs
                )
            }
            val rotated = rotatePixels(frame, rotation)
            if (!current.needsCrop || (rotated === frame && rotation != 0)) return rotated
            try {
                val cropWidth = (current.orientedWidth * current.scaleX).roundToInt().coerceAtLeast(1)
                val cropHeight = (current.orientedHeight * current.scaleY).roundToInt().coerceAtLeast(1)
                val cropped = rotated.buffer.cropAndScale(
                    (current.orientedWidth - cropWidth) / 2, (current.orientedHeight - cropHeight) / 2,
                    cropWidth, cropHeight, current.width, current.height
                )
                return VideoFrame(cropped, 0, frame.timestampNs)
            } finally {
                if (rotated !== frame) rotated.release()
            }
        }
    }

    /** Image fills 16:9 or 9:16 without stretching or carrying rotation metadata. */
    private class FrameLayout(val sourceWidth: Int, val sourceHeight: Int, val rotation: Int) {
        val orientedWidth = if (rotation % 180 == 0) sourceWidth else sourceHeight
        val orientedHeight = if (rotation % 180 == 0) sourceHeight else sourceWidth
        private val portrait = orientedHeight > orientedWidth
        private val unitsWide = if (portrait) 9 else 16
        private val unitsTall = if (portrait) 16 else 9
        private val multiplier = (minOf(orientedWidth / unitsWide, orientedHeight / unitsTall) and -2)
            .coerceAtLeast(2)
        val width = unitsWide * multiplier
        val height = unitsTall * multiplier
        private val aspect = width.toFloat() / height
        val scaleX = minOf(1f, orientedHeight * aspect / orientedWidth)
        val scaleY = minOf(1f, orientedWidth / (aspect * orientedHeight))
        val needsCrop = width != orientedWidth || height != orientedHeight
        val sampling = Matrix().apply {
            setRotate(rotation.toFloat(), .5f, .5f)
            preScale(scaleX, scaleY, .5f, .5f)
        }
    }

    /** Bake rotation into pixels for webcam/encoder consumers, without stretching. */
    internal fun rotatePixels(frame: VideoFrame, rotation: Int): VideoFrame {
        require(rotation in listOf(0, 90, 180, 270))
        if (rotation == 0) {
            if (frame.rotation == 0) return frame
            frame.buffer.retain()
            return VideoFrame(frame.buffer, 0, frame.timestampNs)
        }
        val input = frame.buffer.toI420() ?: return frame
        try {
            val swap = rotation % 180 != 0
            val output = JavaI420Buffer.allocate(if (swap) input.height else input.width, if (swap) input.width else input.height)
            try {
                YuvHelper.I420Rotate(input.dataY, input.strideY, input.dataU, input.strideU,
                    input.dataV, input.strideV, output.dataY, output.strideY, output.dataU,
                    output.strideU, output.dataV, output.strideV, input.width, input.height, rotation)
                return VideoFrame(output, 0, frame.timestampNs)
            } catch (error: Throwable) {
                output.release()
                throw error
            }
        } finally { input.release() }
    }
}
