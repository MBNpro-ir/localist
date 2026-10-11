package com.carriez.flutter_hbb

import android.app.Activity
import android.content.Intent
import android.provider.Settings
import android.os.Build
import android.net.VpnService
import android.net.Uri
import ffi.FFI
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodChannel

/** Hosts the upstream engine inside this APK; no companion package is launched. */
class LocalistRemotePlugin : FlutterPlugin, ActivityAware {
    private var activity: Activity? = null
    private var channel: MethodChannel? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "localist/remote")
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "available" -> result.success(true)
                "sdk" -> result.success(Build.VERSION.SDK_INT)
                "features" -> result.success(mapOf(
                    "input" to InputService.isOpen,
                    "capture" to MainService.isReady,
                    "vpn" to (activity?.let { VpnService.prepare(it) == null } ?: false),
                ))
                "shareConnection" -> {
                    val values = call.arguments as? Map<*, *>
                    val text = values?.get("text") as? String ?: ""
                    val share = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_TEXT, text)
                    }
                    activity?.startActivity(Intent.createChooser(share, "Localist"))
                    result.success(activity != null)
                }
                "inputSettings" -> {
                    activity?.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                    result.success(activity != null)
                }
                "permissionSettings" -> {
                    val current = activity
                    if (current == null) {
                        result.success(false)
                    } else {
                        val packageUri = Uri.parse("package:${current.packageName}")
                        val intent = when (call.arguments as? String) {
                            "vpn" -> Intent(Settings.ACTION_VPN_SETTINGS)
                            "battery" -> Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                            "storage" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R)
                                Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION, packageUri)
                                else Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, packageUri)
                            "installUpdates" -> Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, packageUri)
                            "overlay" -> Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, packageUri)
                            else -> Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, packageUri)
                        }
                        result.success(runCatching { current.startActivity(intent); true }.getOrDefault(false))
                    }
                }
                "launchOptions" -> result.success(activity?.intent?.getStringExtra("localistRemoteOptions") ?: "{}")
                "open" -> {
                    val current = activity
                    if (current == null) result.error("NO_ACTIVITY", "Application is not visible.", null)
                    else {
                        current.startActivity(Intent(current, RemoteActivity::class.java)
                            .putExtra("localistRemoteOptions", call.arguments as? String ?: "{}"))
                        result.success(true)
                    }
                }
                "close" -> { activity?.finish(); result.success(true) }
                else -> result.notImplemented()
            }
        }
    }
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }
    override fun onDetachedFromActivity() { activity = null }
    override fun onDetachedFromActivityForConfigChanges() { activity = null }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
    }
}
