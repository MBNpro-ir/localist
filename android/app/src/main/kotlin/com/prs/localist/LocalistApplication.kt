package com.prs.localist

import android.app.Application
import ffi.FFI

/** Initializes JNI and certificate verification for both UI and boot services. */
class LocalistApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        FFI.onAppStart(applicationContext)
        RemoteReceivedFiles.start(applicationContext)
    }
}
