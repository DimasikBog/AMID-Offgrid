import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Development builds are explicit. Distribution builds must never fall back to a debug key.
val amidSigning = System.getenv("AMID_SIGNING") ?: "development"
require(amidSigning in setOf("development", "distribution")) { "Unknown AMID_SIGNING mode" }
val amidKeyProperties = Properties().apply {
    val source = rootProject.file("key.properties")
    if (source.isFile) source.inputStream().use { load(it) }
}
fun amidSigningValue(environment: String, property: String): String =
    (System.getenv(environment) ?: amidKeyProperties.getProperty(property))
        ?.takeIf { it.isNotBlank() }
        ?: error("Distribution signing requires $environment or android/key.properties:$property")

android {
    namespace = "com.amid.offgrid"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        ndk {
            abiFilters.clear()
            abiFilters.add("arm64-v8a")
        }
        applicationId = "com.amid.offgrid"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (amidSigning == "distribution") {
            create("distribution") {
                storeFile = rootProject.file(amidSigningValue("ANDROID_KEYSTORE_PATH", "storeFile"))
                require(storeFile!!.isFile) { "Distribution keystore file does not exist" }
                storePassword = amidSigningValue("ANDROID_KEYSTORE_PASSWORD", "storePassword")
                keyAlias = amidSigningValue("ANDROID_KEY_ALIAS", "keyAlias")
                keyPassword = amidSigningValue("ANDROID_KEY_PASSWORD", "keyPassword")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            isShrinkResources = false
            signingConfig = signingConfigs.getByName(
                if (amidSigning == "distribution") "distribution" else "debug"
            )
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
