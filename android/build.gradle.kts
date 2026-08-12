allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// إصلاح مشاكل AGP 8+: تفعيل BuildConfig وتعيين namespace تلقائياً للمكتبات القديمة.
// نستخدم plugins.withId (بدلاً من afterEvaluate) لأنه يعمل بشكل صحيح بغضّ النظر عن
// توقيت تقييم المشروع الفرعي (المشاريع تُقيّم مبكراً عبر evaluationDependsOn(":app")).
subprojects {
    plugins.withId("com.android.library") {
        extensions.configure<com.android.build.gradle.LibraryExtension> {
            if (namespace.isNullOrEmpty()) {
                namespace = "com.example.${project.name}"
            }
            buildFeatures.buildConfig = true
        }
    }
    plugins.withId("com.android.application") {
        extensions.configure<com.android.build.gradle.AppExtension> {
            buildFeatures.buildConfig = true
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
