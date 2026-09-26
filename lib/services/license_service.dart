// license_service.dart
// نظام الترخيص المركزي للتطبيق

import 'dart:convert';
import 'dart:io';
import 'dart:math' show Random; // 🌐 لبصمة جهاز الويب
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb; // 🌐 حراسة الويب
import 'package:get_storage/get_storage.dart';
import 'package:shared_preferences/shared_preferences.dart'; // 🌐 التخزين الدائم للويب
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'firebase_sync/firebase_sync_config.dart';

class LicenseService {
  static const String _apiUrl = 'https://script.google.com/macros/s/AKfycbzdk2Fhl_JM1dPotLZal_oAakPndDrRKVli75K_9MyVbMcMNqvXAIUquVA1N6Om3WSqsw/exec';
  
  // مفاتيح التخزين المحلي
  static const String _keyLicense = 'license_data';
  static const String _keyLastCheck = 'last_license_check';
  static const String _keyLastKnownTime = 'last_known_time';
  static const String _keyServerTimeOffset = 'server_time_offset';
  
  // فترة التحقق (6 أشهر بالميلي ثانية)
  static const int _checkIntervalMs = 6 * 30 * 24 * 60 * 60 * 1000; // ~180 يوم
  
  // فترة السماح بعد انتهاء الاشتراك (يومين)
  static const int _gracePeriodDays = 2;
  
  // حد الاشتراك الدائم (إذا كان أكثر من 25 سنة = دائم)
  static const int _lifetimeThresholdYears = 25;
  
  // أقصى مدة للاشتراك المحلي (100 سنة)
  static const int _maxSubscriptionYears = 100;
  
  // 🔐 المفتاح السري للتوقيع التشفيري لمنع التلاعب بالترخيص محلياً أو بالمتصفح
  static const String _licenseSecretSalt = 'AL_NASSER_CRYPT_SIG_v2_987412356_SECRET';
  
  final GetStorage _storage = GetStorage();

  /// 🔒 حساب التوقيع الرقمي المشفر للترخيص
  String _computeLicenseSignature(Map<String, dynamic> data) {
    final payload = '${data['username']}_${data['deviceId']}_${data['appMode']}_${data['type']}_${data['expires']}_$_licenseSecretSalt';
    final bytes = utf8.encode(payload);
    return sha256.convert(bytes).toString();
  }
  
  /// توليد بصمة الجهاز الفريدة وتثبيتها بشكل دائم
  Future<String> generateDeviceId() async {
    try {
      // 🌐 الويب: تثبيت بصمة الجهاز في الذاكرة الدائمة المزدوجة (SharedPreferences + GetStorage)
      // لمنع تغيير البصمة نهائياً عند إعادة التفعيل أو تحديث الصفحة
      if (kIsWeb) {
        String? stored = _storage.read<String>('web_device_id');
        if (stored == null || stored.isEmpty) {
          try {
            final prefs = await SharedPreferences.getInstance();
            stored = prefs.getString('web_device_id');
          } catch (_) {}
        }

        if (stored != null && stored.isNotEmpty) {
          _storage.write('web_device_id', stored);
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('web_device_id', stored);
          } catch (_) {}
          return stored;
        }

        final newId = sha256
            .convert(utf8.encode(
                'web_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1 << 32)}'))
            .toString()
            .substring(0, 32);

        await _storage.write('web_device_id', newId);
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('web_device_id', newId);
        } catch (_) {}
        return newId;
      }

      final List<String> parts = [];

      // اسم الكمبيوتر
      parts.add(Platform.localHostname);
      
      // اسم المستخدم
      parts.add(Platform.environment['USERNAME'] ?? Platform.environment['USER'] ?? 'unknown');
      
      // معرف النظام
      if (Platform.isWindows) {
        // الحصول على معرف القرص الصلب
        final result = await Process.run('wmic', ['diskdrive', 'get', 'serialnumber'], runInShell: true);
        if (result.exitCode == 0) {
          final serial = result.stdout.toString().split('\n').where((s) => s.trim().isNotEmpty && !s.contains('SerialNumber')).join();
          parts.add(serial.trim());
        }
        
        // الحصول على معرف اللوحة الأم
        final mbResult = await Process.run('wmic', ['baseboard', 'get', 'serialnumber'], runInShell: true);
        if (mbResult.exitCode == 0) {
          final mbSerial = mbResult.stdout.toString().split('\n').where((s) => s.trim().isNotEmpty && !s.contains('SerialNumber')).join();
          parts.add(mbSerial.trim());
        }
      }
      
      // إنشاء hash من المعلومات
      final combined = parts.join('|');
      final bytes = utf8.encode(combined);
      final hash = sha256.convert(bytes);
      
      return hash.toString().substring(0, 32); // أول 32 حرف
    } catch (e) {
      // في حالة الخطأ، استخدم معرف بديل
      final fallback =
          '${kIsWeb ? "web" : Platform.localHostname}_${DateTime.now().millisecondsSinceEpoch}';
      final bytes = utf8.encode(fallback);
      return sha256.convert(bytes).toString().substring(0, 32);
    }
  }
  
  /// التحقق من توفر الإنترنت
  Future<bool> hasInternetConnection() async {
    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity.contains(ConnectivityResult.none)) {
        return false;
      }
      
      if (kIsWeb) {
        // 🌐 على الويب: InternetAddress.lookup غير مدعوم في المتصفح، ويكفي فحص الاتصال
        return true;
      }

      // تحقق فعلي من الاتصال للأجهزة الأصلية
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (e) {
      return kIsWeb; // على الويب لا نمنع العملية
    }
  }
  
  /// استدعاء API (يدعم GET فائق السرعة للويب و POST للأجهزة الأصلية)
  Future<Map<String, dynamic>> _callApi(Map<String, dynamic> data) async {
    print('🔐 [LICENSE] Calling API...');
    print('🔐 [LICENSE] URL: $_apiUrl');
    print('🔐 [LICENSE] Data: $data');
    
    try {
      if (kIsWeb) {
        // 🌐 على الويب: نرسل كـ GET عبر Uri Query Parameters لمنع خطأ 405 وقيود CORS للـ 302 Redirect تماماً
        final queryParams = data.map((key, value) => MapEntry(key, value.toString()));
        final uri = Uri.parse(_apiUrl).replace(queryParameters: queryParams);
        
        print('🔐 [LICENSE] Sending Web GET request to: $uri');
        final response = await http.get(uri).timeout(const Duration(seconds: 30));
        
        print('🔐 [LICENSE] Web response status: ${response.statusCode}');
        print('🔐 [LICENSE] Web response body: ${response.body}');
        
        if (response.statusCode == 200) {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic>) {
            return decoded;
          }
          return {'success': false, 'error': 'INVALID_RESPONSE', 'message': 'استجابة غير صالحة من السيرفر'};
        } else {
          return {'success': false, 'error': 'HTTP_${response.statusCode}', 'message': 'خطأ في الاتصال: ${response.statusCode}'};
        }
      }

      // 💻 المنصات الأصلية (ويندوز / أندرويد / آيفون):
      final client = http.Client();
      try {
        var request = http.Request('POST', Uri.parse(_apiUrl));
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(data);
        
        print('🔐 [LICENSE] Sending native POST request...');
        var streamedResponse = await client.send(request).timeout(const Duration(seconds: 30));
        
        // معالجة redirects
        var response = await http.Response.fromStream(streamedResponse);
        
        // إذا كان redirect، اتبع الرابط الجديد
        if (response.statusCode == 302 || response.statusCode == 301) {
          final redirectUrl = response.headers['location'];
          if (redirectUrl != null) {
            final getResponse = await http.get(Uri.parse(redirectUrl)).timeout(const Duration(seconds: 30));
            response = getResponse;
          }
        }
        
        print('🔐 [LICENSE] Final status: ${response.statusCode}');
        print('🔐 [LICENSE] Response body: ${response.body}');
        
        if (response.statusCode == 200) {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic>) {
            return decoded;
          }
          return {'success': false, 'error': 'INVALID_RESPONSE', 'message': 'استجابة غير صالحة من السيرفر'};
        } else {
          return {'success': false, 'error': 'HTTP_${response.statusCode}', 'message': 'خطأ في الاتصال: ${response.statusCode}'};
        }
      } finally {
        client.close();
      }
    } catch (e, stackTrace) {
      print('🔐 [LICENSE] EXCEPTION: $e');
      print('🔐 [LICENSE] Stack: $stackTrace');
      return {'success': false, 'error': 'NETWORK_ERROR', 'message': 'فشل الاتصال بالسيرفر: $e'};
    }
  }

  /// معالج قوي لتواريخ السيرفر (يقبل ISO-8601 أو Timestamp)
  /// يقوم بتقييد التواريخ الضخمة إلى 100 سنة كحد أقصى (اشتراك مدى الحياة)
  DateTime? _parseDate(dynamic input) {
    if (input == null) return null;
    
    // الحد الأقصى: 100 سنة من الآن (للاشتراك مدى الحياة)
    final maxDate = DateTime.now().add(Duration(days: 365 * _maxSubscriptionYears));
    DateTime? result;
    
    try {
      if (input is int) {
        // إذا كان الرقم ضخماً جداً (أكبر من سنة 3000)، استخدم الحد الأقصى
        if (input > 32503680000000) {
          print('🔐 [LICENSE] Huge timestamp detected: $input, treating as LIFETIME');
          result = maxDate;
        } else {
          result = DateTime.fromMillisecondsSinceEpoch(input);
        }
      } else if (input is String) {
        final inputStr = input.toString().trim();
        
        // إذا كان الرقم كبير جداً لا يمكن تحويله لـ int (أكثر من 15 خانة)
        // أو يحتوي على أرقام فقط وطوله كبير
        if (RegExp(r'^\d+$').hasMatch(inputStr)) {
          if (inputStr.length > 15) {
            // رقم ضخم جداً - اعتبره lifetime
            print('🔐 [LICENSE] Huge timestamp string (${inputStr.length} digits): treating as LIFETIME');
            result = maxDate;
          } else {
            final ms = int.tryParse(inputStr);
            if (ms != null) {
              if (ms > 32503680000000) {
                result = maxDate;
              } else {
                result = DateTime.fromMillisecondsSinceEpoch(ms);
              }
            } else {
              // فشل التحويل - استخدم الحد الأقصى
              result = maxDate;
            }
          }
        } else {
          // محاولة قراءة ISO-8601
          try {
            result = DateTime.parse(inputStr);
          } catch (_) {
            // فشل - استخدم الحد الأقصى
            print('🔐 [LICENSE] Could not parse date string: $inputStr, treating as LIFETIME');
            result = maxDate;
          }
        }
      }
    } catch (e) {
      print('🔐 [LICENSE] Date parse error: $e, treating as LIFETIME');
      result = maxDate;
    }
    
    // تقييد التاريخ إلى 100 سنة كحد أقصى
    if (result != null && result.isAfter(maxDate)) {
      result = maxDate;
    }
    
    // إذا فشل كل شيء وكان هناك input، استخدم الحد الأقصى
    if (result == null && input != null && input.toString().isNotEmpty) {
      print('🔐 [LICENSE] Fallback: using LIFETIME for unparseable input');
      result = maxDate;
    }
    
    return result;
  }
  
  /// تفعيل الترخيص (أول مرة)
  Future<LicenseResult> activateLicense(String username, String password) async {
    print('🔐 [LICENSE] Activating license for user: $username');
    final deviceId = await generateDeviceId();
    print('🔐 [LICENSE] Device ID: $deviceId');
    
    final response = await _callApi({
      'action': 'validate',
      'username': username,
      'password': password,
      'deviceId': deviceId,
    });
    
    print('🔐 [LICENSE] Activation response: $response');
    
    if (response['success'] == true) {
      // تصحيح صيغة التاريخ قبل الحفظ
      final expiresDate = _parseDate(response['expires']);
      
      if (expiresDate == null) {
        return LicenseResult(
          success: false,
          error: 'INVALID_DATE',
          message: 'تاريخ الانتهاء غير صالح من السيرفر',
        );
      }

      final newAppMode = (response['appMode'] ?? 'full_sync').toString().toLowerCase();
      final bool newSyncAllowed = response['isSyncAllowed'] as bool? ?? 
          (newAppMode == 'full_sync' || (newAppMode == 'full' && newAppMode != 'debts_only' && newAppMode != 'full_offline'));

      // حفظ بيانات الترخيص محلياً
      final licenseData = {
        'username': response['subUsername'] ?? username,
        'mainUsername': response['mainUsername'] ?? username,
        'subUsername': response['subUsername'] ?? username,
        'appMode': newAppMode,
        'isSyncAllowed': newSyncAllowed,
        'deviceId': deviceId,
        'type': response['type'],
        'expires': expiresDate.toIso8601String(),
        'daysLeft': expiresDate.difference(DateTime.now()).inDays,
        'activatedAt': DateTime.now().toIso8601String(),
      };
      
      // 🔒 إضافة التوقيع الرقمي لمنع التلاعب
      licenseData['signature'] = _computeLicenseSignature(licenseData);
      
      final licenseJson = jsonEncode(licenseData);
      await _storage.write(_keyLicense, licenseJson);
      await _storage.write(_keyLastCheck, DateTime.now().millisecondsSinceEpoch);
      await _storage.write(_keyLastKnownTime, DateTime.now().millisecondsSinceEpoch);

      if (kIsWeb) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_keyLicense, licenseJson);
          await prefs.setInt(_keyLastCheck, DateTime.now().millisecondsSinceEpoch);
          await prefs.setInt(_keyLastKnownTime, DateTime.now().millisecondsSinceEpoch);
        } catch (_) {}
      }
      
      // 🚀 تفعيل/تعطيل مفتاح المزامنة أوتوماتيكياً حسب نوع الترخيص عند التفعيل
      await FirebaseSyncConfig.setEnabled(newSyncAllowed);

      // حفظ فرق الوقت مع السيرفر
      if (response['serverTime'] != null) {
        final serverTime = _parseDate(response['serverTime']);
        if (serverTime != null) {
          final offset = serverTime.difference(DateTime.now()).inSeconds;
          await _storage.write(_keyServerTimeOffset, offset);
          if (kIsWeb) {
            try {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setInt(_keyServerTimeOffset, offset);
            } catch (_) {}
          }
        }
      }
      
      return LicenseResult(
        success: true,
        type: response['type'],
        appMode: newAppMode,
        mainUsername: response['mainUsername'],
        subUsername: response['subUsername'],
        expires: expiresDate.toIso8601String(),
        daysLeft: expiresDate.difference(DateTime.now()).inDays,
        warning: response['warning'],
      );
    } else {
      return LicenseResult(
        success: false,
        error: response['error'] ?? 'UNKNOWN_ERROR',
        message: response['message'] ?? 'خطأ غير معروف',
      );
    }
  }
  
  /// جلب بيانات الترخيص المحفوظة مع التحقق التشفيري الصارم من عدم التلاعب
  LicenseData? getStoredLicense() {
    dynamic data = _storage.read(_keyLicense);
    if (data == null) return null;
    
    try {
      final decoded = data is String ? jsonDecode(data) : data;
      if (decoded is! Map) return null;
      final Map<String, dynamic> map = Map<String, dynamic>.from(decoded);
      if (map.isEmpty) return null;

      final storedSignature = map['signature'] as String?;
      final expectedSignature = _computeLicenseSignature(map);

      // 🚨 إذا كان التوقيع غير مطابق (تم التلاعب ببيانات الترخيص في الذاكرة أو المتصفح)
      if (storedSignature != null && storedSignature != expectedSignature) {
        print('🚨 [SECURITY_ALERT] تم اكتشاف تلاعب غير مصرح به في بيانات الترخيص! تم إلغاء التفعيل وقفل النظام.');
        clearLicense();
        return null;
      }

      // إذا كان ترخيصاً قديماً بدون ختم، نختمه تشفيرياً
      if (storedSignature == null) {
        map['signature'] = expectedSignature;
        _storage.write(_keyLicense, jsonEncode(map));
      }

      return LicenseData.fromJson(map);
    } catch (e) {
      return null;
    }
  }
  
  /// هل الترخيص مفعّل؟
  bool isLicenseActivated() {
    return getStoredLicense() != null;
  }
  
  /// فحص حماية تغيير التاريخ
  AntiTamperResult checkAntiTampering() {
    final lastKnownTime = _storage.read(_keyLastKnownTime);
    if (lastKnownTime == null) {
      // أول مرة - لا مشكلة
      _storage.write(_keyLastKnownTime, DateTime.now().millisecondsSinceEpoch);
      return AntiTamperResult(isValid: true);
    }
    
    DateTime? lastTime;
    try {
      if (lastKnownTime is int) {
        lastTime = DateTime.fromMillisecondsSinceEpoch(lastKnownTime);
      } else if (lastKnownTime is String) {
        lastTime = DateTime.tryParse(lastKnownTime) ?? DateTime.fromMillisecondsSinceEpoch(int.tryParse(lastKnownTime) ?? 0);
      }
    } catch (_) {}
    
    if (lastTime == null) {
      // تجاوز الخطأ إذا كانت البيانات تالفة
      _storage.write(_keyLastKnownTime, DateTime.now().millisecondsSinceEpoch);
      return AntiTamperResult(isValid: true);
    }
    
    final now = DateTime.now();
    
    // إذا كان الوقت الحالي أقل من آخر وقت معروف بأكثر من ساعة
    if (now.isBefore(lastTime.subtract(const Duration(hours: 1)))) {
      return AntiTamperResult(
        isValid: false,
        message: '⚠️ تم اكتشاف تغيير في تاريخ النظام!\n\nيرجى إعادة ضبط التاريخ والوقت بشكل صحيح.',
      );
    }
    
    // تحديث آخر وقت معروف
    _storage.write(_keyLastKnownTime, now.millisecondsSinceEpoch);
    return AntiTamperResult(isValid: true);
  }
  
  /// فحص انتهاء الصلاحية مع دعم فترة السماح
  /// إذا كان الاشتراك أكثر من 25 سنة = دائم ولا يُفحص أبداً
  ExpiryResult checkExpiry() {
    final license = getStoredLicense();
    if (license == null) {
      return ExpiryResult(status: ExpiryStatus.notActivated);
    }
    
    // ✅ اشتراك دائم (lifetime) - لا تتحقق أبداً
    if (license.type == 'lifetime' || license.type == 'master') {
      print('🔐 [LICENSE] LIFETIME subscription detected - skipping all checks');
      return ExpiryResult(status: ExpiryStatus.lifetime, daysLeft: 9999999);
    }
    
    final expires = _parseDate(license.expires);
    if (expires == null) {
      return ExpiryResult(
        status: ExpiryStatus.expired,
        message: 'خطأ في بيانات الترخيص (تاريخ غير صالح). يرجى إعادة التفعيل.',
      );
    }
    
    final now = DateTime.now();
    final daysLeft = expires.difference(now).inDays;
    
    // ✅ إذا كان الاشتراك أكثر من 25 سنة = دائم
    if (daysLeft > (_lifetimeThresholdYears * 365)) {
      print('🔐 [LICENSE] Subscription >25 years ($daysLeft days) - treating as LIFETIME');
      return ExpiryResult(status: ExpiryStatus.lifetime, daysLeft: daysLeft);
    }
    
    // منتهي وتجاوز فترة السماح
    if (daysLeft < -_gracePeriodDays) {
      return ExpiryResult(
        status: ExpiryStatus.expired,
        daysLeft: daysLeft,
        message: '⛔ انتهت صلاحية الترخيص\n\nيرجى التواصل مع المطور لتجديد الاشتراك (واتساب / اتصال: 07705252905).',
      );
    }
    
    // في فترة السماح (0 إلى -2 أيام)
    if (daysLeft <= 0 && daysLeft >= -_gracePeriodDays) {
      final graceDaysLeft = _gracePeriodDays + daysLeft;
      return ExpiryResult(
        status: ExpiryStatus.gracePeriod,
        daysLeft: graceDaysLeft,
        message: '⚠️ انتهى اشتراكك!\n\nأنت في آخر مهلة ($graceDaysLeft ${graceDaysLeft == 1 ? "يوم" : "أيام"} متبقية)\n\nيجب تجديد الاشتراك للاستمرار (تواصل معنا: 07705252905).',
      );
    }
    
    // تحديد فترة التحذير حسب نوع الحساب
    final warningDays = 3;
    
    if (daysLeft <= warningDays) {
      final dayWord = daysLeft == 1 ? 'يوم واحد' : '$daysLeft أيام';
      return ExpiryResult(
        status: ExpiryStatus.warning,
        daysLeft: daysLeft,
        message: '⚠️ تنبيه: سينتهي اشتراكك بعد $dayWord\n\nيرجى التواصل مع المطور لتجديد الاشتراك (واتساب / اتصال: 07705252905).',
      );
    }
    
    return ExpiryResult(status: ExpiryStatus.valid, daysLeft: daysLeft);
  }
  
  /// هل يجب التحقق من السيرفر؟ (كل 6 أشهر)
  bool shouldVerifyWithServer() {
    final lastCheck = _storage.read(_keyLastCheck);
    if (lastCheck == null) return true;
    
    // التأكد من أن lastCheck رقم صحيح
    if (lastCheck is! int) return true;
    
    final elapsed = DateTime.now().millisecondsSinceEpoch - lastCheck;
    return elapsed >= _checkIntervalMs;
  }
  
  /// التحقق من السيرفر (تحديث صامت في الخلفية)
  Future<LicenseResult> verifyWithServer({bool silent = false}) async {
    final license = getStoredLicense();
    if (license == null) {
      return LicenseResult(success: false, error: 'NOT_ACTIVATED');
    }
    
    // التحقق من الإنترنت
    if (!await hasInternetConnection()) {
      // لا إنترنت - نستمر بالترخيص المحلي
      return LicenseResult(
        success: true,
        type: license.type,
        expires: license.expires,
        noInternet: true,
      );
    }
    
    final deviceId = await generateDeviceId();
    
    final response = await _callApi({
      'action': 'validate',
      'username': license.username,
      'password': '', // لا نحتاج كلمة المرور للتحقق
      'deviceId': deviceId,
    });
    
    if (response['success'] == true) {
      final expiresDate = _parseDate(response['expires']);
      
      if (expiresDate == null) {
        return LicenseResult(
          success: false,
          error: 'INVALID_DATE',
          message: 'تاريخ الانتهاء غير صالح من السيرفر',
        );
      }
      
      // تحديث البيانات المحلية شأملة نمط التطبيق وسماح المزامنة
      final newAppMode = (response['appMode'] ?? license.appMode).toString().toLowerCase();
      final bool newSyncAllowed = response['isSyncAllowed'] as bool? ?? (newAppMode == 'full_sync' || (newAppMode == 'full' && newAppMode != 'debts_only' && newAppMode != 'full_offline'));

      final licenseData = {
        'username': license.username,
        'mainUsername': response['mainUsername'] ?? license.mainUsername,
        'subUsername': response['subUsername'] ?? license.subUsername,
        'appMode': newAppMode,
        'isSyncAllowed': newSyncAllowed,
        'deviceId': deviceId,
        'type': response['type'] ?? license.type,
        'expires': expiresDate.toIso8601String(),
        'daysLeft': expiresDate.difference(DateTime.now()).inDays,
        'lastVerified': DateTime.now().toIso8601String(),
      };
      
      // 🔒 إضافة التوقيع الرقمي لمنع التلاعب
      licenseData['signature'] = _computeLicenseSignature(licenseData);
      
      final licenseJson = jsonEncode(licenseData);
      await _storage.write(_keyLicense, licenseJson);
      await _storage.write(_keyLastCheck, DateTime.now().millisecondsSinceEpoch);
      await _storage.write(_keyLastKnownTime, DateTime.now().millisecondsSinceEpoch);

      if (kIsWeb) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_keyLicense, licenseJson);
          await prefs.setInt(_keyLastCheck, DateTime.now().millisecondsSinceEpoch);
          await prefs.setInt(_keyLastKnownTime, DateTime.now().millisecondsSinceEpoch);
        } catch (_) {}
      }

      // 🚀 تفعيل/تعطيل مفتاح المزامنة أوتوماتيكياً حسب النمط المجلوب من السيرفر
      await FirebaseSyncConfig.setEnabled(newSyncAllowed);
      
      print('🔐 [LICENSE] License updated silently. Mode: $newAppMode, Sync: $newSyncAllowed, Expiry: $expiresDate');
      
      return LicenseResult(
        success: true,
        type: response['type'] ?? license.type,
        appMode: newAppMode,
        mainUsername: response['mainUsername'] ?? license.mainUsername,
        subUsername: response['subUsername'] ?? license.subUsername,
        expires: expiresDate.toIso8601String(),
        daysLeft: expiresDate.difference(DateTime.now()).inDays,
        warning: response['warning'],
        wasRenewed: true,
      );
    } else {
      // فشل التحقق - ربما تم تعليق الحساب أو تغيير الجهاز
      return LicenseResult(
        success: false,
        error: response['error'] ?? 'VERIFICATION_FAILED',
        message: response['message'] ?? 'فشل التحقق من الترخيص',
      );
    }
  }
  
  /// الفحص الكامل عند بدء التطبيق
  Future<StartupCheckResult> performStartupCheck() async {
    try {
      // 1. فحص حماية التاريخ
      final antiTamper = checkAntiTampering();
      if (!antiTamper.isValid) {
        return StartupCheckResult(
          canProceed: false,
          reason: StartupBlockReason.clockTampering,
          message: antiTamper.message,
        );
      }
      
      // 2. فحص وجود ترخيص
      if (!isLicenseActivated()) {
        return StartupCheckResult(
          canProceed: false,
          reason: StartupBlockReason.notActivated,
        );
      }
      
      // 3. فحص انتهاء الصلاحية
      final expiry = checkExpiry();
      
      switch (expiry.status) {
        case ExpiryStatus.expired:
          // منتهي تماماً - لا يدخل
          return StartupCheckResult(
            canProceed: false,
            reason: StartupBlockReason.expired,
            message: expiry.message,
          );
          
        case ExpiryStatus.gracePeriod:
          // في فترة السماح - يحتاج إنترنت
          final hasInternet = await hasInternetConnection();
          
          if (!hasInternet) {
            // لا إنترنت في فترة السماح - لا يدخل
            return StartupCheckResult(
              canProceed: false,
              reason: StartupBlockReason.noInternetInGrace,
              message: '⚠️ انتهى اشتراكك!\n\nيجب توفر اتصال بالإنترنت للتحقق من تجديد الاشتراك.',
            );
          }
          
          // تحقق من السيرفر - ربما تم التجديد
          final serverResult = await verifyWithServer();
          
          if (serverResult.wasRenewed == true) {
            // تم التجديد! تحقق مرة أخرى
            final newExpiry = checkExpiry();
            if (newExpiry.status == ExpiryStatus.valid || newExpiry.status == ExpiryStatus.warning) {
              // الاشتراك صالح الآن
              return StartupCheckResult(
                canProceed: true,
                showWarning: newExpiry.status == ExpiryStatus.warning,
                warningMessage: newExpiry.message,
                daysLeft: newExpiry.daysLeft,
              );
            }
          }
          
          // لم يتم التجديد - يدخل مع تحذير
          return StartupCheckResult(
            canProceed: true,
            showWarning: true,
            warningMessage: expiry.message,
            daysLeft: expiry.daysLeft,
            isGracePeriod: true,
          );
          
        case ExpiryStatus.warning:
          // قريب من الانتهاء - يدخل مع تحذير
          // محاولة تحديث صامت في الخلفية
          _silentBackgroundUpdate();
          
          return StartupCheckResult(
            canProceed: true,
            showWarning: true,
            warningMessage: expiry.message,
            daysLeft: expiry.daysLeft,
          );
          
        case ExpiryStatus.valid:
          // صالح - يدخل
          // محاولة تحديث صامت في الخلفية
          _silentBackgroundUpdate();
          
          return StartupCheckResult(canProceed: true);
          
        case ExpiryStatus.lifetime:
          // ✅ اشتراك دائم - يدخل مباشرة بدون أي تحقق
          print('🔐 [LICENSE] LIFETIME user - direct access granted');
          return StartupCheckResult(canProceed: true);
          
        case ExpiryStatus.notActivated:
          return StartupCheckResult(
            canProceed: false,
            reason: StartupBlockReason.notActivated,
          );
      }
    } catch (e, stack) {
      print('🔐 [LICENSE] Critical error in startup check: $e\n$stack');
      // في حالة وجود خطأ غير متوقع، نمنع الدخول للأمان ونعرض الرسالة
      return StartupCheckResult(
        canProceed: false,
        reason: StartupBlockReason.serverRejected,
        message: 'حدث خطأ في النظام: $e',
      );
    }
  }
  
  /// تحديث صامت في الخلفية (بدون انتظار)
  void _silentBackgroundUpdate() {
    // لا ننتظر النتيجة - يعمل في الخلفية
    Future.microtask(() async {
      try {
        if (await hasInternetConnection()) {
          await verifyWithServer(silent: true);
          print('🔐 [LICENSE] Silent background update completed');
        }
      } catch (e) {
        print('🔐 [LICENSE] Silent background update failed: $e');
      }
    });
  }
  
  /// التصفير الذاتي للجهاز وتسجيل الخروج
  Future<LicenseResult> selfUnbindDevice(String password) async {
    final license = getStoredLicense();
    if (license == null) {
      return LicenseResult(success: false, error: 'NOT_ACTIVATED', message: 'الترخيص غير مفعّل');
    }

    if (!await hasInternetConnection()) {
      return LicenseResult(success: false, error: 'NETWORK_ERROR', message: 'يلزم توفر اتصال بالإنترنت لتصفير الجهاز');
    }

    final deviceId = await generateDeviceId();
    final response = await _callApi({
      'action': 'self_unbind_device',
      'username': license.subUsername ?? license.username,
      'password': password,
      'deviceId': deviceId,
    });

    if (response['success'] == true) {
      await clearLicense();
      return LicenseResult(success: true, message: response['message'] ?? 'تم تصفير الجهاز بنجاح');
    } else {
      return LicenseResult(
        success: false,
        error: response['error'] ?? 'UNBIND_FAILED',
        message: response['message'] ?? 'فشل تصفير الجهاز',
      );
    }
  }

  /// مسح بيانات الترخيص (للاختبار أو إعادة التفعيل)
  Future<void> clearLicense() async {
    await _storage.remove(_keyLicense);
    await _storage.remove(_keyLastCheck);
    await _storage.remove(_keyLastKnownTime);
    await _storage.remove(_keyServerTimeOffset);
    if (kIsWeb) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_keyLicense);
        await prefs.remove(_keyLastCheck);
        await prefs.remove(_keyLastKnownTime);
        await prefs.remove(_keyServerTimeOffset);
      } catch (_) {}
    }
    print('🔐 [LICENSE] License data cleared');
  }
}

// ========== Data Classes ==========

class LicenseData {
  final String username;
  final String? mainUsername;
  final String? subUsername;
  final String appMode; // 'full', 'debts_only', 'full_offline', 'full_sync'
  final String deviceId;
  final String type;
  final String expires;
  final int? daysLeft;
  final bool isSyncAllowed;

  LicenseData({
    required this.username,
    this.mainUsername,
    this.subUsername,
    this.appMode = 'full',
    required this.deviceId,
    required this.type,
    required this.expires,
    this.daysLeft,
    bool? isSyncAllowed,
  }) : isSyncAllowed = isSyncAllowed ?? (appMode == 'full_sync' || (appMode == 'full' && appMode != 'debts_only' && appMode != 'full_offline' && appMode != 'full_no_sync'));

  bool get isDebtsOnly => appMode == 'debts_only';
  bool get isFullOffline => appMode == 'full_offline' || appMode == 'full_no_sync';
  bool get isFullSync => isSyncAllowed;

  factory LicenseData.fromJson(Map<String, dynamic> json) {
    final mode = (json['appMode'] ?? json['mode'] ?? 'full').toString().toLowerCase();
    final bool syncAllowed = json['isSyncAllowed'] as bool? ?? (mode == 'full_sync' || (mode == 'full' && mode != 'debts_only' && mode != 'full_offline' && mode != 'full_no_sync'));
    return LicenseData(
      username: json['username'] ?? json['subUsername'] ?? '',
      mainUsername: json['mainUsername'],
      subUsername: json['subUsername'],
      appMode: mode,
      deviceId: json['deviceId'] ?? '',
      type: json['type'] ?? 'trial',
      expires: (json['expires'] ?? '').toString(),
      daysLeft: json['daysLeft'],
      isSyncAllowed: syncAllowed,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'username': username,
      'mainUsername': mainUsername,
      'subUsername': subUsername,
      'appMode': appMode,
      'isSyncAllowed': isSyncAllowed,
      'deviceId': deviceId,
      'type': type,
      'expires': expires,
      'daysLeft': daysLeft,
    };
  }
}

class LicenseResult {
  final bool success;
  final String? type;
  final String appMode;
  final String? mainUsername;
  final String? subUsername;
  final String? expires;
  final int? daysLeft;
  final String? warning;
  final String? error;
  final String? message;
  final bool noInternet;
  final bool? wasRenewed;
  
  LicenseResult({
    required this.success,
    this.type,
    this.appMode = 'full',
    this.mainUsername,
    this.subUsername,
    this.expires,
    this.daysLeft,
    this.warning,
    this.error,
    this.message,
    this.noInternet = false,
    this.wasRenewed,
  });
}

class AntiTamperResult {
  final bool isValid;
  final String? message;
  
  AntiTamperResult({required this.isValid, this.message});
}

enum ExpiryStatus { valid, warning, expired, notActivated, gracePeriod, lifetime }

class ExpiryResult {
  final ExpiryStatus status;
  final int? daysLeft;
  final String? message;
  
  ExpiryResult({required this.status, this.daysLeft, this.message});
}

enum StartupBlockReason {
  notActivated,
  expired,
  clockTampering,
  serverRejected,
  noInternetInGrace,
}

class StartupCheckResult {
  final bool canProceed;
  final StartupBlockReason? reason;
  final String? message;
  final bool showWarning;
  final String? warningMessage;
  final int? daysLeft;
  final bool isGracePeriod;
  
  StartupCheckResult({
    required this.canProceed,
    this.reason,
    this.message,
    this.showWarning = false,
    this.warningMessage,
    this.daysLeft,
    this.isGracePeriod = false,
  });
}
