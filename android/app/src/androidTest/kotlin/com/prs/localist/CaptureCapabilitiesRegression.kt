package com.prs.localist

import android.content.Context
import android.hardware.camera2.CameraManager
import org.json.JSONObject

object CaptureCapabilitiesRegression {
    fun verify(context: Context): String {
        val manager = context.getSystemService(CameraManager::class.java)
        val cameras = manager.cameraIdList.map { id ->
            val caps = CaptureDeviceControls.capabilities(context, id, false, 640, 480, 30)
            val modes = caps["modes"] as List<*>
            check(modes.isNotEmpty()) { "No camera modes reported for $id" }
            check(modes.all { row -> val mode=row as Map<*,*>; (mode["width"] as Int)>0 && (mode["height"] as Int)>0 && (mode["maxFps"] as Int)>0 })
            val minimum = caps["minBitrateKbps"] as Int; val maximum = caps["maxBitrateKbps"] as Int
            check(minimum > 0 && maximum >= minimum) { "No encoder range for $id" }
            mapOf("id" to id, "modeCount" to modes.size, "minBitrateKbps" to minimum,
                "maxBitrateKbps" to maximum, "codecs" to caps["codecs"], "modes" to modes)
        }
        check(cameras.isNotEmpty())
        return "LOCALIST_CAPTURE_CAPABILITIES_OK " + JSONObject(mapOf("cameras" to cameras))
    }
}
