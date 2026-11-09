import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.d2048"
    compileSdk = flutter.compileSdkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.d2048"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // 只打 arm64：通用 APK 會多塞 armeabi-v7a 與 x86_64 兩份引擎庫（與 dNeko 同）。
        // 要裝舊 32 位機或 x86 模擬器時再放開，並同步拿掉 CI 的 --target-platform。
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // 與 dNeko／dHealth 同一套：金鑰與密碼不進版控（android/.gitignore 已擋 *.keystore、key.properties）。
        // 開發機放 android/app/{d2048.keystore,key.properties}，CI 由 secrets KEYSTORE_B64 / KEY_PROPERTIES 還原。
        // 沒有 key.properties 就退回 debug 簽章，fork 與沒設 secret 的 CI 照样能出 release。
        // ⚠️ 但 debug 簽章每台 runner 現生一把 → 每版簽名不同，只能砍掉重裝；要正式發版前先準備 keystore。
        // key.properties 四行（storeFile 是相對 android/app/ 的路徑）；PKCS12 的 keyPassword 請填與 storePassword 同值。
        val propsFile = file("key.properties")
        if (propsFile.exists()) {
            create("release") {
                val props = Properties().apply { propsFile.inputStream().use { load(it) } }
                storeFile = file(props.getProperty("storeFile"))
                storePassword = props.getProperty("storePassword")
                keyAlias = props.getProperty("keyAlias")
                keyPassword = props.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
