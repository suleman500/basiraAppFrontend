plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.projctlitgudei"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.projctlitgudei"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // ⚠️ إصلاح منفصل تمامًا عن موضوع compileSdk: sherpa_onnx وonnxruntime
    // (الحزمتين مع بعض بمشروعنا) كل وحدة فيهم بتجيب نسخة خاصة فيها من
    // نفس ملف libonnxruntime.so الأصلي (ONNX Runtime native). Gradle
    // كان يفشل لأنه ما بيعرف يختار وحدة منهم وقت دمج مكتبات التطبيق
    // النهائي. pickFirsts هون بتقوله: "خذ أول نسخة تلاقيها وتجاهل
    // الباقي" بدل ما تفشل. هذا الإصلاح يبقى مطلوبًا بغض النظر عن حل
    // مشكلة compileSdk (المضبوطة هلق مركزيًا بـandroid/build.gradle.kts
    // الجذري).
    packaging {
        jniLibs {
            pickFirsts += listOf(
                "**/libonnxruntime.so",
                "**/libonnxruntime4j_jni.so"
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
dependencies {
    compileOnly("org.tensorflow:tensorflow-lite:2.14.0")
}