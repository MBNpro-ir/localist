package com.prs.localist

import com.carriez.flutter_hbb.MainApplication

/** Initializes JNI and certificate verification for both UI and boot services. */
class LocalistApplication : MainApplication() {
    override fun onCreate() {
        super.onCreate()
        RemoteReceivedFiles.start(applicationContext)
    }
}
