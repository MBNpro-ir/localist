allprojects {
    repositories {
        google()
        mavenCentral()
        maven("https://jitpack.io") {
            content { includeGroup("com.github.getActivity") }
        }
        maven(rootProject.file("../third_party/localist_remote/android/maven")) {
            metadataSources { artifact() }
            content { includeGroup("rustls") }
        }
        maven("https://maven.aliyun.com/repository/google") {
            name = "AliyunGoogleMirror"
            content {
                includeGroupByRegex("com\\.android(\\..*)?")
                includeGroupByRegex("androidx(\\..*)?")
                includeGroupByRegex("com\\.google\\.android(\\..*)?")
                includeGroupByRegex("com\\.google\\.mlkit(\\..*)?")
                includeGroupByRegex("com\\.google\\.firebase(\\..*)?")
                includeGroupByRegex("com\\.google\\.android\\.datatransport(\\..*)?")
            }
        }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
    afterEvaluate {
        // Older plugins still declare API 31/33; the shared engine's
        // AndroidX dependencies require the current compile SDK.
        extensions.findByType<com.android.build.gradle.LibraryExtension>()?.compileSdk = 37
        if (name == "flutter_webrtc") {
            // ConnectivityManager omits downstream USB/hotspot interfaces. Its
            // WebRTC monitor consequently drops rndis0 even when signaling over
            // that interface succeeds. Let native WebRTC enumerate/poll local
            // interfaces instead. Keep the pinned pub package/cache untouched.
            val library = extensions.getByType<com.android.build.api.dsl.LibraryExtension>()
            val original = file("src/main/java")
            val marker = "options.networkIgnoreMask = networkIgnoreMask;"
            val patched = layout.buildDirectory.dir("localist-java")
            val prepare = tasks.register<Sync>("prepareLocalistWebRtcLan") {
                inputs.property("localistLanPatch", 3)
                from(original)
                from(rootProject.file("LocalistAudioInput.java")) { into("com/cloudwebrtc/webrtc") }
                into(patched)
                doFirst {
                    check(original.resolve("com/cloudwebrtc/webrtc/MethodCallHandlerImpl.java")
                        .readText().split(marker).size == 2) {
                        "Pinned flutter_webrtc factory changed; review the Localist LAN patch"
                    }
                }
                filesMatching("com/cloudwebrtc/webrtc/MethodCallHandlerImpl.java") {
                    filter { line: String ->
                        if (line.trim() == marker)
                            "$line\n    options.disableNetworkMonitor = true;"
                        else if(line.contains("JavaAudioDeviceModule.builder(context);"))
                            "$line\n    audioDeviceModuleBuilder.setAudioBufferCallback(LocalistAudioInput.bridge);"
                        else if(line.contains("device.getType() == AudioDeviceInfo.TYPE_WIRED_HEADSET) {"))
                            line.replace("device.getType() == AudioDeviceInfo.TYPE_WIRED_HEADSET) {",
                              "device.getType() == AudioDeviceInfo.TYPE_WIRED_HEADSET || device.getType() == AudioDeviceInfo.TYPE_USB_DEVICE || device.getType() == AudioDeviceInfo.TYPE_USB_ACCESSORY || (Build.VERSION.SDK_INT >= 26 && device.getType() == AudioDeviceInfo.TYPE_USB_HEADSET) || (Build.VERSION.SDK_INT >= 31 && device.getType() == AudioDeviceInfo.TYPE_BLE_HEADSET)) {")
                        else line
                    }
                }
                filesMatching("com/cloudwebrtc/webrtc/audio/AudioUtils.java") {
                    filter { line: String -> line.replace(
                        "device.getType() == AudioDeviceInfo.TYPE_BLUETOOTH_SCO",
                        "(device.getType() == AudioDeviceInfo.TYPE_BLUETOOTH_SCO || (Build.VERSION.SDK_INT >= 31 && device.getType() == AudioDeviceInfo.TYPE_BLE_HEADSET))") }
                }
            }
            library.sourceSets.getByName("main").java.setSrcDirs(listOf(patched))
            tasks.named("preBuild").configure { dependsOn(prepare) }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
