package com.prs.localist

import android.content.Context
import android.net.wifi.WifiManager

object HotspotController {
    fun snapshot(context: Context): Map<String, Any> {
        val systemActive = isSystemHotspotActive(context)
        val activeInfo = if (systemActive) {
            HotspotInfo(
                active = true,
                ssid = "Android hotspot",
                password = "",
                ipAddress = localIpAddress(),
            )
        } else {
            HotspotInfo(
                active = false,
                ssid = "Android hotspot",
                password = "",
                ipAddress = DEFAULT_HOTSPOT_IP,
            )
        }
        return mapOf(
            "active" to activeInfo.active,
            "ssid" to activeInfo.ssid,
            "password" to activeInfo.password,
            "ipAddress" to activeInfo.ipAddress.ifBlank { localIpAddress() },
            "managedByLocalist" to false,
            "systemDetected" to systemActive,
        )
    }

    fun localIpAddress(): String {
        return NetworkAddressInspector.primaryLocalIp()
    }

    private fun isSystemHotspotActive(context: Context): Boolean {
        val wifiManager =
            context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        runCatching {
            val method = wifiManager.javaClass.methods.firstOrNull {
                it.name == "isWifiApEnabled"
            } ?: wifiManager.javaClass.declaredMethods.firstOrNull {
                it.name == "isWifiApEnabled"
            }
            if (method != null) {
                method.isAccessible = true
                return method.invoke(wifiManager) == true
            }
        }
        return hasLikelyHotspotInterface()
    }

    private fun hasLikelyHotspotInterface(): Boolean {
        return runCatching {
            java.net.NetworkInterface.getNetworkInterfaces().asSequence().any { network ->
                val name = network.name.lowercase()
                val isHotspotName = name.contains("ap") ||
                    name.contains("wlan") ||
                    name.contains("swlan") ||
                    name.contains("bridge")
                isHotspotName && network.inetAddresses.asSequence().any { address ->
                    val host = address.hostAddress ?: return@any false
                    !address.isLoopbackAddress &&
                        !host.contains(':') &&
                        (host == DEFAULT_HOTSPOT_IP ||
                            host.startsWith("192.168.") && host.endsWith(".1"))
                }
            }
        }.getOrDefault(false)
    }

    private const val DEFAULT_HOTSPOT_IP = "192.168.43.1"
}

data class HotspotInfo(
    val active: Boolean,
    val ssid: String,
    val password: String,
    val ipAddress: String,
)
