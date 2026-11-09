package com.prs.localist

import android.app.*
import android.content.*
import android.os.*
import com.carriez.flutter_hbb.LocalistNotifications
import com.carriez.flutter_hbb.MainService
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Device-side lifecycle regression: no UI automation or extra test libraries. */
class NotificationRegressionRunner : Instrumentation() {
    private lateinit var args: Bundle
    override fun onCreate(arguments: Bundle?) {
        super.onCreate(arguments)
        args = arguments ?: Bundle()
        start()
    }

    override fun onStart() {
        val results = Bundle()
        try {
            // Application.onCreate and the instrumentation thread can overlap.
            main { }
            if (args.getString("captureServiceLifecycle") == "true") {
                CaptureServiceRegression.verify(targetContext, this)
                results.putString("stream", "\nLOCALIST_CAPTURE_SERVICE_LIFECYCLE_OK: rapid restart and stop during startup\n")
                finish(Activity.RESULT_OK, results)
                return
            }
            if (args.getString("captureCapabilities") == "true") {
                results.putString("stream", "\n" + CaptureCapabilitiesRegression.verify(targetContext) + "\n")
                finish(Activity.RESULT_OK, results)
                return
            }
            if (args.getString("captureRotation") == "true") {
                CaptureRotationRegression.verify()
                results.putString("stream", "\nLOCALIST_CAPTURE_ROTATION_OK: pixel rotation, sensor directions, locks, buffer ownership\n")
                finish(Activity.RESULT_OK, results)
                return
            }
            if (args.getString("seedLegacy") == "true") seedLegacy() else verifyLifecycle()
            results.putString("stream", "\nLOCALIST_NOTIFICATIONS_OK\n")
            finish(Activity.RESULT_OK, results)
        } catch (error: Throwable) {
            results.putString("stream", "\n" + error.stackTraceToString())
            finish(Activity.RESULT_CANCELED, results)
        }
    }

    private val manager get() = targetContext.getSystemService(NotificationManager::class.java)
    private fun main(block: () -> Unit) {
        var failure: Throwable? = null
        runOnMainSync { try { block() } catch (error: Throwable) { failure = error } }
        failure?.let { throw it }
    }
    private fun waitFor(message: String, condition: () -> Boolean) {
        val until = SystemClock.elapsedRealtime() + 10000
        while (!condition()) {
            check(SystemClock.elapsedRealtime() < until) { message }
            SystemClock.sleep(100)
        }
        // Catch delayed Android notification cancellation/reposts as well.
        SystemClock.sleep(300)
        check(condition()) { "Unstable state: $message" }
    }
    private fun single(vararg contents: String) {
        waitFor("Expected one silent notification containing ${contents.toList()}") {
            val items = manager.activeNotifications
            if (items.size != 1 || items[0].id != LocalistNotifications.ID) false
            else {
                val item = items[0].notification
                val text = item.extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString().orEmpty()
                item.channelId == LocalistNotifications.CHANNEL && item.sound == null &&
                    item.vibrate == null && item.defaults == 0 && contents.all(text::contains)
            }
        }
    }
    private fun seedLegacy() {
        manager.createNotificationChannel(NotificationChannel("Localist", "Old loud channel", NotificationManager.IMPORTANCE_HIGH).apply {
            enableVibration(true)
        })
        manager.notify(1, Notification.Builder(targetContext, "Localist")
            .setSmallIcon(android.R.drawable.stat_sys_upload).setContentTitle("Legacy fixture").build())
    }

    private fun verifyLifecycle() {
        val context = targetContext
        check(manager.getNotificationChannel("Localist") == null) { "Old loud channel was not migrated" }
        val channel = manager.getNotificationChannel(LocalistNotifications.CHANNEL)
        check(channel != null && channel.importance == NotificationManager.IMPORTANCE_LOW &&
            channel.sound == null && !channel.shouldVibrate() && !channel.canShowBadge())
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).edit()
            .putString("flutter.app.language", "en").commit()
        val quick = Intent(context, QuickSendForegroundService::class.java).putExtra("deviceName", "QA")
        val remote = Intent(context, MainService::class.java)
        val vpn = Intent(context, LocalistVpnService::class.java).setAction(LocalistVpnService.ACTION_START)
            .putStringArrayListExtra(LocalistVpnService.EXTRA_PROTOCOLS, arrayListOf("socks5"))
            .putExtra(LocalistVpnService.EXTRA_SOCKS5_PORT, 51990)
        val capture = Intent(context, CaptureForegroundService::class.java)
            .putExtra("camera", true).putExtra("microphone", true)
        var remoteService: MainService? = null
        val connected = CountDownLatch(1)
        val connection = object : ServiceConnection {
            override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
                remoteService = (binder as MainService.LocalBinder).getService()
                connected.countDown()
            }
            override fun onServiceDisconnected(name: ComponentName?) {}
        }
        var bound = false
        try {
            main { context.startForegroundService(quick) }
            single("Quick Send")
            main { context.startForegroundService(remote); bound = context.bindService(remote, connection, Context.BIND_AUTO_CREATE) }
            check(connected.await(10, TimeUnit.SECONDS)) { "Remote service binding timed out" }
            single("Quick Send", "Remote control")
            // Exercise the actual native callback entry point used by incoming peers.
            main { remoteService!!.rustSetByName("add_connection", """{"id":9001,"name":"Peer QA","peer_id":"123456","authorized":false,"is_file_transfer":true}""", "") }
            single("Connection request", "Peer QA", "Quick Send")
            main { remoteService!!.rustSetByName("add_connection", """{"id":9001,"name":"Peer QA","peer_id":"123456","authorized":true,"is_file_transfer":true}""", "") }
            single("Quick Send", "Remote control")
            check(!manager.activeNotifications.single().notification.extras.getCharSequence(Notification.EXTRA_BIG_TEXT).toString().contains("Peer QA"))
            repeat(3) { check(QuickSendForegroundService.showEventNotification(context, "Files", "Batch $it")) }
            single("Batch 2", "Remote control")
            QuickSendForegroundService.clearEvent(context)
            main { context.startForegroundService(vpn) }
            single("Quick Send", "Remote control", "VPN sharing")
            main { context.startForegroundService(capture) }
            single("Quick Send", "Remote control", "VPN sharing", "Camera & Mic")
            val stopCapture = manager.activeNotifications.single().notification.actions.first { it.title.toString() == "Stop camera/mic" }.actionIntent
            stopCapture.send()
            waitFor("Camera stop must retain the other services") {
                val text = manager.activeNotifications.singleOrNull()?.notification?.extras?.getCharSequence(Notification.EXTRA_BIG_TEXT).toString()
                "VPN sharing" in text && "Camera & Mic" !in text
            }
            main { context.stopService(quick) }
            single("Remote control", "VPN sharing")
            // Restarting one service must not duplicate the shared notification.
            main { context.startForegroundService(quick); context.startForegroundService(quick) }
            single("Quick Send", "Remote control", "VPN sharing")
            main { if (bound) { context.unbindService(connection); bound = false }; context.stopService(remote) }
            single("Quick Send", "VPN sharing")
            main { context.startService(Intent(context, LocalistVpnService::class.java).setAction(LocalistVpnService.ACTION_STOP)) }
            single("Quick Send")
            context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).edit().putString("flutter.app.language", "fa").commit()
            main { context.startForegroundService(quick) }
            single("ارسال سریع")
            main { context.stopService(quick) }
            waitFor("Final service stop must remove the notification") { manager.activeNotifications.isEmpty() }
        } finally {
            main {
                if (bound) context.unbindService(connection)
                context.stopService(capture); context.stopService(vpn)
                context.stopService(remote); context.stopService(quick)
            }
        }
    }
}
