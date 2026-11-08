package com.prs.localist

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import io.flutter.plugin.common.MethodChannel

/** Owns visible, explicitly started camera/microphone capture in the background. */
class CaptureForegroundService : Service() {
    private var wake: PowerManager.WakeLock? = null
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == STOP) {
            channel?.invokeMethod("stopCapture", null)
            stopSelf()
            return START_NOT_STICKY
        }
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(CHANNEL, "Localist Camera & Mic", NotificationManager.IMPORTANCE_LOW))
        val stop = PendingIntent.getService(this, 0, Intent(this, CaptureForegroundService::class.java).setAction(STOP), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val fa = resources.configuration.locales[0].language == "fa"
        val notification = Notification.Builder(this, CHANNEL)
            .setSmallIcon(android.R.drawable.presence_video_online)
            .setContentTitle(if (fa) "انتقال دوربین و میکروفون Localist" else "Localist Camera & Mic")
            .setContentText(if (fa) "انتقال زنده فعال است؛ برای توقف دکمه را بزنید." else "Live capture is active. Tap Stop to end sharing.")
            .setContentIntent(open).setOngoing(true)
            .addAction(Notification.Action.Builder(null, if (fa) "توقف" else "Stop", stop).build()).build()
        if (Build.VERSION.SDK_INT >= 30) {
            var types = 0
            if (intent?.getBooleanExtra("camera", false) == true) types = types or ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
            if (intent?.getBooleanExtra("microphone", false) == true) types = types or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            startForeground(1084, notification, types)
        } else startForeground(1084, notification)
        if (wake == null) {
            wake = (getSystemService(Context.POWER_SERVICE) as PowerManager).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Localist:Capture").apply { acquire(4 * 60 * 60 * 1000L) }
        }
        return START_NOT_STICKY
    }
    override fun onDestroy() {
        if (wake?.isHeld == true) wake?.release()
        wake = null
        channel?.invokeMethod("stopCapture", null)
        super.onDestroy()
    }
    companion object {
        private const val CHANNEL = "localist_live_capture"
        private const val STOP = "com.prs.localist.CAPTURE_STOP"
        var channel: MethodChannel? = null
    }
}
