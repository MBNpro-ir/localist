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

class LocalistProxyServer(
    protocolPorts: Map<String, Int>,
    private val bindAddresses: Set<String> = emptySet(),
    private val listener: Listener,
) {
    interface Listener {
        fun onTraffic(uploadedBytes: Long, downloadedBytes: Long)
        fun onLog(message: String)
    }

    @Volatile
    private var running = false
    private val serverSockets = mutableListOf<ServerSocket>()
    private val executor = Executors.newCachedThreadPool()
    private val protocolPorts = protocolPorts
        .mapKeys { it.key.lowercase(Locale.US) }
        .filterKeys { it in SUPPORTED_PROTOCOLS }
        .ifEmpty { mapOf("socks5" to 3075) }
    private val protocols = this.protocolPorts.keys
        .map { it.lowercase(Locale.US) }
        .filter { it in SUPPORTED_PROTOCOLS }
        .toSet()

    fun start() {
        if (running) {
            return
        }
        running = true
        val addresses = bindAddresses.ifEmpty { setOf("0.0.0.0") }
        for ((protocol, port) in protocolPorts) {
            for (address in addresses) {
                executor.execute { serve(protocol, address, port) }
            }
        }
    }

    fun stop() {
        running = false
        synchronized(serverSockets) {
            for (socket in serverSockets) {
                runCatching { socket.close() }
            }
            serverSockets.clear()
        }
        executor.shutdownNow()
    }

    private fun serve(protocol: String, bindAddress: String, port: Int) {
        runCatching {
            ServerSocket().use { socket ->
                synchronized(serverSockets) { serverSockets.add(socket) }
                socket.reuseAddress = true
                socket.bind(InetSocketAddress(bindAddress, port))
                listener.onLog("${protocol.uppercase(Locale.US)} proxy listening on $bindAddress:$port")
                while (running) {
                    val client = socket.accept()
                    executor.execute { handleClient(protocol, client) }
                }
            }
        }.onFailure { error ->
            if (running) {
                listener.onLog("Proxy listener on $bindAddress:$port stopped: ${error.message}")
            }
        }
    }

    private fun handleClient(protocol: String, client: Socket) {
        runCatching {
            client.tcpNoDelay = true
            client.use {
                val input = PushbackInputStream(it.getInputStream(), 1)
                when (protocol) {
                    "http" -> handleHttp(it, input)
                    else -> handleSocks5(it, input)
                }
            }
        }.onFailure { error ->
            listener.onLog("Client connection closed: ${error.message}")
            runCatching { client.close() }
        }
    }

    private fun handleSocks5(client: Socket, input: InputStream) {
        val output = client.getOutputStream()
        if (input.readChecked() != 0x05) {
            throw EOFException("Unsupported SOCKS version")
        }
        val methods = input.readChecked()
        input.skipFully(methods)
        output.write(byteArrayOf(0x05, 0x00))
        output.flush()

        val version = input.readChecked()
        val command = input.readChecked()
        input.readChecked()
        val addressType = input.readChecked()
        if (version != 0x05 || command != 0x01) {
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
        Socket().use { remote ->
            remote.tcpNoDelay = true
            remote.connect(InetSocketAddress(host, targetPort), CONNECT_TIMEOUT_MS)
            output.write(byteArrayOf(0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0))
            output.flush()
            relay(client, remote)
        }
    }

    private fun handleHttp(client: Socket, input: InputStream) {
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
            Socket().use { remote ->
                remote.connect(InetSocketAddress(host, targetPort), CONNECT_TIMEOUT_MS)
                output.write("HTTP/1.1 200 Connection Established\r\n\r\n".toByteArray())
                output.flush()
                relay(client, remote)
            }
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

        Socket().use { remote ->
            remote.connect(InetSocketAddress(host, targetPort), CONNECT_TIMEOUT_MS)
            remote.getOutputStream().write(rebuiltHeader.toByteArray())
            remote.getOutputStream().flush()
            relay(client, remote)
        }
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
        private const val CONNECT_TIMEOUT_MS = 10_000
        private const val RELAY_IDLE_SECONDS = 300L
        private const val MAX_HEADER_BYTES = 64 * 1024
        private val SUPPORTED_PROTOCOLS = setOf("http", "socks5")

        fun validateBindings(
            protocolPorts: Map<String, Int>,
            bindAddresses: List<String>,
        ): String? {
            val normalized = protocolPorts
                .mapKeys { it.key.lowercase(Locale.US) }
                .filterKeys { it in SUPPORTED_PROTOCOLS }
            val duplicatePort = normalized.values
                .groupingBy { it }
                .eachCount()
                .entries
                .firstOrNull { it.value > 1 }
                ?.key
            if (duplicatePort != null) {
                return "Port $duplicatePort is assigned to more than one protocol."
            }
            val addresses = bindAddresses.ifEmpty { listOf("0.0.0.0") }
            for ((protocol, port) in normalized) {
                if (port !in 1024..65535) {
                    return "${protocol.uppercase(Locale.US)} port $port is outside the allowed range."
                }
                for (address in addresses) {
                    val ok = runCatching {
                        ServerSocket().use { socket ->
                            socket.reuseAddress = true
                            socket.bind(InetSocketAddress(address, port))
                        }
                    }.isSuccess
                    if (!ok) {
                        return "${protocol.uppercase(Locale.US)} cannot bind $address:$port."
                    }
                }
            }
            return null
        }
    }
}
