package com.prs.localist

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.os.Build
import android.widget.RemoteViews

class LocalistWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        updateWidgets(context, appWidgetManager, appWidgetIds)
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
        val manager = AppWidgetManager.getInstance(context)
        updateWidgets(context, manager, manager.getAppWidgetIds(componentName(context)))
    }

    private fun toggleSharing(context: Context) {
        val snapshot = LocalistVpnService.snapshot(context)
        if (snapshot["proxyRunning"] == true || snapshot["receivingRunning"] == true || snapshot["localProxyRunning"] == true) {
            startService(context, Intent(context, LocalistVpnService::class.java).setAction(LocalistVpnService.ACTION_STOP))
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
        if (snapshot["receivingRunning"] == true || snapshot["localProxyRunning"] == true || snapshot["proxyRunning"] == true) {
            startService(context, Intent(context, LocalistVpnService::class.java).setAction(LocalistVpnService.ACTION_STOP))
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
            updateWidgets(context, manager, manager.getAppWidgetIds(componentName(context)))
        }

        private fun updateWidgets(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetIds: IntArray,
        ) {
            val snapshot = LocalistVpnService.snapshot(context)
            val sharingActive = snapshot["proxyRunning"] == true
            val receivingActive = snapshot["receivingRunning"] == true || snapshot["localProxyRunning"] == true
            for (widgetId in appWidgetIds) {
                val views = RemoteViews(context.packageName, R.layout.localist_widget)
                views.setTextViewText(
                    R.id.localist_widget_status,
                    when {
                        sharingActive -> "Sending is on"
                        receivingActive -> "Receiving is on"
                        else -> "Ready"
                    },
                )
                views.setTextViewText(
                    R.id.localist_widget_sending,
                    if (sharingActive) "Stop sending" else "Start sending",
                )
                views.setTextViewText(
                    R.id.localist_widget_receiving,
                    if (receivingActive) "Stop receiving" else "Receiving",
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
                    R.id.localist_widget_root,
                    PendingIntent.getActivity(
                        context,
                        100,
                        context.packageManager.getLaunchIntentForPackage(context.packageName)
                            ?: Intent(context, MainActivity::class.java),
                        pendingFlags(),
                    ),
                )
                views.setOnClickPendingIntent(
                    R.id.localist_widget_sending,
                    broadcastIntent(context, ACTION_TOGGLE_SHARING, 101),
                )
                views.setOnClickPendingIntent(
                    R.id.localist_widget_receiving,
                    broadcastIntent(context, ACTION_TOGGLE_RECEIVING, 102),
                )
                appWidgetManager.updateAppWidget(widgetId, views)
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

        private fun componentName(context: Context): android.content.ComponentName {
            return android.content.ComponentName(context, LocalistWidgetProvider::class.java)
        }

        private fun pendingFlags(): Int {
            return PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        }
    }
}
