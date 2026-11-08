package com.prs.localist

import android.content.Context
import android.hardware.SensorManager
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.view.OrientationEventListener
import android.view.WindowManager
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
        val transform = FrameRotation(mode, sensor, front, initial)
        local.addProcessor(transform)
        track = local
        processor = transform
        if (mode == "auto") {
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
    ) : LocalVideoTrack.ExternalVideoFrameProcessing {
        @Volatile private var physical = initial
        private var fixedRotation: Int? = null

        fun update(degrees: Int) {
            // Hysteresis prevents jitter at the portrait/landscape boundary.
            val distance = abs(degrees - physical).let { minOf(it, 360 - it) }
            if (distance >= 60) physical = ((degrees + 45) / 90 * 90) % 360
        }

        override fun onFrame(frame: VideoFrame): VideoFrame {
            var rotation = sensor?.let { (it + (if (front) -physical else physical) + 360) % 360 }
                ?: frame.rotation
            if (mode != "auto") {
                if (fixedRotation == null) {
                    val portrait = if (rotation % 180 == 0) frame.buffer.height > frame.buffer.width
                        else frame.buffer.width > frame.buffer.height
                    fixedRotation = if (portrait == (mode == "portrait")) rotation else (rotation + 90) % 360
                }
                rotation = fixedRotation!!
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
