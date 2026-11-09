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
        val displayPhysical = {
            @Suppress("DEPRECATION")
            (360 - context.getSystemService(WindowManager::class.java).defaultDisplay.rotation * 90) % 360
        }
        val transform = FrameRotation(mode, front, initial, displayPhysical, diagnostics = { detail ->
            Handler(Looper.getMainLooper()).post {
                if (track === local) CaptureForegroundService.channel?.invokeMethod("captureDiagnostics",
                    "Camera orientation: id=$id sensor=$sensor front=$front $detail")
            }
        }) { message ->
            Handler(Looper.getMainLooper()).post {
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
        private val mode: String,
        private val front: Boolean,
        initial: Int,
        private val displayPhysical: () -> Int = { initial },
        private val diagnostics: ((String) -> Unit)? = null,
        private val failure: ((String) -> Unit)? = null,
    ) : LocalVideoTrack.ExternalVideoFrameProcessing {
        @Volatile private var physical = initial
        @Volatile private var lockedPhysical = if (mode == "landscape") 270 else 0
        private var awaitingPose = true
        private var logged = false
        private var reported = false

        fun update(degrees: Int) {
            // Hysteresis prevents jitter at the portrait/landscape boundary.
            val distance = abs(degrees - physical).let { minOf(it, 360 - it) }
            if (distance >= 60) physical = ((degrees + 45) / 90 * 90) % 360
            if (awaitingPose) {
                val landscape = mode == "landscape"
                if ((physical % 180 != 0) == landscape) lockedPhysical = physical
                awaitingPose = false
            }
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
            // The capturer's metadata is authoritative: Camera1, Camera2 and
            // vendor texture transforms need not share raw sensor coordinates.
            // Only compensate for the difference between screen and physical pose.
            val target = if (mode == "auto") physical else lockedPhysical
            val delta = target - displayPhysical()
            var rotation = (frame.rotation + (if (front) -delta else delta) + 720) % 360
            if (mode != "auto") {
                val rotatedWide = if (rotation % 180 == 0)
                    frame.buffer.width >= frame.buffer.height else frame.buffer.height >= frame.buffer.width
                if (rotatedWide != (mode == "landscape")) rotation = (rotation + 90) % 360
            }
            if (!logged) {
                logged = true
                diagnostics?.invoke("mode=$mode native=${frame.rotation} physical=$physical target=$target rotation=$rotation size=${frame.buffer.width}x${frame.buffer.height}")
            }
            return rotatePixels(frame, rotation)
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
