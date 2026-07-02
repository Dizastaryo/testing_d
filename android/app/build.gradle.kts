plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.my_app"
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
        applicationId = "com.example.my_app"
        // ARCore requires minSdk 24
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    // TEMP: ARCore + Sceneform 3D face masks disabled for this build — the
    // sceneform community fork (1.17.1) pulls legacy com.android.support
    // (AndroidX conflict) and no longer compiles. ARFaceMaskViewFactory is
    // stubbed. Restore these + the real renderer once Sceneform is pinned.
    // implementation("com.google.ar:core:1.44.0")
    // implementation("com.google.ar.sceneform.ux:sceneform-ux:1.17.1")
    // implementation("com.google.ar.sceneform:assets:1.17.1")
}

flutter {
    source = "../.."
}
