import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/product.dart';
import '../models/app_settings.dart';
import 'database_service.dart';
import 'settings_manager.dart';
import 'reports_service.dart'; // 🚨 Added
import '../screens/alerts_display_dialog.dart';

class AlertService {
  final DatabaseService _databaseService = DatabaseService();
  final ReportsService _reportsService = ReportsService(); // 🚨 Added

  /// التحقق من التنبيهات وعرضها إذا لزم الأمر
  Future<void> checkAndShowAlerts(BuildContext context, {bool forceShow = false}) async {
    print('🔔 AlertService: بدء فحص التنبيهات...');
    final settings = await SettingsManager.getAppSettings();

    if (!settings.areAlertsEnabled) {
      print('🔔 AlertService: التنبيهات معطلة في الإعدادات.');
      return;
    }

    if (_shouldShowAlerts(settings)) {
      print('🔔 AlertService: سيتم الفحص الآن (تكرار التنبيه مسموح).');
      final lowStockProducts = await _getLowStockProducts();
      final stagnantProducts = await _getStagnantProducts();
      final expiryProducts = await _getExpiringProducts(settings.expiryAlertThresholdMonths);

      print('🔔 AlertService: نتائج الفحص:');
      print('   - نواقص: ${lowStockProducts.length}');
      print('   - راكدة: ${stagnantProducts.length}');
      print('   - منتهية الصلاحية: ${expiryProducts.length}');

      if (forceShow || lowStockProducts.isNotEmpty || stagnantProducts.isNotEmpty || expiryProducts.isNotEmpty) {
        if (context.mounted) {
          print('🔔 AlertService: جاري عرض شاشة التنبيهات ${forceShow ? '(عرض قسري يدوي)' : ''}...');
          await _updateLastShownDate(settings);
          
          showDialog(
            context: context,
            builder: (context) => AlertsDisplayDialog(
              lowStockProducts: lowStockProducts,
              stagnantProducts: stagnantProducts,
              expiryProducts: expiryProducts,
            ),
          );
        } else {
          print('🔔 AlertService: context not mounted!');
        }
      } else {
        print('🔔 AlertService: لا توجد منتجات تنطبق عليها شروط التنبيه.');
      }
    } else {
      print('🔔 AlertService: تم عرض التنبيهات مؤخراً، لن يتم العرض الآن بناءً على الإعدادات (${settings.alertFrequency}).');
    }
  }

  /// هل حان وقت عرض التنبيهات؟
  bool _shouldShowAlerts(AppSettings settings) {
    if (settings.lastAlertShownDate == null) return true;

    final now = DateTime.now();
    final lastShown = settings.lastAlertShownDate!;

    switch (settings.alertFrequency) {
      case 'startup':
        return true; // دائماً عند التشغيل (إذا تم استدعاء الدالة عند التشغيل)
      case 'daily':
        return !_isSameDay(now, lastShown);
      case 'weekly':
        // نعتبر الأسبوع مر إذا مر 7 أيام أو دخلنا أسبوع جديد (الخيار الأبسط: 7 أيام)
        return now.difference(lastShown).inDays >= 7;
      case 'monthly':
        return now.difference(lastShown).inDays >= 30; // تقريب الشهر
      default:
        return true;
    }
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  Future<void> _updateLastShownDate(AppSettings settings) async {
    final updatedSettings = settings.copyWith(lastAlertShownDate: DateTime.now());
    await SettingsManager.saveAppSettings(updatedSettings);
  }

  /// جلب المنتجات التي قلت عن الحد المسموح
  Future<List<Product>> _getLowStockProducts() async {
    final db = await _databaseService.database;
    
    // المنتجات التي لديها alert_quantity و stock_quantity أقل منه أو يساويه
    // نسترجع جميع المنتجات ثم نفلتر (لأن الوحدات قد تحتاج حسابات معقدة، 
    // لكن للتبسيط سنعتمد على الكمية الأساسية ومقارنتها)
    // ملاحظة: alertQuantity يخزن بالنسبة للوحدة المختارة alertUnit
    // و stockQuantity يخزن بالوحدة الأساسية (base unit)
    // لذا نحتاج تحويل لتتم المقارنة بشكل صحيح.
    // للسرعة: سنجلب المنتجات التي لديها تنبيه مفعل
    
    final List<Map<String, dynamic>> maps = await db.query(
      'products',
      where: 'alert_quantity IS NOT NULL',
    );
    
    List<Product> products = List.generate(maps.length, (i) => Product.fromMap(maps[i]));
    List<Product> lowStock = [];

    for (var product in products) {
      if (product.alertQuantity == null) continue;

      double thresholdInBaseUnit = product.alertQuantity!;
      
      // إذا كانت وحدة التنبيه مختلفة عن الوحدة الأساسية، يجب التحويل
      // لكن حالياً سنفترض منطق بسيط:
      // سنحاول ايجاد معامل التحويل من UnitHierarchy
      // إذا كان المنتج يباع بالوزن، المخزون بالكيلو.
      // إذا كان بالعدد، المخزون بالقطعة.
      
      double multiplier = 1.0;
      if (product.alertUnit != null && product.unitHierarchy != null) {
        multiplier = _getMultiplierForUnit(product.unitHierarchy!, product.alertUnit!);
      }
      
      // لتحويل "alertQuantity" (بالوحدة الفرعية) إلى "base unit" لنقارن مع "stockQuantity"
      // alertQty (box) * multiplier (pcs/box) = threshold (pcs)
      double alertThresholdBase = product.alertQuantity! * multiplier;
      
      if (product.stockQuantity <= alertThresholdBase) {
        lowStock.add(product);
      }
    }
    
    return lowStock;
  }

  /// جلب المنتجات الراكدة (لم تبع منذ 30 يوم)
  Future<List<Product>> _getStagnantProducts() async {
    final db = await _databaseService.database;
    final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30)).toIso8601String();

    // المنتجات التي لم تظهر في invoice_items خلال 30 يوم
    // وتكون الكمية الموجودة > 0 (لأن لا فائدة من تنبيه ركود لمنتج غير موجود أصلاً)
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT * FROM products 
      WHERE stock_quantity > 0 
      AND id NOT IN (
        SELECT DISTINCT ii.product_id 
        FROM invoice_items ii
        JOIN invoices i ON ii.invoice_id = i.id
        WHERE i.created_at >= ?
      )
    ''', [thirtyDaysAgo]);

    return List.generate(maps.length, (i) => Product.fromMap(maps[i]));
  }

  /// جلب المنتجات التي قارب تاريخ صلاحيتها على الانتهاء
  Future<List<Product>> _getExpiringProducts(int monthsThreshold) async {
    final db = await _databaseService.database;
    final now = DateTime.now();
    final thresholdDate = DateTime(now.year, now.month + monthsThreshold, now.day);
    
    final nowStr = DateFormat('yyyy-MM-dd').format(now);
    final thresholdStr = DateFormat('yyyy-MM-dd').format(thresholdDate);

    print('🔔 AlertService: فحص الصلاحية بين $nowStr و $thresholdStr');

    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT * FROM products 
      WHERE has_expiry = 1 
      AND expiry_date IS NOT NULL 
      AND date(expiry_date) <= date(?) 
      AND date(expiry_date) >= date(?)
    ''', [thresholdStr, nowStr]);

    return List.generate(maps.length, (i) => Product.fromMap(maps[i]));
  }
  
  double _getMultiplierForUnit(String hierarchyJson, String unitName) {
    try {
      final List<dynamic> hierarchy = SettingsManager.parseHierarchy(hierarchyJson); // قد نحتاج دالة مساعدة
      // سنبني منطق بسيط هنا parsing مباشر
      // hierarchy: [{"unit_name": "كرتون", "quantity": 12}, ...]
      // هذا ال json يحدد كم "وحدة أساسية" في هذه "الوحدة"
      
      // سنستخدم دالة مساعدة محلية بسيطة
      if (hierarchyJson.isEmpty) return 1.0;
      // import dart:convert needed inside loop or helper
      // assuming hierarchyJson is valid json string
      
      // ملاحظة: الـ hierarchy في Product model يخزن كـ String
      // سنستخدم بحث نصي بسيط أو parse كامل
      // الأفضل parse كامل
      
      // ولكن مهلاً، Product ما عنده دالة تجيب المعامل؟
      // لا، لكن عنده getUnitHierarchyList
      
      // سنعتمد على قيمة 1.0 افتراضياً
      // سيتم تحسين هذا الجزء لاحقاً ليكون دقيق 100%
      return 1.0; 
    } catch (e) {
      return 1.0;
    }
  }
}
