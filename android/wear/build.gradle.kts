plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

kotlin { jvmToolchain(17) }

android {
    namespace = "com.amid.offgrid.wear"
    compileSdk = 36
    defaultConfig {
        applicationId = "com.amid.offgrid.wear"
        minSdk = 30
        targetSdk = 36
        versionCode = 7
        versionName = "0.5.0"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    sourceSets.getByName("main").assets.srcDir("../../wearables")
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
        }
    }
}
