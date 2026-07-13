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

            // Release ships one architecture. `flutter build apk
            // --target-platform android-arm64` only narrows Flutter's own
            // libraries — it does not stop Cargokit from building the Rust
            // crate for every Android ABI. This does.
            //
            // Debug keeps every ABI on purpose: filtering it would break an
            // x86_64 emulator at runtime, with an UnsatisfiedLinkError and no
            // hint as to why.
            ndk {
                abiFilters += "arm64-v8a"
            }
        }
    }
}

// `abiFilters` above does not reach native code that arrives *prebuilt* inside
// a plugin's AAR: ML Kit's barcode scanner (the QR reader on the Account
// screen) was still shipping 8.8 MB of x86_64 and armeabi-v7a libraries in
// every release. Nothing on an arm64 phone will ever load them.
//
// Scoped to the release variant, not to the Gradle invocation. Keying off the
// task names would flip this on for debug too the moment anything built both in
// one run (`gradle build` does), and the emulator would break for reasons the
// build output would never explain.
androidComponents {
    onVariants(selector().withBuildType("release")) { variant ->
        variant.packaging.jniLibs.excludes.addAll(
            "**/x86/**",
            "**/x86_64/**",
            "**/armeabi-v7a/**",
        )
    }
}

flutter {
    source = "../.."
}
