package com.prs.localist

import android.Manifest
import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.ClipData
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.Uri
import android.net.VpnService
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.provider.Settings
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.net.InetSocketAddress
import java.net.Inet4Address
import java.net.NetworkInterface
import java.net.ServerSocket
import java.util.Collections
import java.util.UUID

class MainActivity : FlutterActivity() {
    private var pendingVpnResult: MethodChannel.Result? = null
    private var pendingSaveFileResult: MethodChannel.Result? = null
    private var pendingSaveFileText: String = ""
    private var methodChannel: MethodChannel? = null
    private var quickSendMulticastLock: WifiManager.MulticastLock? = null
    private var localOnlyHotspotReservation: WifiManager.LocalOnlyHotspotReservation? = null
    private var localOnlyHotspotInfo: Map<String, Any?>? = null
    private var pendingLocalOnlyHotspotResult: MethodChannel.Result? = null
    private val pendingQuickSendFiles = mutableListOf<Map<String, String>>()
    private val pendingQuickSendFilesLock = Any()
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
        receiveQuickSendFiles(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        receiveQuickSendFiles(intent)
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
                "shareFileExternally" -> shareFileExternally(call, result)
                "openUri" -> openUri(call, result)
                "openFile" -> openFile(call, result)
                "openContainingFolder" -> openContainingFolder(call, result)
                "openHotspotSettings" -> openHotspotSettings(result)
                "startLocalOnlyHotspot" -> startLocalOnlyHotspot(result)
                "stopLocalOnlyHotspot" -> {
                    stopLocalOnlyHotspot(notifyFlutter = false)
                    result.success(true)
                }
                "saveTextFile" -> saveTextFile(call, result)
                "takeQuickSendSharedFiles" -> result.success(takeQuickSendSharedFiles())
                "hasQuickSendSharedFiles" -> result.success(hasQuickSendSharedFiles())
                "getDeviceDetails" -> result.success(deviceDetails())
                "setQuickSendMulticastLock" -> {
                    result.success(setQuickSendMulticastLock(call.argument<Boolean>("enabled") == true))
                }
                "getPublicStorageRoot" -> {
                    @Suppress("DEPRECATION")
                    result.success(Environment.getExternalStorageDirectory().absolutePath)
                }
                else -> result.notImplemented()
            }
        }
        registerNativeLogReceiver()
    }

    override fun onDestroy() {
        setQuickSendMulticastLock(false)
        stopLocalOnlyHotspot(notifyFlutter = false)
        unregisterNativeLogReceiver()
        methodChannel = null
        super.onDestroy()
    }

    private fun setQuickSendMulticastLock(enabled: Boolean): Boolean {
        if (enabled) {
            val lock = quickSendMulticastLock ?: run {
                val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                wifiManager.createMulticastLock("localist-quick-send").also {
                    it.setReferenceCounted(false)
                    quickSendMulticastLock = it
                }
            }
            if (!lock.isHeld) {
                lock.acquire()
            }
            return lock.isHeld
        }
        quickSendMulticastLock?.let { lock ->
            if (lock.isHeld) {
                lock.release()
            }
        }
        quickSendMulticastLock = null
        return false
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

    private fun shareFileExternally(call: MethodCall, result: MethodChannel.Result) {
        val file = File(call.argument<String>("path") ?: "")
        if (!file.isFile) {
            result.success(false)
            return
        }
        runCatching {
            val uri = fileProviderUri(file)
            val shareIntent = Intent(Intent.ACTION_SEND).apply {
                type = mimeTypeFor(file)
                putExtra(Intent.EXTRA_STREAM, uri)
                putExtra(Intent.EXTRA_SUBJECT, file.name)
                clipData = ClipData.newRawUri("Localist file", uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(Intent.createChooser(shareIntent, "Share file"))
        }.onSuccess {
            result.success(true)
        }.onFailure { error ->
            result.error("share_file_failed", error.message, null)
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

    private fun openFile(call: MethodCall, result: MethodChannel.Result) {
        val file = File(call.argument<String>("path") ?: "")
        if (!file.isFile) {
            result.success(false)
            return
        }
        runCatching {
            val uri = fileProviderUri(file)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, mimeTypeFor(file))
                clipData = ClipData.newRawUri("Localist file", uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(Intent.createChooser(intent, "Open file"))
        }.onSuccess {
            result.success(true)
        }.onFailure { error ->
            result.error("open_file_failed", error.message, null)
        }
    }

    private fun openContainingFolder(call: MethodCall, result: MethodChannel.Result) {
        val input = File(call.argument<String>("path") ?: "")
        val folder = if (input.isDirectory) input else input.parentFile
        if (folder == null || !folder.isDirectory) {
            result.success(false)
            return
        }
        runCatching {
            val initialUri = externalStorageDocumentUri(folder)
            val viewed = initialUri != null && runCatching {
                val viewIntent = Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(initialUri, DocumentsContract.Document.MIME_TYPE_DIR)
                    addFlags(
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or
                            Intent.FLAG_ACTIVITY_NEW_TASK,
                    )
                }
                startActivity(viewIntent)
            }.isSuccess
            if (!viewed) {
                val treeIntent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                    addFlags(
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or
                            Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                            Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                            Intent.FLAG_GRANT_PREFIX_URI_PERMISSION,
                    )
                    if (initialUri != null) {
                        putExtra(DocumentsContract.EXTRA_INITIAL_URI, initialUri)
                    }
                }
                startActivity(treeIntent)
            }
        }.onSuccess {
            result.success(true)
        }.onFailure { error ->
            result.error("open_folder_failed", error.message, null)
        }
    }

    private fun externalStorageDocumentUri(folder: File): Uri? {
        return runCatching {
            val storageRoot = Environment.getExternalStorageDirectory().canonicalFile
            val canonicalFolder = folder.canonicalFile
            val rootPath = storageRoot.path
            val folderPath = canonicalFolder.path
            if (folderPath != rootPath &&
                !folderPath.startsWith("$rootPath${File.separator}")
            ) {
                return null
            }
            val relative = canonicalFolder.relativeTo(storageRoot)
                .invariantSeparatorsPath
                .takeUnless { it == "." }
                .orEmpty()
            val documentId = if (relative.isEmpty()) "primary:" else "primary:$relative"
            DocumentsContract.buildDocumentUri(
                "com.android.externalstorage.documents",
                documentId,
            )
        }.getOrNull()
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

    private fun startLocalOnlyHotspot(result: MethodChannel.Result) {
        localOnlyHotspotReservation?.let {
            result.success(refreshLocalOnlyHotspotAddresses(localOnlyHotspotInfo.orEmpty()))
            return
        }
        if (pendingLocalOnlyHotspotResult != null) {
            result.success(
                localOnlyHotspotFailure(
                    code = "request_pending",
                    message = "A private hotspot request is already pending.",
                ),
            )
            return
        }
        val requiredPermission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Manifest.permission.NEARBY_WIFI_DEVICES
        } else {
            Manifest.permission.ACCESS_FINE_LOCATION
        }
        if (checkSelfPermission(requiredPermission) != PackageManager.PERMISSION_GRANTED) {
            result.success(
                localOnlyHotspotFailure(
                    code = "permission_required",
                    message = "Nearby Wi-Fi permission is required.",
                    permissionRequired = true,
                ),
            )
            return
        }

        val addressesBefore = localIpv4Addresses()
            .map { "${it.interfaceName}|${it.address}" }
            .toSet()
        val wifiManager =
            applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val handler = Handler(Looper.getMainLooper())
        pendingLocalOnlyHotspotResult = result
        runCatching {
            wifiManager.startLocalOnlyHotspot(
                object : WifiManager.LocalOnlyHotspotCallback() {
                    override fun onStarted(reservation: WifiManager.LocalOnlyHotspotReservation) {
                        localOnlyHotspotReservation = reservation
                        handler.postDelayed({
                            val pending = pendingLocalOnlyHotspotResult
                            if (pending == null) {
                                return@postDelayed
                            }
                            val info = buildLocalOnlyHotspotInfo(
                                reservation = reservation,
                                addressesBefore = addressesBefore,
                            )
                            localOnlyHotspotInfo = info
                            pendingLocalOnlyHotspotResult = null
                            pending.success(info)
                        }, HOTSPOT_ADDRESS_SETTLE_DELAY_MS)
                    }

                    override fun onStopped() {
                        localOnlyHotspotReservation = null
                        localOnlyHotspotInfo = null
                        pendingLocalOnlyHotspotResult?.let { pending ->
                            pendingLocalOnlyHotspotResult = null
                            pending.success(
                                localOnlyHotspotFailure(
                                    code = "stopped",
                                    message = "The private hotspot stopped before it was ready.",
                                ),
                            )
                        }
                        methodChannel?.invokeMethod("localOnlyHotspotStopped", null)
                    }

                    override fun onFailed(reason: Int) {
                        localOnlyHotspotReservation = null
                        localOnlyHotspotInfo = null
                        pendingLocalOnlyHotspotResult?.let { pending ->
                            pendingLocalOnlyHotspotResult = null
                            pending.success(
                                localOnlyHotspotFailure(
                                    code = localOnlyHotspotErrorCode(reason),
                                    message = localOnlyHotspotErrorMessage(reason),
                                ),
                            )
                        }
                    }
                },
                handler,
            )
        }.onFailure { error ->
            pendingLocalOnlyHotspotResult = null
            result.success(
                localOnlyHotspotFailure(
                    code = if (error is SecurityException) {
                        "permission_required"
                    } else {
                        "start_failed"
                    },
                    message = error.message ?: "Could not start the private hotspot.",
                    permissionRequired = error is SecurityException,
                ),
            )
        }
    }

    private fun stopLocalOnlyHotspot(notifyFlutter: Boolean) {
        val reservation = localOnlyHotspotReservation
        localOnlyHotspotReservation = null
        localOnlyHotspotInfo = null
        runCatching { reservation?.close() }
        if (notifyFlutter && reservation != null) {
            methodChannel?.invokeMethod("localOnlyHotspotStopped", null)
        }
    }

    private fun buildLocalOnlyHotspotInfo(
        reservation: WifiManager.LocalOnlyHotspotReservation,
        addressesBefore: Set<String>,
    ): Map<String, Any?> {
        val credentials = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val configuration = reservation.softApConfiguration
            configuration.ssid.orEmpty() to configuration.passphrase.orEmpty()
        } else {
            @Suppress("DEPRECATION")
            val configuration = reservation.wifiConfiguration
            unquoteWifiValue(configuration?.SSID.orEmpty()) to
                unquoteWifiValue(configuration?.preSharedKey.orEmpty())
        }
        val addresses = localIpv4Addresses().sortedWith(
            compareBy<LocalIpv4Address> {
                if ("${it.interfaceName}|${it.address}" in addressesBefore) 1 else 0
            }.thenBy { hotspotInterfacePriority(it.interfaceName) }
                .thenBy { it.address },
        )
        return mapOf(
            "supported" to true,
            "active" to true,
            "managed" to true,
            "ssid" to credentials.first,
            "password" to credentials.second,
            "addresses" to addresses.map { it.address }.distinct(),
            "primaryAddress" to addresses.firstOrNull()?.address.orEmpty(),
            "errorCode" to "",
            "message" to "",
            "permissionRequired" to false,
        )
    }

    private fun refreshLocalOnlyHotspotAddresses(
        current: Map<String, Any?>,
    ): Map<String, Any?> {
        val addresses = localIpv4Addresses()
            .sortedWith(
                compareBy<LocalIpv4Address> { hotspotInterfacePriority(it.interfaceName) }
                    .thenBy { it.address },
            )
            .map { it.address }
            .distinct()
        return current.toMutableMap().apply {
            this["addresses"] = addresses
            this["primaryAddress"] = addresses.firstOrNull().orEmpty()
        }
    }

    private fun localIpv4Addresses(): List<LocalIpv4Address> {
        return runCatching {
            Collections.list(NetworkInterface.getNetworkInterfaces())
                .filter {
                    it.isUp &&
                        !it.isLoopback &&
                        !isIgnoredHotspotInterface(it.name)
                }
                .flatMap { networkInterface ->
                    Collections.list(networkInterface.inetAddresses)
                        .filterIsInstance<Inet4Address>()
                        .filter {
                            !it.isLoopbackAddress &&
                                (it.isSiteLocalAddress || it.isLinkLocalAddress)
                        }
                        .map {
                            LocalIpv4Address(
                                interfaceName = networkInterface.name,
                                address = it.hostAddress.orEmpty(),
                            )
                        }
                }
                .filter { it.address.isNotBlank() }
        }.getOrDefault(emptyList())
    }

    private fun isIgnoredHotspotInterface(name: String): Boolean {
        val normalized = name.lowercase()
        return normalized == "lo" ||
            normalized.startsWith("lo") ||
            normalized.startsWith("tun") ||
            normalized.startsWith("tap") ||
            normalized.startsWith("rmnet") ||
            normalized.startsWith("ccmni") ||
            normalized.startsWith("pdp")
    }

    private fun hotspotInterfacePriority(name: String): Int {
        val normalized = name.lowercase()
        return when {
            normalized.contains("softap") || normalized.startsWith("ap") -> 0
            normalized.contains("wlan") || normalized.contains("wifi") -> 1
            normalized.contains("usb") || normalized.contains("rndis") -> 2
            normalized.startsWith("eth") -> 3
            else -> 4
        }
    }

    private fun unquoteWifiValue(value: String): String {
        return value.removePrefix("\"").removeSuffix("\"")
    }

    private fun localOnlyHotspotFailure(
        code: String,
        message: String,
        permissionRequired: Boolean = false,
    ): Map<String, Any?> {
        return mapOf(
            "supported" to true,
            "active" to false,
            "managed" to false,
            "ssid" to "",
            "password" to "",
            "addresses" to emptyList<String>(),
            "primaryAddress" to "",
            "errorCode" to code,
            "message" to message,
            "permissionRequired" to permissionRequired,
        )
    }

    private fun localOnlyHotspotErrorCode(reason: Int): String {
        return when (reason) {
            WifiManager.LocalOnlyHotspotCallback.ERROR_NO_CHANNEL -> "no_channel"
            WifiManager.LocalOnlyHotspotCallback.ERROR_INCOMPATIBLE_MODE ->
                "incompatible_mode"
            WifiManager.LocalOnlyHotspotCallback.ERROR_TETHERING_DISALLOWED ->
                "tethering_disallowed"
            else -> "generic"
        }
    }

    private fun localOnlyHotspotErrorMessage(reason: Int): String {
        return when (reason) {
            WifiManager.LocalOnlyHotspotCallback.ERROR_NO_CHANNEL ->
                "No Wi-Fi channel is available for a private hotspot."
            WifiManager.LocalOnlyHotspotCallback.ERROR_INCOMPATIBLE_MODE ->
                "The current Wi-Fi or tethering mode is incompatible with a private hotspot."
            WifiManager.LocalOnlyHotspotCallback.ERROR_TETHERING_DISALLOWED ->
                "Hotspot use is disabled by this device or administrator."
            else -> "Android could not start the private hotspot."
        }
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

    private fun receiveQuickSendFiles(incomingIntent: Intent?) {
        val intent = incomingIntent ?: return
        if (intent.action != Intent.ACTION_SEND && intent.action != Intent.ACTION_SEND_MULTIPLE) {
            return
        }
        val uris = linkedSetOf<Uri>()
        @Suppress("DEPRECATION")
        when (intent.action) {
            Intent.ACTION_SEND -> {
                intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)?.let(uris::add)
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)?.let(uris::addAll)
            }
        }
        val clipData = intent.clipData
        if (clipData != null) {
            for (index in 0 until clipData.itemCount) {
                clipData.getItemAt(index).uri?.let(uris::add)
            }
        }
        if (uris.isEmpty()) {
            return
        }
        Thread {
            val files = uris.mapNotNull(::cacheQuickSendSharedUri)
            if (files.isEmpty()) {
                return@Thread
            }
            synchronized(pendingQuickSendFilesLock) {
                pendingQuickSendFiles.addAll(files)
            }
            runOnUiThread {
                methodChannel?.invokeMethod("quickSendSharedFiles", files)
            }
        }.start()
    }

    private fun cacheQuickSendSharedUri(uri: Uri): Map<String, String>? {
        return runCatching {
            val displayName = displayNameFor(uri)
            val directory = File(cacheDir, "quick-send-shared").apply { mkdirs() }
            val destination = File(
                directory,
                "${System.currentTimeMillis()}-${UUID.randomUUID()}-$displayName",
            )
            contentResolver.openInputStream(uri)?.use { input ->
                destination.outputStream().use { output ->
                    input.copyTo(output, DEFAULT_BUFFER_SIZE)
                }
            } ?: return null
            mapOf(
                "path" to destination.absolutePath,
                "name" to displayName,
            )
        }.getOrNull()
    }

    private fun takeQuickSendSharedFiles(): List<Map<String, String>> {
        synchronized(pendingQuickSendFilesLock) {
            val files = pendingQuickSendFiles.toList()
            pendingQuickSendFiles.clear()
            return files
        }
    }

    private fun hasQuickSendSharedFiles(): Boolean {
        synchronized(pendingQuickSendFilesLock) {
            return pendingQuickSendFiles.isNotEmpty()
        }
    }

    private fun displayNameFor(uri: Uri): String {
        var displayName = ""
        runCatching {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val column = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        if (column >= 0) {
                            displayName = cursor.getString(column).orEmpty()
                        }
                    }
                }
        }
        if (displayName.isBlank()) {
            displayName = uri.lastPathSegment.orEmpty()
        }
        val safeName = File(displayName).name
            .replace(Regex("[\\\\/:*?\"<>|]"), "_")
            .trim()
            .take(180)
        return safeName.ifBlank { "shared-file" }
    }

    private fun fileProviderUri(file: File): Uri {
        return FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
    }

    private fun mimeTypeFor(file: File): String {
        val extension = file.extension.lowercase()
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension) ?: "*/*"
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

    private data class LocalIpv4Address(
        val interfaceName: String,
        val address: String,
    )

    companion object {
        private const val CHANNEL = "com.prs.localist.vpn"
        private const val ACTION_NATIVE_LOG = "com.prs.localist.NATIVE_LOG"
        private const val EXTRA_NATIVE_LOG_MESSAGE = "message"
        private const val EXTRA_NATIVE_LOG_SOURCE = "source"
        private const val VPN_REQUEST_CODE = 41088
        private const val SAVE_FILE_REQUEST_CODE = 41089
        private const val HOTSPOT_ADDRESS_SETTLE_DELAY_MS = 700L

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
