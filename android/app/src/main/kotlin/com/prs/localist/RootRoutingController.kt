package com.prs.localist

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import java.net.Inet4Address
import java.net.NetworkInterface
import java.util.Locale
import java.util.concurrent.TimeUnit

object RootRoutingController {
    private const val PREFS = "localist_root_routing"
    private const val KEY_AVAILABLE = "available"
    private const val KEY_ENABLED = "enabled"
    private const val KEY_ACTIVE = "active"
    private const val KEY_VPN_IFACE = "vpn_iface"
    private const val KEY_CLIENT_SUBNETS = "client_subnets"
    private const val KEY_LAST_ERROR = "last_error"
    private const val ROUTE_TABLE = 10888
    private const val RULE_PREF = 10888

    fun checkRootAccess(context: Context): Map<String, Any> {
        val result = runRoot("id")
        val available = result.success && result.output.contains("uid=0")
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        prefs.edit()
            .putBoolean(KEY_AVAILABLE, available)
            .putString(KEY_LAST_ERROR, if (available) "" else result.output.ifBlank { result.error })
            .apply()
        return snapshot(context)
    }

    fun setEnabled(context: Context, enabled: Boolean): Map<String, Any> {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!enabled) {
            stop(context)
            prefs.edit()
                .putBoolean(KEY_ENABLED, false)
                .apply()
            return snapshot(context)
        }

        val root = checkRootAccess(context)
        if (root["available"] != true) {
            prefs.edit()
                .putBoolean(KEY_ENABLED, false)
                .apply()
            return snapshot(context)
        }

        prefs.edit()
            .putBoolean(KEY_ENABLED, true)
            .apply()
        return snapshot(context)
    }

    fun start(
        context: Context,
        shareAllRoutes: Boolean = true,
        selectedLocalIps: List<String> = emptyList(),
    ): Map<String, Any> {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!prefs.getBoolean(KEY_ENABLED, false)) {
            return fail(context, "Root routing is disabled in settings.")
        }
        val root = checkRootAccess(context)
        if (root["available"] != true) {
            return fail(context, "Root access was not granted.")
        }

        val vpnInterface = findVpnInterface(context)
            ?: return fail(context, "No active VPN interface was found.")
        val clientSubnets = if (shareAllRoutes) {
            findClientSubnets(vpnInterface)
        } else {
            findClientSubnets(vpnInterface, selectedLocalIps.toSet())
        }
        if (clientSubnets.isEmpty()) {
            return fail(context, "No local client subnet was found.")
        }

        cleanupRules(
            vpnInterface = prefs.getString(KEY_VPN_IFACE, "") ?: "",
            clientSubnets = prefs.getString(KEY_CLIENT_SUBNETS, "")?.split(',')
                ?.filter { it.isNotBlank() }
                ?: emptyList(),
        )

        val commands = buildApplyCommands(vpnInterface, clientSubnets)
        val failed = commands.firstOrNull { command -> !runRoot(command).success }
        if (failed != null) {
            cleanupRules(vpnInterface, clientSubnets)
            return fail(context, "Root routing command failed: $failed")
        }

        prefs.edit()
            .putBoolean(KEY_ACTIVE, true)
            .putString(KEY_VPN_IFACE, vpnInterface)
            .putString(KEY_CLIENT_SUBNETS, clientSubnets.joinToString(","))
            .putString(KEY_LAST_ERROR, "")
            .apply()
        return snapshot(context)
    }

    fun stop(context: Context): Map<String, Any> {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val vpnInterface = prefs.getString(KEY_VPN_IFACE, "") ?: ""
        val clientSubnets = prefs.getString(KEY_CLIENT_SUBNETS, "")?.split(',')
            ?.filter { it.isNotBlank() }
            ?: emptyList()
        cleanupRules(vpnInterface, clientSubnets)
        prefs.edit()
            .putBoolean(KEY_ACTIVE, false)
            .putString(KEY_VPN_IFACE, "")
            .putString(KEY_CLIENT_SUBNETS, "")
            .apply()
        return snapshot(context)
    }

    fun snapshot(context: Context): Map<String, Any> {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val clientSubnets = prefs.getString(KEY_CLIENT_SUBNETS, "")?.split(',')
            ?.filter { it.isNotBlank() }
            ?: emptyList()
        val availableSubnets = runCatching {
            findClientSubnets(prefs.getString(KEY_VPN_IFACE, "") ?: "")
        }.getOrDefault(emptyList())
        val availableLocalIps = NetworkAddressInspector.localProxyIps()
        return mapOf(
            "available" to prefs.getBoolean(KEY_AVAILABLE, false),
            "enabled" to prefs.getBoolean(KEY_ENABLED, false),
            "active" to prefs.getBoolean(KEY_ACTIVE, false),
            "vpnInterface" to (prefs.getString(KEY_VPN_IFACE, "") ?: ""),
            "clientSubnets" to clientSubnets,
            "availableClientSubnets" to availableSubnets,
            "availableLocalIps" to availableLocalIps,
            "lastError" to (prefs.getString(KEY_LAST_ERROR, "") ?: ""),
        )
    }

    fun readHotspotCredentials(): HotspotCredentials? {
        val commands = listOf(
            "dumpsys wifi",
            "cat /data/misc/apexdata/com.android.wifi/WifiConfigStoreSoftAp.xml 2>/dev/null",
            "cat /data/misc/wifi/WifiConfigStore.xml 2>/dev/null",
            "cat /data/misc/wifi/softap.conf 2>/dev/null",
        )
        for (command in commands) {
            val result = runRoot(command, timeoutSeconds = 5)
            if (!result.success || result.output.isBlank()) {
                continue
            }
            parseHotspotCredentials(result.output)?.let { return it }
        }
        return null
    }

    private fun fail(context: Context, message: String): Map<String, Any> {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        prefs.edit()
            .putBoolean(KEY_ACTIVE, false)
            .putString(KEY_LAST_ERROR, message)
            .apply()
        return snapshot(context)
    }

    private fun buildApplyCommands(vpnInterface: String, clientSubnets: List<String>): List<String> {
        val commands = mutableListOf(
            "sysctl -w net.ipv4.ip_forward=1 || echo 1 > /proc/sys/net/ipv4/ip_forward",
            "echo 0 > /proc/sys/net/ipv4/conf/all/rp_filter || true",
            "ip route replace default dev $vpnInterface table $ROUTE_TABLE",
        )
        for (subnet in clientSubnets) {
            commands += listOf(
                "ip rule list | grep -q 'from $subnet lookup $ROUTE_TABLE' || ip rule add from $subnet table $ROUTE_TABLE pref $RULE_PREF",
                iptablesEnsure("-t nat -C POSTROUTING -s $subnet -o $vpnInterface -j MASQUERADE", "-t nat -A POSTROUTING -s $subnet -o $vpnInterface -j MASQUERADE"),
                iptablesEnsure("-C FORWARD -s $subnet -o $vpnInterface -j ACCEPT", "-A FORWARD -s $subnet -o $vpnInterface -j ACCEPT"),
                iptablesEnsure("-C FORWARD -d $subnet -i $vpnInterface -m state --state ESTABLISHED,RELATED -j ACCEPT", "-A FORWARD -d $subnet -i $vpnInterface -m state --state ESTABLISHED,RELATED -j ACCEPT"),
            )
        }
        return commands
    }

    private fun cleanupRules(vpnInterface: String, clientSubnets: List<String>) {
        if (vpnInterface.isBlank()) {
            return
        }
        for (subnet in clientSubnets) {
            runRoot(iptablesDelete("-t nat -D POSTROUTING -s $subnet -o $vpnInterface -j MASQUERADE"))
            runRoot(iptablesDelete("-D FORWARD -s $subnet -o $vpnInterface -j ACCEPT"))
            runRoot(iptablesDelete("-D FORWARD -d $subnet -i $vpnInterface -m state --state ESTABLISHED,RELATED -j ACCEPT"))
            runRoot("ip rule del from $subnet table $ROUTE_TABLE pref $RULE_PREF || true")
        }
        runRoot("ip route flush table $ROUTE_TABLE || true")
    }

    private fun iptablesEnsure(checkArgs: String, addArgs: String): String {
        return "(iptables -w 2 $checkArgs || iptables $checkArgs) || " +
            "(iptables -w 2 $addArgs || iptables $addArgs)"
    }

    private fun iptablesDelete(deleteArgs: String): String {
        return "(iptables -w 2 $deleteArgs || iptables $deleteArgs || true)"
    }

    private fun findVpnInterface(context: Context): String? {
        val connectivity =
            context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        for (network in connectivity.allNetworks) {
            val capabilities = connectivity.getNetworkCapabilities(network) ?: continue
            if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) {
                val iface = connectivity.getLinkProperties(network)?.interfaceName
                if (!iface.isNullOrBlank()) {
                    return iface
                }
            }
        }
        return NetworkInterface.getNetworkInterfaces().asSequence()
            .firstOrNull { network ->
                network.isUp &&
                    !network.isLoopback &&
                    (network.name.startsWith("tun") ||
                        network.name.startsWith("ppp") ||
                        network.name.startsWith("wg"))
            }?.name
    }

    private fun findClientSubnets(
        vpnInterface: String,
        onlyLocalIps: Set<String> = emptySet(),
    ): List<String> {
        return NetworkInterface.getNetworkInterfaces().asSequence()
            .filter { network ->
                network.isUp &&
                    !network.isLoopback &&
                    network.name != vpnInterface &&
                    isClientInterface(network.name)
            }
            .flatMap { network ->
                network.interfaceAddresses.asSequence().mapNotNull { address ->
                    val inet = address.address as? Inet4Address ?: return@mapNotNull null
                    val host = inet.hostAddress ?: return@mapNotNull null
                    if (onlyLocalIps.isNotEmpty() && !onlyLocalIps.contains(host)) {
                        return@mapNotNull null
                    }
                    if (!isPrivateIpv4(host)) {
                        return@mapNotNull null
                    }
                    val prefix = address.networkPrefixLength.toInt()
                    if (prefix !in 8..30) {
                        return@mapNotNull null
                    }
                    ipv4Cidr(host, prefix)
                }
            }
            .distinct()
            .toList()
    }

    private fun isClientInterface(name: String): Boolean {
        val lower = name.lowercase(Locale.US)
        if (lower.startsWith("rmnet") ||
            lower.startsWith("ccmni") ||
            lower.startsWith("tun") ||
            lower.startsWith("ppp") ||
            lower.startsWith("lo") ||
            lower.startsWith("dummy") ||
            lower.startsWith("ifb") ||
            lower.contains("clat")
        ) {
            return false
        }
        return lower.contains("wlan") ||
            lower.contains("swlan") ||
            lower.contains("ap") ||
            lower.contains("bridge") ||
            lower.contains("br-") ||
            lower.contains("eth") ||
            lower.contains("rndis") ||
            lower.contains("usb")
    }

    private fun isPrivateIpv4(value: String): Boolean {
        val parts = value.split('.').mapNotNull { it.toIntOrNull() }
        if (parts.size != 4) {
            return false
        }
        return parts[0] == 10 ||
            (parts[0] == 172 && parts[1] in 16..31) ||
            (parts[0] == 192 && parts[1] == 168)
    }

    private fun ipv4Cidr(host: String, prefix: Int): String? {
        val parts = host.split('.').mapNotNull { it.toIntOrNull() }
        if (parts.size != 4) {
            return null
        }
        var value = 0
        for (part in parts) {
            value = (value shl 8) or (part and 0xff)
        }
        val mask = if (prefix == 0) 0 else (-1 shl (32 - prefix))
        val network = value and mask
        val address = listOf(
            (network ushr 24) and 0xff,
            (network ushr 16) and 0xff,
            (network ushr 8) and 0xff,
            network and 0xff,
        ).joinToString(".")
        return "$address/$prefix"
    }

    private fun parseHotspotCredentials(text: String): HotspotCredentials? {
        val ssidPatterns = listOf(
            Regex("""(?i)<string name="(?:SSID|ApSsid)">([^<]+)</string>"""),
            Regex("""(?i)\bSSID\s*[:=]\s*"?([^"\n,]+)"?"""),
            Regex("""(?i)\bssid\s*[:=]\s*"?([^"\n,]+)"?"""),
        )
        val passwordPatterns = listOf(
            Regex("""(?i)<string name="(?:PreSharedKey|Passphrase|ApPassphrase)">([^<]+)</string>"""),
            Regex("""(?i)\b(?:PreSharedKey|Passphrase|preSharedKey|password)\s*[:=]\s*"?([^"\n,]+)"?"""),
        )
        val ssid = ssidPatterns.firstNotNullOfOrNull { pattern ->
            pattern.find(text)?.groupValues?.getOrNull(1)?.trim()?.trim('"')
        } ?: return null
        val password = passwordPatterns.firstNotNullOfOrNull { pattern ->
            pattern.find(text)?.groupValues?.getOrNull(1)?.trim()?.trim('"')
        } ?: return null
        if (ssid.isBlank() || password.isBlank() || password.equals("<removed>", ignoreCase = true)) {
            return null
        }
        return HotspotCredentials(ssid = ssid, password = password)
    }

    private fun runRoot(command: String, timeoutSeconds: Long = 8): CommandResult {
        return runCatching {
            val process = ProcessBuilder("su", "-c", command)
                .redirectErrorStream(true)
                .start()
            val finished = process.waitFor(timeoutSeconds, TimeUnit.SECONDS)
            if (!finished) {
                process.destroyForcibly()
                return CommandResult(false, "", "Root command timed out.")
            }
            val output = process.inputStream.bufferedReader().readText().trim()
            CommandResult(process.exitValue() == 0, output, "")
        }.getOrElse { error ->
            CommandResult(false, "", error.message ?: error.javaClass.simpleName)
        }
    }
}

data class HotspotCredentials(
    val ssid: String,
    val password: String,
)

private data class CommandResult(
    val success: Boolean,
    val output: String,
    val error: String,
)
