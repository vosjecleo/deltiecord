import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val signingProperties = Properties()
val signingPropertiesFile = rootProject.file("key.properties")
if (signingPropertiesFile.exists()) {
    signingPropertiesFile.inputStream().use(signingProperties::load)
}
val releaseStoreFile = System.getenv("DELTIECORD_ANDROID_KEYSTORE")
    ?: signingProperties.getProperty("storeFile")
val releaseStorePassword = System.getenv("DELTIECORD_ANDROID_STORE_PASSWORD")
    ?: signingProperties.getProperty("storePassword")
val releaseKeyAlias = System.getenv("DELTIECORD_ANDROID_KEY_ALIAS")
    ?: signingProperties.getProperty("keyAlias")
val releaseKeyPassword = System.getenv("DELTIECORD_ANDROID_KEY_PASSWORD")
    ?: signingProperties.getProperty("keyPassword")
val hasReleaseSigning = listOf(
    releaseStoreFile,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
).all { !it.isNullOrBlank() }

android {
    namespace = "net.deltie.deltiecord"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "net.deltie.deltiecord"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("deltiecordRelease") {
                storeFile = file(releaseStoreFile!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            // Stable update signatures come from an untracked key.properties
            // file or CI secrets. Debug signing remains a development fallback
            // only; release packaging verifies that real signing is present.
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("deltiecordRelease")
            } else {
                signingConfigs.getByName("debug")
            }
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    implementation("org.unifiedpush.android:connector:3.3.3") {
        // flutter_secure_storage already supplies the Android Tink artifact.
        // Both artifacts contain the same core classes, so including the
        // connector's JVM Tink dependency makes D8 reject the application.
        exclude(group = "com.google.crypto.tink", module = "tink")
    }
}
