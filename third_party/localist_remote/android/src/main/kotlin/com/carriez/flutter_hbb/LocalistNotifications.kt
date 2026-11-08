package com.carriez.flutter_hbb

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.NotificationCompat
import java.util.Locale

/** All foreground services share one ID, while retaining their own Android FGS types. */
object LocalistNotifications {
    const val ID = 41090
    const val CHANNEL = "localist.activity.silent.v1"
    private data class Activity(
        val label: String,
        val detail: String,
        val actions: List<NotificationCompat.Action>,
    )
    private data class Event(val owner: String, val text: String, val open: PendingIntent)
    private val activities = linkedMapOf<String, Activity>()
    private val events = linkedMapOf<String, Event>()
    private var initialized = false
    private val handler = Handler(Looper.getMainLooper())

    fun text(context: Context, fa: String, en: String): String {
        val language = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .getString("flutter.app.language", "system")
        return if (language == "fa" || (language == "system" && Locale.getDefault().language == "fa")) fa else en
    }

    @Synchronized
    fun initialize(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(
            CHANNEL, text(context, "فعالیت لوکالیست (بی‌صدا)", "Localist activity (silent)"),
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = text(context, "وضعیت سرویس‌ها و درخواست‌های ورودی در یک اعلان", "Services and incoming requests in one notification")
            setSound(null, null)
            enableVibration(false)
            enableLights(false)
            setShowBadge(false)
            lockscreenVisibility = Notification.VISIBILITY_PRIVATE
        })
        if (initialized) return
        initialized = true
        // Channels cannot be made silent in place after creation. Retire the old
        // loud channels and their stale notifications during the app upgrade.
        for (old in listOf("Localist", "localist_service", "localist_live_capture",
            "localist.quick_send.background", "localist.quick_send.events.v2", "localist.quick_send.events.silent.v2")) {
            manager.deleteNotificationChannel(old)
        }
    }

    private fun key(service: Service) = service.javaClass.name

    @Synchronized
    fun start(service: Service, label: String, detail: String = "",
              actions: List<NotificationCompat.Action> = emptyList(), types: Int? = null) {
        initialize(service)
        val owner = key(service)
        val previous = activities.put(owner, Activity(label, detail, actions))
        try {
            val notification = build(service)
            if (Build.VERSION.SDK_INT >= 29 && types != null) service.startForeground(ID, notification, types)
            else service.startForeground(ID, notification)
        } catch (error: RuntimeException) {
            if (previous == null) activities.remove(owner) else activities[owner] = previous
            throw error
        }
    }

    @Synchronized
    fun update(service: Service, label: String, detail: String = "",
               actions: List<NotificationCompat.Action>? = null) {
        val owner = key(service)
        val previous = activities[owner] ?: return
        val next = Activity(label, detail, actions ?: previous.actions)
        if (next == previous) return
        activities[owner] = next
        refresh(service)
    }

    @Synchronized
    fun stop(service: Service) {
        val owner = key(service)
        if (activities.remove(owner) == null) return
        events.entries.removeAll { it.value.owner == owner }
        // REMOVE would cancel the notification belonging to the other services.
        // DETACH first clears this service's ownership, then rebuild surviving state.
        service.stopForeground(Service.STOP_FOREGROUND_DETACH)
        refresh(service)
        val app = service.applicationContext
        handler.post { synchronized(this) { refresh(app) } }
    }

    @Synchronized
    fun showEvent(context: Context, id: String, owner: String, title: String,
                  message: String, open: PendingIntent) {
        initialize(context)
        events.remove(id)
        events[id] = Event(owner, "$title: $message", open)
        while (events.size > 20) events.remove(events.keys.first())
        refresh(context)
    }

    @Synchronized
    fun clearEvent(context: Context, id: String) {
        if (events.remove(id) != null) refresh(context)
    }

    private fun refresh(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        if (activities.isEmpty() && events.isEmpty()) manager.cancel(ID)
        else manager.notify(ID, build(context))
    }

    private fun openApp(context: Context): PendingIntent {
        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: Intent(context, RemoteActivity::class.java)
        intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(context, ID, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    private fun build(context: Context): Notification {
        val summary = activities.values.joinToString(" • ") { it.label }
        val lines = events.values.map { it.text } + activities.values.map {
            if (it.detail.isBlank()) it.label else "${it.label}: ${it.detail}"
        }
        val builder = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.mipmap.ic_stat_logo)
            .setContentTitle("Localist")
            .setContentText(events.values.lastOrNull()?.text ?: summary)
            .setStyle(NotificationCompat.BigTextStyle().bigText(lines.joinToString("\n")))
            .setContentIntent(events.values.lastOrNull()?.open ?: openApp(context))
            .setCategory(if (events.isEmpty()) Notification.CATEGORY_SERVICE else Notification.CATEGORY_MESSAGE)
            .setOngoing(activities.isNotEmpty()).setAutoCancel(activities.isEmpty())
            .setOnlyAlertOnce(true).setShowWhen(false).setSilent(true)
            .setDefaults(0).setSound(null).setVibrate(null)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
        // Keep capture Stop visible even when other services have actions.
        val serviceActions = activities.entries.sortedBy {
            if (it.key.endsWith("CaptureForegroundService")) 0 else 1
        }.flatMap { it.value.actions }
        val requestActions = events.values.distinctBy { it.owner }.map {
            NotificationCompat.Action(0, text(context, "مشاهدهٔ درخواست", "View request"), it.open)
        }
        for (action in (requestActions + serviceActions).take(3)) builder.addAction(action)
        return builder.build()
    }
}
