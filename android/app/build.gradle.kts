plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.prs.localist"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.prs.localist"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    packaging {
        jniLibs {
            // Compress native prstun/hevtunnel libraries in APKs. Android extracts them
            // at install time, trading a little install time for a much smaller APK.
            useLegacyPackaging = true
        }
        resources {
            excludes += setOf(
                "META-INF/AL2.0",
                "META-INF/LGPL2.1",
                "META-INF/LICENSE*",
                "META-INF/NOTICE*",
                "META-INF/*.kotlin_module",
            )
        }
    }

    signingConfigs {
        create("localistRelease") {
            val releaseStoreFile =
                providers.environmentVariable("LOCALIST_UPLOAD_STORE_FILE").orNull
                    ?: "localist-upload.jks"
            storeFile = file(releaseStoreFile)
            storePassword =
                providers.environmentVariable("LOCALIST_KEYSTORE_PASSWORD").orNull
                    ?: "localist-update"
            keyAlias =
                providers.environmentVariable("LOCALIST_KEY_ALIAS").orNull
                    ?: "localist"
            keyPassword =
                providers.environmentVariable("LOCALIST_KEY_PASSWORD").orNull
                    ?: "localist-update"
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("localistRelease")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("com.zaneschepke:hevtunnel:1.0.1") {
        isTransitive = false
    }
}
