package com.prs.localist

import java.net.Inet4Address
import java.net.InetSocketAddress
import java.net.NetworkInterface
import java.net.ServerSocket
import java.util.Locale

object NetworkAddressInspector {
    fun localProxyIps(): List<String> {
        return runCatching {
            NetworkInterface.getNetworkInterfaces().asSequence()
                .filter { network ->
                    network.isUp &&
                        !network.isLoopback &&
                        !isIgnoredInterface(network.name)
                }
                .flatMap { network ->
                    network.interfaceAddresses.asSequence().mapNotNull { address ->
                        val inet = address.address as? Inet4Address ?: return@mapNotNull null
                        val host = inet.hostAddress ?: return@mapNotNull null
                        if (isUsableIpv4(inet, host) && canBind(host)) host else null
                    }
                }
                .distinct()
                .sortedWith(compareBy<String> { !it.endsWith(".1") }.thenBy { it })
                .toList()
        }.getOrDefault(emptyList())
    }

    fun primaryLocalIp(): String {
        return localProxyIps().firstOrNull() ?: DEFAULT_HOTSPOT_IP
    }

    private fun canBind(host: String): Boolean {
        return runCatching {
            ServerSocket().use { socket ->
                socket.reuseAddress = true
                socket.bind(InetSocketAddress(host, 0))
            }
        }.isSuccess
    }

    private fun isIgnoredInterface(name: String): Boolean {
        val lower = name.lowercase(Locale.US)
        return lower.startsWith("lo") ||
            lower.startsWith("dummy") ||
            lower.startsWith("ifb") ||
            lower.contains("clat") ||
            lower.startsWith("tun") ||
            lower.startsWith("ppp")
    }

    private fun isUsableIpv4(address: Inet4Address, value: String): Boolean {
        if (
            address.isAnyLocalAddress ||
            address.isLoopbackAddress ||
            address.isMulticastAddress ||
            value == "255.255.255.255"
        ) {
            return false
        }
        val parts = value.split('.').mapNotNull { it.toIntOrNull() }
        if (parts.size != 4 || parts.any { it !in 0..255 }) {
            return false
        }
        return parts[0] !in 224..255 && parts[0] != 127
    }

    private const val DEFAULT_HOTSPOT_IP = "192.168.43.1"
}
