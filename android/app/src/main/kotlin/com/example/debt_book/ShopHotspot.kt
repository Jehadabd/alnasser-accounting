// 📶 شبكة المتجر بلا راوتر (lib/lan/shop_hotspot.dart).
//
//   • startLocal: «شبكة التطبيق» — LocalOnlyHotspot (Android 8+). Android يفرض اسماً وكلمة
//     سر عشوائيين، وتبقى ما دام التطبيق يعمل. لا يستطيع تطبيق عادي تشغيل نقطة اتصال النظام.
//   • openSystemSettings: يفتح إعدادات «نقطة الاتصال» لمن يريد شبكة باسم ثابت.
//   • join: الطرفية تنضم لشبكة المتجر (Android 10+، WifiNetworkSpecifier) بعد موافقة
//     المستخدم في نافذة النظام، وتُربط اتصالات التطبيق بها (لا إنترنت فيها).
package com.example.debt_book

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSpecifier
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

class ShopHotspotChannel(private val activity: Activity) {
    private val main = Handler(Looper.getMainLooper())
    private var reservation: WifiManager.LocalOnlyHotspotReservation? = null
    private var joinCallback: ConnectivityManager.NetworkCallback? = null

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "alnaser/hotspot").setMethodCallHandler { call, result ->
            when (call.method) {
                "sdk" -> result.success(Build.VERSION.SDK_INT)
                "startLocal" -> startLocal(result)
                "stopLocal" -> {
                    try { reservation?.close() } catch (_: Exception) {}
                    reservation = null
                    result.success(true)
                }
                "localInfo" -> result.success(reservation?.let { info(it) })
                "openSystemSettings" -> {
                    try {
                        activity.startActivity(Intent().setClassName("com.android.settings", "com.android.settings.TetherSettings"))
                    } catch (_: Exception) {
                        try { activity.startActivity(Intent(Settings.ACTION_WIRELESS_SETTINGS)) } catch (_: Exception) {}
                    }
                    result.success(true)
                }
                "openWifiSettings" -> {
                    try { activity.startActivity(Intent(Settings.ACTION_WIFI_SETTINGS)) } catch (_: Exception) {}
                    result.success(true)
                }
                "join" -> join(call.argument<String>("ssid"), call.argument<String>("password"), result)
                "leave" -> {
                    leave()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun info(r: WifiManager.LocalOnlyHotspotReservation): Map<String, Any?> {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val c = r.softApConfiguration
            mapOf("ssid" to c.ssid?.trim('"'), "password" to c.passphrase)
        } else {
            val c = r.wifiConfiguration
            mapOf("ssid" to c?.SSID?.trim('"'), "password" to c?.preSharedKey?.trim('"'))
        }
    }

    private fun startLocal(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.error("UNSUPPORTED", "يحتاج Android 8 أو أحدث", null)
            return
        }
        reservation?.let {
            result.success(info(it))
            return
        }
        val wm = activity.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        var replied = false
        try {
            wm.startLocalOnlyHotspot(object : WifiManager.LocalOnlyHotspotCallback() {
                override fun onStarted(r: WifiManager.LocalOnlyHotspotReservation) {
                    reservation = r
                    if (!replied) {
                        replied = true
                        result.success(info(r))
                    }
                }

                override fun onStopped() {
                    reservation = null
                }

                override fun onFailed(reason: Int) {
                    if (!replied) {
                        replied = true
                        // 1 = نقطة اتصال النظام شغّالة، 2 = وضع غير متوافق (مشاركة Wi-Fi مثلاً)
                        result.error("FAILED", "reason=$reason", reason)
                    }
                }
            }, main)
        } catch (e: SecurityException) {
            if (!replied) { replied = true; result.error("PERMISSION", e.message, null) }
        } catch (e: Exception) {
            if (!replied) { replied = true; result.error("FAILED", e.message, null) }
        }
    }

    private fun join(ssid: String?, password: String?, result: MethodChannel.Result) {
        if (ssid.isNullOrEmpty()) {
            result.error("INVALID_ARG", "ssid", null)
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.error("UNSUPPORTED", "يحتاج Android 10 أو أحدث — اتصل من إعدادات الواي فاي", null)
            return
        }
        leave()
        val cm = activity.applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val spec = WifiNetworkSpecifier.Builder().setSsid(ssid).apply {
            if (!password.isNullOrEmpty()) setWpa2Passphrase(password)
        }.build()
        val req = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .setNetworkSpecifier(spec)
            .build()
        var replied = false
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                cm.bindProcessToNetwork(network) // اتصالات التطبيق تذهب لشبكة المتجر
                main.post { if (!replied) { replied = true; result.success(true) } }
            }

            override fun onUnavailable() {
                main.post { if (!replied) { replied = true; result.success(false) } }
            }

            override fun onLost(network: Network) {
                cm.bindProcessToNetwork(null)
            }
        }
        joinCallback = cb
        try {
            cm.requestNetwork(req, cb, 60_000)
        } catch (e: Exception) {
            joinCallback = null
            if (!replied) { replied = true; result.error("FAILED", e.message, null) }
        }
    }

    private fun leave() {
        val cm = activity.applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        joinCallback?.let {
            try { cm.unregisterNetworkCallback(it) } catch (_: Exception) {}
            cm.bindProcessToNetwork(null)
        }
        joinCallback = null
    }
}
