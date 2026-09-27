// models/app_user.dart
import 'dart:convert';

class AppUser {
  final int? id;
  final String username;
  final String passwordHash;
  final String role; // 'admin' | 'accountant'
  final DateTime createdAt;
  final List<String> permissions;

  AppUser({
    this.id,
    required this.username,
    required this.passwordHash,
    required this.role,
    required this.createdAt,
    this.permissions = const [],
  });

  bool get isAdmin => role == 'admin';
  bool get isAccountant => role == 'accountant';

  bool hasPermission(String permissionKey) {
    if (isAdmin) return true; // Admin has all permissions
    return permissions.contains(permissionKey);
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'username': username,
      'password_hash': passwordHash,
      'role': role,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory AppUser.fromMap(Map<String, dynamic> map, {List<String>? permissions}) {
    return AppUser(
      id: map['id'],
      username: map['username'],
      passwordHash: map['password_hash'],
      role: map['role'],
      createdAt: DateTime.parse(map['created_at']),
      permissions: permissions ?? [],
    );
  }

  AppUser copyWith({
    int? id,
    String? username,
    String? passwordHash,
    String? role,
    DateTime? createdAt,
    List<String>? permissions,
  }) {
    return AppUser(
      id: id ?? this.id,
      username: username ?? this.username,
      passwordHash: passwordHash ?? this.passwordHash,
      role: role ?? this.role,
      createdAt: createdAt ?? this.createdAt,
      permissions: permissions ?? this.permissions,
    );
  }
}

/// قائمة الصلاحيات المتاحة في التطبيق
class AppPermissions {
  // 🏠 أزرار الشاشة الرئيسية
  static const String posAccess = 'pos_access'; // الكاشير
  static const String debtRegister = 'debt_register'; // سجل الديون
  static const String productEntry = 'product_entry'; // إدخال البضاعة
  static const String createInvoice = 'create_invoice'; // إنشاء قائمة
  static const String lateCustomers = 'late_customers'; // المتأخرين عن الديون
  static const String shareDebtsPdf = 'share_debts_pdf'; // مشاركة الديون PDF
  static const String uploadDatabase = 'upload_database'; // رفع قاعدة البيانات
  static const String settings = 'settings'; // الإعدادات
  static const String editInvoices = 'edit_invoices'; // تعديل القوائم
  static const String editProducts = 'edit_products'; // تعديل البضاعة
  static const String monthlyInventory = 'monthly_inventory'; // الجرد الشهري
  static const String reports = 'reports'; // التقارير
  static const String suppliers = 'suppliers'; // الموردون
  
  // 🔧 صلاحيات إضافية
  static const String addCustomer = 'add_customer'; // إضافة عميل
  static const String addTransaction = 'add_transaction'; // إضافة معاملة
  static const String manageUsers = 'manage_users'; // إدارة المستخدمين

  // 🏛️ النسخة المحاسبية
  static const String accounting = 'accounting'; // عرض المحاسبة والقيود والكشوفات
  static const String accountingPost = 'accounting_post'; // السندات والقيود اليدوية وشجرة الحسابات
  static const String viewCostProfit = 'view_cost_profit'; // رؤية الكلفة والأرباح وقائمة الدخل
  static const String manageBranches = 'manage_branches'; // الفروع والمخازن
  static const String stockTransfer = 'stock_transfer'; // التحويل بين المخازن
  static const String itemCard = 'item_card'; // بطاقة المادة الموسّعة
  static const String networkSettings = 'network_settings'; // إعداد الشبكة (سيرفر/طرفية)

  static const Map<String, String> allPermissions = {
    // أزرار الشاشة الرئيسية
    posAccess: 'الوصول للكاشير',
    debtRegister: 'سجل الديون',
    productEntry: 'إدخال البضاعة',
    createInvoice: 'إنشاء قائمة',
    lateCustomers: 'المتأخرين عن الديون',
    shareDebtsPdf: 'مشاركة الديون PDF',
    uploadDatabase: 'رفع قاعدة البيانات',
    settings: 'الإعدادات',
    editInvoices: 'تعديل القوائم',
    editProducts: 'تعديل البضاعة',
    monthlyInventory: 'الجرد الشهري',
    reports: 'التقارير',
    suppliers: 'الموردون',
    // صلاحيات إضافية
    addCustomer: 'إضافة عميل',
    addTransaction: 'إضافة معاملة',
    manageUsers: 'إدارة المستخدمين',
    // النسخة المحاسبية
    accounting: 'المحاسبة: عرض القيود والكشوفات وميزان المراجعة',
    accountingPost: 'المحاسبة: السندات والمصاريف والقيود اليدوية',
    viewCostProfit: 'رؤية الكلفة والأرباح (قائمة الدخل والميزانية)',
    manageBranches: 'الفروع والمخازن',
    stockTransfer: 'التحويل بين المخازن',
    itemCard: 'بطاقة المادة الموسّعة',
    networkSettings: 'إعداد الشبكة (سيرفر/طرفية)',
  };

  /// قوالب الأدوار الجاهزة — تملأ الصلاحيات بضغطة، ويمكن تعديلها بعدها.
  static const Map<String, List<String>> roleTemplates = {
    'كاشير': [posAccess, createInvoice, debtRegister, addCustomer, addTransaction],
    'أمين مخزن': [productEntry, editProducts, monthlyInventory, stockTransfer, itemCard, suppliers],
    'محاسب': [
      debtRegister, lateCustomers, shareDebtsPdf, reports, suppliers, addCustomer,
      addTransaction, editInvoices, accounting, accountingPost, viewCostProfit,
    ],
    'مدير فرع': [
      posAccess, debtRegister, productEntry, createInvoice, lateCustomers, shareDebtsPdf,
      editInvoices, editProducts, monthlyInventory, reports, suppliers, addCustomer,
      addTransaction, accounting, accountingPost, viewCostProfit, manageBranches,
      stockTransfer, itemCard,
    ],
  };

  static List<String> get allKeys => allPermissions.keys.toList();
}
