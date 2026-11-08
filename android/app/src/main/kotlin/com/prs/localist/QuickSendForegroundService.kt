package com.prs.localist

import android.Manifest
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.content.ContextCompat
import com.carriez.flutter_hbb.LocalistNotifications

class QuickSendForegroundService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun onCreate() { super.onCreate(); acquireNetworkLocks() }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val deviceName = intent?.getStringExtra(EXTRA_DEVICE_NAME)?.trim()
            ?.ifBlank { "Localist device" } ?: "Localist device"
        LocalistNotifications.start(this,
            LocalistText.choose(this, "ارسال سریع", "Quick Send"),
            LocalistText.choose(this, "$deviceName آماده دریافت است", "$deviceName is ready to receive"))
        acquireNetworkLocks()
        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) { stopSelf(); super.onTaskRemoved(rootIntent) }
    override fun onDestroy() { LocalistNotifications.stop(this); releaseNetworkLocks(); super.onDestroy() }
    override fun onBind(intent: Intent?): IBinder? = null

    private fun acquireNetworkLocks() {
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = wakeLock ?: power.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK, "Localist:QuickSend",
        ).apply { setReferenceCounted(false) }
        if (wakeLock?.isHeld != true) wakeLock?.acquire()
        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        @Suppress("DEPRECATION")
        wifiLock = wifiLock ?: wifi.createWifiLock(
            WifiManager.WIFI_MODE_FULL_HIGH_PERF, "Localist:QuickSendWifi",
        ).apply { setReferenceCounted(false) }
        multicastLock = multicastLock ?: wifi.createMulticastLock(
            "Localist:QuickSendMulticast",
        ).apply { setReferenceCounted(false) }
        if (wifiLock?.isHeld != true) wifiLock?.acquire()
        if (multicastLock?.isHeld != true) multicastLock?.acquire()
    }

    private fun releaseNetworkLocks() {
        if (multicastLock?.isHeld == true) multicastLock?.release()
        if (wifiLock?.isHeld == true) wifiLock?.release()
        if (wakeLock?.isHeld == true) wakeLock?.release()
        multicastLock = null; wifiLock = null; wakeLock = null
    }

    companion object {
        private const val EXTRA_DEVICE_NAME = "deviceName"
        private const val EVENT_ID = "quick-send-request"

        fun setEnabled(context: Context, enabled: Boolean, deviceName: String): Boolean =
            runCatching {
                val intent = Intent(context, QuickSendForegroundService::class.java)
                    .putExtra(EXTRA_DEVICE_NAME, deviceName)
                if (enabled) ContextCompat.startForegroundService(context, intent)
                else context.stopService(intent)
                true
            }.getOrDefault(false)

        fun showEventNotification(
            context: Context, title: String, message: String,
        ): Boolean = runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED
            ) return false
            LocalistNotifications.showEvent(context, EVENT_ID,
                QuickSendForegroundService::class.java.name, title, message,
                openAppPendingIntent(context, LocalistNotifications.ID + 1))
            true
        }.getOrDefault(false)

        fun clearEvent(context: Context) = LocalistNotifications.clearEvent(context, EVENT_ID)

        private fun openAppPendingIntent(context: Context, requestCode: Int): PendingIntent {
            val intent = Intent(context, MainActivity::class.java).apply {
                action = "com.prs.localist.OPEN_QUICK_SEND"
                putExtra("openQuickSendRequest", true)
                addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }
            return PendingIntent.getActivity(
                context, requestCode, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
    }
}
