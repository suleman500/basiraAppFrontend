allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// لازم هذا الجزء يجي قبل evaluationDependsOn(":app") تحت، حتى afterEvaluate
// يقدر يسجّل نفسه على كل مشروع قبل ما يصير "مُقيَّم" فعليًا.
subprojects {
    afterEvaluate {
        extensions.findByType(com.android.build.gradle.BaseExtension::class.java)?.apply {
            // ⚠️ حزم Flutter قديمة (زي vosk_flutter_2) ما بتحدد "namespace"
            // بملف build.gradle الخاص فيها، وهذا مطلوب إجباريًا من AGP
            // الحديث. هذا السطر يحقن namespace تلقائيًا (من "group" الحزمة)
            // لو كانت غير محددة، بدون الحاجة لتعديل ملفات الحزمة نفسها.
            if (namespace == null) {
                namespace = project.group.toString()
            }


            compileOptions {
                sourceCompatibility = JavaVersion.VERSION_17
                targetCompatibility = JavaVersion.VERSION_17
            }
        }
        extensions.findByType(org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension::class.java)?.apply {
            compilerOptions {
                jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
            }
        }
    }
}

// ⚠️ إصلاح مؤقت لمشكلة توافق معروفة بين camera_android_camerax وGradle
// 9.x: مكتبة camera-core تحتاج androidx.concurrent:concurrent-futures
// وقت الترجمة (compile)، لكن الاعتماد معرّف "runtime scope" بس بملفها
// الأصلي. Gradle 8.x كان يتساهل ويرفّعه تلقائيًا لـcompile classpath؛
// Gradle 9.x صار أكثر صرامة وما بيعمل هذا الترفيع، فتفشل الترجمة برسالة
// "class file for androidx.concurrent.futures.CallbackToFutureAdapter
// not found". نحقن الاعتماد هون صراحة بدل ما نعدّل الحزمة نفسها (أي
// تعديل مباشر جوا pub cache بينمسح تلقائيًا بأول flutter pub get). لو
// طلعت نسخة لاحقة من camera_android_camerax فيها هذا الإصلاح رسميًا،
// ممكن تشيل هذا البلوك بأمان وقتها.
subprojects {
    afterEvaluate {
        if (project.name == "camera_android_camerax") {
            project.dependencies.add(
                "implementation",
                "androidx.concurrent:concurrent-futures:1.2.0",
            )
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}