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

    // Two builds: `full` bundles the on-device LLM (SmolLM2 + llama.cpp),
    // `lite` leaves it out. Whisper (speech) is in both. Build with
    // `--flavor full` or `--flavor lite`; Dart reads it via appFlavor
    // (lib/core/build/build_flavor.dart), the model asset is flavor-scoped in
    // pubspec.yaml, and lite's llama.cpp libraries are stripped below.
    flavorDimensions += "ai"
    productFlavors {
        create("full") {
            dimension = "ai"
            isDefault = true
        }
        create("lite") {
            dimension = "ai"
            versionNameSuffix = "-lite"
        }
    }

    packaging {
        jniLibs {
            // libVLC and ffmpeg-kit both bundle the NDK C++ runtime.
            pickFirsts += "lib/**/libc++_shared.so"
        }
    }

    sourceSets {
        getByName("main") {
            // Calls engine Java side (Telegram-Android's org.webrtc, GPL; see
            // docs/DECISIONS.md D14) and stand-ins for the Telegram helpers it uses.
            java.srcDirs("../calls-engine/java", "../calls-engine/java-shims")
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
            // JNI-bound classes of the calls engine.
            proguardFiles("calls-rules.pro")
            // JNI-bound classes of libVLC (video playback).
            proguardFiles("media-rules.pro")
            proguardFiles("proguard-rules.pro")
        }
    }
}

// llamadart's native libraries (whisper_edge links whisper.cpp statically and
// needs none of them).
androidComponents {
    onVariants(selector().withFlavor("ai" to "lite")) { variant ->
        variant.packaging.jniLibs.excludes.addAll(
            listOf(
                "lib/*/libllama*.so",
                "lib/*/libggml*.so",
                "lib/*/libmtmd.so",
                "lib/*/libLiteRt*.so",
                "lib/*/libGemmaModelConstraintProvider.so",
                "lib/*/libwebgpu_dawn.so",
            ),
        )
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
    // The vendored org.webrtc sources use its annotations.
    implementation("androidx.annotation:annotation:1.9.1")
    // Message notifications (MessagingStyle, inline reply) and the
    // battery-saver sync (no Firebase; see docs/AGENT_HANDOFF.md §2.3 G).
    implementation("androidx.core:core:1.16.0")
    implementation("androidx.work:work-runtime:2.10.5")
}

// TDLib must be in the APK: without it the app starts but never connects.
// Fails the build when libtdjson.so is missing for a targeted ABI or isn't
// the pinned release (packages/lumina_tdlib/schema/VERSION).
val checkTdlib by tasks.registering {
    val root = rootProject.projectDir.parentFile
    val version = File(root, "packages/lumina_tdlib/schema/VERSION").readLines()
        .first { it.startsWith("version=") }.removePrefix("version=")
    val abis = when (val target = findProperty("target-platform") as String?) {
        null -> listOf("arm64-v8a", "x86_64")
        else -> target.split(",").mapNotNull {
            mapOf("android-arm64" to "arm64-v8a", "android-x64" to "x86_64", "android-arm" to "armeabi-v7a")[it]
        }
    }
    val libs = abis.map { File(projectDir, "src/main/jniLibs/$it/libtdjson.so") }
    doLast {
        for (lib in libs) {
            if (!lib.isFile) {
                throw GradleException("$lib is missing: run tool/build_tdlib.sh ${lib.parentFile.name} and copy it there")
            }
            if (!String(lib.readBytes(), Charsets.ISO_8859_1).contains(version)) {
                throw GradleException("$lib is not TDLib $version: rebuild it with tool/build_tdlib.sh")
            }
        }
    }
}
tasks.named("preBuild") { dependsOn(checkTdlib) }
