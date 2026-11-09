package com.prs.localist

import android.content.Context
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
import org.webrtc.VideoFrame
import org.webrtc.YuvHelper
import kotlin.math.abs

/** Physical orientation is independent of Android's display/auto-rotate lock. */
object CaptureOrientation {
    private var track: LocalVideoTrack? = null
    private var processor: LocalVideoTrack.ExternalVideoFrameProcessing? = null
    private var listener: OrientationEventListener? = null

    @Synchronized fun set(context: Context, trackId: String?, mode: String, cameraId: String?, rear: Boolean) {
        require(mode in listOf("auto", "portrait", "landscape"))
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
        val front = characteristics?.get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_FRONT
        val sensor = characteristics?.get(CameraCharacteristics.SENSOR_ORIENTATION)
        @Suppress("DEPRECATION")
        val initial = (360 - context.getSystemService(WindowManager::class.java).defaultDisplay.rotation * 90) % 360
        val transform = FrameRotation(mode, sensor, front, initial) { message ->
            Handler(Looper.getMainLooper()).post {
                if (track === local) CaptureForegroundService.channel?.invokeMethod("captureError", message)
            }
        }
        local.addProcessor(transform)
        track = local
        processor = transform
        if (sensor != null) {
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
        private val mode: String,
        private val sensor: Int?,
        private val front: Boolean,
        initial: Int,
        private val failure: ((String) -> Unit)? = null,
    ) : LocalVideoTrack.ExternalVideoFrameProcessing {
        @Volatile private var physical = initial
        private var blackY = ByteArray(0)
        private var blackUV = ByteArray(0)
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
            val rotation = sensor?.let { (it + (if (front) -physical else physical) + 360) % 360 }
                ?: frame.rotation
            val rotated = rotatePixels(frame, rotation)
            if (mode == "auto") return rotated
            val wide = maxOf(frame.buffer.width, frame.buffer.height) and -2
            val narrow = minOf(frame.buffer.width, frame.buffer.height) and -2
            val width = if (mode == "landscape") wide else narrow
            val height = if (mode == "landscape") narrow else wide
            if (rotated.buffer.width == width && rotated.buffer.height == height) return rotated
            try {
            if (blackY.size != width * height) {
                blackY = ByteArray(width * height) { 16 }
                blackUV = ByteArray(width * height / 4) { 128.toByte() }
            }
            val fitted = fitPixels(rotated, width, height, blackY, blackUV)
            if (rotated !== frame && fitted !== rotated) rotated.release()
            return fitted
            } catch (error: Throwable) {
                if (rotated !== frame) rotated.release()
                throw error
            }
        }
    }

    /** Upright portrait content is letterboxed into a stable landscape canvas. */
    internal fun fitPixels(frame: VideoFrame, width: Int, height: Int, blackY: ByteArray, blackUV: ByteArray): VideoFrame {
        val scale = minOf(width.toDouble() / frame.buffer.width, height.toDouble() / frame.buffer.height)
        val innerWidth = maxOf(2, (frame.buffer.width * scale).toInt() and -2)
        val innerHeight = maxOf(2, (frame.buffer.height * scale).toInt() and -2)
        val scaled = frame.buffer.cropAndScale(0, 0, frame.buffer.width, frame.buffer.height, innerWidth, innerHeight)
        val input = scaled.toI420() ?: run { scaled.release(); return frame }
        try {
            val output = JavaI420Buffer.allocate(width, height)
            try {
                output.dataY.put(blackY); output.dataU.put(blackUV); output.dataV.put(blackUV)
                val left = ((width - innerWidth) / 2) and -2
                val top = ((height - innerHeight) / 2) and -2
                val y = output.dataY; y.position(top * output.strideY + left)
                val u = output.dataU; u.position(top / 2 * output.strideU + left / 2)
                val v = output.dataV; v.position(top / 2 * output.strideV + left / 2)
                YuvHelper.I420Copy(input.dataY, input.strideY, input.dataU, input.strideU,
                    input.dataV, input.strideV, y.slice(), output.strideY, u.slice(), output.strideU,
                    v.slice(), output.strideV, innerWidth, innerHeight)
                return VideoFrame(output, 0, frame.timestampNs)
            } catch (error: Throwable) { output.release(); throw error }
        } finally { input.release(); scaled.release() }
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
