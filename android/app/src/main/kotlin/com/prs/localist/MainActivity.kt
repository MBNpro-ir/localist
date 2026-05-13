package com.prs.localist

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.net.InetSocketAddress
import java.net.ServerSocket

class MainActivity : FlutterActivity() {
    private var pendingVpnResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "ensureVpnPermission" -> ensureVpnPermission(result)
                "startProxyService" -> startProxyService(call, result)
                "startReceivingVpn" -> startReceivingVpn(call, result)
                "startLocalProxy" -> startLocalProxy(call, result)
                "checkRootAccess" -> result.success(RootRoutingController.checkRootAccess(this))
                "setRootRoutingEnabled" -> setRootRoutingEnabled(call, result)
                "startRootSharing" -> startRootSharing(call, result)
                "stopRootSharing" -> result.success(RootRoutingController.stop(this))
                "stopProxyService" -> {
                    sendServiceAction(LocalistVpnService.ACTION_STOP)
                    RootRoutingController.stop(this)
                    result.success(true)
                }
                "getStats" -> result.success(LocalistVpnService.stats(this))
                "getServiceState" -> result.success(LocalistVpnService.snapshot(this))
                "shareApk" -> shareApk(result)
                "shareText" -> shareText(call, result)
                "openUri" -> openUri(call, result)
                "openHotspotSettings" -> openHotspotSettings(result)
                else -> result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_REQUEST_CODE) {
            pendingVpnResult?.success(resultCode == Activity.RESULT_OK)
            pendingVpnResult = null
        }
    }

    private fun ensureVpnPermission(result: MethodChannel.Result) {
        val intent = VpnService.prepare(this)
        if (intent == null) {
            result.success(true)
            return
        }
        if (pendingVpnResult != null) {
            result.error("vpn_permission_pending", "VPN permission is already pending.", null)
            return
        }
        pendingVpnResult = result
        startActivityForResult(intent, VPN_REQUEST_CODE)
    }

    private fun startProxyService(call: MethodCall, result: MethodChannel.Result) {
        RootRoutingController.stop(this)
        val protocols = call.argument<List<String>>("protocols")
            ?.filter { it in LocalistVpnService.SUPPORTED_PROTOCOLS }
            ?.takeIf { it.isNotEmpty() }
            ?: call.argument<String>("protocol")?.let { listOf(it) }
            ?: listOf("socks5")
        val portsArg = call.argument<Map<String, Any>>("ports") ?: emptyMap()
        val protocolPorts = protocols.associateWith { protocol ->
            (portsArg[protocol] as? Int) ?: LocalistVpnService.defaultPort(protocol)
        }
        val shareAllRoutes = call.argument<Boolean>("shareAllRoutes") ?: true
        val selectedLocalIps = call.argument<List<String>>("selectedLocalIps")
            ?.filter { it.isNotBlank() }
            ?: emptyList()
        val bindAddresses = if (shareAllRoutes) {
            emptyList()
        } else {
            selectedLocalIps
        }
        val validationError = LocalistProxyServer.validateBindings(protocolPorts, bindAddresses)
        if (validationError != null) {
            result.error("port_unavailable", validationError, null)
            return
        }
        val intent = Intent(this, LocalistVpnService::class.java).apply {
            action = LocalistVpnService.ACTION_START
            putStringArrayListExtra(
                LocalistVpnService.EXTRA_PROTOCOLS,
                ArrayList(protocols),
            )
            putExtra(
                LocalistVpnService.EXTRA_HTTP_PORT,
                protocolPorts["http"] ?: LocalistVpnService.defaultPort("http"),
            )
            putExtra(
                LocalistVpnService.EXTRA_SOCKS5_PORT,
                protocolPorts["socks5"] ?: LocalistVpnService.defaultPort("socks5"),
            )
            putExtra(LocalistVpnService.EXTRA_SHARE_ALL_ROUTES, shareAllRoutes)
            putStringArrayListExtra(
                LocalistVpnService.EXTRA_SELECTED_LOCAL_IPS,
                ArrayList(selectedLocalIps),
            )
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
        result.success(true)
    }

    private fun startRootSharing(call: MethodCall, result: MethodChannel.Result) {
        sendServiceAction(LocalistVpnService.ACTION_STOP)
        val shareAllRoutes = call.argument<Boolean>("shareAllRoutes") ?: true
        val selectedLocalIps = call.argument<List<String>>("selectedLocalIps")
            ?.filter { it.isNotBlank() }
            ?: emptyList()
        result.success(
            RootRoutingController.start(
                context = this,
                shareAllRoutes = shareAllRoutes,
                selectedLocalIps = selectedLocalIps,
            ),
        )
    }

    private fun startReceivingVpn(call: MethodCall, result: MethodChannel.Result) {
        RootRoutingController.stop(this)
        val protocol = call.argument<String>("protocol") ?: "socks5"
        val host = call.argument<String>("host") ?: ""
        val port = call.argument<Int>("port") ?: LocalistVpnService.defaultPort(protocol)
        if (host.isBlank()) {
            result.error("missing_proxy_host", "Proxy host is required.", null)
            return
        }
        val prepareIntent = VpnService.prepare(this)
        if (prepareIntent != null) {
            result.error(
                "vpn_permission_required",
                "Call ensureVpnPermission before starting the receiving VPN.",
                null,
            )
            return
        }
        val intent = Intent(this, LocalistVpnService::class.java).apply {
            action = LocalistVpnService.ACTION_START_RECEIVING
            putExtra(LocalistVpnService.EXTRA_REMOTE_PROTOCOL, protocol)
            putExtra(LocalistVpnService.EXTRA_REMOTE_HOST, host)
            putExtra(LocalistVpnService.EXTRA_REMOTE_PORT, port)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
        result.success(true)
    }

    private fun startLocalProxy(call: MethodCall, result: MethodChannel.Result) {
        RootRoutingController.stop(this)
        val protocol = call.argument<String>("protocol") ?: "socks5"
        val host = call.argument<String>("host") ?: ""
        val port = call.argument<Int>("port") ?: LocalistVpnService.defaultPort(protocol)
        val localPort = call.argument<Int>("localPort") ?: LocalProxyForwarder.DEFAULT_LOCAL_PORT
        if (host.isBlank()) {
            result.error("missing_proxy_host", "Proxy host is required.", null)
            return
        }
        if (!isLocalPortAvailable(localPort)) {
            result.error("local_proxy_port_unavailable", "Local port $localPort is busy.", null)
            return
        }
        val intent = Intent(this, LocalistVpnService::class.java).apply {
            action = LocalistVpnService.ACTION_START_LOCAL_PROXY
            putExtra(LocalistVpnService.EXTRA_REMOTE_PROTOCOL, protocol)
            putExtra(LocalistVpnService.EXTRA_REMOTE_HOST, host)
            putExtra(LocalistVpnService.EXTRA_REMOTE_PORT, port)
            putExtra(LocalistVpnService.EXTRA_LOCAL_PROXY_PORT, localPort)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
        result.success(true)
    }

    private fun setRootRoutingEnabled(call: MethodCall, result: MethodChannel.Result) {
        val enabled = call.argument<Boolean>("enabled") ?: false
        if (enabled) {
            sendServiceAction(LocalistVpnService.ACTION_STOP)
        }
        result.success(RootRoutingController.setEnabled(this, enabled))
    }

    private fun sendServiceAction(actionName: String) {
        val intent = Intent(this, LocalistVpnService::class.java).apply {
            action = actionName
        }
        if (actionName == LocalistVpnService.ACTION_STOP) {
            startService(intent)
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun shareApk(result: MethodChannel.Result) {
        runCatching {
            val sourceApk = File(applicationInfo.sourceDir)
            val shareDir = File(cacheDir, "shared").apply { mkdirs() }
            val sharedApk = File(shareDir, "localist.apk")
            sourceApk.inputStream().use { input ->
                sharedApk.outputStream().use { output ->
                    input.copyTo(output)
                }
            }
            val uri = FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                sharedApk,
            )
            val shareIntent = Intent(Intent.ACTION_SEND).apply {
                type = "application/vnd.android.package-archive"
                putExtra(Intent.EXTRA_STREAM, uri)
                putExtra(Intent.EXTRA_SUBJECT, "localist APK")
                putExtra(Intent.EXTRA_TEXT, "localist APK")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(Intent.createChooser(shareIntent, "Share localist APK"))
        }.onSuccess {
            result.success(true)
        }.onFailure { error ->
            result.error("share_apk_failed", error.message, null)
        }
    }

    private fun shareText(call: MethodCall, result: MethodChannel.Result) {
        val text = call.argument<String>("text") ?: ""
        val title = call.argument<String>("title") ?: "Share localist config"
        if (text.isBlank()) {
            result.success(false)
            return
        }
        val shareIntent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, text)
            putExtra(Intent.EXTRA_SUBJECT, title)
        }
        startActivity(Intent.createChooser(shareIntent, title))
        result.success(true)
    }

    private fun openUri(call: MethodCall, result: MethodChannel.Result) {
        val uri = call.argument<String>("uri") ?: ""
        runCatching {
            val intent = Intent(Intent.ACTION_VIEW, android.net.Uri.parse(uri)).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
        }.onSuccess {
            result.success(true)
        }.onFailure { error ->
            result.error("open_uri_failed", error.message, null)
        }
    }

    private fun openHotspotSettings(result: MethodChannel.Result) {
        val actions = listOf(
            "android.settings.TETHER_SETTINGS",
            Settings.ACTION_WIRELESS_SETTINGS,
            Settings.ACTION_WIFI_SETTINGS,
        )
        for (action in actions) {
            val opened = runCatching {
                startActivity(Intent(action).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }.isSuccess
            if (opened) {
                result.success(true)
                return
            }
        }
        result.success(false)
    }

    private fun isLocalPortAvailable(port: Int): Boolean {
        return runCatching {
            ServerSocket().use { socket ->
                socket.reuseAddress = true
                socket.bind(InetSocketAddress(LocalProxyForwarder.LOCAL_HOST, port))
            }
        }.isSuccess
    }

    companion object {
        private const val CHANNEL = "com.prs.localist.vpn"
        private const val VPN_REQUEST_CODE = 41088
    }
}
