// lib/services/database/database_service.dart
// الخدمة الرئيسية لقاعدة البيانات - تجمع جميع الـ DAOs
// 
// 🎯 هذا الملف هو الواجهة الرئيسية (Facade) لقاعدة البيانات
// يجمع جميع الـ DAOs ويوفر نفس الواجهة القديمة للتوافق

// Core
export 'core/database_config.dart';
export 'core/database_helpers.dart';

// Business Logic
export 'business/customer_locking.dart';
export 'business/profit_calculator.dart';
export 'business/debt_calculator.dart';

// DAOs
export 'dao/customer_dao.dart';
export 'dao/product_dao.dart';
export 'dao/installer_dao.dart';
export 'dao/invoice_dao.dart';
export 'dao/transaction_dao.dart';
export 'dao/audit_dao.dart';

// Analytics
export 'analytics/sales_analytics.dart';

// Sync
export 'sync/sync_operations.dart';

// ملاحظة: هذا الملف يُصدّر جميع المكونات الفرعية
// الملف الرئيسي (lib/services/database_service.dart) يبقى كما هو
// ولكن يستطيع استيراد واستخدام هذه المكونات الجديدة تدريجياً

