import java.util.Properties
import java.io.FileInputStream
import java.util.Base64

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing lives in android/key.properties (gitignored — never
// commit it). Falls back to null (and the debug key below) when it's
// missing, so a fresh clone without the keystore can still build/run.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

// Cleartext (http://) traffic is allowed ONLY when this build's
// API_BASE_URL dart-define is itself an http:// origin (local/LAN testing).
// HTTPS production builds keep Android's default cleartext block.
val dartDefines: List<String> = (project.findProperty("dart-defines") as String?)
    ?.split(",")
    ?.mapNotNull { encoded: String ->
        runCatching { String(Base64.getDecoder().decode(encoded)) }.getOrNull()
    }
    ?: emptyList()
val apiBaseUrl: String = dartDefines
    .firstOrNull { it.startsWith("API_BASE_URL=") }
    ?.removePrefix("API_BASE_URL=")
    ?: ""
val allowCleartext: Boolean = apiBaseUrl.startsWith("http://")

android {
    namespace = "com.example.taleem_plus"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.example.taleem_plus"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["usesCleartextTraffic"] = allowCleartext.toString()
    }

    signingConfigs {
        create("release") {
            val envKeystorePath = System.getenv("KEYSTORE_PATH")
            if (!envKeystorePath.isNullOrEmpty() && file(envKeystorePath).exists()) {
                storeFile = file(envKeystorePath)
                storePassword = System.getenv("KEYSTORE_PASSWORD") ?: ""
                keyAlias = System.getenv("KEY_ALIAS") ?: ""
                keyPassword = System.getenv("KEY_PASSWORD") ?: ""
            } else if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            val envKeystorePath = System.getenv("KEYSTORE_PATH")
            val hasReleaseSigning = (!envKeystorePath.isNullOrEmpty() && file(envKeystorePath).exists()) || keystorePropertiesFile.exists()
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }

            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

base {
    archivesName.set("Final_Year_Project-version-1")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
