package com.prs.localist

import android.app.Instrumentation
import android.content.Context
import android.os.SystemClock
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

object CaptureServiceRegression {
    private class Reply : MethodChannel.Result {
        val done = CountDownLatch(1)
        var failure: String? = null
        override fun success(value: Any?) { done.countDown() }
        override fun error(code: String, message: String?, details: Any?) { failure = "$code: $message"; done.countDown() }
        override fun notImplemented() { failure = "notImplemented"; done.countDown() }
        fun await() { check(done.await(12, TimeUnit.SECONDS)) { "Service reply timed out" }; check(failure == null) { failure.orEmpty() } }
    }
    fun verify(context: Context, instrumentation: Instrumentation) {
        repeat(5) {
            val start = Reply()
            instrumentation.runOnMainSync { CaptureForegroundService.requestStart(context, true, true, start) }
            start.await()
            val stop = Reply()
            instrumentation.runOnMainSync { CaptureForegroundService.requestStop(context, stop) }
            stop.await()
        }
        val start = Reply(); val stop = Reply()
        instrumentation.runOnMainSync {
            CaptureForegroundService.requestStart(context, true, true, start)
            CaptureForegroundService.requestStop(context, stop)
        }
        start.await(); stop.await()
        SystemClock.sleep(6000) // Catch Android's deferred foreground-service deadline.
    }
}
