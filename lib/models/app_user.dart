// models/app_user.dart

class AppUser {
  final int? id;
  final String username;
  final String passwordHash;
  final String role; // 'admin' | 'accountant'
  final DateTime createdAt;
  final List<String> permissions;
  final String? displayName; // اسم الموظف للعرض (اختياري)
  final DateTime? lastLoginAt;
  final String? jobTitle; // 👷 المسمى الوظيفي: محاسب، مجهز، مدقق...

  AppUser({
    this.id,
    required this.username,
    required this.passwordHash,
    required this.role,
    required this.createdAt,
    this.permissions = const [],
    this.displayName,
    this.lastLoginAt,
    this.jobTitle,
  });

  bool get isAdmin => role == 'admin';
  bool get isAccountant => role == 'accountant';

  /// الاسم الظاهر: اسم الموظف إن وُجد وإلا اسم المستخدم
  String get shownName => (displayName != null && displayName!.trim().isNotEmpty) ? displayName! : username;

  /// وصف الدور للواجهة: «مدير» أو «موظف»
  String get roleLabel => isAdmin ? 'مدير' : 'موظف';

  bool hasPermission(String permissionKey) {
    if (isAdmin) return true; // Admin has all permissions
    if (permissions.contains(permissionKey)) return true;
    // 📊 تقرير محدد: الموظف القديم (صلاحية «التقارير» بلا اختيار تقارير محددة) يرى كل التقارير
    if (AppPermissions.isReportKey(permissionKey)) {
      return permissions.contains(AppPermissions.reports) && !permissions.any(AppPermissions.isReportKey);
    }
    // 📒 أزرار سجل الديون: الموظف القديم (بلا أي صلاحية سجل ديون محددة) يبقى كما كان
    if (AppPermissions.isDebtKey(permissionKey) && !permissions.any(AppPermissions.isDebtKey)) {
      return AppPermissions.legacyDebtKeys(permissions).contains(permissionKey);
    }
    return false;
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
      createdAt: DateTime.tryParse('${map['created_at']}') ?? DateTime.now(),
      permissions: permissions ?? [],
      displayName: map['display_name'] as String?,
      lastLoginAt: DateTime.tryParse('${map['last_login_at'] ?? ''}'),
      jobTitle: map['job_title'] as String?,
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
      displayName: displayName,
      lastLoginAt: lastLoginAt,
      jobTitle: jobTitle,
    );
  }
}

/// قائمة الصلاحيات المتاحة في التطبيق
class AppPermissions {
  // 🏠 أزرار الشاشة الرئيسية
  static const String posAccess = 'pos_access'; // الكاشير
  static const String debtRegister = 'debt_register'; // سجل الديون
  static const String productEntry = 'product_entry'; // إدخال البضاعة
  static const String createInvoice = 'create_invoice'; // إنشاء فاتورة
  static const String lateCustomers = 'late_customers'; // المتأخرين عن الديون
  static const String shareDebtsPdf = 'share_debts_pdf'; // مشاركة الديون PDF
  static const String uploadDatabase = 'upload_database'; // رفع قاعدة البيانات
  static const String settings = 'settings'; // الإعدادات
  static const String editInvoices = 'edit_invoices'; // تعديل الفواتير
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

  // 🧱 ميزات الإداري وسهل
  static const String dashboard = 'erp_dashboard'; // لوحة المؤشرات
  static const String salesDocs = 'erp_sales_docs'; // المرتجعات، عروض الأسعار، الطلبات
  static const String changePrice = 'change_price'; // 🏷️ تغيير سعر البيع في الفاتورة بلا موافقة
  static const String delivery = 'erp_delivery'; // 🚚 شركات التوصيل وطلباتها
  static const String loyalty = 'erp_loyalty'; // 🎁 برنامج الولاء
  static const String collection = 'erp_collection'; // وصولات القبض، الاستحقاقات، المطابقة
  static const String debtReports = 'erp_debt_reports'; // أعمار الديون ونسب التحصيل
  static const String customerCard = 'erp_customer_card'; // بطاقة العميل الموسّعة
  static const String inventoryDocs = 'erp_inventory_docs'; // إدخال/إخراج/جرد/تصنيع
  static const String priceTools = 'erp_price_tools'; // تعديل الأسعار الجماعي
  static const String inventoryReports = 'erp_inventory_reports'; // تقارير المخزون
  static const String currencies = 'erp_currencies'; // العملات وأسعار الصرف
  static const String periodClose = 'erp_period_close'; // تثبيت الإدخالات وإقفال السنة

  // 📊 التقارير واحداً واحداً (تحتاج معها «التقارير» لفتح الشاشة)
  static const String repDaily = 'rep_daily';
  static const String repWeekly = 'rep_weekly';
  static const String repMonthly = 'rep_monthly';
  static const String repYearly = 'rep_yearly';
  static const String repCustom = 'rep_custom';
  static const String repProducts = 'rep_products';
  static const String repPeople = 'rep_people';
  static const String repReturns = 'rep_returns';
  static const String repFounders = 'rep_founders';
  static const String repEmployees = 'rep_employees'; // 👷 مبيعات الموظفين

  static const List<String> reportKeys = [
    repDaily, repWeekly, repMonthly, repYearly, repCustom, repProducts, repPeople, repReturns, repFounders,
    repEmployees,
  ];

  static bool isReportKey(String k) => k.startsWith('rep_');

  // 📒 سجل الديون زراً زراً (تحتاج معها «سجل الديون» لفتح الشاشة)
  static const String drView = 'dr_view'; // عرض السجل والعملاء وأرصدتهم (يُضاف تلقائياً مع «سجل الديون»)
  static const String drAddCustomer = 'dr_add_customer';
  static const String drAddDebt = 'dr_add_debt';
  static const String drPayment = 'dr_payment';
  static const String drEditTx = 'dr_edit_tx';
  static const String drStatement = 'dr_statement';
  static const String drReceipts = 'dr_receipts';
  static const String drEditCustomer = 'dr_edit_customer';
  static const String drMessage = 'dr_message';
  static const String drReminders = 'dr_reminders';
  static const String drAudit = 'dr_audit';
  static const String drRepair = 'dr_repair';
  static const String drDeleteCustomer = 'dr_delete_customer';

  /// المعروضة في شاشة الموظفين (drView لا يظهر: يتبع «سجل الديون»)
  static const List<String> debtKeys = [
    drAddCustomer, drAddDebt, drPayment, drEditTx, drStatement, drReceipts,
    drEditCustomer, drMessage, drReminders, drAudit, drRepair, drDeleteCustomer,
  ];

  static bool isDebtKey(String k) => k.startsWith('dr_');

  /// ما كان يستطيعه موظف قديم في سجل الديون قبل هذه الصلاحيات (لم تكن تُفحص):
  /// كل الأزرار لمن له «سجل الديون»، ما عدا أدوات إصلاح الرصيد: لمن له المحاسبة فقط.
  static Set<String> legacyDebtKeys(Iterable<String> perms) {
    final s = perms.toSet();
    final out = <String>{};
    if (s.contains(debtRegister)) {
      out.addAll([drView, ...debtKeys]..remove(drRepair));
      if (s.contains(accounting) || s.contains(accountingPost)) out.add(drRepair);
    } else if (s.contains(addCustomer)) {
      out.add(drAddCustomer);
    }
    return out;
  }

  /// صلاحيات موظف قديم تُكتب صريحة عند فتحه للتعديل:
  /// «التقارير» بلا تقارير محددة = كل التقارير، و«سجل الديون» بلا أزرار محددة = ما كان يستطيعه.
  static Set<String> expandLegacy(Iterable<String> perms) {
    final s = perms.toSet();
    if (s.contains(reports) && !s.any(isReportKey)) s.addAll(reportKeys);
    if (!s.any(isDebtKey)) s.addAll(legacyDebtKeys(s));
    return s;
  }

  static const Map<String, String> allPermissions = {
    // أزرار الشاشة الرئيسية
    posAccess: 'الوصول للكاشير',
    debtRegister: 'سجل الديون',
    productEntry: 'إدخال البضاعة',
    createInvoice: 'إنشاء فاتورة',
    lateCustomers: 'المتأخرين عن الديون',
    shareDebtsPdf: 'مشاركة الديون PDF',
    uploadDatabase: 'رفع قاعدة البيانات',
    settings: 'الإعدادات',
    editInvoices: 'تعديل الفواتير',
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
    viewCostProfit: 'رؤية الكلفة والأرباح (عمود الكلفة والربح في الفاتورة، قائمة الدخل، الميزانية)',
    manageBranches: 'الفروع والمخازن',
    stockTransfer: 'التحويل بين المخازن',
    itemCard: 'بطاقة المادة الموسّعة',
    networkSettings: 'إعداد الشبكة (سيرفر/طرفية)',
    // ميزات الإداري وسهل
    dashboard: 'لوحة المؤشرات',
    salesDocs: 'مستندات المبيعات: المرتجعات، عروض الأسعار، الطلبات',
    changePrice: 'تغيير سعر البيع في الفاتورة (بلا موافقة المدير)',
    delivery: 'شركات التوصيل وطلباتها',
    loyalty: 'برنامج الولاء: الأعضاء والمكافآت',
    collection: 'التحصيل: وصولات القبض، الاستحقاقات، مطابقة الأرصدة',
    debtReports: 'تقارير الديون: أعمار الديون ونسب التحصيل',
    customerCard: 'بطاقة العميل الموسّعة (سقف الدين، المجموعة...)',
    inventoryDocs: 'مستندات المخزون: إدخال، إخراج، جرد، تصنيع',
    priceTools: 'تعديل الأسعار الجماعي',
    inventoryReports: 'تقارير المخزون',
    currencies: 'العملات وأسعار الصرف',
    periodClose: 'تثبيت الإدخالات وإقفال السنة المالية',
    // التقارير المحددة
    repDaily: 'تقرير اليوم',
    repWeekly: 'تقرير الأسبوع',
    repMonthly: 'التقرير الشهري',
    repYearly: 'التقرير السنوي',
    repCustom: 'تقرير فترة مخصصة',
    repProducts: 'تقارير البضاعة',
    repPeople: 'تقارير الأشخاص',
    repReturns: 'تقرير المرتجعات',
    repFounders: 'تقارير المؤسسين',
    repEmployees: 'مبيعات الموظفين',
    // سجل الديون زراً زراً
    drView: 'عرض سجل الديون والعملاء وأرصدتهم',
    drAddCustomer: 'إضافة عميل جديد',
    drAddDebt: 'إضافة دين يدوي (بلا فاتورة)',
    drPayment: 'تسديد دين (يُنشئ وصل قبض بالصندوق)',
    drEditTx: 'تعديل معاملة يدوية (مبلغ، تاريخ، ملاحظة)',
    drStatement: 'كشف الحساب: عرض وطباعة ومشاركة',
    drReceipts: 'وصولات القبض والسندات المطبوعة: عرض وإعادة طباعة ومشاركة',
    drEditCustomer: 'تعديل بيانات العميل (الاسم، الهاتف، العنوان)',
    drMessage: 'مراسلة العميل (واتساب)',
    drReminders: 'مواعيد المطالبة بالسداد',
    drAudit: 'سجل التدقيق المالي للعميل',
    drRepair: 'فحص السلامة وأدوات إصلاح الرصيد (قد تضيف معاملة تصحيحية)',
    drDeleteCustomer: 'حذف العميل',
  };

  /// قوالب الأدوار الجاهزة — تملأ الصلاحيات بضغطة، ويمكن تعديلها بعدها.
  static const Map<String, List<String>> roleTemplates = {
    // 🧾 الكاشير: يبيع ويقبض ويطبع الوصل — لا دين يدوي ولا تعديل معاملات (فصل المهام:
    //    من يقبض المال لا يغيّر الأرصدة)
    'كاشير': [
      posAccess, createInvoice, debtRegister, drView, drAddCustomer, drPayment, drStatement, drReceipts,
      drMessage, collection,
    ],
    // 💰 محصّل الديون: يرى السجل ويقبض ويرسل الكشوفات والتذكيرات فقط
    'محصّل ديون': [
      debtRegister, drView, drPayment, drStatement, drReceipts, drMessage, drReminders, lateCustomers,
      collection,
    ],
    // 👁️ مشاهد: يرى الأرصدة ويطبع الكشف — لا يغيّر شيئاً
    'مشاهد سجل الديون': [debtRegister, drView, drStatement],
    'أمين مخزن': [
      productEntry, editProducts, monthlyInventory, stockTransfer, itemCard, suppliers,
      inventoryDocs, inventoryReports,
    ],
    // 📚 المحاسب: كل سجل الديون عدا حذف العميل، والمحاسبة والتقارير
    'محاسب': [
      debtRegister, drView, drAddCustomer, drAddDebt, drPayment, drEditTx, drStatement, drReceipts,
      drEditCustomer, drMessage, drReminders, drAudit, drRepair,
      lateCustomers, shareDebtsPdf, reports, suppliers, editInvoices, accounting, accountingPost, viewCostProfit,
      dashboard, salesDocs, collection, debtReports, customerCard, currencies, inventoryReports,
      ...reportKeys,
    ],
    'مدير فرع': [
      posAccess, debtRegister, drView, ...debtKeys, productEntry, createInvoice, lateCustomers, shareDebtsPdf,
      editInvoices, editProducts, monthlyInventory, reports, suppliers,
      accounting, accountingPost, viewCostProfit, manageBranches,
      stockTransfer, itemCard, dashboard, salesDocs, collection, debtReports, customerCard,
      inventoryDocs, priceTools, inventoryReports, currencies,
      ...reportKeys,
    ],
  };

  static List<String> get allKeys => allPermissions.keys.toList();
}
