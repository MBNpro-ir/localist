package com.prs.localist

import android.content.Context
import android.net.wifi.WifiManager
import android.os.Build
import java.net.DatagramPacket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.MulticastSocket
import java.util.Locale
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import org.json.JSONArray
import org.json.JSONObject

data class LocalistDiscoveryEndpoint(
    val protocol: String,
    val host: String,
    val port: Int,
)

class LocalistDiscoveryResponder(private val context: Context) {
    @Volatile
    private var running = false
    private var socket: MulticastSocket? = null
    private var executor: ExecutorService? = null
    private var multicastLock: WifiManager.MulticastLock? = null
    private var endpointsProvider: (() -> List<LocalistDiscoveryEndpoint>)? = null

    fun start(endpointsProvider: () -> List<LocalistDiscoveryEndpoint>) {
        stop()
        this.endpointsProvider = endpointsProvider
        running = true
        acquireMulticastLock()
        executor = Executors.newSingleThreadExecutor().also { service ->
            service.execute { listenLoop() }
        }
    }

    fun stop() {
        running = false
        runCatching { socket?.close() }
        socket = null
        executor?.shutdownNow()
        executor = null
        endpointsProvider = null
        releaseMulticastLock()
    }

    private fun listenLoop() {
        val group = InetAddress.getByName(MULTICAST_ADDRESS)
        runCatching {
            MulticastSocket(null).use { udpSocket ->
                udpSocket.reuseAddress = true
                udpSocket.broadcast = true
                udpSocket.bind(InetSocketAddress(DISCOVERY_PORT))
                socket = udpSocket
                @Suppress("DEPRECATION")
                runCatching { udpSocket.joinGroup(group) }
                val buffer = ByteArray(MAX_PACKET_BYTES)
                while (running) {
                    val packet = DatagramPacket(buffer, buffer.size)
                    runCatching {
                        udpSocket.receive(packet)
                        handlePacket(udpSocket, packet)
                    }
                }
            }
        }
        socket = null
    }

    private fun handlePacket(udpSocket: MulticastSocket, packet: DatagramPacket) {
        val request = runCatching {
            JSONObject(String(packet.data, packet.offset, packet.length, Charsets.UTF_8))
        }.getOrNull() ?: return
        if (
            request.optString("type") != DISCOVERY_TYPE ||
                request.optString("op") != QUERY_OP ||
                request.optString("deviceId") == deviceId()
        ) {
            return
        }
        val endpoints = endpointsProvider?.invoke().orEmpty()
        if (endpoints.isEmpty()) {
            return
        }
        val response = JSONObject()
            .put("type", DISCOVERY_TYPE)
            .put("op", ANNOUNCE_OP)
            .put("deviceId", deviceId())
            .put("deviceName", deviceName())
            .put("platform", "Android")
            .put(
                "endpoints",
                JSONArray().also { array ->
                    endpoints.forEach { endpoint ->
                        array.put(
                            JSONObject()
                                .put("protocol", endpoint.protocol)
                                .put("host", endpoint.host)
                                .put("port", endpoint.port),
                        )
                    }
                },
            )
        val bytes = response.toString().toByteArray(Charsets.UTF_8)
        udpSocket.send(DatagramPacket(bytes, bytes.size, packet.address, packet.port))
    }

    private fun acquireMulticastLock() {
        val wifiManager = context.applicationContext.getSystemService(WifiManager::class.java)
        multicastLock = wifiManager?.createMulticastLock(
            "${context.packageName}:LocalistDiscovery",
        )?.apply {
            setReferenceCounted(false)
            runCatching { acquire() }
        }
    }

    private fun releaseMulticastLock() {
        runCatching {
            if (multicastLock?.isHeld == true) {
                multicastLock?.release()
            }
        }
        multicastLock = null
    }

    private fun deviceId(): String {
        val prefs = context.getSharedPreferences(PREFS_DISCOVERY, Context.MODE_PRIVATE)
        val stored = prefs.getString(KEY_DEVICE_ID, null)
        if (!stored.isNullOrBlank()) {
            return stored
        }
        val generated = UUID.randomUUID().toString()
        prefs.edit().putString(KEY_DEVICE_ID, generated).apply()
        return generated
    }

    private fun deviceName(): String {
        val manufacturer = Build.MANUFACTURER
            ?.replaceFirstChar { it.titlecase(Locale.US) }
            ?.trim()
            .orEmpty()
        val model = Build.MODEL?.trim().orEmpty()
        return listOf(manufacturer, model)
            .filter { it.isNotBlank() }
            .distinct()
            .joinToString(" ")
            .ifBlank { "Android device" }
    }

    companion object {
        private const val DISCOVERY_TYPE = "localist.discovery.v1"
        private const val QUERY_OP = "query"
        private const val ANNOUNCE_OP = "announce"
        private const val MULTICAST_ADDRESS = "239.255.88.88"
        private const val DISCOVERY_PORT = 37888
        private const val MAX_PACKET_BYTES = 4096
        private const val PREFS_DISCOVERY = "localist_discovery"
        private const val KEY_DEVICE_ID = "device_id"
    }
}
