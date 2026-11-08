package com.prs.localist

import android.accessibilityservice.AccessibilityService
import android.app.Activity
import android.content.Context
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.os.Build
import android.view.WindowManager
import android.widget.Toast
import com.carriez.flutter_hbb.InputService

object CaptureDeviceControls {
    fun capabilities(context: Context, cameraId: String?, rear: Boolean): Map<String, Any> {
        val manager = context.getSystemService(CameraManager::class.java)
        val ids = manager.cameraIdList
        val normalized = cameraId?.takeIf { ids.contains(it) }
            ?: cameraId?.let { Regex("^Camera (\\d+)").find(it)?.groupValues?.get(1) }?.takeIf { ids.contains(it) }
        val id = normalized ?: ids.firstOrNull {
            manager.getCameraCharacteristics(it).get(CameraCharacteristics.LENS_FACING) ==
                if (rear) CameraCharacteristics.LENS_FACING_BACK else CameraCharacteristics.LENS_FACING_FRONT
        } ?: ids.firstOrNull() ?: return mapOf("maxZoom" to 1.0, "torch" to false)
        val camera = manager.getCameraCharacteristics(id)
        return mapOf(
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
