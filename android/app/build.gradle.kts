plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.lumina.lumina"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // handy_tdlib_next also ships x86 / armeabi-v7a; keep only the ABIs
        // this app targets (arm64 devices, x86_64 emulators). `flutter build
        // apk --split-per-abi` sets its own ABI splits, which Gradle refuses
        // to combine with ndk.abiFilters.
        if (!project.hasProperty("split-per-abi")) {
            ndk {
                abiFilters += listOf("arm64-v8a", "x86_64")
            }
        }
        applicationId = "dev.lumina.lumina"
        // 24, not 21: whisper_edge builds whisper.cpp with minSdk 24, which sets
        // the floor for the whole app. See docs/DECISIONS.md (D2).
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    packaging {
        jniLibs {
            // libVLC and ffmpeg-kit both bundle the NDK C++ runtime.
            pickFirsts += "lib/**/libc++_shared.so"
        }
    }

    androidResources {
        // Bundled models are already incompressible; storing them uncompressed
        // makes first-use extraction a straight copy.
        noCompress += listOf("bin", "gguf")
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
