package com.prs.localist

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.ClipData
import android.content.IntentFilter
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
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
    private var pendingSaveFileResult: MethodChannel.Result? = null
    private var pendingSaveFileText: String = ""
    private var methodChannel: MethodChannel? = null
    private var nativeLogReceiverRegistered = false
    private val nativeLogReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != ACTION_NATIVE_LOG) {
                return
            }
            val message = intent.getStringExtra(EXTRA_NATIVE_LOG_MESSAGE).orEmpty()
            if (message.isBlank()) {
                return
            }
            methodChannel?.invokeMethod(
                "nativeLog",
                mapOf(
                    "source" to intent.getStringExtra(EXTRA_NATIVE_LOG_SOURCE).orEmpty()
                        .ifBlank { "android" },
                    "message" to message,
                ),
            )
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        LocalistCrashReporter.install(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "ensureVpnPermission" -> ensureVpnPermission(result)
                "getAndroidSdkInt" -> result.success(Build.VERSION.SDK_INT)
                "getAndroidSupportedAbis" -> result.success(Build.SUPPORTED_ABIS.toList())
                "getUpdateDirectory" -> result.success(updateDirectory().absolutePath)
                "canInstallPackages" -> result.success(canInstallPackages())
                "openInstallPermissionSettings" -> openInstallPermissionSettings(result)
                "installApk" -> installApk(call, result)
                "isIgnoringBatteryOptimizations" -> result.success(isIgnoringBatteryOptimizations())
                "requestIgnoreBatteryOptimizations" -> requestIgnoreBatteryOptimizations(result)
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
                "saveTextFile" -> saveTextFile(call, result)
                "getDeviceDetails" -> result.success(deviceDetails())
                else -> result.notImplemented()
            }
        }
        registerNativeLogReceiver()
    }

    override fun onDestroy() {
        unregisterNativeLogReceiver()
        methodChannel = null
        super.onDestroy()
    }

    private fun registerNativeLogReceiver() {
        if (nativeLogReceiverRegistered) {
            return
        }
        val filter = IntentFilter(ACTION_NATIVE_LOG)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(nativeLogReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(nativeLogReceiver, filter)
        }
        nativeLogReceiverRegistered = true
    }

    private fun unregisterNativeLogReceiver() {
        if (!nativeLogReceiverRegistered) {
            return
        }
        runCatching { unregisterReceiver(nativeLogReceiver) }
        nativeLogReceiverRegistered = false
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_REQUEST_CODE) {
            pendingVpnResult?.success(resultCode == Activity.RESULT_OK)
            pendingVpnResult = null
            return
        }
        if (requestCode == SAVE_FILE_REQUEST_CODE) {
            val saveResult = pendingSaveFileResult
            val text = pendingSaveFileText
            pendingSaveFileResult = null
            pendingSaveFileText = ""
            val uri = data?.data
            if (saveResult == null) {
                return
            }
            if (resultCode != Activity.RESULT_OK || uri == null) {
                saveResult.success(
                    mapOf(
                        "saved" to false,
                        "canceled" to true,
                    ),
                )
                return
            }
            runCatching {
                contentResolver.openOutputStream(uri)?.use { output ->
                    output.writer(Charsets.UTF_8).buffered().use { writer ->
                        writer.write(text)
                    }
                } ?: error("Could not open selected output stream.")
            }.onSuccess {
                saveResult.success(
                    mapOf(
                        "saved" to true,
                        "canceled" to false,
                        "path" to uri.toString(),
                    ),
                )
            }.onFailure { error ->
                saveResult.error("save_text_file_failed", error.message, null)
            }
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

    private fun isIgnoringBatteryOptimizations(): Boolean {
        val powerManager = getSystemService(PowerManager::class.java)
        return powerManager?.isIgnoringBatteryOptimizations(packageName) == true
    }

    private fun requestIgnoreBatteryOptimizations(result: MethodChannel.Result) {
        if (isIgnoringBatteryOptimizations()) {
            result.success(true)
            return
        }
        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
            data = Uri.parse("package:$packageName")
        }
        runCatching {
            startActivity(intent)
        }.onSuccess {
            result.success(true)
        }.onFailure {
            runCatching {
                startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
            }.onSuccess {
                result.success(false)
            }.onFailure { error ->
                result.error("battery_settings_unavailable", error.message, null)
            }
        }
    }

    private fun canInstallPackages(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            packageManager.canRequestPackageInstalls()
    }

    private fun openInstallPermissionSettings(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.success(true)
            return
        }
        val intent = Intent(
            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
            Uri.parse("package:$packageName"),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        runCatching {
            startActivity(intent)
        }.onSuccess {
            result.success(true)
        }.onFailure { error ->
            result.error("install_settings_unavailable", error.message, null)
        }
    }

    private fun installApk(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path") ?: ""
        if (path.isBlank()) {
            result.error("missing_apk_path", "APK path is required.", null)
            return
        }
        if (!canInstallPackages()) {
            openInstallPermissionSettings(result)
            return
        }
        val apk = File(path)
        if (!apk.exists() || !apk.isFile) {
            result.error("apk_not_found", "Downloaded APK was not found.", null)
            return
        }
        runCatching {
            val uri = FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                apk,
            )
            val installIntent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                clipData = ClipData.newRawUri("Localist update", uri)
                putExtra(Intent.EXTRA_NOT_UNKNOWN_SOURCE, true)
                putExtra(Intent.EXTRA_INSTALLER_PACKAGE_NAME, packageName)
                putExtra(Intent.EXTRA_RETURN_RESULT, false)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(installIntent)
        }.onSuccess {
            result.success(true)
        }.onFailure { error ->
            result.error("install_apk_failed", error.message, null)
        }
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
        val discoveryDeviceId = call.argument<String>("discoveryDeviceId").orEmpty()
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
            putExtra(LocalistVpnService.EXTRA_DISCOVERY_DEVICE_ID, discoveryDeviceId)
        }
        startLocalistService(intent, result, "proxy_service_start_failed", "proxy service")
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
        if (!isLocalPortAvailable(LocalProxyForwarder.DEFAULT_LOCAL_PORT)) {
            result.error(
                "local_proxy_port_unavailable",
                "Local port ${LocalProxyForwarder.DEFAULT_LOCAL_PORT} is busy.",
                null,
            )
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
        startLocalistService(intent, result, "receiving_service_start_failed", "receiving VPN")
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
        startLocalistService(intent, result, "local_proxy_start_failed", "local proxy")
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

    private fun startLocalistService(
        intent: Intent,
        result: MethodChannel.Result,
        errorCode: String,
        serviceName: String,
    ) {
        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        }.onSuccess {
            result.success(true)
        }.onFailure { error ->
            result.error(errorCode, "Could not start $serviceName: ${error.message}", null)
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
        runCatching {
            val shareIntent = Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_TEXT, text)
                putExtra(Intent.EXTRA_SUBJECT, title)
            }
            startActivity(Intent.createChooser(shareIntent, title))
        }.onSuccess {
            result.success(true)
        }.onFailure { error ->
            result.error("share_text_failed", error.message, null)
        }
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

    private fun saveTextFile(call: MethodCall, result: MethodChannel.Result) {
        if (pendingSaveFileResult != null) {
            result.error("save_file_pending", "A save dialog is already open.", null)
            return
        }
        val text = call.argument<String>("text") ?: ""
        val suggestedName = call.argument<String>("suggestedName")
            ?.ifBlank { "localist-debug-log.txt" }
            ?: "localist-debug-log.txt"
        val mimeType = call.argument<String>("mimeType")
            ?.ifBlank { "text/plain" }
            ?: "text/plain"
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = mimeType
            putExtra(Intent.EXTRA_TITLE, suggestedName)
            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        }
        pendingSaveFileResult = result
        pendingSaveFileText = text
        runCatching {
            startActivityForResult(intent, SAVE_FILE_REQUEST_CODE)
        }.onFailure { error ->
            pendingSaveFileResult = null
            pendingSaveFileText = ""
            result.error("save_text_file_unavailable", error.message, null)
        }
    }

    private fun deviceDetails(): Map<String, Any?> {
        val displayMetrics = resources.displayMetrics
        return mapOf(
            "manufacturer" to Build.MANUFACTURER,
            "brand" to Build.BRAND,
            "model" to Build.MODEL,
            "device" to Build.DEVICE,
            "product" to Build.PRODUCT,
            "hardware" to Build.HARDWARE,
            "board" to Build.BOARD,
            "bootloader" to Build.BOOTLOADER,
            "fingerprint" to Build.FINGERPRINT,
            "androidRelease" to Build.VERSION.RELEASE,
            "androidSdkInt" to Build.VERSION.SDK_INT,
            "androidSecurityPatch" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                Build.VERSION.SECURITY_PATCH
            } else {
                ""
            },
            "supportedAbis" to Build.SUPPORTED_ABIS.toList(),
            "packageName" to packageName,
            "installerPackageName" to packageManager.getInstallerPackageName(packageName),
            "isIgnoringBatteryOptimizations" to isIgnoringBatteryOptimizations(),
            "screenWidthPx" to displayMetrics.widthPixels,
            "screenHeightPx" to displayMetrics.heightPixels,
            "screenDensity" to displayMetrics.density,
            "screenDensityDpi" to displayMetrics.densityDpi,
        )
    }

    private fun updateDirectory(): File {
        return File(cacheDir, "updates").apply { mkdirs() }
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
        private const val ACTION_NATIVE_LOG = "com.prs.localist.NATIVE_LOG"
        private const val EXTRA_NATIVE_LOG_MESSAGE = "message"
        private const val EXTRA_NATIVE_LOG_SOURCE = "source"
        private const val VPN_REQUEST_CODE = 41088
        private const val SAVE_FILE_REQUEST_CODE = 41089

        fun broadcastNativeLog(context: Context, source: String, message: String) {
            if (message.isBlank()) {
                return
            }
            context.sendBroadcast(
                Intent(ACTION_NATIVE_LOG)
                    .setPackage(context.packageName)
                    .putExtra(EXTRA_NATIVE_LOG_SOURCE, source)
                    .putExtra(EXTRA_NATIVE_LOG_MESSAGE, message),
            )
        }
    }
}
