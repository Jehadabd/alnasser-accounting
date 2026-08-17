// providers/app_provider.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/customer.dart';
import '../models/transaction.dart';
import '../models/invoice.dart';
import '../models/invoice_item.dart';
import '../models/account_statement_item.dart'; // ✅ Added import
import '../services/database_service.dart';
// DriveService removed
import '../services/pdf_service.dart';
import '../services/financial_audit_service.dart';
import '../services/telegram_backup_service.dart';
import '../services/settings_manager.dart';
import '../services/debt_report_service.dart'; // ✅ Added import
import '../services/firebase_sync/sync_event_bus.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart';
// Note: XZEncoder is part of the archive package and uses LZMA2 algorithm
// import 'package:lzma/lzma.dart'; // No longer needed directly

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
  // final DriveService _drive = DriveService(); // Removed
  final PdfService _pdf = PdfService();

  List<Customer> _customers = [];
  List<Customer> _filteredCustomers = [];
  Customer? _selectedCustomer;
  List<DebtTransaction> _customerTransactions = [];
  bool _isLoading = false;
  String _searchQuery = '';
  // Drive related fields removed
  bool _autoCreateCustomerOnSync = true; // إنشاء العميل تلقائياً عند المزامنة إذا لم يكن موجوداً
  CustomerSortType _currentSortType = CustomerSortType.alphabetical; // نوع الترتيب الحالي

  // 📄 Pagination لسجل الديون (تحمل آلاف العملاء بكفاءة)
  static const int _pageSize = 50;
  int _currentPage = 0;
  bool _hasMoreData = true;
  bool _isFetchingMore = false;
  bool _isLoadingMore = false; // for UI indicator
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
      await ensureAudioNotesDirectory();
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
      _currentPage = 0;
      _hasMoreData = true;
      _customers.clear();
      _filteredCustomers.clear();
    }
    if (_isFetchingMore || !_hasMoreData) return;
    _isFetchingMore = true;

    try {
      final orderBy = _sortTypeToSqlOrderBy(_currentSortType);
      final newCustomers = await _db.getCustomersForDebtRegisterPaginated(
        limit: _pageSize,
        offset: _currentPage * _pageSize,
        searchQuery: _searchQuery,
        orderBy: orderBy,
      );
      if (newCustomers.length < _pageSize) {
        _hasMoreData = false;
      }
      _customers.addAll(newCustomers);
      _filteredCustomers = List.from(_customers);
      _currentPage++;
    } catch (e) {
      print('Error loading customers page: $e');
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

  // تطبيق الترتيب على قائمة العملاء
  Future<void> _applySorting() async {
    switch (_currentSortType) {
      case CustomerSortType.alphabetical:
        _customers.sort((a, b) => a.name.compareTo(b.name));
        break;
      case CustomerSortType.lastDebtAdded:
        // ترتيب حسب آخر إضافة دين
        final sortedIds = await _db.getCustomerIdsSortedByLastDebtAdded();
        _sortCustomersByIds(sortedIds);
        break;
      case CustomerSortType.lastPayment:
        // ترتيب حسب آخر تسديد
        final sortedIds = await _db.getCustomerIdsSortedByLastPayment();
        _sortCustomersByIds(sortedIds);
        break;
      case CustomerSortType.lastTransaction:
        // ترتيب حسب آخر معاملة (أي نوع)
        final sortedIds = await _db.getCustomerIdsSortedByLastTransaction();
        _sortCustomersByIds(sortedIds);
        break;
      case CustomerSortType.highestDebt:
        // ترتيب حسب أكبر مبلغ دين
        _customers.sort((a, b) => (b.currentTotalDebt ?? 0).compareTo(a.currentTotalDebt ?? 0));
        break;
    }
  }

  // ترتيب العملاء حسب قائمة IDs
  void _sortCustomersByIds(List<int> sortedIds) {
    final idToIndex = <int, int>{};
    for (int i = 0; i < sortedIds.length; i++) {
      idToIndex[sortedIds[i]] = i;
    }
    _customers.sort((a, b) {
      final indexA = idToIndex[a.id] ?? 999999;
      final indexB = idToIndex[b.id] ?? 999999;
      return indexA.compareTo(indexB);
    });
  }

  // تغيير نوع الترتيب
  Future<void> setSortType(CustomerSortType sortType) async {
    _currentSortType = sortType;
    await _applySorting();
    _applySearchFilter();
    notifyListeners();
  }

  // إعادة تعيين الترتيب للافتراضي (أبجدي)
  void resetSortType() {
    _currentSortType = CustomerSortType.alphabetical;
    _customers.sort((a, b) => a.name.compareTo(b.name));
    _applySearchFilter();
    notifyListeners();
  }

  Future<void> addCustomer(Customer customer) async {
    final id = await _db.insertCustomer(customer);
    final newCustomer = customer.copyWith(id: id);
    _customers.add(newCustomer);
    _applySearchFilter();
    notifyListeners();
  }

  Future<void> updateCustomer(Customer customer) async {
    await _db.updateCustomer(customer);
    final index = _customers.indexWhere((c) => c.id == customer.id);
    if (index != -1) {
      _customers[index] = customer;
      if (_selectedCustomer?.id == customer.id) {
        _selectedCustomer = customer;
      }
      _applySearchFilter();
      notifyListeners();
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
      print('تحذير: فشل تسجيل التدقيق: $e');
    }

    notifyListeners();
  }

  Future<void> updateTransaction(DebtTransaction transaction) async {
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
  }

  // Search functionality - مع debounce لتفادي إثقال قاعدة البيانات
  void setSearchQuery(String query) {
    _searchQuery = query;
    // 📄 debounce 500ms ثم إعادة تحميل من SQL (بدل فلترة الذاكرة)
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), () async {
      await _loadCustomersPage(refresh: true);
      notifyListeners();
    });
    notifyListeners();
  }

  void _applySearchFilter() {
    if (_searchQuery.isEmpty) {
      _filteredCustomers = List.from(_customers);
    } else {
      _filteredCustomers = _customers
          .where((customer) =>
              customer.name.toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList();
    }
    notifyListeners();
  }

  // Customer selection
  Future<void> selectCustomer(Customer customer) async {
    _selectedCustomer = customer;
    await loadCustomerTransactions(customer.id!);
  }

  // Drive upload methods removed

  // رفع ملف قاعدة البيانات إلى Telegram فقط (بدلاً من Drive)
  Future<void> backupDatabaseToTelegram({ValueChanged<double>? onProgress}) async {
    _setLoading(true);
    try {
      // 1) تحضير المحتوى المطلوب: قاعدة البيانات + جميع ملفات الصوت
      onProgress?.call(0.05);
      final dbFile = await _db.getDatabaseFile();
      final audioPaths = await _db.getAllAudioNotePaths();

      // 2) إنشاء مجلد مؤقت ونسخ قاعدة البيانات وجمع الصوتيات
      onProgress?.call(0.15);
      final tempDir = await getTemporaryDirectory();
      final backupRoot = Directory('${tempDir.path}/backup_${DateTime.now().millisecondsSinceEpoch}');
      if (!await backupRoot.exists()) {
        await backupRoot.create(recursive: true);
      }
      final dbCopy = File('${backupRoot.path}/debt_book.db');
      await dbCopy.writeAsBytes(await dbFile.readAsBytes(), flush: true);

      final audioDir = Directory('${backupRoot.path}/audio');
      await audioDir.create(recursive: true);
      
      int copiedAudioFiles = 0;
      for (final p in audioPaths) {
        try {
          final f = File(p);
          File? sourceFile = f;
          if (!await f.exists()) {
            // البحث عن الملف في مجلدات أخرى محتملة
            final fileName = p.split(Platform.pathSeparator).last;
            
            // البحث في مجلد قاعدة البيانات الحالي أولاً
            final supportDir = await getApplicationSupportDirectory();
            final dbAudioDir = Directory('${supportDir.path}/audio_notes');
            final currentUserFile = File('${dbAudioDir.path}/$fileName');
            if (await currentUserFile.exists()) {
              sourceFile = currentUserFile;
            } else {
              // البحث في مجلد المستندات العام
              final publicDocs = Directory('${Platform.environment['PUBLIC'] ?? ''}\\Documents');
              if (await publicDocs.exists()) {
                final publicFile = File('${publicDocs.path}\\$fileName');
                if (await publicFile.exists()) {
                  sourceFile = publicFile;
                }
              }
              
              // البحث في مجلد المستندات للمستخدمين الآخرين
              final usersDir = Directory('C:\\Users');
              if (await usersDir.exists()) {
                await for (final userDir in usersDir.list()) {
                  if (userDir is Directory) {
                    final userDocs = Directory('${userDir.path}\\Documents');
                    if (await userDocs.exists()) {
                      final userFile = File('${userDocs.path}\\$fileName');
                      if (await userFile.exists()) {
                        sourceFile = userFile;
                        break;
                      }
                    }
                  }
                }
              }
            }
          }
          
          if (sourceFile != null && await sourceFile.exists()) {
            final fileName = sourceFile.path.split(Platform.pathSeparator).last;
            final targetPath = '${audioDir.path}/$fileName';
            final sourceSize = await sourceFile.length();
            
            if (sourceSize > 0) {
              await sourceFile.copy(targetPath);
              final copiedFile = File(targetPath);
              final copiedSize = await copiedFile.length();
              if (copiedSize == sourceSize) {
                copiedAudioFiles++;
              }
            }
          }
        } catch (e) {
          // تجاهل أخطاء نسخ الملفات الصوتية
        }
      }
      
      // نسخ إضافي للملفات الصوتية من مجلد قاعدة البيانات الحالي
      if (copiedAudioFiles == 0) {
        try {
          final supportDir = await getApplicationSupportDirectory();
          final currentAudioDir = Directory('${supportDir.path}/audio_notes');
          if (await currentAudioDir.exists()) {
            final currentAudioFiles = await currentAudioDir.list().toList();
            for (final file in currentAudioFiles) {
              if (file is File) {
                final fileName = file.path.split(Platform.pathSeparator).last;
                final targetPath = '${audioDir.path}/$fileName';
                if (!await File(targetPath).exists()) {
                  await file.copy(targetPath);
                  copiedAudioFiles++;
                }
              }
            }
          }
        } catch (e) {
          // تجاهل الأخطاء
        }
      }
      
      // نسخ إضافي للملفات الصوتية في مجلد قاعدة البيانات للنسخ الاحتياطية
      if (copiedAudioFiles > 0) {
        try {
          final supportDir = await getApplicationSupportDirectory();
          final backupAudioDir = Directory('${supportDir.path}/audio_backup');
          await backupAudioDir.create(recursive: true);
          
          for (final p in audioPaths) {
            try {
              final f = File(p);
              if (await f.exists()) {
                final base = p.split(Platform.pathSeparator).last;
                final backupPath = '${backupAudioDir.path}/$base';
                await f.copy(backupPath);
              }
            } catch (e) {
              // تجاهل الأخطاء
            }
          }
        } catch (e) {
          // تجاهل الأخطاء
        }
      }

      // 3) استخدام XZ (LZMA2 container) للحصول على أقوى ضغط + ملف أرشيف سليم
      // XZ يستخدم نفس خوارزمية LZMA2 القوية لكن مع Header يجعله ملف أرشيف نظامي
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
      
      // ضغط الـ TAR باستخدام XZ (LZMA2 مع Header صحيح)
      // هذا يعطي أقوى نسبة ضغط (مثل 7-Zip Ultra) وملف سليم .tar.xz
      onProgress?.call(0.65);
      final xzEncoder = XZEncoder();
      final xzData = xzEncoder.encode(tarData);
      
      // اسم الملف النهائي .tar.xz
      final compressedName = '${folderName}_${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}.tar.xz';
      
      final compressedFile = File('${tempDir.path}/$compressedName');
      await compressedFile.writeAsBytes(xzData);

      // 5) إرسال النسخة الاحتياطية إلى Telegram
      onProgress?.call(0.70);
      try {
        final telegramService = TelegramBackupService();
        if (await telegramService.isConfigured) {
          // 📦 1. إرسال ملف قاعدة البيانات (المضغوط)
          final caption = '📦 نسخة XZ Ultra - $branchName - ${now.year}/${now.month}/${now.day} ${now.hour}:${now.minute.toString().padLeft(2, '0')}';
          await telegramService.sendDocument(file: compressedFile, caption: caption);

          // 🛑 2. إرسال نسخ PDF (تقرير الديون وكشوفات الحسابات)
          // يتم إرسالها دائماً عند الرفع اليدوي لضمان اكتمال النسخة
          onProgress?.call(0.75);
          
          print('📄 جاري إرسال تقارير PDF الملحقة...');
          await telegramService.backupDebtRecordsPdf();
          await telegramService.backupAccountStatementsPdf();
          print('✅ تم إرسال كافة التقارير بنجاح');

        } else {
             print('Telegram is not configured');
        }
      } catch (e) {
        print('Error uploading to Telegram: $e');
         throw e; 
      }

      onProgress?.call(1.0);
    } finally {
      _setLoading(false);
    }
  }

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
    print(
        'DEBUG: AppProvider - Saving temp data with ${invoiceItems.length} items');
    for (int i = 0; i < invoiceItems.length; i++) {
      print(
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
    print(
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
    print(
        'DEBUG: AppProvider - Updating temp invoice items. Count: ${items.length}');
    for (int i = 0; i < items.length; i++) {
      print(
          'DEBUG: AppProvider - Update Item $i: ${items[i].productName} - ${items[i].itemTotal}');
    }
    _tempInvoiceItems = List.from(items);
    _hasTempInvoiceData = true;
    print(
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
      print(
          'DEBUG: AppProvider - Updating temp data with ${invoiceItems.length} items');
      _tempInvoiceItems = List.from(invoiceItems);
    }
    _hasTempInvoiceData = true;
    notifyListeners();
  }

  // إنشاء مجلد الملفات الصوتية في نفس مجلد قاعدة البيانات
  Future<void> ensureAudioNotesDirectory() async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      final audioDir = Directory('${supportDir.path}/audio_notes');
      if (!await audioDir.exists()) {
        await audioDir.create(recursive: true);
      }
    } catch (e) {
      // تجاهل الأخطاء
    }
  }

}
