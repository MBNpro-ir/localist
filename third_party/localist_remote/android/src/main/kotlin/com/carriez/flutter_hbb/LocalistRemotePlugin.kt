package com.carriez.flutter_hbb

import android.app.Activity
import android.content.Intent
import android.provider.Settings
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
                "inputSettings" -> {
                    activity?.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                    result.success(activity != null)
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
