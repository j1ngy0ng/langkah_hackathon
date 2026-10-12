import java.util.Base64

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val sandboxBuild = (project.findProperty("dart-defines") as? String).orEmpty()
    .split(',').filter { it.isNotEmpty() }.any {
        String(Base64.getDecoder().decode(it), Charsets.UTF_8) == "LANGKAH_SANDBOX=true"
    }

android {
    namespace = "com.example.langkah_hackathon"
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
        applicationId = "com.example.langkah_hackathon" + if (sandboxBuild) ".sandbox" else ""
        manifestPlaceholders["appLabel"] = if (sandboxBuild) "Langkah Sandbox" else "Langkah"
        manifestPlaceholders["authScheme"] = if (sandboxBuild) "langkah-sandbox" else "langkah"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        testInstrumentationRunner = "com.example.langkah_hackathon.LocationChecks"
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
