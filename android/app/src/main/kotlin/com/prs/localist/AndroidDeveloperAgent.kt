package com.prs.localist

import android.content.Context
import android.content.pm.PackageManager
import android.app.ActivityManager
import android.os.Build
import android.security.KeyPairGeneratorSpec
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Log
import org.json.JSONObject
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.io.FileOutputStream
import java.math.BigInteger
import java.net.InetAddress
import java.net.ServerSocket
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.MessageDigest
import java.security.SecureRandom
import java.security.spec.ECGenParameterSpec
import java.util.Date
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import javax.net.ssl.KeyManagerFactory
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLServerSocket
import javax.net.ssl.SSLSocket
import javax.security.auth.x500.X500Principal

/** User-started, foreground-session Android Developer Agent. */
object AndroidDeveloperAgent {
    private const val TAG = "LocalistDevAgent"
    private const val KEY_ALIAS = "localist_developer_agent_tls_v2"
    private const val LEGACY_KEY_ALIAS = "localist_developer_agent_tls_v1"
    private const val LISTEN_PORT = 48291
    private const val MAX_FRAME = 1024 * 1024
    private const val MAX_APK_BYTES = 512L * 1024L * 1024L
    private const val PROTOCOL_VERSION = 1

    private val running = AtomicBoolean(false)
    private val badPairingAttempts = AtomicInteger(0)
    private val executor = Executors.newCachedThreadPool()
    @Volatile private var listener: SSLServerSocket? = null
    private val activeClient = AtomicReference<SSLSocket?>(null)
    @Volatile private var pairingCode = ""
    @Volatile private var pairingExpiry = 0L
    @Volatile private var eventCallback: ((Map<String, Any?>) -> Unit)? = null
    @Volatile private var listeningPort = 0
    @Volatile private var certificateFingerprint = ""

    @Synchronized
    fun start(context: Context, onEvent: (Map<String, Any?>) -> Unit): Map<String, Any> {
        if (running.get() && listener != null) return status()
        eventCallback = onEvent
        badPairingAttempts.set(0)
        val identity = loadOrCreateIdentity(context)
        certificateFingerprint = identity.second
        val ssl = SSLContext.getInstance("TLS")
        val keyManagers = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm())
        keyManagers.init(identity.first, null)
        ssl.init(keyManagers.keyManagers, null, SecureRandom())
        val socket = ssl.serverSocketFactory.createServerSocket(
            LISTEN_PORT,
            2,
            InetAddress.getByName("0.0.0.0"),
        ) as SSLServerSocket
        socket.enabledProtocols = socket.supportedProtocols.filter {
            it == "TLSv1.3" || it == "TLSv1.2"
        }.toTypedArray()
        listener = socket
        listeningPort = socket.localPort
        pairingCode = (SecureRandom().nextInt(100_000_000)).toString().padStart(8, '0')
        pairingExpiry = System.currentTimeMillis() + 10 * 60 * 1000L
        running.set(true)
        executor.execute { acceptLoop(context.applicationContext, socket) }
        emit(mapOf("type" to "started", "port" to listeningPort))
        return status()
    }

    @Synchronized
    fun stop() {
        running.set(false)
        activeClient.getAndSet(null)?.let { runCatching { it.close() } }
        listener?.let { runCatching { it.close() } }
        listener = null
        pairingCode = ""
        pairingExpiry = 0L
        emit(mapOf("type" to "stopped"))
        eventCallback = null
    }

    fun status(): Map<String, Any> = mapOf(
        "running" to running.get(),
        "port" to listeningPort,
        "pairingCode" to pairingCode,
        "pairingExpiresAt" to pairingExpiry,
        "certificateSha256" to certificateFingerprint,
    )

    fun verifyInstalledPackage(context: Context, packageName: String): Map<String, Any?> {
        if (!packageName.matches(Regex("^[A-Za-z0-9_]+(\\.[A-Za-z0-9_]+)+$"))) {
            return mapOf("installed" to false, "error" to "invalid_package_name")
        }
        val packageInfo = try {
            if (Build.VERSION.SDK_INT >= 33) {
                context.packageManager.getPackageInfo(
                    packageName,
                    PackageManager.PackageInfoFlags.of(0),
                )
            } else {
                @Suppress("DEPRECATION")
                context.packageManager.getPackageInfo(packageName, 0)
            }
        } catch (_: PackageManager.NameNotFoundException) {
            return mapOf("installed" to false, "packageName" to packageName)
        }
        val versionCode = if (Build.VERSION.SDK_INT >= 28) packageInfo.longVersionCode else packageInfo.versionCode.toLong()
        return mapOf(
            "installed" to true,
            "packageName" to packageName,
            "versionName" to (packageInfo.versionName ?: ""),
            "versionCode" to versionCode,
        )
    }

    fun processStatus(context: Context, packageName: String): Map<String, Any?> {
        val processes = context.getSystemService(ActivityManager::class.java)
            ?.runningAppProcesses
            .orEmpty()
        val matches = processes.filter { it.processName == packageName || it.processName.startsWith("$packageName:") }
        return when {
            matches.isNotEmpty() -> mapOf(
                "status" to "running",
                "processes" to matches.map { mapOf("name" to it.processName, "pid" to it.pid) },
            )
            else -> mapOf("status" to "not_running_or_not_visible", "processes" to emptyList<Map<String, Any>>())
        }
    }

    private fun loadOrCreateIdentity(context: Context): Pair<KeyStore, String> {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (!keyStore.containsAlias(KEY_ALIAS)) {
            val generator = KeyPairGenerator.getInstance(
                KeyProperties.KEY_ALGORITHM_EC,
                "AndroidKeyStore",
            )
            val notBefore = Date(System.currentTimeMillis() - 60_000)
            val notAfter = Date(System.currentTimeMillis() + 5L * 365 * 24 * 60 * 60 * 1000)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                generator.initialize(
                    KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_SIGN)
                        .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                        // JSSE computes the TLS transcript digest itself and
                        // asks Android Keystore to sign the pre-hashed value.
                        // Android's TLS guidance requires DIGEST_NONE here.
                        .setDigests(KeyProperties.DIGEST_NONE)
                        .setCertificateSubject(X500Principal("CN=Localist Developer Agent"))
                        .setCertificateSerialNumber(BigInteger.valueOf(System.currentTimeMillis()))
                        .setCertificateNotBefore(notBefore)
                        .setCertificateNotAfter(notAfter)
                        .build(),
                )
            } else {
                @Suppress("DEPRECATION")
                generator.initialize(
                    KeyPairGeneratorSpec.Builder(context)
                        .setAlias(KEY_ALIAS)
                        .setKeyType("EC")
                        .setKeySize(256)
                        .setSubject(X500Principal("CN=Localist Developer Agent"))
                        .setSerialNumber(BigInteger.valueOf(System.currentTimeMillis()))
                        .setStartDate(notBefore)
                        .setEndDate(notAfter)
                        .build(),
                )
            }
            generator.generateKeyPair()
            keyStore.load(null)
        }
        val cert = keyStore.getCertific