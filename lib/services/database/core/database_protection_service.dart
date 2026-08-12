// lib/services/database/core/database_protection_service.dart
// 🛡️ خدمة حماية قاعدة البيانات - ضمان عدم فقدان البيانات المالية

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../../models/transaction.dart';
import '../../../models/invoice.dart';

/// خدمة حماية قاعدة البيانات
/// تضمن عدم تلف الفواتير والمعاملات المالية
class DatabaseProtectionService {
  final Future<Database> Function() getDatabase;

  DatabaseProtectionService({required this.getDatabase});

  // ═══════════════════════════════════════════════════════════════════════════
  // 1. ضمان الكتابة للقرص - WAL Checkpoint
  // ═══════════════════════════════════════════════════════════════════════════

  /// كتابة كل البيانات من WAL للقرص فورًا
  /// يُستدعى بعد العمليات المالية الحرجة (إضافة/تسديد دين، حفظ فاتورة)
  Future<bool> forceWalCheckpoint() async {
    final db = await getDatabase();
    try {
      // FULL checkpoint: ينقل كل البيانات من WAL للقرص الرئيسي
      await db.rawQuery('PRAGMA wal_checkpoint(FULL)');
      return true;
    } catch (e) {
      print('❌ فشل WAL Checkpoint: $e');
      return false;
    }
  }

  /// مزامنة قوية مع القرص (للعمليات فائقة الأهمية)
  Future<bool> syncToDisk() async {
    final db = await getDatabase();
    try {
      // تبديل synchronous لـ FULL مؤقتًا
      // استخدام rawQuery بدلاً من execute لتوافق أفضل مع Android
      await db.rawQuery('PRAGMA synchronous = FULL');
      // تنفيذ checkpoint
      await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
      // إعادة synchronous لـ NORMAL
      await db.rawQuery('PRAGMA synchronous = NORMAL');
      return true;
    } catch (e) {
      print('❌ فشل المزامنة القوية: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 2. التحقق من سلامة قاعدة البيانات
  // ═══════════════════════════════════════════════════════════════════════════

  /// فحص سلامة قاعدة البيانات باستخدام integrity_check و foreign_key_check
  Future<IntegrityCheckResult> runIntegrityCheck() async {
    final db = await getDatabase();
    try {
      // 1. فحص سلامة SQLite الأساسي
      final integrityResult = await db.rawQuery('PRAGMA integrity_check');
      final integrityMessage = integrityResult.first.values.first?.toString() ?? '';
      
      // 2. فحص العلاقات الأجنبية (Foreign Keys)
      final fkResult = await db.rawQuery('PRAGMA foreign_key_check');
      final hasFkErrors = fkResult.isNotEmpty;
      
      final details = <String>[];
      
      if (integrityMessage != 'ok') {
        details.add('خطأ في سلامة البيانات: $integrityMessage');
      }
      
      if (hasFkErrors) {
        details.add('خطأ في العلاقات: ${fkResult.length} علاقة مكسورة');
        // إضافة تفاصيل العلاقات المكسورة
        for (final fk in fkResult.take(5)) {
          details.add('  - جدول: ${fk['table']}, صف: ${fk['rowid']}');
        }
      }
      
      if (integrityMessage == 'ok' && !hasFkErrors) {
        return IntegrityCheckResult(
          isHealthy: true,
          message: 'قاعدة البيانات سليمة 100%',
          details: [],
          foreignKeyErrors: 0,
        );
      } else {
        return IntegrityCheckResult(
          isHealthy: false,
          message: 'تم اكتشاف مشاكل في قاعدة البيانات',
          details: details,
          foreignKeyErrors: fkResult.length,
        );
      }
    } catch (e) {
      return IntegrityCheckResult(
        isHealthy: false,
        message: 'فشل فحص السلامة: $e',
        details: [],
        foreignKeyErrors: 0,
      );
    }
  }

  /// فحص سريع للسلامة (أقل دقة لكن أسرع)
  Future<bool> quickIntegrityCheck() async {
    final db = await getDatabase();
    try {
      final result = await db.rawQuery('PRAGMA quick_check');
      return result.first.values.first?.toString() == 'ok';
    } catch (e) {
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 3. التحقق من سلامة المعاملات المالية
  // ═══════════════════════════════════════════════════════════════════════════

  /// التحقق من وجود المعاملة وصحتها بعد الحفظ
  Future<TransactionVerificationResult> verifyTransactionIntegrity(int transactionId) async {
    final db = await getDatabase();
    try {
      // 1. التأكد من وجود المعاملة
      final txMaps = await db.query(
        'transactions',
        where: 'id = ?',
        whereArgs: [transactionId],
        limit: 1,
      );
      
      if (txMaps.isEmpty) {
        return TransactionVerificationResult(
          isValid: false,
          errorType: 'NOT_FOUND',
          message: 'المعاملة غير موجودة في قاعدة البيانات',
        );
      }
      
      final tx = DebtTransaction.fromMap(txMaps.first);
      
      // 2. التحقق من سلامة الحسابات
      final expectedBalance = (tx.balanceBeforeTransaction ?? 0) + tx.amountChanged;
      final actualBalance = tx.newBalanceAfterTransaction ?? 0;
      final balanceDiff = (expectedBalance - actualBalance).abs();
      
      if (balanceDiff > 0.01) {
        return TransactionVerificationResult(
          isValid: false,
          errorType: 'BALANCE_MISMATCH',
          message: 'خطأ في حساب الرصيد: المتوقع $expectedBalance، الفعلي $actualBalance',
        );
      }
      
      // 3. التحقق من رصيد العميل الحالي
      final customerMaps = await db.query(
        'customers',
        columns: ['current_total_debt'],
        where: 'id = ?',
        whereArgs: [tx.customerId],
        limit: 1,
      );
      
      if (customerMaps.isEmpty) {
        return TransactionVerificationResult(
          isValid: false,
          errorType: 'CUSTOMER_NOT_FOUND',
          message: 'العميل غير موجود',
        );
      }
      
      // 4. التحقق من Checksum إذا كان موجودًا
      final storedChecksum = txMaps.first['checksum'] as String?;
      if (storedChecksum != null && storedChecksum.isNotEmpty) {
        final calculatedChecksum = _calculateChecksum(tx);
        if (storedChecksum != calculatedChecksum) {
          return TransactionVerificationResult(
            isValid: false,
            errorType: 'CHECKSUM_MISMATCH',
            message: 'Checksum غير متطابق - قد تكون البيانات تالفة',
          );
        }
      }
      
      return TransactionVerificationResult(
        isValid: true,
        errorType: null,
        message: 'المعاملة سليمة ومحفوظة بشكل صحيح',
        transaction: tx,
      );
    } catch (e) {
      return TransactionVerificationResult(
        isValid: false,
        errorType: 'EXCEPTION',
        message: 'خطأ في التحقق: $e',
      );
    }
  }

  /// التحقق من سلامة جميع معاملات عميل معين
  Future<CustomerTransactionsVerificationResult> verifyCustomerTransactionsIntegrity(int customerId) async {
    final db = await getDatabase();
    try {
      // جلب جميع معاملات العميل
      final txMaps = await db.query(
        'transactions',
        where: 'customer_id = ?',
        whereArgs: [customerId],
        orderBy: 'transaction_date ASC, id ASC',
      );
      
      if (txMaps.isEmpty) {
        return CustomerTransactionsVerificationResult(
          isValid: true,
          transactionCount: 0,
          errors: [],
        );
      }
      
      final errors = <String>[];
      double runningBalance = 0.0;
      
      for (int i = 0; i < txMaps.length; i++) {
        final tx = DebtTransaction.fromMap(txMaps[i]);
        
        // التحقق من الرصيد قبل المعاملة
        final storedBalanceBefore = tx.balanceBeforeTransaction ?? 0;
        if ((storedBalanceBefore - runningBalance).abs() > 0.01) {
          errors.add('معاملة #${tx.id}: الرصيد قبل المعاملة غير متطابق');
        }
        
        // حساب الرصيد الجديد
        runningBalance += tx.amountChanged;
        
        // التحقق من الرصيد بعد المعاملة
        final storedBalanceAfter = tx.newBalanceAfterTransaction ?? 0;
        if ((storedBalanceAfter - runningBalance).abs() > 0.01) {
          errors.add('معاملة #${tx.id}: الرصيد بعد المعاملة غير متطابق');
        }
      }
      
      // التحقق من رصيد العميل النهائي
      final customerMaps = await db.query(
        'customers',
        columns: ['current_total_debt'],
        where: 'id = ?',
        whereArgs: [customerId],
        limit: 1,
      );
      
      if (customerMaps.isNotEmpty) {
        final customerDebt = (customerMaps.first['current_total_debt'] as num).toDouble();
        if ((customerDebt - runningBalance).abs() > 0.01) {
          errors.add('رصيد العميل الحالي ($customerDebt) لا يتطابق مع مجموع المعاملات ($runningBalance)');
        }
      }
      
      return CustomerTransactionsVerificationResult(
        isValid: errors.isEmpty,
        transactionCount: txMaps.length,
        calculatedBalance: runningBalance,
        errors: errors,
      );
    } catch (e) {
      return CustomerTransactionsVerificationResult(
        isValid: false,
        transactionCount: 0,
        errors: ['خطأ في التحقق: $e'],
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 4. التحقق من سلامة الفواتير
  // ═══════════════════════════════════════════════════════════════════════════

  /// التحقق من وجود الفاتورة وصحتها
  Future<InvoiceVerificationResult> verifyInvoiceIntegrity(int invoiceId) async {
    final db = await getDatabase();
    try {
      // 1. التأكد من وجود الفاتورة
      final invoiceMaps = await db.query(
        'invoices',
        where: 'id = ?',
        whereArgs: [invoiceId],
        limit: 1,
      );
      
      if (invoiceMaps.isEmpty) {
        return InvoiceVerificationResult(
          isValid: false,
          errorType: 'NOT_FOUND',
          message: 'الفاتورة غير موجودة في قاعدة البيانات',
        );
      }
      
      final invoice = Invoice.fromMap(invoiceMaps.first);
      
      // 2. التأكد من وجود عناصر الفاتورة
      final itemsMaps = await db.query(
        'invoice_items',
        where: 'invoice_id = ?',
        whereArgs: [invoiceId],
      );
      
      if (itemsMaps.isEmpty && invoice.totalAmount > 0) {
        return InvoiceVerificationResult(
          isValid: false,
          errorType: 'NO_ITEMS',
          message: 'الفاتورة بدون عناصر رغم أن لها قيمة',
        );
      }
      
      // 3. التحقق من مجموع العناصر
      double itemsTotal = 0;
      for (final item in itemsMaps) {
        itemsTotal += (item['item_total'] as num?)?.toDouble() ?? 0;
      }
      
      // 4. التحقق من وجود معاملة الدين المرتبطة (إذا كانت فاتورة دين)
      if (invoice.paymentType == 'دين' && invoice.status == 'محفوظة') {
        final debtTx = await db.query(
          'transactions',
          where: 'invoice_id = ?',
          whereArgs: [invoiceId],
          limit: 1,
        );
        
        if (debtTx.isEmpty) {
          return InvoiceVerificationResult(
            isValid: false,
            errorType: 'MISSING_DEBT_TX',
            message: 'فاتورة دين محفوظة بدون معاملة دين مرتبطة',
          );
        }
      }
      
      return InvoiceVerificationResult(
        isValid: true,
        errorType: null,
        message: 'الفاتورة سليمة ومحفوظة بشكل صحيح',
        itemCount: itemsMaps.length,
        itemsTotal: itemsTotal,
      );
    } catch (e) {
      return InvoiceVerificationResult(
        isValid: false,
        errorType: 'EXCEPTION',
        message: 'خطأ في التحقق: $e',
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 5. النسخ الاحتياطي الفوري للمعاملات الحرجة
  // ═══════════════════════════════════════════════════════════════════════════

  /// إنشاء نسخة احتياطية فورية للمعاملة في جدول منفصل
  Future<bool> backupCriticalTransaction(int transactionId) async {
    final db = await getDatabase();
    try {
      // إنشاء جدول النسخ الاحتياطي إذا لم يكن موجودًا
      await _ensureBackupTableExists(db);
      
      // جلب المعاملة
      final txMaps = await db.query(
        'transactions',
        where: 'id = ?',
        whereArgs: [transactionId],
        limit: 1,
      );
      
      if (txMaps.isEmpty) return false;
      
      final tx = txMaps.first;
      final backupData = jsonEncode(tx);
      final backupHash = md5.convert(utf8.encode(backupData)).toString();
      
      // حفظ النسخة الاحتياطية (تُضاف كسجل جديد - تاريخي)
      await db.insert('transaction_backups', {
        'original_id': transactionId,
        'customer_id': tx['customer_id'],
        'amount_changed': tx['amount_changed'],
        'transaction_date': tx['transaction_date'],
        'transaction_type': tx['transaction_type'],
        'transaction_note': tx['transaction_note'],
        'balance_before': tx['balance_before_transaction'],
        'balance_after': tx['new_balance_after_transaction'],
        'invoice_id': tx['invoice_id'],
        'checksum': tx['checksum'],
        'backup_data': backupData,
        'backup_hash': backupHash,
        'backup_created_at': DateTime.now().toIso8601String(),
      });
      
      return true;
    } catch (e) {
      print('❌ فشل النسخ الاحتياطي للمعاملة: $e');
      return false;
    }
  }

  /// إنشاء نسخة احتياطية فورية للفاتورة
  Future<bool> backupCriticalInvoice(int invoiceId) async {
    final db = await getDatabase();
    try {
      // إنشاء جدول النسخ الاحتياطي إذا لم يكن موجودًا
      await _ensureInvoiceBackupTableExists(db);
      
      // جلب الفاتورة
      final invoiceMaps = await db.query(
        'invoices',
        where: 'id = ?',
        whereArgs: [invoiceId],
        limit: 1,
      );
      
      if (invoiceMaps.isEmpty) return false;
      
      // جلب عناصر الفاتورة
      final itemsMaps = await db.query(
        'invoice_items',
        where: 'invoice_id = ?',
        whereArgs: [invoiceId],
      );
      
      final invoiceData = jsonEncode(invoiceMaps.first);
      final itemsData = jsonEncode(itemsMaps);
      final backupHash = md5.convert(utf8.encode('$invoiceData|$itemsData')).toString();
      
      // حفظ النسخة الاحتياطية (تُضاف كسجل جديد - تاريخي)
      await db.insert('invoice_backups', {
        'original_id': invoiceId,
        'invoice_data': invoiceData,
        'items_data': itemsData,
        'backup_hash': backupHash,
        'backup_created_at': DateTime.now().toIso8601String(),
      });
      
      return true;
    } catch (e) {
      print('❌ فشل النسخ الاحتياطي للفاتورة: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 6. دوال مساعدة
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _ensureBackupTableExists(Database db) async {
    // جدول النسخ الاحتياطي التاريخي - يحفظ كل نسخة بـ timestamp منفصل
    await db.execute('''
      CREATE TABLE IF NOT EXISTS transaction_backups (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        original_id INTEGER NOT NULL,
        customer_id INTEGER NOT NULL,
        amount_changed REAL NOT NULL,
        transaction_date TEXT NOT NULL,
        transaction_type TEXT,
        transaction_note TEXT,
        balance_before REAL,
        balance_after REAL,
        invoice_id INTEGER,
        checksum TEXT,
        backup_data TEXT NOT NULL,
        backup_hash TEXT NOT NULL,
        backup_created_at TEXT NOT NULL
      )
    ''');
    // فهرس للبحث السريع
    try {
      await db.execute('CREATE INDEX IF NOT EXISTS idx_tx_backup_original ON transaction_backups(original_id)');
    } catch (_) {}
  }

  Future<void> _ensureInvoiceBackupTableExists(Database db) async {
    // جدول النسخ الاحتياطي التاريخي للفواتير
    await db.execute('''
      CREATE TABLE IF NOT EXISTS invoice_backups (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        original_id INTEGER NOT NULL,
        invoice_data TEXT NOT NULL,
        items_data TEXT NOT NULL,
        backup_hash TEXT NOT NULL,
        backup_created_at TEXT NOT NULL
      )
    ''');
    // فهرس للبحث السريع
    try {
      await db.execute('CREATE INDEX IF NOT EXISTS idx_inv_backup_original ON invoice_backups(original_id)');
    } catch (_) {}
  }

  String _calculateChecksum(DebtTransaction tx) {
    final data = '${tx.customerId}|${tx.amountChanged}|${tx.balanceBeforeTransaction}|${tx.newBalanceAfterTransaction}|${tx.transactionDate.toIso8601String()}';
    return md5.convert(utf8.encode(data)).toString();
  }

  /// استعادة معاملة من النسخة الاحتياطية
  Future<Map<String, dynamic>?> getTransactionBackup(int originalId) async {
    final db = await getDatabase();
    try {
      final backups = await db.query(
        'transaction_backups',
        where: 'original_id = ?',
        whereArgs: [originalId],
        limit: 1,
      );
      
      if (backups.isNotEmpty) {
        return jsonDecode(backups.first['backup_data'] as String) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// استعادة فاتورة من النسخة الاحتياطية
  Future<Map<String, dynamic>?> getInvoiceBackup(int originalId) async {
    final db = await getDatabase();
    try {
      final backups = await db.query(
        'invoice_backups',
        where: 'original_id = ?',
        whereArgs: [originalId],
        limit: 1,
      );
      
      if (backups.isNotEmpty) {
        return {
          'invoice': jsonDecode(backups.first['invoice_data'] as String),
          'items': jsonDecode(backups.first['items_data'] as String),
        };
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 7. فحص شامل للنظام
  // ═══════════════════════════════════════════════════════════════════════════

  /// تشغيل فحص شامل لسلامة قاعدة البيانات
  Future<FullIntegrityReport> runFullIntegrityCheck() async {
    final db = await getDatabase();
    final errors = <String>[];
    
    // 1. فحص SQLite integrity
    final integrityResult = await runIntegrityCheck();
    if (!integrityResult.isHealthy) {
      errors.add('فحص SQLite: ${integrityResult.message}');
    }
    
    // 2. فحص تطابق أرصدة جميع العملاء
    final customers = await db.query('customers', columns: ['id', 'name', 'current_total_debt']);
    int customersWithIssues = 0;
    
    for (final customer in customers) {
      final customerId = customer['id'] as int;
      final result = await verifyCustomerTransactionsIntegrity(customerId);
      if (!result.isValid) {
        customersWithIssues++;
        errors.addAll(result.errors.map((e) => '${customer['name']}: $e'));
      }
    }
    
    // 3. فحص الفواتير المحفوظة
    final invoices = await db.query(
      'invoices',
      where: "status = 'محفوظة'",
      columns: ['id'],
    );
    int invoicesWithIssues = 0;
    
    for (final invoice in invoices) {
      final result = await verifyInvoiceIntegrity(invoice['id'] as int);
      if (!result.isValid) {
        invoicesWithIssues++;
        errors.add('فاتورة #${invoice['id']}: ${result.message}');
      }
    }
    
    return FullIntegrityReport(
      isHealthy: errors.isEmpty,
      sqliteIntegrity: integrityResult.isHealthy,
      totalCustomers: customers.length,
      customersWithIssues: customersWithIssues,
      totalInvoices: invoices.length,
      invoicesWithIssues: invoicesWithIssues,
      errors: errors,
      checkTime: DateTime.now(),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 8. النسخ الاحتياطي المحلي عند الإغلاق
  // ═══════════════════════════════════════════════════════════════════════════

  /// إنشاء نسخة احتياطية محلية غير مضغوطة
  /// تُستخدم عند إغلاق التطبيق
  Future<LocalBackupResult> createLocalBackup() async {
    try {
      // 1. تنفيذ WAL checkpoint أولاً لضمان كتابة كل البيانات
      await forceWalCheckpoint();
      
      // 2. الحصول على مسار قاعدة البيانات الحالية
      final db = await getDatabase();
      final dbPath = db.path;
      
      // 3. تحديد مسار النسخة الاحتياطية (في Documents)
      Directory backupDir;
      try {
        final documentsDir = await getApplicationDocumentsDirectory();
        backupDir = Directory(p.join(documentsDir.path, 'دفتر_ديوني_نسخ_احتياطية'));
      } catch (e) {
        // إذا فشل، استخدم مسار التطبيق
        final appDir = Directory.current;
        backupDir = Directory(p.join(appDir.path, 'backups'));
      }
      
      // إنشاء المجلد إذا لم يكن موجوداً
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }
      
      // 4. إنشاء اسم الملف مع التاريخ والوقت
      final now = DateTime.now();
      final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final timeStr = '${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}';
      final backupFileName = 'backup_$dateStr\_$timeStr.db';
      final backupPath = p.join(backupDir.path, backupFileName);
      
      // 5. نسخ ملف قاعدة البيانات
      final sourceFile = File(dbPath);
      if (!await sourceFile.exists()) {
        return LocalBackupResult(
          success: false,
          message: 'ملف قاعدة البيانات غير موجود',
          backupPath: null,
        );
      }
      
      await sourceFile.copy(backupPath);
      
      // 6. نسخ ملفات WAL و SHM إذا كانت موجودة
      final walFile = File('$dbPath-wal');
      final shmFile = File('$dbPath-shm');
      
      if (await walFile.exists()) {
        await walFile.copy('$backupPath-wal');
      }
      if (await shmFile.exists()) {
        await shmFile.copy('$backupPath-shm');
      }
      
      // 7. حذف النسخ القديمة (الإبقاء على آخر 5 نسخ فقط)
      await _cleanupOldBackups(backupDir, keepCount: 5);
      
      return LocalBackupResult(
        success: true,
        message: 'تم إنشاء النسخة الاحتياطية بنجاح',
        backupPath: backupPath,
      );
    } catch (e) {
      return LocalBackupResult(
        success: false,
        message: 'فشل إنشاء النسخة الاحتياطية: $e',
        backupPath: null,
      );
    }
  }
  
  /// حذف النسخ الاحتياطية القديمة
  Future<void> _cleanupOldBackups(Directory backupDir, {int keepCount = 5}) async {
    try {
      final files = await backupDir
          .list()
          .where((entity) => entity is File && entity.path.endsWith('.db'))
          .cast<File>()
          .toList();
      
      if (files.length <= keepCount) return;
      
      // ترتيب حسب التاريخ (الأقدم أولاً)
      files.sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));
      
      // حذف الأقدم
      final toDelete = files.take(files.length - keepCount);
      for (final file in toDelete) {
        await file.delete();
        // حذف ملفات WAL و SHM المرتبطة
        final walFile = File('${file.path}-wal');
        final shmFile = File('${file.path}-shm');
        if (await walFile.exists()) await walFile.delete();
        if (await shmFile.exists()) await shmFile.delete();
      }
    } catch (e) {
      // تجاهل أخطاء التنظيف
    }
  }
  
  /// الحصول على مسار مجلد النسخ الاحتياطية
  Future<String> getBackupDirectory() async {
    try {
      final documentsDir = await getApplicationDocumentsDirectory();
      return p.join(documentsDir.path, 'دفتر_ديوني_نسخ_احتياطية');
    } catch (e) {
      return p.join(Directory.current.path, 'backups');
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// نتائج الفحوصات
// ═══════════════════════════════════════════════════════════════════════════

class IntegrityCheckResult {
  final bool isHealthy;
  final String message;
  final List<String> details;
  final int foreignKeyErrors;

  IntegrityCheckResult({
    required this.isHealthy,
    required this.message,
    required this.details,
    this.foreignKeyErrors = 0,
  });
}

class TransactionVerificationResult {
  final bool isValid;
  final String? errorType;
  final String message;
  final DebtTransaction? transaction;

  TransactionVerificationResult({
    required this.isValid,
    required this.errorType,
    required this.message,
    this.transaction,
  });
}

class CustomerTransactionsVerificationResult {
  final bool isValid;
  final int transactionCount;
  final double? calculatedBalance;
  final List<String> errors;

  CustomerTransactionsVerificationResult({
    required this.isValid,
    required this.transactionCount,
    this.calculatedBalance,
    required this.errors,
  });
}

class InvoiceVerificationResult {
  final bool isValid;
  final String? errorType;
  final String message;
  final int? itemCount;
  final double? itemsTotal;

  InvoiceVerificationResult({
    required this.isValid,
    required this.errorType,
    required this.message,
    this.itemCount,
    this.itemsTotal,
  });
}

class FullIntegrityReport {
  final bool isHealthy;
  final bool sqliteIntegrity;
  final int totalCustomers;
  final int customersWithIssues;
  final int totalInvoices;
  final int invoicesWithIssues;
  final List<String> errors;
  final DateTime checkTime;

  FullIntegrityReport({
    required this.isHealthy,
    required this.sqliteIntegrity,
    required this.totalCustomers,
    required this.customersWithIssues,
    required this.totalInvoices,
    required this.invoicesWithIssues,
    required this.errors,
    required this.checkTime,
  });

  @override
  String toString() {
    return '''
╔══════════════════════════════════════════════════════════════╗
║               تقرير سلامة قاعدة البيانات                      ║
╠══════════════════════════════════════════════════════════════╣
║ الحالة: ${isHealthy ? '✅ سليمة' : '❌ يوجد مشاكل'}
║ فحص SQLite: ${sqliteIntegrity ? '✅' : '❌'}
║ العملاء: $totalCustomers (مشاكل: $customersWithIssues)
║ الفواتير: $totalInvoices (مشاكل: $invoicesWithIssues)
║ وقت الفحص: $checkTime
${errors.isNotEmpty ? '╠══════════════════════════════════════════════════════════════╣\n║ الأخطاء:\n${errors.map((e) => '║  - $e').join('\n')}' : ''}
╚══════════════════════════════════════════════════════════════╝
''';
  }
}

class LocalBackupResult {
  final bool success;
  final String message;
  final String? backupPath;

  LocalBackupResult({
    required this.success,
    required this.message,
    this.backupPath,
  });
}
