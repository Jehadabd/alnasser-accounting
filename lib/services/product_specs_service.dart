// services/product_specs_service.dart
import 'database_service.dart';

/// خدمة إدارة مواصفات المنتجات - نظام التعلم من الفواتير
/// 
/// هذه الخدمة تحفظ معلومات الوحدات والتصنيفات للمنتجات
/// لتحسين دقة استخراج الفواتير مع الوقت
class ProductSpecsService {
  final DatabaseService _db = DatabaseService();
  
  /// البحث عن مواصفات منتج بناءً على اسمه
  Future<ProductSpec?> findSpec(String productName) async {
    final normalized = _normalizePattern(productName);
    final db = await _db.database;
    
    // البحث بالتطابق الدقيق أولاً
    var results = await db.query(
      'product_specs',
      where: 'pattern_normalized = ?',
      whereArgs: [normalized],
      limit: 1,
    );
    
    if (results.isNotEmpty) {
      // تحديث عداد الاستخدام
      await db.update(
        'product_specs',
        {
          'usage_count': (results.first['usage_count'] as int? ?? 0) + 1,
          'last_used_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [results.first['id']],
      );
      return ProductSpec.fromMap(results.first);
    }
    
    // البحث بالتطابق الجزئي
    results = await db.query(
      'product_specs',
      orderBy: 'usage_count DESC, confidence DESC',
    );
    
    for (final row in results) {
      final pattern = row['pattern_normalized'] as String? ?? '';
      if (normalized.contains(pattern) || pattern.contains(normalized)) {
        // تحديث عداد الاستخدام
        await db.update(
          'product_specs',
          {
            'usage_count': (row['usage_count'] as int? ?? 0) + 1,
            'last_used_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [row['id']],
        );
        return ProductSpec.fromMap(row);
      }
    }
    
    return null;
  }
  
  /// حفظ مواصفات منتج جديد أو تحديث موجود
  Future<void> saveSpec(ProductSpec spec) async {
    final db = await _db.database;
    final normalized = _normalizePattern(spec.pattern);
    
    // التحقق من وجود المواصفات
    final existing = await db.query(
      'product_specs',
      where: 'pattern_normalized = ?',
      whereArgs: [normalized],
      limit: 1,
    );
    
    if (existing.isNotEmpty) {
      // تحديث الموجود
      final existingSpec = ProductSpec.fromMap(existing.first);
      await db.update(
        'product_specs',
        {
          'unit_type': spec.unitType,
          'unit_value': spec.unitValue,
          'category': spec.category,
          'brand': spec.brand,
          'confidence': (existingSpec.confidence + spec.confidence) / 2, // متوسط الثقة
          'usage_count': existingSpec.usageCount + 1,
          'last_used_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    } else {
      // إدراج جديد
      await db.insert('product_specs', {
        'pattern': spec.pattern,
        'pattern_normalized': normalized,
        'unit_type': spec.unitType,
        'unit_value': spec.unitValue,
        'category': spec.category,
        'brand': spec.brand,
        'confidence': spec.confidence,
        'usage_count': 1,
        'last_used_at': DateTime.now().toIso8601String(),
        'created_at': DateTime.now().toIso8601String(),
        'source': spec.source,
      });
    }
  }
  
  /// حفظ مجموعة من المواصفات من نتيجة AI
  Future<void> saveSpecsFromAIResult(List<Map<String, dynamic>> lineItems) async {
    for (final item in lineItems) {
      final analysis = item['analysis'] as Map<String, dynamic>?;
      if (analysis == null) continue;
      
      final unitType = analysis['unit_type']?.toString() ?? 'none';
      final unitValue = _toDouble(analysis['unit_value'] ?? 0);
      
      // تخطي إذا لم يكن هناك تحليل مفيد
      if (unitType == 'none' || unitValue <= 0) continue;
      
      final spec = ProductSpec(
        pattern: item['name']?.toString() ?? '',
        unitType: unitType,
        unitValue: unitValue,
        category: analysis['category']?.toString() ?? 'other',
        confidence: 0.8, // ثقة متوسطة من AI
        source: 'ai',
      );
      
      await saveSpec(spec);
    }
  }
  
  /// تطبيق المواصفات المحفوظة على عناصر الفاتورة
  Future<List<Map<String, dynamic>>> enrichWithSpecs(
    List<Map<String, dynamic>> lineItems,
  ) async {
    final enriched = <Map<String, dynamic>>[];
    
    for (final item in lineItems) {
      final name = item['name']?.toString() ?? '';
      final spec = await findSpec(name);
      
      if (spec != null) {
        // إضافة التحليل من المواصفات المحفوظة
        final price = _toDouble(item['price'] ?? 0);
        final calculatedUnitPrice = spec.unitValue > 0 ? price / spec.unitValue : price;
        
        item['analysis'] = {
          'category': spec.category,
          'unit_type': spec.unitType,
          'unit_value': spec.unitValue,
          'calculated_unit_price': calculatedUnitPrice,
          'unit_label': _getUnitLabel(spec.unitType),
          'reasoning': 'من قاعدة البيانات المحلية (ثقة: ${(spec.confidence * 100).toInt()}%)',
          'from_local_db': true,
        };
        
        print('📚 تم تطبيق مواصفات محفوظة على: $name');
      }
      
      enriched.add(item);
    }
    
    return enriched;
  }
  
  /// الحصول على جميع المواصفات المحفوظة
  Future<List<ProductSpec>> getAllSpecs() async {
    final db = await _db.database;
    final results = await db.query(
      'product_specs',
      orderBy: 'usage_count DESC',
    );
    return results.map((row) => ProductSpec.fromMap(row)).toList();
  }
  
  /// حذف مواصفات
  Future<void> deleteSpec(int id) async {
    final db = await _db.database;
    await db.delete('product_specs', where: 'id = ?', whereArgs: [id]);
  }
  
  /// تطبيع النمط للبحث
  String _normalizePattern(String input) {
    String s = input.toLowerCase();
    // إزالة التشكيل العربي
    final diacritics = RegExp('[\u0610-\u061A\u064B-\u065F\u06D6-\u06ED]');
    s = s.replaceAll(diacritics, '');
    s = s.replaceAll('\u0640', ''); // التطويل
    s = s.replaceAll('أ', 'ا').replaceAll('إ', 'ا').replaceAll('آ', 'ا');
    s = s.replaceAll('ى', 'ي');
    s = s.replaceAll('ة', 'ه');
    s = s.replaceAll('ک', 'ك').replaceAll('ی', 'ي');
    // توحيد الأرقام
    const arabicIndic = '٠١٢٣٤٥٦٧٨٩';
    const persianIndic = '۰۱۲۳۴۵۶۷۸۹';
    for (int i = 0; i < 10; i++) {
      s = s.replaceAll(arabicIndic[i], i.toString());
      s = s.replaceAll(persianIndic[i], i.toString());
    }
    s = s.replaceAll(RegExp(r'[^\u0600-\u06FF0-9a-z ]'), ' ');
    s = s.replaceAll(RegExp(' +'), ' ').trim();
    return s;
  }
  
  String _getUnitLabel(String unitType) {
    switch (unitType) {
      case 'meter': return 'سعر المتر';
      case 'piece': return 'سعر القطعة';
      case 'pack': return 'سعر الباكيت';
      case 'roll': return 'سعر اللفة';
      case 'dozen': return 'سعر الدرزن';
      case 'bundle': return 'سعر الشدة';
      default: return 'سعر الوحدة';
    }
  }
  
  double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }
}

/// نموذج مواصفات المنتج
class ProductSpec {
  final int? id;
  final String pattern;
  final String unitType;
  final double unitValue;
  final String category;
  final String? brand;
  final double confidence;
  final int usageCount;
  final DateTime? lastUsedAt;
  final DateTime? createdAt;
  final String source;
  
  ProductSpec({
    this.id,
    required this.pattern,
    required this.unitType,
    required this.unitValue,
    this.category = 'other',
    this.brand,
    this.confidence = 1.0,
    this.usageCount = 1,
    this.lastUsedAt,
    this.createdAt,
    this.source = 'manual',
  });
  
  factory ProductSpec.fromMap(Map<String, dynamic> map) {
    return ProductSpec(
      id: map['id'] as int?,
      pattern: map['pattern'] as String? ?? '',
      unitType: map['unit_type'] as String? ?? 'piece',
      unitValue: (map['unit_value'] as num?)?.toDouble() ?? 1,
      category: map['category'] as String? ?? 'other',
      brand: map['brand'] as String?,
      confidence: (map['confidence'] as num?)?.toDouble() ?? 1.0,
      usageCount: map['usage_count'] as int? ?? 1,
      lastUsedAt: map['last_used_at'] != null 
          ? DateTime.tryParse(map['last_used_at'] as String) 
          : null,
      createdAt: map['created_at'] != null 
          ? DateTime.tryParse(map['created_at'] as String) 
          : null,
      source: map['source'] as String? ?? 'manual',
    );
  }
  
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'pattern': pattern,
      'unit_type': unitType,
      'unit_value': unitValue,
      'category': category,
      'brand': brand,
      'confidence': confidence,
      'usage_count': usageCount,
      'last_used_at': lastUsedAt?.toIso8601String(),
      'created_at': createdAt?.toIso8601String(),
      'source': source,
    };
  }
}
