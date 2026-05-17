package com.prs.localist

import android.content.Context
import org.amnezia.awg.hevtunnel.TProxyService
import java.io.File

class PrsTunEngine(private val context: Context) {
    @Volatile
    private var running = false
    private var worker: Thread? = null

    fun start(tunFd: Int, socksHost: String, socksPort: Int) {
        stop()
        val config = writeConfig(socksHost, socksPort)
        running = true
        worker = Thread {
            runCatching {
                TProxyService.TProxyStartService(config.absolutePath, tunFd)
            }.onFailure {
                running = false
            }
        }.apply {
            name = "prstun"
            isDaemon = true
            start()
        }
    }

    fun stop() {
        if (running) {
            runCatching { TProxyService.TProxyStopService() }
        }
        running = false
        worker?.interrupt()
        worker = null
    }

    fun stats(): LongArray {
        return runCatching {
            TProxyService.TProxyGetStats() ?: longArrayOf(0, 0)
        }.getOrDefault(longArrayOf(0, 0))
    }

    private fun writeConfig(socksHost: String, socksPort: Int): File {
        val file = File(context.cacheDir, "prstun.yml")
        file.writeText(
            """
            tunnel:
              mtu: 1500
              ipv4: 10.0.0.2

            socks5:
              port: $socksPort
              address: $socksHost
              udp: 'udp'

            mapdns:
              address: $MAPPED_DNS_ADDRESS
              port: 53
              network: $MAPPED_DNS_NETWORK
              netmask: $MAPPED_DNS_NETMASK
              cache-size: 10000

            misc:
              log-level: warn
              task-stack-size: 24576
            """.trimIndent(),
        )
        return file
    }

    companion object {
        const val MAPPED_DNS_ADDRESS = "198.18.0.2"
        private const val MAPPED_DNS_NETWORK = "240.0.0.0"
        private const val MAPPED_DNS_NETMASK = "240.0.0.0"
    }
}
