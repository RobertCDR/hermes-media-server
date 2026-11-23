import java.io.File
import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

fun signingValue(propKey: String, envKey: String): String? {
    val propVal = keystoreProperties.getProperty(propKey)?.trim()
    if (!propVal.isNullOrEmpty()) return propVal
    val envVal = System.getenv(envKey)?.trim()
    return if (envVal.isNullOrEmpty()) null else envVal
}

val releaseStorePath = signingValue("storeFile", "HERMES_KEYSTORE_PATH")
val releaseStorePassword = signingValue("storePassword", "HERMES_KEYSTORE_PASSWORD")
val releaseKeyAlias = signingValue("keyAlias", "HERMES_KEY_ALIAS")
val releaseKeyPassword = signingValue("keyPassword", "HERMES_KEY_PASSWORD")
val releaseStoreFile: File? = releaseStorePath?.let { path ->
    val candidate = File(path)
    if (candidate.isAbsolute) candidate else rootProject.file(path)
}
val hasReleaseSigning =
    releaseStoreFile != null &&
    releaseStoreFile.exists() &&
    !releaseStorePassword.isNullOrEmpty() &&
    !releaseKeyAlias.isNullOrEmpty() &&
    !releaseKeyPassword.isNullOrEmpty()

val requireReleaseSigning =
    providers.gradleProperty("requireReleaseSigning").orNull?.toBoolean() == true

android {
    namespace = "dev.hermes.hermes_client"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "dev.hermes.hermes_client"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = releaseStoreFile
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            if (!hasReleaseSigning && requireReleaseSigning) {
                throw GradleException("Release signing credentials are required.")
            }
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                // Local unsigned release builds fall back to debug keys unless -PrequireReleaseSigning=true is set.
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
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
