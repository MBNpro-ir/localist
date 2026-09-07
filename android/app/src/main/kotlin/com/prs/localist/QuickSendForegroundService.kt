package com.prs.localist

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import java.util.concurrent.atomic.AtomicInteger

class QuickSendForegroundService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun onCreate() { super.onCreate(); createBackgroundChannel(); acquireNetworkLocks() }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val deviceName = intent?.getStringExtra(EXTRA_DEVICE_NAME)?.trim()
            ?.ifBlank { "Localist device" } ?: "Localist device"
        startForeground(BACKGROUND_NOTIFICATION_ID, backgroundNotification(deviceName))
        acquireNetworkLocks()
        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) { stopSelf(); super.onTaskRemoved(rootIntent) }
    override fun onDestroy() { releaseNetworkLocks(); super.onDestroy() }
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

    private fun createBackgroundChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(
                BACKGROUND_CHANNEL_ID, "Quick Send background receiving",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Keeps Localist ready to receive nearby Quick Send requests"
                setShowBadge(false)
            },
        )
    }

    private fun backgroundNotification(deviceName: String): Notification =
        NotificationCompat.Builder(this, BACKGROUND_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_upload_done)
            .setContentTitle("Localist Quick Send")
            .setContentText("$deviceName is ready to receive")
            .setCategory(Notification.CATEGORY_SERVICE)
            .setOngoing(true).setOnlyAlertOnce(true).setShowWhen(false)
            .setContentIntent(openAppPendingIntent(this, BACKGROUND_NOTIFICATION_ID))
            .build()

    companion object {
        private const val BACKGROUND_CHANNEL_ID = "localist.quick_send.background"
        private const val EVENT_CHANNEL_LOUD = "localist.quick_send.events.v2"
        private const val EVENT_CHANNEL_SILENT = "localist.quick_send.events.silent.v2"
        private const val BACKGROUND_NOTIFICATION_ID = 41091
        private const val EXTRA_DEVICE_NAME = "deviceName"
        private val nextEventId = AtomicInteger(41100)

        fun setEnabled(context: Context, enabled: Boolean, deviceName: String): Boolean =
            runCatching {
                val intent = Intent(context, QuickSendForegroundService::class.java)
                    .putExtra(EXTRA_DEVICE_NAME, deviceName)
                if (enabled) ContextCompat.startForegroundService(context, intent)
                else context.stopService(intent)
                true
            }.getOrDefault(false)

        fun showEventNotification(
            context: Context, title: String, message: String, soundEnabled: Boolean,
        ): Boolean = runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED
            ) return false
            val manager = context.getSystemService(NotificationManager::class.java)
            val channelId = if (soundEnabled) EVENT_CHANNEL_LOUD else EVENT_CHANNEL_SILENT
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = NotificationChannel(
                    channelId,
                    if (soundEnabled) "Quick Send requests" else "Quick Send silent requests",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = "Incoming Localist Quick Send requests"
                    enableVibration(soundEnabled)
                    if (soundEnabled) {
                        val sound = Uri.parse(
                            "android.resource://${context.packageName}/${R.raw.localist_request}",
                        )
                        setSound(sound, AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_NOTIFICATION_EVENT)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
                    } else setSound(null, null)
                }
                manager.createNotificationChannel(channel)
            }
            val id = nextEventId.updateAndGet { if (it >= 41999) 41100 else it + 1 }
            manager.notify(
                id,
                NotificationCompat.Builder(context, channelId)
                    .setSmallIcon(android.R.drawable.stat_sys_download_done)
                    .setContentTitle(title).setContentText(message)
                    .setStyle(NotificationCompat.BigTextStyle().bigText(message))
                    .setCategory(Notification.CATEGORY_MESSAGE)
                    .setPriority(NotificationCompat.PRIORITY_HIGH)
                    .setAutoCancel(true)
                    .setContentIntent(openAppPendingIntent(context, id)).build(),
            )
            true
        }.getOrDefault(false)

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
