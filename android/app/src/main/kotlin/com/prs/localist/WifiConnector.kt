package com.prs.localist

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiConfiguration
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSpecifier
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

object WifiConnector {
    private var activeCallback: ConnectivityManager.NetworkCallback? = null

    fun connect(
        context: Context,
        ssid: String,
        password: String,
        result: MethodChannel.Result,
    ) {
        if (ssid.isBlank()) {
            result.success(false)
            return
        }
        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                connectWithSpecifier(context, ssid, password, result)
            } else {
                connectLegacy(context, ssid, password, result)
            }
        }.onFailure { error ->
            result.error("wifi_connect_failed", error.message, null)
        }
    }

    private fun connectWithSpecifier(
        context: Context,
        ssid: String,
        password: String,
        result: MethodChannel.Result,
    ) {
        val connectivity = context.getSystemService(ConnectivityManager::class.java)
        val builder = WifiNetworkSpecifier.Builder().setSsid(ssid)
        if (password.isNotBlank()) {
            builder.setWpa2Passphrase(password)
        }
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .setNetworkSpecifier(builder.build())
            .build()
        var completed = false
        val handler = Handler(Looper.getMainLooper())
        activeCallback?.let { callback ->
            runCatching { connectivity.unregisterNetworkCallback(callback) }
        }
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                if (completed) {
                    return
                }
                completed = true
                connectivity.bindProcessToNetwork(network)
                result.success(true)
            }

            override fun onUnavailable() {
                if (completed) {
                    return
                }
                completed = true
                result.success(false)
            }

            override fun onLost(network: Network) {
                if (activeCallback === this) {
                    activeCallback = null
                    connectivity.bindProcessToNetwork(null)
                }
            }
        }
        activeCallback = callback
        connectivity.requestNetwork(request, callback)
        handler.postDelayed(
            {
                if (!completed) {
                    completed = true
                    runCatching { connectivity.unregisterNetworkCallback(callback) }
                    if (activeCallback === callback) {
                        activeCallback = null
                    }
                    result.success(false)
                }
            },
            CONNECT_TIMEOUT_MS,
        )
    }

    @Suppress("DEPRECATION")
    private fun connectLegacy(
        context: Context,
        ssid: String,
        password: String,
        result: MethodChannel.Result,
    ) {
        val wifi = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        if (!wifi.isWifiEnabled) {
            wifi.isWifiEnabled = true
        }
        val quotedSsid = "\"$ssid\""
        val existingId = runCatching {
            wifi.configuredNetworks
                ?.firstOrNull { it.SSID == quotedSsid }
                ?.networkId
        }.getOrNull()
        val networkId = existingId ?: wifi.addNetwork(
            WifiConfiguration().apply {
                SSID = quotedSsid
                if (password.isBlank()) {
                    allowedKeyManagement.set(WifiConfiguration.KeyMgmt.NONE)
                } else {
                    preSharedKey = "\"$password\""
                }
            },
        )
        val ok = networkId >= 0 && wifi.enableNetwork(networkId, true) && wifi.reconnect()
        result.success(ok)
    }

    private const val CONNECT_TIMEOUT_MS = 30_000L
}
