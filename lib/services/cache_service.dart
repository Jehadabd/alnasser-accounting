/// خدمة التخزين المؤقت الذكية
/// تضمن سرعة القراءة من الذاكرة مع ضمان الكتابة للهارد (قاعدة البيانات)
///
/// المبادئ:
/// 1. القراءة سريعة من الذاكرة (Cache)
/// 2. الكتابة دائماً للهارد (Database) - ضمان البيانات
/// 3. تحديث الـ Cache تلقائياً بعد الكتابة
/// 4. TTL للبيانات القديمة

import 'dart:async';

/// عنصر في الـ Cache
class CacheItem<T> {
  final T data;
  final DateTime cachedAt;
  final Duration? ttl;
  
  CacheItem(this.data, {this.ttl}) : cachedAt = DateTime.now();
  
  bool get isExpired {
    if (ttl == null) return false;
    return DateTime.now().difference(cachedAt) > ttl!;
  }
  
  bool get isValid => !isExpired;
}

/// خدمة التخزين المؤقت الذكية
class CacheService {
  // Singleton
  static final CacheService _instance = CacheService._internal();
  factory CacheService() => _instance;
  CacheService._internal();
  
  // الـ Cache الرئيسي
  final Map<String, CacheItem<dynamic>> _cache = {};
  
  // أوقات انتهاء الصلاحية الافتراضية
  static const Duration defaultTTL = Duration(minutes: 5);
  static const Duration longTTL = Duration(hours: 1);
  static const Duration shortTTL = Duration(minutes: 1);
  
  // فترات TTL مختلفة حسب نوع البيانات
  final Map<String, Duration> _entityTTL = {
    'products': longTTL,      // المنتجات تتغير نادراً
    'customers': defaultTTL,  // الزبائن قد تتغير
    'suppliers': defaultTTL,  // الموردين قد يتغيرون
    'invoices': shortTTL,     // الفواتير قد تتغير
    'transactions': shortTTL, // المعاملات قد تتغير
  };
  
  /// الحصول على بيانات من الـ Cache
  T? get<T>(String key) {
    final item = _cache[key];
    if (item == null) return null;
    if (item.isExpired) {
      _cache.remove(key);
      return null;
    }
    return item.data as T;
  }
  
  /// تخزين بيانات في الـ Cache
  void set<T>(String key, T data, {Duration? ttl}) {
    _cache[key] = CacheItem(data, ttl: ttl ?? _entityTTL[key.split('_').first] ?? defaultTTL);
  }
  
  /// إزالة عنصر من الـ Cache
  void remove(String key) {
    _cache.remove(key);
  }
  
  /// إزالة جميع العناصر من نوع معين
  void removeByPrefix(String prefix) {
    _cache.removeWhere((key, _) => key.startsWith(prefix));
  }
  
  /// مسح كل الـ Cache
  void clearAll() {
    _cache.clear();
  }
  
  /// مسح العناصر المنتهية صلاحيتها
  void cleanExpired() {
    _cache.removeWhere((_, item) => item.isExpired);
  }
}
