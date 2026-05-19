package com.prs.localist

import android.content.Context
import android.net.wifi.WifiManager
import android.os.Build
import java.net.DatagramPacket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.MulticastSocket
import java.net.NetworkInterface
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
    private var cachedEndpoints: List<LocalistDiscoveryEndpoint> = emptyList()
    private var cachedEndpointsAtMs: Long = 0L
    private val lastResponseByPeer = mutableMapOf<String, Long>()

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
        cachedEndpoints = emptyList()
        cachedEndpointsAtMs = 0L
        lastResponseByPeer.clear()
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
                joinGroupOnInterfaces(udpSocket, group)
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
        val now = System.currentTimeMillis()
        val peerKey = "${packet.address.hostAddress}:${packet.port}"
        if (isPeerRateLimited(peerKey, now)) {
            return
        }
        val endpoints = currentEndpoints(now)
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

    private fun joinGroupOnInterfaces(udpSocket: MulticastSocket, group: InetAddress) {
        runCatching {
            NetworkInterface.getNetworkInterfaces().asSequence()
                .filter { it.isUp && !it.isLoopback }
                .forEach { network ->
                    runCatching {
                        udpSocket.joinGroup(InetSocketAddress(group, DISCOVERY_PORT), network)
                    }
                }
        }
    }

    private fun currentEndpoints(now: Long): List<LocalistDiscoveryEndpoint> {
        if (now - cachedEndpointsAtMs < ENDPOINT_CACHE_TTL_MS) {
            return cachedEndpoints
        }
        val endpoints = runCatching {
            endpointsProvider?.invoke().orEmpty()
        }.getOrDefault(cachedEndpoints)
        cachedEndpoints = endpoints
        cachedEndpointsAtMs = now
        return endpoints
    }

    private fun isPeerRateLimited(peerKey: String, now: Long): Boolean {
        val iterator = lastResponseByPeer.iterator()
        while (iterator.hasNext()) {
            if (now - iterator.next().value > PEER_RESPONSE_MEMORY_MS) {
                iterator.remove()
            }
        }
        val last = lastResponseByPeer[peerKey]
        if (last != null && now - last < PEER_RESPONSE_INTERVAL_MS) {
            return true
        }
        lastResponseByPeer[peerKey] = now
        return false
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
        val stateDeviceId = LocalistVpnService.discoveryDeviceId()
        if (stateDeviceId.isNotBlank()) {
            return stateDeviceId
        }
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
        private const val ENDPOINT_CACHE_TTL_MS = 2_000L
        private const val PEER_RESPONSE_INTERVAL_MS = 750L
        private const val PEER_RESPONSE_MEMORY_MS = 60_000L
        private const val PREFS_DISCOVERY = "localist_discovery"
        private const val KEY_DEVICE_ID = "device_id"
    }
}
