// providers/app_provider.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/customer.dart';
import '../models/transaction.dart';
import '../models/invoice.dart';
import '../models/invoice_item.dart';
import '../services/database_service.dart';
import '../erp/erp_common.dart' show PeriodLock;
// DriveService removed
import '../services/financial_audit_service.dart';
import '../services/telegram_backup_service.dart';
import '../services/backup_files.dart';
import '../services/settings_manager.dart';
import '../services/firebase_sync/sync_event_bus.dart';
import '../services/firebase_sync/firebase_sync_service.dart'; // 🚀 رفع فوري عند الإنشاء/التعديل
import '../services/firebase_sync/firebase_sync_config.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart';
import '../services/xz/xz_backup.dart'; // 🗜️ ضغط XZ حقيقي متحقق منه لنسخة تيليجرام

// أنواع ترتيب العملاء
enum CustomerSortType {
  alphabetical,      // أبجدي (الافتراضي)
  lastDebtAdded,     // آخر إضافة دين
  lastPayment,       // آخر تسديد
  lastTransaction,   // آخر معاملة (أي نوع)
  highestDebt,       // الأكبر مبلغاً
}

class AppProvider with ChangeNotifier {
  final DatabaseService _db = DatabaseService();

  final List<Customer> _customers = [];
  List<Customer> _filteredCustomers = [];
  Customer? _selectedCustomer;
  List<DebtTransaction> _customerTransactions = [];
  bool _isLoading = false;
  String _searchQuery = '';
  // Drive related fields removed
  final bool _autoCreateCustomerOnSync = true; // إنشاء العميل تلقائياً عند المزامنة إذا لم يكن موجوداً
  CustomerSortType _currentSortType = CustomerSortType.alphabetical; // نوع الترتيب الحالي

  // 📄 Pagination لسجل الديون (تحمل آلاف العملاء بكفاءة)
  static const int _pageSize = 50;
  int _currentPage = 0;
  bool _hasMoreData = true;
  bool _isFetchingMore = false;
  bool _isLoadingMore = false; // for UI indicator
  int _searchRequestId = 0;
  Timer? _searchDebounce;
  Timer? _syncRefreshDebounce;
  StreamSubscription<SyncEvent>? _syncEventsSub;

  // Temporary invoice state for preserving unsaved invoice data
  String _tempCustomerName = '';
  String _tempCustomerPhone = '';
  String _tempCustomerAddress = '';
  String _tempInstallerName = '';
  DateTime _tempInvoiceDate = DateTime.now();
  String _tempPaymentType = 'نقد';
  double _tempDiscount = 0.0;
  String _tempPaidAmount = '0.00';
  List<InvoiceItem> _tempInvoiceItems = [];
  bool _hasTempInvoiceData = false;

  // Getters
  List<Customer> get customers => _filteredCustomers;
  Customer? get selectedCustomer => _selectedCustomer;
  List<DebtTransaction> get customerTransactions => _customerTransactions;
  bool get isLoading => _isLoading;
  bool get isFetchingMore => _isFetchingMore;
  bool get hasMoreData => _hasMoreData;
  String get searchQuery => _searchQuery;
  // Drive related getters removed
  bool get autoCreateCustomerOnSync => _autoCreateCustomerOnSync;
  CustomerSortType get currentSortType => _currentSortType;

  // Temporary invoice getters
  String get tempCustomerName => _tempCustomerName;
  String get tempCustomerPhone => _tempCustomerPhone;
  String get tempCustomerAddress => _tempCustomerAddress;
  String get tempInstallerName => _tempInstallerName;
  DateTime get tempInvoiceDate => _tempInvoiceDate;
  String get tempPaymentType => _tempPaymentType;
  double get tempDiscount => _tempDiscount;
  String get tempPaidAmount => _tempPaidAmount;
  List<InvoiceItem> get tempInvoiceItems =>
      List.unmodifiable(_tempInvoiceItems);
  bool get hasTempInvoiceData => _hasTempInvoiceData;

  // Initialize the app
  Future<void> initialize() async {
    _setLoading(true);
    try {
      await _loadCustomers();
      _listenToIncomingSync();
    } finally {
      _setLoading(false);
    }
  }

  /// عند وصول فاتورة/عميل/معاملة من جهاز آخر نحدّث سجل الديون فوراً.
  void _listenToIncomingSync() {
    _syncEventsSub?.cancel();
    _syncEventsSub = SyncEventBus.instance.stream.listen((event) {
      final type = event.entityType;
      if (type != 'invoice' && type != 'customer' && type != 'transaction') {
        return;
      }
      _syncRefreshDebounce?.cancel();
      _syncRefreshDebounce = Timer(const Duration(milliseconds: 400), () {
        refreshCustomers();
      });
    });
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  // Customer operations
  Future<void> _loadCustomers() async {
    // 📄 تحميل أول صفحة فقط (50 عميل) بدل تحميل الكل دفعة واحدة
    await _loadCustomersPage(refresh: true);
  }

  /// 📄 تحميل صفحة عملاء (Pagination) مع بحث في SQL.
  Future<void> _loadCustomersPage({bool refresh = false}) async {
    if (refresh) {
      final requestId = ++_searchRequestId;
      _currentPage = 0;
      _hasMoreData = true;

      try {
        final orderBy = _sortTypeToSqlOrderBy(_currentSortType);
        final newCustomers = await _db.getCustomersForDebtRegisterPaginated(
          limit: _pageSize,
          offset: 0,
          searchQuery: _searchQuery,
          orderBy: orderBy,
        );

        if (requestId != _searchRequestId) return; // تم طلب بحث أحدث، تجاهل هذا الاستعلام القديم

        _customers.clear();
        _customers.addAll(newCustomers);
        _filteredCustomers = List.from(_customers);
        _hasMoreData = newCustomers.length >= _pageSize;
        _currentPage = 1;
        notifyListeners();
      } catch (e) {
        debugPrint('Error loading customers page (refresh): $e');
      }
      return;
    }

    if (_isFetchingMore || !_hasMoreData) return;
    _isFetchingMore = true;

    try {
      final requestId = _searchRequestId;
      final orderBy = _sortTypeToSqlOrderBy(_currentSortType);
      final newCustomers = await _db.getCustomersForDebtRegisterPaginated(
        limit: _pageSize,
        offset: _currentPage * _pageSize,
        searchQuery: _searchQuery,
        orderBy: orderBy,
      );

      if (requestId != _searchRequestId) return; // تم بدء بحث جديد أثناء التصفح

      if (newCustomers.length < _pageSize) {
        _hasMoreData = false;
      }
      _customers.addAll(newCustomers);
      _filteredCustomers = List.from(_customers);
      _currentPage++;
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading customers page: $e');
    } finally {
      _isFetchingMore = false;
    }
  }

  /// 📄 تحميل المزيد من العملاء (يُستدعى من الـ ScrollController)
  Future<void> loadMoreCustomers() async {
    if (_isFetchingMore || !_hasMoreData) return;
    _isLoadingMore = true;
    notifyListeners();
    await _loadCustomersPage();
    _isLoadingMore = false;
    notifyListeners();
  }

  /// 🔼 تحديث بيانات العملاء بصمت (بدون إظهار مؤشر التحميل)
  /// يُستخدم عند العودة من شاشة تفاصيل العميل لتحديث البيانات
  /// مع الحفاظ على موضع التمرير في القائمة
  Future<void> refreshCustomers() async {
    await _loadCustomersPage(refresh: true);
    notifyListeners();
  }

  /// يحول نوع الترتيب إلى جملة SQL ORDER BY
  String _sortTypeToSqlOrderBy(CustomerSortType type) {
    switch (type) {
      case CustomerSortType.alphabetical:
        return 'name ASC';
      case CustomerSortType.highestDebt:
        return 'current_total_debt DESC';
      // للأنواع المعقدة (المعتمدة على JOIN معاملات) نستخدم الافتراضي محلياً
      case CustomerSortType.lastDebtAdded:
      case CustomerSortType.lastPayment:
      case CustomerSortType.lastTransaction:
        return 'last_modified_at DESC';
    }
  }

  bool get isLoadingMore => _isLoadingMore;



  // تغيير نوع الترتيب - 📄 يعيد التحميل من الصفحة الأولى بالترتيب الجديد
  Future<void> setSortType(CustomerSortType sortType) async {
    _currentSortType = sortType;
    await _loadCustomersPage(refresh: true);
    _filteredCustomers = List.from(_customers);
    notifyListeners();
  }

  /// 🧹 تنظيف مؤقت البحث عند التخلص من الـ provider
  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }


  /// 📄 مع Pagination: البحث يجري في SQL، وهذه مجرد مزامنة القائمة المعروضة
  /// مع القائمة المحمّلة (تبقى لاستدعاءات addCustomer/updateCustomer القديمة).
  void _applySearchFilter() {
    _filteredCustomers = List.from(_customers);
    notifyListeners();
  }

  // إعادة تعيين الترتيب للافتراضي (أبجدي) - 📄 مع إعادة تحميل من SQL
  Future<void> resetSortType() async {
    _currentSortType = CustomerSortType.alphabetical;
    await _loadCustomersPage(refresh: true);
    _applySearchFilter();
  }

  /// 🚀 رفع فوري لعميل إلى السحابة (إن كانت المزامنة مفعّلة) — لا يفعل شيئاً محلياً.
  Future<void> _syncCustomerNow(int customerId) async {
    try {
      if (!await FirebaseSyncConfig.isEnabled()) return;
      await FirebaseSyncService().syncCustomerNow(customerId);
    } catch (_) {
      // المزامنة الخلفية ستتكفل به لاحقاً
    }
  }

  Future<void> addCustomer(Customer customer) async {
    final id = await _db.insertCustomer(customer);
    final newCustomer = customer.copyWith(id: id);
    _customers.add(newCustomer);
    _applySearchFilter();
    notifyListeners();

    // 🚀 رفع فوري للسحابة لحظة الإنشاء (لا ننتظر الدورة الخلفية):
    // إذا أُغلق التطبيق بسرعة بعد الإضافة يبقى العميل محلياً فقط.
    // fire-and-forget: لا نحظر الواجهة، والفشل تلتقطه المزامنة الخلفية.
    unawaited(_syncCustomerNow(id));
  }

  Future<void> updateCustomer(Customer customer, {bool updateBalance = false}) async {
    await _db.updateCustomer(customer, updateBalance: updateBalance);
    // 🛡️ اقرأ النسخة المحفوظة فعلاً بدل وضع الكائن الممرَّر في الذاكرة،
    // وإلا عرضت الواجهة رصيداً لم يُكتب في قاعدة البيانات.
    Customer stored = customer;
    if (customer.id != null) {
      try {
        final fresh = await _db.getCustomerById(customer.id!);
        if (fresh != null) stored = fresh;
      } catch (e) {
        debugPrint('تعذّر إعادة قراءة العميل بعد التحديث: $e');
      }
    }

    final index = _customers.indexWhere((c) => c.id == customer.id);
    if (index != -1) {
      _customers[index] = stored;
      if (_selectedCustomer?.id == customer.id) {
        _selectedCustomer = stored;
      }
      _applySearchFilter();
      notifyListeners();

      // 🚀 رفع فوري للتعديل أيضاً (الاسم/الهاتف/العنوان تصل فوراً)
      final editedId = customer.id;
      if (editedId != null) unawaited(_syncCustomerNow(editedId));
    }
  }

  Future<void> deleteCustomer(int id) async {
    await _db.deleteCustomer(id);
    _customers.removeWhere((c) => c.id == id);
    if (_selectedCustomer?.id == id) {
      _selectedCustomer = null;
      _customerTransactions = [];
    }
    _applySearchFilter();
    notifyListeners();
  }

  // Transaction operations
  Future<void> loadCustomerTransactions(int customerId) async {
    _customerTransactions = await _db.getCustomerTransactions(customerId);
    notifyListeners();
  }

  Future<void> addTransaction(DebtTransaction transaction) async {
    // 🔒 تثبيت الإدخالات: لا معاملة بتاريخ داخل فترة مثبّتة
    await PeriodLock.assertOpen(transaction.transactionDate);
    // 1. إدراج المعاملة (تقوم قاعدة البيانات بتحديث رصيد العميل والتحقق منه)
    final id = await _db.insertTransaction(transaction);
    
    // 2. إعادة تحميل العميل من قاعدة البيانات للحصول على الرصيد المحدث والموثق
    final updatedCustomer = await _db.getCustomerById(transaction.customerId);
    
    if (updatedCustomer != null) {
      // تحديث القائمة المحلية
      final index = _customers.indexWhere((c) => c.id == transaction.customerId);
      if (index != -1) {
        _customers[index] = updatedCustomer;
      }
      // تحديث العميل المحدد إذا كان هو نفسه
      if (_selectedCustomer?.id == transaction.customerId) {
        _selectedCustomer = updatedCustomer;
      }
    }

    // 3. إعادة تحميل المعاملات لعرض الأرصدة الصحيحة (قبل/بعد) التي حسبتها قاعدة البيانات
    await loadCustomerTransactions(transaction.customerId);

    // 🚀 رفع فوري للسحابة لحظة إنشاء المعاملة (العميل أولاً ثم معاملاته).
    // قبل هذا كانت المعاملة تنتظر دورة watchdog/الخلفية — فإذا أُغلق التطبيق
    // قبل الدورة بقيت محلية ولا تصل لبقية الأجهزة إلا عند فتحه مجدداً.
    unawaited(_syncCustomerNow(transaction.customerId));

    // 4. تسجيل العملية في سجل التدقيق
    try {
      final auditService = FinancialAuditService();
      await auditService.logOperation(
        operationType: transaction.transactionType == 'manual_debt' 
            ? 'transaction_create' 
            : 'payment_create',
        entityType: 'customer',
        entityId: transaction.customerId,
        newValues: {
          'transaction_id': id,
          'amount': transaction.amountChanged,
          'type': transaction.transactionType,
          'balance_before': transaction.balanceBeforeTransaction,
          'balance_after': transaction.newBalanceAfterTransaction,
          'note': transaction.transactionNote,
        },
        notes: transaction.transactionType == 'manual_debt'
            ? 'إضافة دين يدوي بقيمة ${transaction.amountChanged}'
            : 'تسديد دين بقيمة ${transaction.amountChanged.abs()}',
      );
    } catch (e) {
      debugPrint('تحذير: فشل تسجيل التدقيق: $e');
    }

    notifyListeners();
  }

  Future<void> updateTransaction(DebtTransaction transaction) async {
    // 🔒 تثبيت الإدخالات: لا تعديل لمعاملة مثبّتة، ولا نقلها إلى فترة مثبّتة
    await PeriodLock.assertOpen(transaction.transactionDate);
    if (transaction.id != null) {
      final old = await _db.getTransactionById(transaction.id!);
      if (old != null) await PeriodLock.assertOpen(old.transactionDate);
    }
    // Only manual transactions (not linked to invoice) are supported here
    final updatedCustomer = await _db.updateManualTransaction(transaction);

    // Update local customer list/state
    final customerIndex = _customers.indexWhere((c) => c.id == updatedCustomer.id);
    if (customerIndex != -1) {
      _customers[customerIndex] = updatedCustomer;
    }
    if (_selectedCustomer?.id == updatedCustomer.id) {
      _selectedCustomer = updatedCustomer;
    }

    // Refresh transactions list for this customer
    await loadCustomerTransactions(updatedCustomer.id!);
    _applySearchFilter();
    notifyListeners();

    // 🚀 رفع فوري للتعديل (updateManualTransaction يعلّم is_uploaded=0
    // فيلتقطه syncCustomerNow ويعيد رفعه فوراً)
    final updId = updatedCustomer.id;
    if (updId != null) unawaited(_syncCustomerNow(updId));
  }

  // Search functionality - مع debounce لتفادي إثقال قاعدة البيانات
  void setSearchQuery(String query) {
    if (_searchQuery == query) return;
    _searchQuery = query;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () async {
      await _loadCustomersPage(refresh: true);
    });
    notifyListeners();
  }

  // Customer selection
  Future<void> selectCustomer(Customer customer) async {
    Customer freshCustomer = customer;
    if (customer.id != null) {
      try {
        final loaded = await _db.getCustomerById(customer.id!);
        if (loaded != null) {
          freshCustomer = loaded;
        }
      } catch (e) {
        debugPrint('Error loading fresh customer: $e');
      }
    }
    _selectedCustomer = freshCustomer;
    await loadCustomerTransactions(freshCustomer.id!);
    notifyListeners();
  }

  // Drive upload methods removed

  /// رفع قاعدة البيانات (XZ) ثم تقارير PDF إلى Telegram.
  /// يرمي استثناءً إن لم تصل القاعدة نفسها (فلا يظهر «نجح» كذباً)،
  /// ويعيد قائمة بمشاكل غير قاتلة (تقرير PDF لم يُرسل، Telegram غير مضبوط).
  Future<List<String>> backupDatabaseToTelegram({ValueChanged<double>? onProgress}) async {
    _setLoading(true);
    final problems = <String>[];
    Directory? workDir;
    try {
      // 1) نسخة متّسقة من القاعدة في مجلد مؤقت
      onProgress?.call(0.05);
      final tempDir = await getTemporaryDirectory();
      final backupRoot = workDir = Directory('${tempDir.path}/backup_${DateTime.now().millisecondsSinceEpoch}');
      if (!await backupRoot.exists()) {
        await backupRoot.create(recursive: true);
      }
      final dbCopy = File('${backupRoot.path}/debt_book.db');
      // نسخة متّسقة تشمل ما في WAL (نسخ الملف مباشرة كان يفوّت آخر العمليات)،
      // مهيّأة لأصغر أرشيف XZ — انظر BackupFiles.snapshotForBackup
      await BackupFiles.snapshotForBackup(dbCopy.path);

      // 2) أرشيف TAR ثم ضغط XZ
      onProgress?.call(0.45);
      final now = DateTime.now();
      final settings = await SettingsManager.getAppSettings();
      final branchName = settings.branchName;
      
      // اسم المجلد الذي سيظهر عند فك الضغط
      final folderName = '${branchName}_${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      
      // إنشاء Archive
      final archive = Archive();
      
      // إضافة ملف قاعدة البيانات
      final dbBytes = await dbCopy.readAsBytes();
      archive.addFile(ArchiveFile('$folderName/debt_book.db', dbBytes.length, dbBytes));
      
      // تحويل الأرشيف إلى TAR
      onProgress?.call(0.55);
      final tarData = TarEncoder().encode(archive);
      
      // 🗜️ ضغط XZ حقيقي (LZMA2، قاموس 8MB) في معالج منفصل، ثم فكّه بمسار الاستعادة
      // نفسه ومقارنته بالأصل بايتاً ببايت — انظر XzBackup.
      // (XZEncoder في مكتبة archive لا يضغط: كان الملف بحجم القاعدة نفسه)
      onProgress?.call(0.58);
      final tarBytes = tarData is Uint8List ? tarData : Uint8List.fromList(tarData);
      final xzData = await XzBackup.compressVerified(
        tarBytes,
        onProgress: (p) => onProgress?.call(0.58 + p * 0.10),
      );
      final stamp = '${folderName}_${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}';
      final File compressedFile;
      final String format;
      if (xzData != null) {
        compressedFile = File('${tempDir.path}/$stamp.tar.xz');
        await compressedFile.writeAsBytes(xzData, flush: true);
        format = 'XZ';
      } else {
        // بديل آمن نادر: ZIP (deflate) — الاستعادة تقبله أيضاً
        debugPrint('⚠️ نسخة تيليجرام: تعذّر XZ المتحقق منه — تُرفع ZIP بدلاً منه');
        compressedFile = File('${tempDir.path}/$stamp.zip');
        await compressedFile.writeAsBytes(ZipEncoder().encode(archive)!, flush: true);
        format = 'ZIP';
      }
      final sizeNote = '${_mb(dbBytes.length)} ← ${_mb(await compressedFile.length())} MB';

      // 3) إرسال النسخة إلى Telegram — النتيجة تُفحص ولا تُتجاهل
      onProgress?.call(0.70);
      final telegramService = TelegramBackupService();
      if (!await telegramService.isConfigured) {
        problems.add('قاعدة البيانات لم تُرفع: إعدادات Telegram غير مكتملة');
      } else {
        final caption = '📦 نسخة $format ($sizeNote) - $branchName - ${now.year}/${now.month}/${now.day} ${now.hour}:${now.minute.toString().padLeft(2, '0')}';
        final sent = await telegramService.sendDocumentWithDetails(file: compressedFile, caption: caption);
        if (!sent.success) {
          throw Exception('لم تُرفع قاعدة البيانات إلى Telegram: ${sent.errorMessage ?? 'خطأ غير معروف'}'
              '${sent.statusCode != null ? ' (كود ${sent.statusCode})' : ''}'
              '${sent.errorDetails != null && sent.errorDetails!.isNotEmpty ? ' — ${sent.errorDetails}' : ''}');
        }

        // 4) تقارير PDF (تقرير الديون وكشوفات الحسابات) — فشلها لا يلغي رفع القاعدة لكنه يُبلَّغ
        onProgress?.call(0.75);
        final debtPdf = await telegramService.backupDebtRecordsPdf();
        if (debtPdf != null) problems.add(debtPdf);
        final statementsPdf = await telegramService.backupAccountStatementsPdf();
        if (statementsPdf != null) problems.add(statementsPdf);
      }

      onProgress?.call(1.0);
      return problems;
    } finally {
      // نسخة القاعدة المؤقتة لا تبقى على القرص. (الملف المضغوط يبقى: ديسكورد
      // قد يكون ما زال يقرؤه في الخلفية)
      try {
        if (workDir != null && await workDir.exists()) await workDir.delete(recursive: true);
      } catch (_) {}
      _setLoading(false);
    }
  }

  static String _mb(int bytes) => (bytes / 1048576).toStringAsFixed(1);

  Future<List<Invoice>> getAllInvoices() async {
    return await _db.getAllInvoices();
  }

  // New method to update an invoice and notify listeners
  Future<void> updateInvoice(Invoice invoice) async {
    await _db.updateInvoice(invoice);
    // Consider how you want to update local state if necessary,
    // e.g., if invoices are cached in AppProvider.
    // For now, simply notifying listeners will trigger a re-fetch in consuming widgets.
    notifyListeners();
  }

  // Temporary invoice state management methods
  void saveTempInvoiceData({
    required String customerName,
    required String customerPhone,
    required String customerAddress,
    required String installerName,
    required DateTime invoiceDate,
    required String paymentType,
    required double discount,
    required String paidAmount,
    required List<InvoiceItem> invoiceItems,
  }) {
    debugPrint(
        'DEBUG: AppProvider - Saving temp data with ${invoiceItems.length} items');
    for (int i = 0; i < invoiceItems.length; i++) {
      debugPrint(
          'DEBUG: AppProvider - Item $i: ${invoiceItems[i].productName} - ${invoiceItems[i].itemTotal}');
    }
    _tempCustomerName = customerName;
    _tempCustomerPhone = customerPhone;
    _tempCustomerAddress = customerAddress;
    _tempInstallerName = installerName;
    _tempInvoiceDate = invoiceDate;
    _tempPaymentType = paymentType;
    _tempDiscount = discount;
    _tempPaidAmount = paidAmount;
    _tempInvoiceItems = List.from(invoiceItems);
    _hasTempInvoiceData = true;
    debugPrint(
        'DEBUG: AppProvider - Temp data saved. Items count: ${_tempInvoiceItems.length}');
    notifyListeners();
  }

  void clearTempInvoiceData() {
    _tempCustomerName = '';
    _tempCustomerPhone = '';
    _tempCustomerAddress = '';
    _tempInstallerName = '';
    _tempInvoiceDate = DateTime.now();
    _tempPaymentType = 'نقد';
    _tempDiscount = 0.0;
    _tempPaidAmount = '0.00';
    _tempInvoiceItems.clear();
    _hasTempInvoiceData = false;
    notifyListeners();
  }

  void updateTempInvoiceItems(List<InvoiceItem> items) {
    debugPrint(
        'DEBUG: AppProvider - Updating temp invoice items. Count: ${items.length}');
    for (int i = 0; i < items.length; i++) {
      debugPrint(
          'DEBUG: AppProvider - Update Item $i: ${items[i].productName} - ${items[i].itemTotal}');
    }
    _tempInvoiceItems = List.from(items);
    _hasTempInvoiceData = true;
    debugPrint(
        'DEBUG: AppProvider - Updated temp items. New count: ${_tempInvoiceItems.length}');
    notifyListeners();
  }

  // New method to update temp data with all fields
  void updateTempData({
    String? customerName,
    String? customerPhone,
    String? customerAddress,
    String? installerName,
    DateTime? invoiceDate,
    String? paymentType,
    double? discount,
    String? paidAmount,
    List<InvoiceItem>? invoiceItems,
  }) {
    if (customerName != null) _tempCustomerName = customerName;
    if (customerPhone != null) _tempCustomerPhone = customerPhone;
    if (customerAddress != null) _tempCustomerAddress = customerAddress;
    if (installerName != null) _tempInstallerName = installerName;
    if (invoiceDate != null) _tempInvoiceDate = invoiceDate;
    if (paymentType != null) _tempPaymentType = paymentType;
    if (discount != null) _tempDiscount = discount;
    if (paidAmount != null) _tempPaidAmount = paidAmount;
    if (invoiceItems != null) {
      debugPrint(
          'DEBUG: AppProvider - Updating temp data with ${invoiceItems.length} items');
      _tempInvoiceItems = List.from(invoiceItems);
    }
    _hasTempInvoiceData = true;
    notifyListeners();
  }
}
