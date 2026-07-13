import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
val releaseKeystoreFile =
    keystoreProperties["storeFile"]?.toString()?.let { file(it) }

// Strip every ABI but arm64 — but only when building a release artifact.
//
// Every 64-bit Android phone of the last decade is arm64-v8a, so nothing a
// referee holds is affected, and it halves the download. Debug builds keep all
// ABIs on purpose: filtering them would break an x86_64 emulator at runtime,
// with an UnsatisfiedLinkError and no hint as to why.
val releaseOnlyArm64 = gradle.startParameter.taskNames.any {
    it.contains("Release", ignoreCase = true)
}

android {
    namespace = "com.grunch.choke"
    compileSdk = flutter.compileSdkVersion
    // Pinned rather than inherited from `flutter.ndkVersion`: Cargokit builds
    // the Rust crate through the NDK, and CI installs this exact version by
    // reading it back from this line. A Flutter upgrade that moved the NDK
    // underneath us would otherwise break the build with a bare NPE.
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.grunch.choke"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Release ships one architecture; see `releaseOnlyArm64` above.
        //
        // `flutter build apk --target-platform android-arm64` only narrows
        // Flutter's own libraries. It does not stop Cargokit from building the
        // Rust crate for every Android ABI — that is what this reaches.
        if (releaseOnlyArm64) {
            ndk {
                abiFilters += "arm64-v8a"
            }
        }
    }

    // `abiFilters` does not reach native code that arrives *prebuilt* inside a
    // plugin's AAR: ML Kit's barcode scanner (the QR reader on the Account
    // screen) was still shipping 8.8 MB of x86_64 and armeabi-v7a libraries in
    // every release. Nothing on an arm64 phone will ever load them.
    packaging {
        jniLibs {
            if (releaseOnlyArm64) {
                excludes += setOf(
                    "**/x86/**",
                    "**/x86_64/**",
                    "**/armeabi-v7a/**",
                )
            }
        }
    }

    signingConfigs {
        create("release") {
            if (releaseKeystoreFile?.exists() == true) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = releaseKeystoreFile
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (releaseKeystoreFile?.exists() == true) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
