import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 🔑 توقيع النسخة العامة: android/key.properties (خارج git) يشير إلى مفتاح خارج المشروع.
//    بدونه تُوقَّع النسخة بمفتاح debug — صالحة للتجربة فقط، لا للنشر للعملاء.
val keyProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val hasReleaseKey = keyProps.getProperty("storeFile")?.let { file(it).exists() } == true

android {
    namespace = "com.example.debt_book"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        // هوية مستقلة: كانت com.example.debt_book نفس «دفتر الديون» و«شوب مانجر»، فتثبيت أحدها
        // يحلّ محل الآخر على الهاتف (ويفتح بياناته). الـ namespace (كود Kotlin) لم يتغيّر.
        applicationId = "com.alnaser.accounting"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // رفع الحد الأدنى لنظام أندرويد إلى 7.0 (API 24) لدعم المكتبات الحديثة
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(keyProps.getProperty("storeFile"))
                storePassword = keyProps.getProperty("storePassword")
                keyAlias = keyProps.getProperty("keyAlias")
                keyPassword = keyProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseKey) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                logger.warn("⚠️ لا يوجد android/key.properties: النسخة موقّعة بمفتاح debug — لا تنشرها للعملاء.")
                signingConfig = signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
