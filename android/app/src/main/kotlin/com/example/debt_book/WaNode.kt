package com.example.debt_book

// 📱 خادم واتساب على هذا الهاتف (wa_phone_server.dart):
//   • WaNodeNative: Node.js (libnode.so من nodejs-mobile) عبر جسر JNI (cpp/native-lib.cpp).
//   • WaNodeService: خدمة أمامية بإشعار ثابت في عملية مستقلة ":wanode" — Node يبدأ مرة واحدة في
//     عمر العملية، فالإيقاف = إنهاء العملية، والتشغيل التالي عملية جديدة.
//   • WaNodeChannel: قناة «alnaser/wa_node» من Dart: التوفر، فك مكتبات الخادم، تشغيل، إيقاف،
//     واستثناء البطارية.
// مفتاح الخادم يصل إلى Node متغيّرَ بيئة داخل العملية (لا يُكتب على القرص).
// لا يمس قاعدة البيانات ولا أي دين أو معاملة.

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.system.Os
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.zip.ZipInputStream

object WaNodeNative {
    /** يُحمَّل في عملية الخدمة فقط (≈60 ميغابايت) — لا في عملية الواجهة. */
    val loaded: Boolean by lazy {
        try {
            System.loadLibrary("node")
            System.loadLibrary("wanode")
            true
        } catch (t: Throwable) {
            false
        }
    }

    @JvmStatic
    external fun startNodeWithArguments(args: Array<String>): Int
}

class WaNodeService : Service() {
    companion object {
        private const val CHANNEL_ID = "wa_node"
        private const val NOTIF_ID = 8765

        @Volatile
        private var started = false
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startAsForeground()
        if (started) return START_NOT_STICKY
        val i = intent
        val script = i?.getStringExtra("script")
        if (i == null || script == null) {
            // أُعيد تشغيل الخدمة بلا تعليمات (النظام أوقف العملية): البرنامج يشغّلها عند الحاجة
            stopSelf()
            return START_NOT_STICKY
        }
        started = true
        val log = i.getStringExtra("log")
        val names = i.getStringArrayExtra("envNames") ?: emptyArray()
        val values = i.getStringArrayExtra("envValues") ?: emptyArray()
        for (k in names.indices) {
            if (k < values.size) {
                try {
                    Os.setenv(names[k], values[k], true)
                } catch (_: Exception) {
                }
            }
        }
        // Node يحتاج مكدساً أكبر من مكدس الخيط الافتراضي في أندرويد
        Thread(null, {
            var code = -1
            try {
                if (WaNodeNative.loaded) {
                    code = WaNodeNative.startNodeWithArguments(arrayOf("node", script))
                } else {
                    appendLog(log, "تعذّر تحميل Node.js: هذه النسخة من التطبيق بُنيت بلا خادم الهاتف")
                }
            } catch (t: Throwable) {
                appendLog(log, "Node: $t")
            }
            appendLog(log, "توقف Node (الرمز $code)")
            stopSelf()
            android.os.Process.killProcess(android.os.Process.myPid())
        }, "wa-node", 16L * 1024 * 1024).start()
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        // Node لا يُعاد تشغيله في نفس العملية ⇒ الإيقاف ينهي العملية كلها
        android.os.Process.killProcess(android.os.Process.myPid())
    }

    private fun startAsForeground() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "خادم واتساب", NotificationManager.IMPORTANCE_LOW)
            )
        }
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        val pi = if (launch == null) null else PendingIntent.getActivity(this, 0, launch, PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        builder.setContentTitle("خادم واتساب يعمل")
            .setContentText("يرسل رسائل المحل في الخلفية")
            .setSmallIcon(applicationInfo.icon)
            .setOngoing(true)
        if (pi != null) builder.setContentIntent(pi)
        val n = builder.build()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIF_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING)
        } else {
            startForeground(NOTIF_ID, n)
        }
    }

    private fun appendLog(path: String?, line: String) {
        if (path == null) return
        try {
            File(path).appendText("${java.util.Date()} $line\n")
        } catch (_: Exception) {
        }
    }
}

class WaNodeChannel(private val activity: Activity) {
    private val main = Handler(Looper.getMainLooper())

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "alnaser/wa_node").setMethodCallHandler { call, result ->
            when (call.method) {
                "available" -> result.success(
                    mapOf(
                        "native" to activity.resources.getBoolean(R.bool.wa_node),
                        "modules" to hasModules(),
                        "abi" to (Build.SUPPORTED_ABIS.firstOrNull() ?: "")
                    )
                )

                "prepare" -> {
                    val dir = call.argument<String>("dir")
                    if (dir == null) {
                        result.error("ARG", "dir", null)
                        return@setMethodCallHandler
                    }
                    Thread {
                        try {
                            val extracted = prepareModules(File(dir))
                            main.post { result.success(extracted) }
                        } catch (e: Exception) {
                            main.post { result.error("PREPARE", e.message ?: "$e", null) }
                        }
                    }.start()
                }

                "start" -> {
                    try {
                        val names = call.argument<List<String>>("envNames") ?: emptyList()
                        val values = call.argument<List<String>>("envValues") ?: emptyList()
                        val i = Intent(activity, WaNodeService::class.java)
                            .putExtra("script", call.argument<String>("script"))
                            .putExtra("log", call.argument<String>("log"))
                            .putExtra("envNames", names.toTypedArray())
                            .putExtra("envValues", values.toTypedArray())
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            activity.startForegroundService(i)
                        } else {
                            activity.startService(i)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("START", e.message ?: "$e", null)
                    }
                }

                "stop" -> {
                    activity.stopService(Intent(activity, WaNodeService::class.java))
                    result.success(true)
                }

                "batteryExempt" -> {
                    val pm = activity.getSystemService(Context.POWER_SERVICE) as PowerManager
                    result.success(pm.isIgnoringBatteryOptimizations(activity.packageName))
                }

                "requestBatteryExempt" -> {
                    try {
                        activity.startActivity(
                            Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                                .setData(Uri.parse("package:${activity.packageName}"))
                        )
                        result.success(true)
                    } catch (e: Exception) {
                        try {
                            activity.startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                            result.success(true)
                        } catch (e2: Exception) {
                            result.error("BATTERY", e2.message ?: "$e2", null)
                        }
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun hasModules(): Boolean = try {
        activity.assets.open(MODULES_ASSET).close()
        true
    } catch (_: Exception) {
        false
    }

    /**
     * يفك مكتبات الخادم (node_modules) من التطبيق إلى [dir] — مرة لكل نسخة من التطبيق.
     * يفك إلى مجلد مؤقت ثم يستبدل القديم، فلا يبقى نصف تثبيت. يعيد true إن فكّ الآن.
     */
    private fun prepareModules(dir: File): Boolean {
        @Suppress("DEPRECATION")
        val info = activity.packageManager.getPackageInfo(activity.packageName, 0)
        val stamp = "${info.lastUpdateTime}"
        val stampFile = File(dir, ".modules_stamp")
        val target = File(dir, "node_modules")
        if (target.isDirectory && stampFile.isFile && stampFile.readText() == stamp) return false

        dir.mkdirs()
        val tmp = File(dir, "node_modules.tmp")
        tmp.deleteRecursively()
        tmp.mkdirs()
        val root = tmp.canonicalPath + File.separator
        activity.assets.open(MODULES_ASSET).use { input ->
            ZipInputStream(input.buffered()).use { zip ->
                val buf = ByteArray(64 * 1024)
                while (true) {
                    val e = zip.nextEntry ?: break
                    // الأرشيف يبدأ بـ node_modules/ — يُفك محتواه داخل tmp
                    val name = e.name.replace('\\', '/')
                    if (!name.startsWith("node_modules/")) continue
                    val rel = name.removePrefix("node_modules/")
                    if (rel.isEmpty()) continue
                    val out = File(tmp, rel)
                    if (!out.canonicalPath.startsWith(root)) throw SecurityException("مسار غير صالح في الأرشيف: ${e.name}")
                    if (e.isDirectory) {
                        out.mkdirs()
                    } else {
                        out.parentFile?.mkdirs()
                        FileOutputStream(out).use { o ->
                            while (true) {
                                val n = zip.read(buf)
                                if (n <= 0) break
                                o.write(buf, 0, n)
                            }
                        }
                    }
                }
            }
        }
        if (!File(tmp, "baileys/package.json").isFile) {
            tmp.deleteRecursively()
            throw IllegalStateException("أرشيف مكتبات الخادم ناقص (لا baileys)")
        }
        target.deleteRecursively()
        if (!tmp.renameTo(target)) throw IllegalStateException("تعذّر نقل مكتبات الخادم")
        stampFile.writeText(stamp)
        return true
    }

    companion object {
        const val MODULES_ASSET = "wa_node/modules.zip"
    }
}
