package com.prs.localist

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.os.Handler
import android.os.Looper
import android.annotation.SuppressLint
import io.flutter.plugin.common.MethodChannel
import androidx.core.app.NotificationCompat
import com.carriez.flutter_hbb.LocalistNotifications
import java.util.concurrent.atomic.AtomicInteger

/** Owns visible, explicitly started camera/microphone capture in the background. */
class CaptureForegroundService : Service() {
    private var wake: PowerManager.WakeLock? = null
    override fun onBind(intent: Intent?): IBinder? = null
    @SuppressLint("WakelockTimeout") // Owned only by explicit foreground capture; released below and on process death.
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == STOP) {
            channel?.invokeMethod("stopCapture", null)
            stopSelf()
            return START_NOT_STICKY
        }
        val stop = PendingIntent.getService(this, 0, Intent(this, CaptureForegroundService::class.java).setAction(STOP), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        var types: Int? = null
        if (Build.VERSION.SDK_INT >= 30) {
            var captureTypes = 0
            if (intent?.getBooleanExtra("camera", false) == true) captureTypes = captureTypes or ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
            if (intent?.getBooleanExtra("microphone", false) == true) captureTypes = captureTypes or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            types = captureTypes
        }
        try {
            LocalistNotifications.start(this,
                LocalistText.choose(this, "دوربین و میکروفون", "Camera & Mic"),
                LocalistText.choose(this, "انتقال زنده فعال است", "Live capture active"),
                listOf(NotificationCompat.Action(0,
                    LocalistText.choose(this, "توقف دوربین/صدا", "Stop camera/mic"), stop)), types)
            if (wake == null) {
                wake = (getSystemService(Context.POWER_SERVICE) as PowerManager).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Localist:Capture").apply { setReferenceCounted(false); acquire() }
            }
            completeStart(intent?.getIntExtra(REQUEST, 0) ?: 0, null)
        } catch (error: RuntimeException) {
            completeStart(intent?.getIntExtra(REQUEST, 0) ?: 0, error)
            stopSelf(startId)
        }
        return START_NOT_STICKY
    }
    override fun onDestroy() {
        for (id in pending.keys.toList()) completeStart(id, IllegalStateException("Capture stopped before becoming ready"))
        LocalistNotifications.stop(this)
        if (wake?.isHeld == true) wake?.release()
        wake = null
        channel?.invokeMethod("stopCapture", null)
        super.onDestroy()
    }
    companion object {
        private const val STOP = "com.prs.localist.CAPTURE_STOP"
        private const val REQUEST = "captureStartRequest"
        var channel: MethodChannel? = null
        private val sequence = AtomicInteger()
        private val handler = Handler(Looper.getMainLooper())
        private data class Pending(val result: MethodChannel.Result, val timeout: Runnable)
        private val pending = mutableMapOf<Int, Pending>()

        // Returning only after startForeground avoids moving the activity to
        // background before Android 14 checks while-in-use camera/mic access.
        fun requestStart(context: Context, camera: Boolean, microphone: Boolean, result: MethodChannel.Result) {
            val id = sequence.incrementAndGet()
            val timeout = Runnable { completeStart(id, IllegalStateException("Capture service did not become ready")) }
            pending[id] = Pending(result, timeout)
            handler.postDelayed(timeout, 10000)
            try {
                val intent = Intent(context, CaptureForegroundService::class.java)
                    .putExtra("camera", camera).putExtra("microphone", microphone).putExtra(REQUEST, id)
                if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent) else context.startService(intent)
            } catch (error: RuntimeException) { completeStart(id, error) }
        }

        private fun completeStart(id: Int, error: Throwable?) {
            val request = pending.remove(id) ?: return
            handler.removeCallbacks(request.timeout)
            if (error == null) request.result.success(true)
            else request.result.error("CAPTURE_START", error.message, null)
        }
    }
}
