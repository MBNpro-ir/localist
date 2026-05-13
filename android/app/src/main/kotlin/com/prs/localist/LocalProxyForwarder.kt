package com.prs.localist

import java.io.ByteArrayOutputStream
import java.io.EOFException
import java.io.InputStream
import java.io.OutputStream
import java.io.PushbackInputStream
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.URI
import java.util.Locale
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class LocalProxyForwarder(
    private val remoteProtocol: String,
    private val remoteHost: String,
    private val remotePort: Int,
    private val localPort: Int,
    private val listener: Listener,
    private val socketProtector: ((Socket) -> Unit)? = null,
) {
    interface Listener {
        fun onTraffic(uploadedBytes: Long, downloadedBytes: Long)
        fun onLog(message: String)
    }

    @Volatile
    private var running = false
    private var serverSocket: ServerSocket? = null
    private val executor = Executors.newCachedThreadPool()

    fun start() {
        if (running) {
            return
        }
        running = true
        executor.execute { serve() }
    }

    fun stop() {
        running = false
        runCatching { serverSocket?.close() }
        serverSocket = null
        executor.shutdownNow()
    }

    private fun serve() {
        runCatching {
            ServerSocket().use { socket ->
                socket.reuseAddress = true
                socket.bind(InetSocketAddress(LOCAL_HOST, localPort))
                serverSocket = socket
                listener.onLog("Local proxy listening on $LOCAL_HOST:$localPort")
                while (running) {
                    val client = socket.accept()
                    executor.execute { handleClient(client) }
                }
            }
        }.onFailure { error ->
            if (running) {
                listener.onLog("Local proxy stopped: ${error.message}")
            }
        }
    }

    private fun handleClient(client: Socket) {
        runCatching {
            client.tcpNoDelay = true
            client.use {
                val input = PushbackInputStream(it.getInputStream(), 1)
                val first = input.readChecked()
                input.unread(first)
                if (first == SOCKS5_VERSION) {
                    handleSocks5Client(it, input)
                } else {
                    handleHttpClient(it, input)
                }
            }
        }.onFailure { error ->
            listener.onLog("Local proxy client closed: ${error.message}")
            runCatching { client.close() }
        }
    }

    private fun handleSocks5Client(client: Socket, input: InputStream) {
        val output = client.getOutputStream()
        if (input.readChecked() != SOCKS5_VERSION) {
            throw EOFException("Unsupported SOCKS version")
        }
        val methods = input.readChecked()
        input.skipFully(methods)
        output.write(byteArrayOf(SOCKS5_VERSION.toByte(), 0x00))
        output.flush()

        val version = input.readChecked()
        val command = input.readChecked()
        input.readChecked()
        val addressType = input.readChecked()
        if (version != SOCKS5_VERSION || command != SOCKS5_CONNECT) {
            output.write(byteArrayOf(0x05, 0x07, 0x00, 0x01, 0, 0, 0, 0, 0, 0))
            output.flush()
            return
        }
        val host = when (addressType) {
            0x01 -> InetAddress.getByAddress(input.readBytesExact(4)).hostAddress
            0x03 -> String(input.readBytesExact(input.readChecked()))
            0x04 -> InetAddress.getByAddress(input.readBytesExact(16)).hostAddress
            else -> throw EOFException("Unknown SOCKS address type")
        }
        val targetPort = input.readPort()
        val remote = connectRemoteProxy(host, targetPort)
        output.write(byteArrayOf(0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0))
        output.flush()
        remote.use { relay(client, it) }
    }

    private fun handleHttpClient(client: Socket, input: InputStream) {
        val output = client.getOutputStream()
        val header = input.readHttpHeader()
        val lines = header.split("\r\n").filter { it.isNotEmpty() }
        val firstLine = lines.firstOrNull() ?: throw EOFException("Empty HTTP request")
        val firstParts = firstLine.split(" ")
        if (firstParts.size < 3) {
            throw EOFException("Malformed HTTP request")
        }

        if (firstParts[0].equals("CONNECT", ignoreCase = true)) {
            val (host, targetPort) = parseHostPort(firstParts[1], 443)
            val remote = connectRemoteProxy(host, targetPort)
            output.write("HTTP/1.1 200 Connection Established\r\n\r\n".toByteArray())
            output.flush()
            remote.use { relay(client, it) }
            return
        }

        val uri = URI(firstParts[1])
        val hostHeader = lines.firstOrNull { it.startsWith("Host:", ignoreCase = true) }
            ?.substringAfter(':')
            ?.trim()
        val host = uri.host ?: hostHeader?.substringBefore(':')
            ?: throw EOFException("Missing HTTP host")
        val targetPort = if (uri.port > 0) {
            uri.port
        } else {
            hostHeader?.substringAfter(':', missingDelimiterValue = "")?.toIntOrNull() ?: 80
        }
        val path = buildString {
            append(if (uri.rawPath.isNullOrBlank()) "/" else uri.rawPath)
            if (!uri.rawQuery.isNullOrBlank()) {
                append('?')
                append(uri.rawQuery)
            }
        }
        val rebuiltHeader = buildString {
            append(firstParts[0])
            append(' ')
            append(path)
            append(' ')
            append(firstParts[2])
            append("\r\n")
            lines.drop(1)
                .filterNot { it.startsWith("Proxy-Connection:", ignoreCase = true) }
                .forEach {
                    append(it)
                    append("\r\n")
                }
            append("\r\n")
        }
        val remote = connectRemoteProxy(host, targetPort)
        remote.getOutputStream().write(rebuiltHeader.toByteArray())
        remote.getOutputStream().flush()
        remote.use { relay(client, it) }
    }

    private fun connectRemoteProxy(targetHost: String, targetPort: Int): Socket {
        val remote = Socket()
        remote.tcpNoDelay = true
        socketProtector?.invoke(remote)
        remote.connect(InetSocketAddress(remoteHost, remotePort), CONNECT_TIMEOUT_MS)
        if (remoteProtocol.lowercase(Locale.US) == "http") {
            val output = remote.getOutputStream()
            val input = remote.getInputStream()
            output.write(
                "CONNECT $targetHost:$targetPort HTTP/1.1\r\nHost: $targetHost:$targetPort\r\nProxy-Connection: keep-alive\r\n\r\n"
                    .toByteArray(),
            )
            output.flush()
            val response = input.readHttpHeader()
            if (!response.startsWith("HTTP/1.1 200") && !response.startsWith("HTTP/1.0 200")) {
                remote.close()
                throw EOFException("Remote HTTP proxy refused $targetHost:$targetPort")
            }
        } else {
            val output = remote.getOutputStream()
            val input = remote.getInputStream()
            output.write(byteArrayOf(0x05, 0x01, 0x00))
            output.flush()
            val version = input.readChecked()
            val method = input.readChecked()
            if (version != 0x05 || method != 0x00) {
                remote.close()
                throw EOFException("Remote SOCKS5 auth refused")
            }
            val hostBytes = targetHost.toByteArray()
            output.write(byteArrayOf(0x05, 0x01, 0x00, 0x03, hostBytes.size.toByte()))
            output.write(hostBytes)
            output.write(byteArrayOf((targetPort shr 8).toByte(), targetPort.toByte()))
            output.flush()
            val reply = input.readBytesExact(10)
            if (reply[1].toInt() != 0x00) {
                remote.close()
                throw EOFException("Remote SOCKS5 refused $targetHost:$targetPort")
            }
        }
        return remote
    }

    private fun relay(client: Socket, remote: Socket) {
        val latch = CountDownLatch(2)
        executor.execute {
            copyPipe(
                input = client.getInputStream(),
                output = remote.getOutputStream(),
                uploaded = true,
                done = latch,
            )
        }
        executor.execute {
            copyPipe(
                input = remote.getInputStream(),
                output = client.getOutputStream(),
                uploaded = false,
                done = latch,
            )
        }
        latch.await(RELAY_IDLE_SECONDS, TimeUnit.SECONDS)
    }

    private fun copyPipe(
        input: InputStream,
        output: OutputStream,
        uploaded: Boolean,
        done: CountDownLatch,
    ) {
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        try {
            while (running) {
                val read = input.read(buffer)
                if (read <= 0) {
                    break
                }
                output.write(buffer, 0, read)
                output.flush()
                if (uploaded) {
                    listener.onTraffic(read.toLong(), 0)
                } else {
                    listener.onTraffic(0, read.toLong())
                }
            }
        } catch (_: Exception) {
        } finally {
            done.countDown()
        }
    }

    private fun parseHostPort(value: String, defaultPort: Int): Pair<String, Int> {
        val host = value.substringBefore(':')
        val targetPort = value.substringAfter(':', "").toIntOrNull() ?: defaultPort
        return host to targetPort
    }

    private fun InputStream.readChecked(): Int {
        val value = read()
        if (value < 0) {
            throw EOFException()
        }
        return value
    }

    private fun InputStream.readBytesExact(count: Int): ByteArray {
        val bytes = ByteArray(count)
        var offset = 0
        while (offset < count) {
            val read = read(bytes, offset, count - offset)
            if (read < 0) {
                throw EOFException()
            }
            offset += read
        }
        return bytes
    }

    private fun InputStream.skipFully(count: Int) {
        var remaining = count
        while (remaining > 0) {
            val skipped = skip(remaining.toLong()).toInt()
            if (skipped <= 0) {
                readChecked()
                remaining--
            } else {
                remaining -= skipped
            }
        }
    }

    private fun InputStream.readPort(): Int {
        return (readChecked() shl 8) or readChecked()
    }

    private fun InputStream.readHttpHeader(): String {
        val buffer = ByteArrayOutputStream()
        var matched = 0
        while (buffer.size() < MAX_HEADER_BYTES) {
            val next = readChecked()
            buffer.write(next)
            matched = when {
                matched == 0 && next == '\r'.code -> 1
                matched == 1 && next == '\n'.code -> 2
                matched == 2 && next == '\r'.code -> 3
                matched == 3 && next == '\n'.code -> return buffer.toString()
                next == '\r'.code -> 1
                else -> 0
            }
        }
        throw EOFException("HTTP header too large")
    }

    companion object {
        const val LOCAL_HOST = "127.0.0.1"
        const val DEFAULT_LOCAL_PORT = 3781
        private const val SOCKS5_VERSION = 0x05
        private const val SOCKS5_CONNECT = 0x01
        private const val CONNECT_TIMEOUT_MS = 10_000
        private const val RELAY_IDLE_SECONDS = 300L
        private const val MAX_HEADER_BYTES = 64 * 1024
    }
}
