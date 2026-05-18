package com.prs.localist

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import java.io.PrintWriter
import java.io.StringWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

object LocalistCrashReporter {
    private const val SUPPORT_EMAIL = "support@prs.localist"

    fun install(context: Context) {
        val appContext = context.applicationContext
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        if (previous is LocalistExceptionHandler) {
            return
        }
        Thread.setDefaultUncaughtExceptionHandler(
            LocalistExceptionHandler(appContext, previous),
        )
    }

    private class LocalistExceptionHandler(
        private val context: Context,
        private val previous: Thread.UncaughtExceptionHandler?,
    ) : Thread.UncaughtExceptionHandler {
        override fun uncaughtException(thread: Thread, throwable: Throwable) {
            runCatching {
                openCrashEmail(context, thread, throwable)
            }
            previous?.uncaughtException(thread, throwable)
        }
    }

    private fun openCrashEmail(context: Context, thread: Thread, throwable: Throwable) {
        val body = buildCrashBody(context, thread, throwable)
        val intent = Intent(Intent.ACTION_SENDTO).apply {
            data = Uri.parse("mailto:$SUPPORT_EMAIL")
            putExtra(Intent.EXTRA_EMAIL, arrayOf(SUPPORT_EMAIL))
            putExtra(Intent.EXTRA_SUBJECT, "Localist Android crash report")
            putExtra(Intent.EXTRA_TEXT, body)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
    }

    private fun buildCrashBody(context: Context, thread: Thread, throwable: Throwable): String {
        val packageInfo = context.packageManager.getPackageInfo(context.packageName, 0)
        val stack = StringWriter().also { writer ->
            throwable.printStackTrace(PrintWriter(writer))
        }.toString()
        return buildString {
            appendLine("Localist Android crash report")
            appendLine("==============================")
            appendLine("Time: ${timestamp()}")
            appendLine("Thread: ${thread.name}")
            appendLine("Package: ${context.packageName}")
            appendLine("Version: ${packageInfo.versionName ?: "unknown"}")
            appendLine("Version code: ${versionCode(packageInfo)}")
            appendLine("Android SDK: ${Build.VERSION.SDK_INT}")
            appendLine("Android release: ${Build.VERSION.RELEASE}")
            appendLine("Device: ${Build.MANUFACTURER} ${Build.MODEL}")
            appendLine("Brand/Product: ${Build.BRAND} / ${Build.PRODUCT}")
            appendLine("ABIs: ${Build.SUPPORTED_ABIS.joinToString()}")
            appendLine()
            appendLine("Crash")
            appendLine("-----")
            appendLine(stack)
            appendLine()
            appendLine("Recent logcat")
            appendLine("-------------")
            appendLine(readLogcat())
        }
    }

    private fun timestamp(): String {
        return SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSSZ", Locale.US).format(Date())
    }

    private fun versionCode(packageInfo: android.content.pm.PackageInfo): Long {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            packageInfo.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            packageInfo.versionCode.toLong()
        }
    }

    private fun readLogcat(): String {
        return runCatching {
            val process = Runtime.getRuntime().exec(arrayOf("logcat", "-d", "-t", "250"))
            process.inputStream.bufferedReader().use { it.readText() }
        }.getOrDefault("Logcat unavailable.")
    }
}
