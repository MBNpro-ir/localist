package com.prs.localist

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.content.ContextCompat

class QuickSendForegroundService : Service() {
    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val deviceName = intent?.getStringExtra(EXTRA_DEVICE_NAME)
            ?.trim()
            ?.ifBlank { "Localist device" }
            ?: "Localist device"
        startForeground(NOTIFICATION_ID, notification(deviceName))
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "Quick Send background receiving",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Keeps Localist ready to receive nearby Quick Send requests"
                setShowBadge(false)
            },
        )
    }

    private fun notification(deviceName: String): Notification {
        val openIntent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            NOTIFICATION_ID,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_upload_done)
            .setContentTitle("Localist Quick Send")
            .setContentText("$deviceName is ready to receive")
            .setCategory(Notification.CATEGORY_SERVICE)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setContentIntent(pendingIntent)
            .build()
    }

    companion object {
        private const val CHANNEL_ID = "localist.quick_send.background"
        private const val NOTIFICATION_ID = 41091
        private const val EXTRA_DEVICE_NAME = "deviceName"

        fun setEnabled(context: Context, enabled: Boolean, deviceName: String): Boolean {
            return runCatching {
                val intent = Intent(context, QuickSendForegroundService::class.java)
                    .putExtra(EXTRA_DEVICE_NAME, deviceName)
                if (enabled) {
                    ContextCompat.startForegroundService(context, intent)
                } else {
                    context.stopService(intent)
                }
                true
            }.getOrDefault(false)
        }
    }
}
