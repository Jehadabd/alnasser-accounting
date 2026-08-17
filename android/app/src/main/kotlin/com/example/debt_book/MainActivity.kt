package com.example.debt_book

import android.content.Context
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.app.PendingIntent
import android.content.Intent
import android.content.BroadcastReceiver
import android.content.IntentFilter
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.OutputStream

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "usb_printer_channel"
        private const val ACTION_USB_PERMISSION = "com.example.debt_book.USB_PERMISSION"

        // USB Printer Class = 7
        private const val USB_CLASS_PRINTER = 7
    }

    private var usbManager: UsbManager? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingDeviceId: Int = -1

    // BroadcastReceiver for USB permission result
    private val usbPermissionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (ACTION_USB_PERMISSION == intent.action) {
                synchronized(this) {
                    val device: UsbDevice? = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
                    val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
                    pendingPermissionResult?.success(granted)
                    pendingPermissionResult = null
                }
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        usbManager = getSystemService(Context.USB_SERVICE) as UsbManager

        // Register USB permission receiver
        val filter = IntentFilter(ACTION_USB_PERMISSION)
        registerReceiver(usbPermissionReceiver, filter)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {

                // ─────────────────────────────────────────────
                // 1. اكتشاف الطابعات المتصلة عبر USB
                // ─────────────────────────────────────────────
                "findUsbPrinters" -> {
                    try {
                        val printers = findUsbPrinters()
                        result.success(printers)
                    } catch (e: Exception) {
                        result.error("USB_ERROR", "Failed to find USB printers: ${e.message}", null)
                    }
                }

                // ─────────────────────────────────────────────
                // 2. طلب إذن الوصول للطابعة
                // ─────────────────────────────────────────────
                "requestUsbPermission" -> {
                    val deviceId = call.argument<Int>("deviceId") ?: run {
                        result.error("INVALID_ARG", "deviceId is required", null)
                        return@setMethodCallHandler
                    }
                    val device = getDeviceById(deviceId) ?: run {
                        result.error("DEVICE_NOT_FOUND", "USB device not found: $deviceId", null)
                        return@setMethodCallHandler
                    }

                    if (usbManager?.hasPermission(device) == true) {
                        result.success(true)
                    } else {
                        pendingPermissionResult = result
                        pendingDeviceId = deviceId
                        val permissionIntent = PendingIntent.getBroadcast(
                            this, 0,
                            Intent(ACTION_USB_PERMISSION),
                            PendingIntent.FLAG_MUTABLE
                        )
                        usbManager?.requestPermission(device, permissionIntent)
                    }
                }

                // ─────────────────────────────────────────────
                // 3. طباعة بيانات PDF/bytes مباشرة للطابعة
                // ─────────────────────────────────────────────
                "printToUsb" -> {
                    val deviceId = call.argument<Int>("deviceId") ?: run {
                        result.error("INVALID_ARG", "deviceId is required", null)
                        return@setMethodCallHandler
                    }
                    val bytes = call.argument<ByteArray>("bytes") ?: run {
                        result.error("INVALID_ARG", "bytes is required", null)
                        return@setMethodCallHandler
                    }

                    Thread {
                        try {
                            val success = printToUsbDevice(deviceId, bytes)
                            runOnUiThread { result.success(success) }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.error("PRINT_ERROR", "Print failed: ${e.message}", null)
                            }
                        }
                    }.start()
                }

                // ─────────────────────────────────────────────
                // 4. فحص إذا كانت الطابعة متصلة
                // ─────────────────────────────────────────────
                "isUsbPrinterConnected" -> {
                    val deviceId = call.argument<Int>("deviceId")
                    if (deviceId == null) {
                        result.success(findUsbPrinters().isNotEmpty())
                    } else {
                        result.success(getDeviceById(deviceId) != null)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    // ────────────────────────────────────────────────────────────
    // Helper: إيجاد كل الطابعات USB المتصلة (Class = 7)
    // ────────────────────────────────────────────────────────────
    private fun findUsbPrinters(): List<Map<String, Any>> {
        val result = mutableListOf<Map<String, Any>>()
        val deviceList = usbManager?.deviceList ?: return result

        for ((_, device) in deviceList) {
            // فحص كل interface في الجهاز
            for (i in 0 until device.interfaceCount) {
                val iface = device.getInterface(i)
                if (iface.interfaceClass == USB_CLASS_PRINTER) {
                    result.add(
                        mapOf(
                            "deviceId" to device.deviceId,
                            "deviceName" to (device.productName ?: "USB Printer"),
                            "vendorId" to device.vendorId,
                            "productId" to device.productId,
                            "manufacturerName" to (device.manufacturerName ?: "Unknown"),
                            "hasPermission" to (usbManager?.hasPermission(device) ?: false)
                        )
                    )
                    break // كافٍ interface واحد من نوع طابعة
                }
            }
        }
        return result
    }

    // ────────────────────────────────────────────────────────────
    // Helper: إيجاد UsbDevice بالـ deviceId
    // ────────────────────────────────────────────────────────────
    private fun getDeviceById(deviceId: Int): UsbDevice? {
        return usbManager?.deviceList?.values?.find { it.deviceId == deviceId }
    }

    // ────────────────────────────────────────────────────────────
    // Helper: إرسال bytes للطابعة عبر Bulk Transfer
    // ────────────────────────────────────────────────────────────
    private fun printToUsbDevice(deviceId: Int, bytes: ByteArray): Boolean {
        val device = getDeviceById(deviceId) ?: return false
        if (usbManager?.hasPermission(device) == false) return false

        val connection = usbManager?.openDevice(device) ?: return false

        try {
            // إيجاد interface الطباعة (class=7)
            for (i in 0 until device.interfaceCount) {
                val iface = device.getInterface(i)
                if (iface.interfaceClass == USB_CLASS_PRINTER) {
                    connection.claimInterface(iface, true)

                    // إيجاد Bulk OUT endpoint (للإرسال للطابعة)
                    for (j in 0 until iface.endpointCount) {
                        val endpoint = iface.getEndpoint(j)
                        // Direction OUT = 0, Transfer Type BULK = 2
                        if (endpoint.direction == 0 && endpoint.type == 2) {
                            val chunkSize = endpoint.maxPacketSize.coerceAtLeast(512)
                            var offset = 0
                            while (offset < bytes.size) {
                                val length = minOf(chunkSize, bytes.size - offset)
                                val chunk = bytes.copyOfRange(offset, offset + length)
                                val transferred = connection.bulkTransfer(endpoint, chunk, chunk.size, 10000)
                                if (transferred < 0) {
                                    connection.releaseInterface(iface)
                                    connection.close()
                                    return false
                                }
                                offset += transferred
                            }
                            connection.releaseInterface(iface)
                            connection.close()
                            return true
                        }
                    }
                    connection.releaseInterface(iface)
                    break
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        } finally {
            connection.close()
        }
        return false
    }

    override fun onDestroy() {
        super.onDestroy()
        try {
            unregisterReceiver(usbPermissionReceiver)
        } catch (_: Exception) {}
    }
}
