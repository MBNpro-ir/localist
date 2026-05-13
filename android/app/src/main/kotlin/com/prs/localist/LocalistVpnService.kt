package com.prs.localist

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.ProxyInfo
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import java.io.FileInputStream
import java.util.Locale

class LocalistVpnService : VpnService() {
    private var vpnInterface: ParcelFileDescriptor? = null
    private var proxyServer: LocalistProxyServer? = null
    private var localProxyForwarder: LocalProxyForwarder? = null
    private var prsTunEngine: PrsTunEngine? = null
    private var packetThread: Thread? = null
    private val notificationHandler = Handler(Looper.getMainLooper())
    private val notificationUpdater = object : Runnable {
        override fun run() {
            if (State.proxyRunning || State.vpnConnected || State.receivingRunning) {
                val manager = getSystemService(NotificationManager::class.java)
                manager.notify(NOTIFICATION_ID, buildNotification())
                notificationHandler.postDelayed(this, NOTIFICATION_REFRESH_MS)
            }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> startLocalist(intent)
            ACTION_START_RECEIVING -> startReceiving(intent)
            ACTION_START_LOCAL_PROXY -> startLocalProxy(intent)
            ACTION_STOP -> stopLocalist()
            ACTION_RESTART -> {
                stopLocalist(removeForeground = false)
                val restartIntent = intentWithCurrentConfig()
                if (restartIntent.action == ACTION_START_RECEIVING) {
                    startReceiving(restartIntent)
                } else if (restartIntent.action == ACTION_START_LOCAL_PROXY) {
                    startLocalProxy(restartIntent)
                } else {
                    startLocalist(restartIntent)
                }
            }
            else -> startLocalist(intentWithCurrentConfig())
        }
        return Service.START_STICKY
    }

    override fun onDestroy() {
        stopLocalist()
        super.onDestroy()
    }

    private fun startLocalist(intent: Intent) {
        val protocols = normalizedProtocols(
            intent.getStringArrayListExtra(EXTRA_PROTOCOLS)
                ?: listOf(intent.getStringExtra(EXTRA_PROTOCOL) ?: State.protocols.first()),
        )
        val protocolPorts = mapOf(
            "http" to intent.getIntExtra(EXTRA_HTTP_PORT, defaultPort("http")),
            "socks5" to intent.getIntExtra(EXTRA_SOCKS5_PORT, defaultPort("socks5")),
        )
        val shareAllRoutes = intent.getBooleanExtra(EXTRA_SHARE_ALL_ROUTES, State.shareAllRoutes)
        val selectedLocalIps = intent.getStringArrayListExtra(EXTRA_SELECTED_LOCAL_IPS)
            ?.filter { it.isNotBlank() }
            ?: emptyList()
        State.mode = MODE_SHARING
        State.protocols = protocols
        State.protocolPorts = protocolPorts
        State.port = protocolPorts[protocols.first()] ?: defaultPort(protocols.first())
        State.shareAllRoutes = shareAllRoutes
        State.selectedLocalIps = selectedLocalIps
        State.ipAddress = HotspotController.localIpAddress()
        State.receivingRunning = false
        State.localProxyRunning = false
        State.vpnConnected = false
        State.remoteProtocol = ""
        State.remoteHost = ""
        State.remotePort = 0
        State.sessionRxBytes = 0
        State.sessionTxBytes = 0

        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification())
        runCatching { vpnInterface?.close() }
        vpnInterface = null
        startProxy(
            protocols = protocols,
            protocolPorts = protocolPorts,
            bindAddresses = if (shareAllRoutes) emptyList() else selectedLocalIps,
        )
        notificationHandler.removeCallbacks(notificationUpdater)
        notificationHandler.post(notificationUpdater)
    }

    private fun startReceiving(intent: Intent) {
        val protocol = intent.getStringExtra(EXTRA_REMOTE_PROTOCOL) ?: "socks5"
        val host = intent.getStringExtra(EXTRA_REMOTE_HOST) ?: ""
        val port = intent.getIntExtra(EXTRA_REMOTE_PORT, defaultPort(protocol))
        State.mode = MODE_RECEIVING
        State.protocols = normalizedProtocols(listOf(protocol))
        State.remoteProtocol = State.protocols.first()
        State.remoteHost = host
        State.remotePort = port
        State.port = port
        State.protocolPorts = State.protocolPorts + (State.remoteProtocol to port)
        State.ipAddress = HotspotController.localIpAddress()
        State.proxyRunning = false
        State.receivingRunning = true
        State.localProxyRunning = false
        State.sessionRxBytes = 0
        State.sessionTxBytes = 0
        proxyServer?.stop()
        proxyServer = null
        localProxyForwarder?.stop()
        localProxyForwarder = null

        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification())
        startVpnInterface(protocol = State.remoteProtocol, host = host, port = port)
        notificationHandler.removeCallbacks(notificationUpdater)
        notificationHandler.post(notificationUpdater)
    }

    private fun startLocalProxy(intent: Intent) {
        val protocol = intent.getStringExtra(EXTRA_REMOTE_PROTOCOL) ?: "socks5"
        val host = intent.getStringExtra(EXTRA_REMOTE_HOST) ?: ""
        val port = intent.getIntExtra(EXTRA_REMOTE_PORT, defaultPort(protocol))
        val localPort = intent.getIntExtra(
            EXTRA_LOCAL_PROXY_PORT,
            LocalProxyForwarder.DEFAULT_LOCAL_PORT,
        )
        State.mode = MODE_LOCAL_PROXY
        State.protocols = normalizedProtocols(listOf(protocol))
        State.remoteProtocol = State.protocols.first()
        State.remoteHost = host
        State.remotePort = port
        State.localProxyPort = localPort
        State.port = localPort
        State.protocolPorts = State.protocolPorts + (State.remoteProtocol to port)
        State.ipAddress = HotspotController.localIpAddress()
        State.proxyRunning = false
        State.receivingRunning = false
        State.localProxyRunning = true
        State.vpnConnected = false
        State.sessionRxBytes = 0
        State.sessionTxBytes = 0
        proxyServer?.stop()
        proxyServer = null
        runCatching { vpnInterface?.close() }
        vpnInterface = null
        startLocalForwarder(protocol = State.remoteProtocol, host = host, port = port, localPort = localPort)

        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification())
        notificationHandler.removeCallbacks(notificationUpdater)
        notificationHandler.post(notificationUpdater)
    }

    private fun startVpnInterface(protocol: String, host: String, port: Int) {
        runCatching { vpnInterface?.close() }
        val tunProxyPort = PRSTUN_PROXY_PORT
        startLocalForwarder(
            protocol = protocol,
            host = host,
            port = port,
            localPort = tunProxyPort,
        )
        val builder = Builder()
            .setSession("localist")
            .addAddress("10.0.0.2", 24)
            .addRoute("0.0.0.0", 0)
            .addDnsServer("1.1.1.1")
            .addDnsServer("8.8.8.8")
            .setMtu(1500)
        vpnInterface = builder.establish()
        State.vpnConnected = vpnInterface != null
        vpnInterface?.let { descriptor ->
            prsTunEngine = PrsTunEngine(this).also {
                it.start(
                    tunFd = descriptor.fd,
                    socksHost = LocalProxyForwarder.LOCAL_HOST,
                    socksPort = tunProxyPort,
                )
            }
        }
    }

    private fun startPacketAccounting() {
        packetThread?.interrupt()
        val descriptor = vpnInterface ?: return
        packetThread = Thread {
            val buffer = ByteArray(32767)
            runCatching {
                FileInputStream(descriptor.fileDescriptor).use { input ->
                    while (!Thread.currentThread().isInterrupted && State.vpnConnected) {
                        val read = input.read(buffer)
                        if (read > 0) {
                            recordTraffic(uploadedBytes = read.toLong(), downloadedBytes = 0)
                        }
                    }
                }
            }
        }.apply {
            name = "localistPacketAccounting"
            isDaemon = true
            start()
        }
    }

    private fun startProxy(
        protocols: List<String>,
        protocolPorts: Map<String, Int>,
        bindAddresses: List<String>,
    ) {
        proxyServer?.stop()
        proxyServer = LocalistProxyServer(
            protocolPorts = protocols.associateWith {
                protocolPorts[it] ?: defaultPort(it)
            },
            bindAddresses = bindAddresses.toSet(),
            listener = object : LocalistProxyServer.Listener {
                override fun onTraffic(uploadedBytes: Long, downloadedBytes: Long) {
                    recordTraffic(uploadedBytes, downloadedBytes)
                }

                override fun onLog(message: String) {
                    // Native logs are available through logcat; Flutter keeps the user-facing list.
                }
            },
        ).also { it.start() }
        State.proxyRunning = true
        State.receivingRunning = false
    }

    private fun startLocalForwarder(
        protocol: String,
        host: String,
        port: Int,
        localPort: Int,
    ) {
        localProxyForwarder?.stop()
        localProxyForwarder = LocalProxyForwarder(
            remoteProtocol = protocol,
            remoteHost = host,
            remotePort = port,
            localPort = localPort,
            listener = object : LocalProxyForwarder.Listener {
                override fun onTraffic(uploadedBytes: Long, downloadedBytes: Long) {
                    recordTraffic(uploadedBytes, downloadedBytes)
                }

                override fun onLog(message: String) {
                    // User-facing logs are collected in Flutter.
                }
            },
            socketProtector = { socket -> protect(socket) },
        ).also { it.start() }
    }

    private fun stopLocalist(removeForeground: Boolean = true) {
        notificationHandler.removeCallbacks(notificationUpdater)
        prsTunEngine?.stop()
        prsTunEngine = null
        proxyServer?.stop()
        proxyServer = null
        localProxyForwarder?.stop()
        localProxyForwarder = null
        packetThread?.interrupt()
        packetThread = null
        runCatching { vpnInterface?.close() }
        vpnInterface = null
        State.vpnConnected = false
        State.proxyRunning = false
        State.receivingRunning = false
        State.localProxyRunning = false
        if (removeForeground) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
    }

    private fun intentWithCurrentConfig(): Intent {
        return Intent(this, LocalistVpnService::class.java).apply {
            if (State.mode == MODE_RECEIVING && State.remoteHost.isNotBlank()) {
                action = ACTION_START_RECEIVING
                putExtra(EXTRA_REMOTE_PROTOCOL, State.remoteProtocol)
                putExtra(EXTRA_REMOTE_HOST, State.remoteHost)
                putExtra(EXTRA_REMOTE_PORT, State.remotePort)
            } else if (State.mode == MODE_LOCAL_PROXY && State.remoteHost.isNotBlank()) {
                action = ACTION_START_LOCAL_PROXY
                putExtra(EXTRA_REMOTE_PROTOCOL, State.remoteProtocol)
                putExtra(EXTRA_REMOTE_HOST, State.remoteHost)
                putExtra(EXTRA_REMOTE_PORT, State.remotePort)
                putExtra(EXTRA_LOCAL_PROXY_PORT, State.localProxyPort)
            } else {
                action = ACTION_START
                putStringArrayListExtra(EXTRA_PROTOCOLS, ArrayList(State.protocols))
                putExtra(EXTRA_HTTP_PORT, State.protocolPorts["http"] ?: defaultPort("http"))
                putExtra(EXTRA_SOCKS5_PORT, State.protocolPorts["socks5"] ?: defaultPort("socks5"))
                putExtra(EXTRA_SHARE_ALL_ROUTES, State.shareAllRoutes)
                putStringArrayListExtra(
                    EXTRA_SELECTED_LOCAL_IPS,
                    ArrayList(State.selectedLocalIps),
                )
            }
        }
    }

    private fun buildNotification(): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(this, MainActivity::class.java)
        val contentIntent = PendingIntent.getActivity(
            this,
            1,
            launchIntent,
            pendingIntentFlags(),
        )
        val stopIntent = PendingIntent.getService(
            this,
            2,
            Intent(this, LocalistVpnService::class.java).setAction(ACTION_STOP),
            pendingIntentFlags(),
        )
        val restartIntent = PendingIntent.getService(
            this,
            3,
            Intent(this, LocalistVpnService::class.java).setAction(ACTION_RESTART),
            pendingIntentFlags(),
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, NOTIFICATION_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val title = when (State.mode) {
            MODE_RECEIVING -> "localist receiving VPN is running"
            MODE_LOCAL_PROXY -> "localist local proxy is running"
            else -> "localist proxy is running"
        }
        val endpoint = when (State.mode) {
            MODE_RECEIVING ->
                "${State.remoteProtocol.uppercase(Locale.US)} ${State.remoteHost}:${State.remotePort}"
            MODE_LOCAL_PROXY ->
                "127.0.0.1:${State.localProxyPort} via ${State.remoteProtocol.uppercase(Locale.US)} ${State.remoteHost}:${State.remotePort}"
            else ->
                State.protocols.joinToString(" / ") { protocol ->
                    "${protocol.uppercase(Locale.US)} ${State.ipAddress}:${State.protocolPorts[protocol] ?: defaultPort(protocol)}"
                }
        }
        return builder
            .setSmallIcon(android.R.drawable.stat_sys_upload_done)
            .setContentTitle(title)
            .setContentText(
                "$endpoint - " +
                    formatBytes(State.sessionRxBytes + State.sessionTxBytes),
            )
            .setOngoing(true)
            .setColor(Color.rgb(103, 58, 183))
            .setContentIntent(contentIntent)
            .addAction(android.R.drawable.ic_media_pause, "Stop", stopIntent)
            .addAction(android.R.drawable.ic_popup_sync, "Restart", restartIntent)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val channel = NotificationChannel(
            NOTIFICATION_CHANNEL_ID,
            "localist service",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Shows localist VPN and proxy sharing status."
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun pendingIntentFlags(): Int {
        return PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    }

    private fun recordTraffic(uploadedBytes: Long, downloadedBytes: Long) {
        synchronized(State) {
            State.sessionTxBytes += uploadedBytes
            State.sessionRxBytes += downloadedBytes
            val prefs = getSharedPreferences(PREFS_STATS, Context.MODE_PRIVATE)
            val totalTx = prefs.getLong(KEY_TOTAL_TX, 0) + uploadedBytes
            val totalRx = prefs.getLong(KEY_TOTAL_RX, 0) + downloadedBytes
            prefs.edit()
                .putLong(KEY_TOTAL_TX, totalTx)
                .putLong(KEY_TOTAL_RX, totalRx)
                .apply()
        }
    }

    companion object {
        const val ACTION_START = "com.prs.localist.START"
        const val ACTION_START_RECEIVING = "com.prs.localist.START_RECEIVING"
        const val ACTION_START_LOCAL_PROXY = "com.prs.localist.START_LOCAL_PROXY"
        const val ACTION_STOP = "com.prs.localist.STOP"
        const val ACTION_RESTART = "com.prs.localist.RESTART"
        const val EXTRA_PROTOCOL = "protocol"
        const val EXTRA_PROTOCOLS = "protocols"
        const val EXTRA_PORT = "port"
        const val EXTRA_HTTP_PORT = "httpPort"
        const val EXTRA_SOCKS5_PORT = "socks5Port"
        const val EXTRA_SELECTIVE = "selectiveSharing"
        const val EXTRA_SHARE_ALL_ROUTES = "shareAllRoutes"
        const val EXTRA_SELECTED_LOCAL_IPS = "selectedLocalIps"
        const val EXTRA_REMOTE_PROTOCOL = "remoteProtocol"
        const val EXTRA_REMOTE_HOST = "remoteHost"
        const val EXTRA_REMOTE_PORT = "remotePort"
        const val EXTRA_LOCAL_PROXY_PORT = "localProxyPort"
        val SUPPORTED_PROTOCOLS = setOf("http", "socks5")

        private const val NOTIFICATION_ID = 10888
        private const val NOTIFICATION_CHANNEL_ID = "localist_service"
        private const val NOTIFICATION_REFRESH_MS = 5_000L
        private const val PRSTUN_PROXY_PORT = 3782
        private const val PREFS_STATS = "localist_stats"
        private const val KEY_TOTAL_RX = "total_rx"
        private const val KEY_TOTAL_TX = "total_tx"
        private const val MODE_SHARING = "sharing"
        private const val MODE_RECEIVING = "receiving"
        private const val MODE_LOCAL_PROXY = "local_proxy"

        fun stats(context: Context): Map<String, Long> {
            val prefs = context.getSharedPreferences(PREFS_STATS, Context.MODE_PRIVATE)
            return synchronized(State) {
                mapOf(
                    "sessionRxBytes" to State.sessionRxBytes,
                    "sessionTxBytes" to State.sessionTxBytes,
                    "totalRxBytes" to prefs.getLong(KEY_TOTAL_RX, 0),
                    "totalTxBytes" to prefs.getLong(KEY_TOTAL_TX, 0),
                )
            }
        }

        fun snapshot(context: Context): Map<String, Any> {
            return synchronized(State) {
                mapOf(
                    "vpnConnected" to State.vpnConnected,
                    "deviceVpnActive" to isDeviceVpnActive(context),
                    "proxyRunning" to State.proxyRunning,
                    "receivingRunning" to State.receivingRunning,
                    "localProxyRunning" to State.localProxyRunning,
                    "localProxyPort" to State.localProxyPort,
                    "hotspot" to HotspotController.snapshot(context),
                    "protocol" to State.protocols.first(),
                    "protocols" to State.protocols,
                    "ports" to State.protocolPorts,
                    "port" to State.port,
                    "shareAllRoutes" to State.shareAllRoutes,
                    "localProxyIps" to NetworkAddressInspector.localProxyIps(),
                    "selectiveSharing" to !State.shareAllRoutes,
                    "usage" to stats(context),
                    "root" to RootRoutingController.snapshot(context),
                    "remoteProxy" to if (State.remoteHost.isBlank()) {
                        emptyMap<String, Any>()
                    } else {
                        mapOf(
                            "protocol" to State.remoteProtocol.ifBlank { State.protocols.first() },
                            "host" to State.remoteHost,
                            "port" to if (State.remotePort > 0) State.remotePort else State.port,
                        )
                    },
                )
            }
        }

        private fun normalizedProtocols(values: List<String>): List<String> {
            val filtered = values
                .map { it.lowercase(Locale.US) }
                .filter { SUPPORTED_PROTOCOLS.contains(it) }
                .distinct()
            return filtered.ifEmpty { listOf("http", "socks5") }
        }

        fun defaultPort(protocol: String): Int {
            return when (protocol.lowercase(Locale.US)) {
                "http" -> 2060
                else -> 2080
            }
        }

        private fun isDeviceVpnActive(context: Context): Boolean {
            if (State.vpnConnected) {
                return true
            }
            val connectivity =
                context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            return connectivity.allNetworks.any { network ->
                connectivity.getNetworkCapabilities(network)
                    ?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true
            }
        }

        private fun formatBytes(bytes: Long): String {
            val units = arrayOf("B", "KB", "MB", "GB", "TB")
            var value = bytes.toDouble()
            var unit = 0
            while (value >= 1024 && unit < units.lastIndex) {
                value /= 1024
                unit++
            }
            return if (unit == 0) {
                "${value.toLong()} ${units[unit]}"
            } else {
                String.format(Locale.US, "%.1f %s", value, units[unit])
            }
        }
    }

    private object State {
        var mode = MODE_SHARING
        var vpnConnected = false
        var proxyRunning = false
        var receivingRunning = false
        var localProxyRunning = false
        var protocols = listOf("http", "socks5")
        var protocolPorts = mapOf("http" to 2060, "socks5" to 2080)
        var port = 2060
        var shareAllRoutes = true
        var selectedLocalIps = emptyList<String>()
        var ipAddress = "192.168.43.1"
        var remoteProtocol = ""
        var remoteHost = ""
        var remotePort = 0
        var localProxyPort = LocalProxyForwarder.DEFAULT_LOCAL_PORT
        var sessionRxBytes = 0L
        var sessionTxBytes = 0L
    }
}
