package com.prs.localist

import android.Manifest
import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.ClipData
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.Uri
import android.net.VpnService
import android.net.wifi.WifiManager
import android.media.MediaPlayer
import android.media.MediaMetadataRetriever
import android.graphics.Bitmap
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.util.Log
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
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors
import java.net.InetSocketAddress
import java.net.Inet4Address
import java.net.NetworkInterface
import java.net.ServerSocket
import java.util.Collections
import java.util.UUID

class MainActivity : com.carriez.flutter_hbb.MainActivity() {
    private val thumbnailExecutor = Executors.newFixedThreadPool(2)
    private var pendingVpnResult: MethodChannel.Result? = null
    private var systemAudioResult: MethodChannel.Result? = null
    private var pendingLocalNetworkPermissionResult: MethodChannel.Result? = null
    private var pendingSaveFileResult: MethodChannel.Result? = null
    private var pendingSaveFileText: String = ""
    private var methodChannel: MethodChannel? = null
    private var developerAgentChannel: MethodChannel? = null
    private var lanDiscoveryRequested = false
    private var quickSendMulticastRequested = false
    private var quickSendMulticastLock: WifiManager.MulticastLock? = null
    private var localOnlyHotspotReservation: WifiManager.LocalOnlyHotspotReservation? = null
    private var localOnlyHotspotInfo: Map<String, Any?>? = null
    private var pendingLocalOnlyHotspotResult: MethodChannel.Result? = null
    private val pendingQuickSendFiles = mutableListOf<Map<String, String>>()
    private val pendingQuickSendFilesLock = Any()
    private var pendingQuickSendNotificationTap = false
    private var nativeLogReceiverRegistered = false
    private val nativeLogReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == RemoteReceivedFiles.ACTION) {
                methodChannel?.invokeMethod("remoteFilesReceived", null)
                return
            }
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
        receiveQuickSendNotificationTap(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        broadcastNativeLog(applicationContext, "MainActivity", "new intent received actionPresent=${intent.action != null}")
        setIntent(intent)
        receiveQuickSendFiles(intent)
        receiveQuickSendNotificationTap(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        CaptureAudioEngine.register(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        CaptureForegroundService.channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "localist/capture").apply {
            setMethodCallHandler { call, result ->
                broadcastNativeLog(applicationContext, "CaptureBridge", "capture method=${call.method} received")
                when (call.method) {
                    "hasBluetoothMicrophone" -> result.success(getSystemService(android.media.AudioManager::class.java)
                        .getDevices(android.media.AudioManager.GET_DEVICES_INPUTS).any {
                            it.type == android.media.AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
                            (Build.VERSION.SDK_INT >= 31 && it.type == android.media.AudioDeviceInfo.TYPE_BLE_HEADSET) })
                    "systemAudioStart" -> {
                        if(Build.VERSION.SDK_INT<29)result.error("SYSTEM_AUDIO_UNSUPPORTED","System audio sharing requires Android 10 or later",null)
                        else if(systemAudioResult!=null)result.error("SYSTEM_AUDIO_BUSY","A consent request is already active",null)
                        else { systemAudioResult=result
                            try { startActivityForResult(getSystemService(android.media.projection.MediaProjectionManager::class.java).createScreenCaptureIntent(),41093) }
                            catch(error: Exception){systemAudioResult=null;result.error("SYSTEM_AUDIO_CONSENT",error.message,null)} }
                    }
                    "systemAudioStop" -> { stopService(Intent(this@MainActivity,SystemAudioCaptureService::class.java));result.success(true) }
                    "audioEffects" -> runCatching {
                        CaptureAudioEngine.configureSource(call.arguments as? Map<*, *> ?: emptyMap<Any,Any>())
                    }.onSuccess { result.success(true) }.onFailure { result.error("AUDIO_EFFECTS",it.message,null) }
                    "audioOutputDevices" -> result.success(CaptureAudioEngine.devices(this@MainActivity))
                    "audioOutputStatus" -> result.success(CaptureAudioEngine.status(call.argument<Int>("slot") ?: 0))
                    "audioOutputBind" -> runCatching {
                        CaptureAudioEngine.bind(this@MainActivity,call.arguments as? Map<*, *> ?: emptyMap<Any,Any>())
                    }.onSuccess { result.success(it) }.onFailure { result.error("AUDIO_OUTPUT",it.message,null) }
                    "audioOutputPcm" -> result.success(CaptureAudioEngine.pcm(call.argument<Int>("slot") ?: 0,call.argument<ByteArray>("data") ?: byteArrayOf()))
                    "orientation" -> runCatching {
                        CaptureOrientation.set(this@MainActivity, call.argument<String>("track"),
                            call.argument<String>("mode") ?: "auto", call.argument<String>("cameraId"),
                            call.argument<Boolean>("rear") != false)
                    }.onSuccess { result.success(true) }.onFailure {
                        result.error("CAMERA_ORIENTATION", it.message, null)
                    }
                    "cameraCapabilities" -> runCatching {
                        CaptureDeviceControls.capabilities(this@MainActivity,
                            call.argument<String>("cameraId"), call.argument<Boolean>("rear") != false,
                            call.argument<Int>("width") ?: 1280, call.argument<Int>("height") ?: 720,
                            call.argument<Int>("fps") ?: 30)
                    }.onSuccess { result.success(it) }.onFailure { result.error("CAMERA_CONTROLS", it.message, null) }
                    "background" -> result.success(CaptureDeviceControls.background(this@MainActivity))
                    "start" -> {
                        val camera = call.argument<Boolean>("camera") == true
                       