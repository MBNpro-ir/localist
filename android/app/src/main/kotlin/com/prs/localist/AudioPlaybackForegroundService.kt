package com.prs.localist

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import com.carriez.flutter_hbb.LocalistNotifications

/** Shares Localist's existing silent notification; owns explicit audio playback. */
class AudioPlaybackForegroundService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onStartCommand(intent: Intent?, flags: Int, id: Int): Int {
        LocalistNotifications.start(this, LocalistText.choose(this,"پخش صدا","Audio player"),
            LocalistText.choose(this,"دریافت صدا فعال است","Audio reception active"),emptyList(),
            if(Build.VERSION.SDK_INT >= 29) ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK else null)
        return START_NOT_STICKY
    }
    override fun onDestroy() { LocalistNotifications.stop(this);super.onDestroy() }
    companion object {
        fun start(context: Context) { context.startForegroundService(Intent(context,AudioPlaybackForegroundService::class.java)) }
        fun stop(context: Context) { context.stopService(Intent(context,AudioPlaybackForegroundService::class.java)) }
    }
}
