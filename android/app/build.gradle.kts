import com.google.firebase.crashlytics.buildtools.gradle.CrashlyticsExtension
import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Upload key for Play Console builds, from android/key.properties (git-ignored,
// never committed). See docs/RELEASING.md.
val keystoreProperties =
    Properties().apply {
        val file = rootProject.file("key.properties")
        if (file.exists()) FileInputStream(file).use { load(it) }
    }
val hasUploadKey = !keystoreProperties.isEmpty

android {
    namespace = "club.buildd.synk"
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
        applicationId = "club.buildd.synk"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasUploadKey) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Without key.properties, fall back to the debug key so
            // `flutter run --release` still works locally. Play Console rejects
            // debug-signed bundles, so scripts/build_release.sh requires the key.
            signingConfig = signingConfigs.getByName(if (hasUploadKey) "release" else "debug")
            // The R8 mapping (readable Android traces in Crashlytics) is uploaded
            // by scripts/build_release.sh after the build, so a flaky network
            // can't fail a release. CRASHLYTICS_UPLOAD=1 uploads during the build.
            configure<CrashlyticsExtension> {
                mappingFileUploadEnabled = System.getenv("CRASHLYTICS_UPLOAD") == "1"
            }
        }
    }
}

flutter {
    source = "../.."
}
