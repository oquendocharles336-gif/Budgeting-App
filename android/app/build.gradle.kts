plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.budgeting.bugeting_app"
    // flutter_local_notifications 23 needs compileSdk 37 or higher.
    compileSdk = maxOf(flutter.compileSdkVersion, 37)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Needed by flutter_local_notifications (java.time on older Android).
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.budgeting.bugeting_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Android 7.0+, required by local_auth 3 and flutter_local_notifications 21+.
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            // Keep SQLCipher's native bindings when R8 shrinks the release build.
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
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

// ---------------------------------------------------------------------------
// Pitaka.apk
//
// `flutter build apk --release` leaves the APK as
//   build/app/outputs/flutter-apk/app-release.apk
// The Flutter tool itself looks for that exact name (and fails if it's
// missing), so the APK can't simply be renamed with `outputFileName`.
// Instead, right after the release build, this copies it next to it as
//   build/app/outputs/flutter-apk/Pitaka.apk
// (with --split-per-abi: Pitaka-arm64-v8a.apk, Pitaka-armeabi-v7a.apk, ...).
// No rename command needed.
// ---------------------------------------------------------------------------
val pitakaApk = tasks.register("pitakaApk") {
    group = "build"
    description = "Copies the release APK in build/app/outputs/flutter-apk to Pitaka.apk."
    val apkDir = layout.buildDirectory.dir("outputs/flutter-apk")
    // A quick copy: always run it, so Pitaka.apk is never older than the build.
    outputs.upToDateWhen { false }
    doLast {
        val dir = apkDir.get().asFile
        // app-release.apk, or app-<abi>-release.apk with --split-per-abi.
        val releaseApk = Regex("""app(-.+)?-release\.apk""")
        val built = dir.listFiles().orEmpty().filter { releaseApk.matches(it.name) }
        if (built.isEmpty()) throw GradleException("No release APK found in $dir")
        for (apk in built) {
            val suffix = releaseApk.matchEntire(apk.name)!!.groupValues[1]
            val target = File(dir, "Pitaka$suffix.apk")
            apk.copyTo(target, overwrite = true)
            logger.lifecycle("Pitaka APK: ${target.path}")
        }
    }
}

// Runs after assembleRelease, which is what `flutter build apk --release`
// calls, once Flutter has copied the APK into flutter-apk.
tasks.configureEach {
    if (name == "assembleRelease") finalizedBy(pitakaApk)
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // Theme.AppCompat for the biometric prompt (local_auth).
    implementation("androidx.appcompat:appcompat:1.7.1")
}
