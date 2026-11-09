package com.prs.localist

import android.accessibilityservice.AccessibilityService
import android.app.Activity
import android.content.Context
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.MediaCodecList
import org.webrtc.Camera2Enumerator
import android.os.Build
import android.view.WindowManager
import android.widget.Toast
import com.carriez.flutter_hbb.InputService

object CaptureDeviceControls {
    fun capabilities(context: Context, cameraId: String?, rear: Boolean,
                     width: Int = 1280, height: Int = 720, fps: Int = 30): Map<String, Any> {
        val manager = context.getSystemService(CameraManager::class.java)
        val ids = manager.cameraIdList
        val normalized = cameraId?.takeIf { ids.contains(it) }
            ?: cameraId?.let { Regex("^Camera (\\d+)").find(it)?.groupValues?.get(1) }?.takeIf { ids.contains(it) }
        val id = normalized ?: ids.firstOrNull {
            manager.getCameraCharacteristics(it).get(CameraCharacteristics.LENS_FACING) ==
                if (rear) CameraCharacteristics.LENS_FACING_BACK else CameraCharacteristics.LENS_FACING_FRONT
        } ?: ids.firstOrNull() ?: return mapOf("maxZoom" to 1.0, "torch" to false)
        val camera = manager.getCameraCharacteristics(id)
        val modes = Camera2Enumerator(context).getSupportedFormats(id).orEmpty().map { format ->
            mapOf("width" to format.width, "height" to format.height,
                "minFps" to maxOf(1, format.framerate.min / 1000), "maxFps" to maxOf(1, format.framerate.max / 1000))
        }
        // Intersect usable Android WebRTC video encoder ranges for this mode.
        // These are platform encoder capabilities, not a network speed claim.
        val encoders = MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos.filter { it.isEncoder }
            .flatMap { info -> info.supportedTypes.filter { it in setOf("video/avc", "video/x-vnd.on2.vp8", "video/x-vnd.on2.vp9", "video/av01") }
                .mapNotNull { mime -> runCatching {
                    val caps = info.getCapabilitiesForType(mime).videoCapabilities ?: return@runCatching null
                    if (!caps.areSizeAndRateSupported(width, height, fps.toDouble())) return@runCatching null
                    Triple(mime, caps.bitrateRange.lower, caps.bitrateRange.upper)
                }.getOrNull() } }
        val minBitrate = encoders.maxOfOrNull { (it.second + 999) / 1000 } ?: 0
        val maxBitrate = encoders.minOfOrNull { it.third / 1000 } ?: 0
        return mapOf(
            "cameraId" to id,
            "modes" to modes,
            "minBitrateKbps" to minBitrate,
            "maxBitrateKbps" to if (maxBitrate >= minBitrate) maxBitrate else 0,
            "codecs" to encoders.map { when(it.first) { "video/avc" -> "H.264"; "video/x-vnd.on2.vp8" -> "VP8"; "video/x-vnd.on2.vp9" -> "VP9"; else -> "AV1" } }.distinct().joinToString(", "),
            "maxZoom" to (camera.get(CameraCharacteristics.SCALER_AVAILABLE_MAX_DIGITAL_ZOOM)?.toDouble() ?: 1.0),
            "torch" to (camera.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true),
        )
    }

    fun background(activity: Activity): Boolean {
        activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        // Use an already-authorized accessibility service only. Locking the
        // phone never causes a new accessibility/device-admin permission flow.
        val locked = Build.VERSION.SDK_INT >= 28 &&
            InputService.ctx?.performGlobalAction(AccessibilityService.GLOBAL_ACTION_LOCK_SCREEN) == true
        if (!locked) {
            Toast.makeText(activity, LocalistText.choose(activity,
                "انتقال ادامه دارد؛ اکنون می‌توانید با دکمهٔ پاور صفحه را خاموش کنید.",
                "Sharing continues. You can now turn the screen off with the power button."), Toast.LENGTH_LONG).show()
        }
        activity.moveTaskToBack(true)
        return locked
    }
}
