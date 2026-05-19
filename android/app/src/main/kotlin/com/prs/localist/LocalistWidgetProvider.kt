package com.prs.localist

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.widget.RemoteViews

open class LocalistWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        updateWidgets(context, appWidgetManager, appWidgetIds, kindFor(javaClass))
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            ACTION_TOGGLE_SHARING -> toggleSharing(context)
            ACTION_TOGGLE_RECEIVING -> toggleReceiving(context)
            LocalistVpnService.ACTION_STOP,
            LocalistVpnService.ACTION_START,
            LocalistVpnService.ACTION_START_RECEIVING,
            LocalistVpnService.ACTION_START_LOCAL_PROXY -> Unit
            else -> return
        }
        updateAll(context)
    }

    private fun toggleSharing(context: Context) {
        val snapshot = LocalistVpnService.snapshot(context)
        if (
            snapshot["proxyRunning"] == true ||
                snapshot["receivingRunning"] == true ||
                snapshot["localProxyRunning"] == true
        ) {
            startService(
                context,
                Intent(context, LocalistVpnService::class.java).setAction(LocalistVpnService.ACTION_STOP),
            )
            return
        }
        startService(
            context,
            Intent(context, LocalistVpnService::class.java).apply {
                action = LocalistVpnService.ACTION_START
                putStringArrayListExtra(
                    LocalistVpnService.EXTRA_PROTOCOLS,
                    arrayListOf("socks5", "http"),
                )
                putExtra(LocalistVpnService.EXTRA_HTTP_PORT, LocalistVpnService.defaultPort("http"))
                putExtra(LocalistVpnService.EXTRA_SOCKS5_PORT, LocalistVpnService.defaultPort("socks5"))
                putExtra(LocalistVpnService.EXTRA_SHARE_ALL_ROUTES, true)
            },
        )
    }

    private fun toggleReceiving(context: Context) {
        val snapshot = LocalistVpnService.snapshot(context)
        if (
            snapshot["receivingRunning"] == true ||
                snapshot["localProxyRunning"] == true ||
                snapshot["proxyRunning"] == true
        ) {
            startService(
                context,
                Intent(context, LocalistVpnService::class.java).setAction(LocalistVpnService.ACTION_STOP),
            )
            return
        }
        val remote = snapshot["remoteProxy"] as? Map<*, *>
        val host = remote?.get("host") as? String ?: ""
        val protocol = remote?.get("protocol") as? String ?: "socks5"
        val port = remote?.get("port") as? Int ?: LocalistVpnService.defaultPort(protocol)
        if (host.isBlank()) {
            openApp(context)
            return
        }
        startService(
            context,
            Intent(context, LocalistVpnService::class.java).apply {
                action = LocalistVpnService.ACTION_START_LOCAL_PROXY
                putExtra(LocalistVpnService.EXTRA_REMOTE_PROTOCOL, protocol)
                putExtra(LocalistVpnService.EXTRA_REMOTE_HOST, host)
                putExtra(LocalistVpnService.EXTRA_REMOTE_PORT, port)
                putExtra(LocalistVpnService.EXTRA_LOCAL_PROXY_PORT, LocalProxyForwarder.DEFAULT_LOCAL_PORT)
            },
        )
    }

    private fun openApp(context: Context) {
        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: Intent(context, MainActivity::class.java)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }

    private fun startService(context: Context, intent: Intent) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && intent.action != LocalistVpnService.ACTION_STOP) {
            context.startForegroundService(intent)
        } else {
            context.startService(intent)
        }
    }

    companion object {
        private const val ACTION_TOGGLE_SHARING = "com.prs.localist.widget.TOGGLE_SHARING"
        private const val ACTION_TOGGLE_RECEIVING = "com.prs.localist.widget.TOGGLE_RECEIVING"

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            for (kind in WidgetKind.entries) {
                val componentName = ComponentName(context, kind.providerClass)
                updateWidgets(
                    context,
                    manager,
                    manager.getAppWidgetIds(componentName),
                    kind,
                )
            }
        }

        private fun updateWidgets(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetIds: IntArray,
            kind: WidgetKind,
        ) {
            val snapshot = LocalistVpnService.snapshot(context)
            val sharingActive = snapshot["proxyRunning"] == true
            val receivingActive = snapshot["receivingRunning"] == true || snapshot["localProxyRunning"] == true
            for (widgetId in appWidgetIds) {
                val views = RemoteViews(context.packageName, kind.layoutId)
                views.setOnClickPendingIntent(
                    R.id.localist_widget_root,
                    PendingIntent.getActivity(
                        context,
                        kind.openRequestCode,
                        context.packageManager.getLaunchIntentForPackage(context.packageName)
                            ?: Intent(context, MainActivity::class.java),
                        pendingFlags(),
                    ),
                )
                when (kind) {
                    WidgetKind.FULL -> bindFullWidget(context, views, sharingActive, receivingActive)
                    WidgetKind.SHARING -> bindSharingWidget(context, views, sharingActive, receivingActive)
                    WidgetKind.RECEIVING -> bindReceivingWidget(context, views, sharingActive, receivingActive)
                }
                appWidgetManager.updateAppWidget(widgetId, views)
            }
        }

        private fun bindFullWidget(
            context: Context,
            views: RemoteViews,
            sharingActive: Boolean,
            receivingActive: Boolean,
        ) {
            views.setTextViewText(R.id.localist_widget_status, statusText(sharingActive, receivingActive))
            views.setTextViewText(
                R.id.localist_widget_sending,
                if (sharingActive) "Stop sending" else "Start sending",
            )
            views.setTextViewText(
                R.id.localist_widget_receiving,
                if (receivingActive) "Stop receiving" else "Start receiving",
            )
            views.setInt(
                R.id.localist_widget_sending,
                "setBackgroundResource",
                if (sharingActive) R.drawable.localist_widget_button_active else R.drawable.localist_widget_button,
            )
            views.setInt(
                R.id.localist_widget_receiving,
                "setBackgroundResource",
                if (receivingActive) R.drawable.localist_widget_button_active else R.drawable.localist_widget_button,
            )
            views.setOnClickPendingIntent(
                R.id.localist_widget_sending,
                broadcastIntent(context, ACTION_TOGGLE_SHARING, 101),
            )
            views.setOnClickPendingIntent(
                R.id.localist_widget_receiving,
                broadcastIntent(context, ACTION_TOGGLE_RECEIVING, 102),
            )
        }

        private fun bindSharingWidget(
            context: Context,
            views: RemoteViews,
            sharingActive: Boolean,
            receivingActive: Boolean,
        ) {
            views.setTextViewText(R.id.localist_widget_status, statusText(sharingActive, receivingActive))
            views.setTextViewText(
                R.id.localist_widget_sending,
                if (sharingActive) "Stop sending" else "Start sending",
            )
            views.setInt(
                R.id.localist_widget_sending,
                "setBackgroundResource",
                if (sharingActive) R.drawable.localist_widget_button_active else R.drawable.localist_widget_button,
            )
            views.setOnClickPendingIntent(
                R.id.localist_widget_sending,
                broadcastIntent(context, ACTION_TOGGLE_SHARING, 201),
            )
        }

        private fun bindReceivingWidget(
            context: Context,
            views: RemoteViews,
            sharingActive: Boolean,
            receivingActive: Boolean,
        ) {
            views.setTextViewText(R.id.localist_widget_status, statusText(sharingActive, receivingActive))
            views.setTextViewText(
                R.id.localist_widget_receiving,
                if (receivingActive) "Stop receiving" else "Start receiving",
            )
            views.setInt(
                R.id.localist_widget_receiving,
                "setBackgroundResource",
                if (receivingActive) R.drawable.localist_widget_button_active else R.drawable.localist_widget_button,
            )
            views.setOnClickPendingIntent(
                R.id.localist_widget_receiving,
                broadcastIntent(context, ACTION_TOGGLE_RECEIVING, 202),
            )
        }

        private fun statusText(sharingActive: Boolean, receivingActive: Boolean): String {
            return when {
                sharingActive -> "Sending is on"
                receivingActive -> "Receiving is on"
                else -> "Ready"
            }
        }

        private fun broadcastIntent(context: Context, action: String, requestCode: Int): PendingIntent {
            return PendingIntent.getBroadcast(
                context,
                requestCode,
                Intent(context, LocalistWidgetProvider::class.java).setAction(action),
                pendingFlags(),
            )
        }

        private fun pendingFlags(): Int {
            return PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        }

        private fun kindFor(providerClass: Class<*>): WidgetKind {
            return WidgetKind.entries.firstOrNull { it.providerClass == providerClass }
                ?: WidgetKind.FULL
        }
    }
}

class LocalistSharingWidgetProvider : LocalistWidgetProvider()

class LocalistReceivingWidgetProvider : LocalistWidgetProvider()

private enum class WidgetKind(
    val providerClass: Class<out AppWidgetProvider>,
    val layoutId: Int,
    val openRequestCode: Int,
) {
    FULL(LocalistWidgetProvider::class.java, R.layout.localist_widget, 100),
    SHARING(LocalistSharingWidgetProvider::class.java, R.layout.localist_widget_sharing, 200),
    RECEIVING(LocalistReceivingWidgetProvider::class.java, R.layout.localist_widget_receiving, 300),
}
