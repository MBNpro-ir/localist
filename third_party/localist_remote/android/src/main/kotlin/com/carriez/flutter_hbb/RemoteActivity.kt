package com.carriez.flutter_hbb

/** Second Flutter entry point in the same Localist application and native engine. */
class RemoteActivity : MainActivity() {
    override fun getDartEntrypointFunctionName(): String = "remoteMain"
}
