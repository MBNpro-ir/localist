package com.prs.localist

import com.carriez.flutter_hbb.MainApplication
import com.carriez.flutter_hbb.LocalistNotifications

/** Initializes JNI and certificate verification for both UI and boot services. */
class LocalistApplication : MainApplication() {
    override fun onCreate() {
        super.onCreate()
        LocalistNotifications.initialize(this)
        RemoteReceivedFiles.start(applicationContext)
    }
}
