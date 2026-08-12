// lib/services/database/dao/installer_dao.dart
// عمليات CRUD للفنيين/المركبين

import 'package:sqflite/sqflite.dart';
import '../../../models/installer.dart';
import '../../../utils/money_calculator.dart';
import '../core/database_helpers.dart';

/// DAO للفنيين/المركبين - عمليات CRUD ونظام النقاط
class InstallerDao {
  final Future<Database> Function() getDatabase;

  InstallerDao({required this.getDatabase});

  /// إضافة فني جديد
  Future<int> insertInstaller(Installer installer) async {
    final db = await getDatabase();
    try {
      return await db.insert('installers', installer.toMap());
    } catch (e) {
      throw Exception(DatabaseHelpers.handleDatabaseError(e));
    }
  }

  /// جلب جميع الفنيين
  Future<List<Installer>> getAllInstallers({String orderBy = 'name ASC'}) async {
    final db = await getDatabase();
    try {
      final List<Map<String, dynamic>> maps =
          await db.query('installers', orderBy: orderBy);
      return List.generate(maps.length, (i) => Installer.fromMap(maps[i]));
    } catch (e) {
      throw Exception(DatabaseHelpers.handleDatabaseError(e));
    }
  }

  /// جلب فني بالاسم
  Future<Installer?> getInstallerByName(String name) async {
    final db = await getDatabase();
    try {
      final List<Map<String, dynamic>> maps = await db.query(
        'installers',
        where: 'name = ?',
        whereArgs: [name],
        limit: 1,
      );
      if (maps.isNotEmpty) {
        return Installer.fromMap(maps.first);
      }
      return null;
    } catch (e) {
      throw Exception(DatabaseHelpers.handleDatabaseError(e));
    }
  }

  /// بحث الفنيين
  Future<List<Installer>> searchInstallers(String query) async {
    final db = await getDatabase();
    try {
      final List<Map<String, dynamic>> maps = await db.query(
        'installers',
        where: 'name LIKE ?',
        whereArgs: ['%$query%'],
        orderBy: 'name ASC',
      );
      return List.generate(maps.length, (i) => Installer.fromMap(maps[i]));
    } catch (e) {
      throw Exception(DatabaseHelpers.handleDatabaseError(e));
    }
  }

  /// جلب فواتير الفني
  Future<List<Map<String, dynamic>>> getInvoicesByInstaller(
    int installerId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final db = await getDatabase();
    try {
      // First get the name if we are using name in invoices table, 
      // OR we might want to filter by ID if invoices has installer_id.
      // Assuming invoices has `installer_name` based on previous code.
      // Ideally we should use installer_id.
      
      final List<Map<String, dynamic>> installerMaps = await db.query(
        'installers',
        columns: ['name'],
        where: 'id = ?',
        whereArgs: [installerId],
      );
      
      if (installerMaps.isEmpty) return [];
      final String installerName = installerMaps.first['name'] as String;

      String whereClause = "installer_name = ?";
      List<dynamic> args = [installerName];

      if (startDate != null) {
        whereClause += " AND invoice_date >= ?";
        args.add(startDate.toIso8601String());
      }
      if (endDate != null) {
        whereClause += " AND invoice_date <= ?";
        args.add(endDate.toIso8601String());
      }

      return await db.query(
        'invoices',
        where: whereClause,
        whereArgs: args,
        orderBy: 'invoice_date DESC',
      );
    } catch (e) {
      throw Exception(DatabaseHelpers.handleDatabaseError(e));
    }
  }

  // --- نظام النقاط ---

  /// إضافة نقاط للفني يدوياً
  Future<void> addInstallerPoints(
    int installerId, 
    double points, 
    String reason, 
    {int? invoiceId}
  ) async {
    final db = await getDatabase();
    await db.transaction((txn) async {
      // 1. Insert into installer_points
      await txn.insert('installer_points', {
        'installer_id': installerId,
        'invoice_id': invoiceId,
        'points': points,
        'reason': reason,
        'created_at': DateTime.now().toIso8601String(),
      });

      // 2. Update installer total_points
      final List<Map<String, dynamic>> installerMaps = await txn.query(
        'installers',
        columns: ['total_points'],
        where: 'id = ?',
        whereArgs: [installerId],
      );
      
      if (installerMaps.isNotEmpty) {
        double currentPoints = (installerMaps.first['total_points'] as num?)?.toDouble() ?? 0.0;
        double newTotal = MoneyCalculator.add(currentPoints, points);
        
        await txn.update(
          'installers',
          {'total_points': newTotal},
          where: 'id = ?',
          whereArgs: [installerId],
        );
      }
    });
  }

  /// خصم نقاط من الفني يدوياً
  Future<void> deductInstallerPoints(int installerId, double points, String reason) async {
    final db = await getDatabase();
    await db.transaction((txn) async {
      // 1. Insert into installer_points with negative value
      await txn.insert('installer_points', {
        'installer_id': installerId,
        'invoice_id': null,
        'points': -points,
        'reason': reason,
        'created_at': DateTime.now().toIso8601String(),
      });

      // 2. Update installer total_points
      final List<Map<String, dynamic>> installerMaps = await txn.query(
        'installers',
        columns: ['total_points'],
        where: 'id = ?',
        whereArgs: [installerId],
      );
      
      if (installerMaps.isNotEmpty) {
        double currentPoints = (installerMaps.first['total_points'] as num?)?.toDouble() ?? 0.0;
        double newTotal = MoneyCalculator.subtract(currentPoints, points);
        
        await txn.update(
          'installers',
          {'total_points': newTotal},
          where: 'id = ?',
          whereArgs: [installerId],
        );
      }
    });
  }

  /// جلب سجل النقاط للفني
  Future<List<Map<String, dynamic>>> getInstallerPointsHistory(int installerId) async {
    final db = await getDatabase();
    return await db.query(
      'installer_points',
      where: 'installer_id = ?',
      whereArgs: [installerId],
      orderBy: 'created_at DESC',
    );
  }

  /// تحديث نقاط الفني من فاتورة
  Future<void> updateInstallerPointsFromInvoice(
    int invoiceId, 
    String installerName, 
    double invoiceTotal, {
    double? customPoints,
    double pointsPerHundredThousand = 1.0,
  }) async {
    if (installerName.trim().isEmpty) return;

    final db = await getDatabase();
    
    // 1. Find the installer by name
    final List<Map<String, dynamic>> installers = await db.query(
      'installers',
      where: 'name = ?',
      whereArgs: [installerName],
    );
    
    if (installers.isEmpty) return; 
    
    final int installerId = installers.first['id'] as int;
    
    // 2. Calculate points
    final double newPoints = customPoints ?? (invoiceTotal / 100000.0) * pointsPerHundredThousand;
    
    await db.transaction((txn) async {
      // 3. Check if points already exist for this invoice
      final List<Map<String, dynamic>> existingPoints = await txn.query(
        'installer_points',
        where: 'invoice_id = ?',
        whereArgs: [invoiceId],
      );
      
      if (existingPoints.isNotEmpty) {
        // Update existing entry
        final double oldPoints = (existingPoints.first['points'] as num).toDouble();
        final double diff = MoneyCalculator.subtract(newPoints, oldPoints);
        
        if (diff.abs() > 0.001) {
          await txn.update(
            'installer_points',
            {
              'points': newPoints,
              'reason': 'فاتورة رقم $invoiceId (تعديل)',
            },
            where: 'invoice_id = ?',
            whereArgs: [invoiceId],
          );
          
          // Update total points
          final List<Map<String, dynamic>> inst = await txn.query(
            'installers',
            columns: ['total_points'],
            where: 'id = ?',
            whereArgs: [installerId],
          );
          double currentTotal = (inst.first['total_points'] as num?)?.toDouble() ?? 0.0;
          await txn.update(
            'installers',
            {'total_points': currentTotal + diff},
            where: 'id = ?',
            whereArgs: [installerId],
          );
        }
      } else {
        // Insert new entry
        await txn.insert('installer_points', {
          'installer_id': installerId,
          'invoice_id': invoiceId,
          'points': newPoints,
          'reason': 'فاتورة رقم $invoiceId',
          'created_at': DateTime.now().toIso8601String(),
        });
        
        // Update total points
        final List<Map<String, dynamic>> inst = await txn.query(
          'installers',
          columns: ['total_points'],
          where: 'id = ?',
          whereArgs: [installerId],
        );
        double currentTotal = (inst.first['total_points'] as num?)?.toDouble() ?? 0.0;
        await txn.update(
          'installers',
          {'total_points': currentTotal + newPoints},
          where: 'id = ?',
          whereArgs: [installerId],
        );
      }
    });
  }

  /// تحديث إجمالي المبلغ المفوتر للفني
  Future<void> updateInstallerBilledAmount(int installerId) async {
    final db = await getDatabase();
    
    // 1. Get installer name
    final List<Map<String, dynamic>> installerMaps = await db.query(
      'installers',
      columns: ['name'],
      where: 'id = ?',
      whereArgs: [installerId],
    );
    
    if (installerMaps.isEmpty) return;
    final String installerName = installerMaps.first['name'] as String;

    // 2. Sum all invoices for this installer
    final List<Map<String, dynamic>> result = await db.rawQuery('''
      SELECT SUM(total_amount) as total 
      FROM invoices 
      WHERE installer_name = ? AND status = 'محفوظة'
    ''', [installerName]);
    
    double total = 0.0;
    if (result.isNotEmpty && result.first['total'] != null) {
      total = (result.first['total'] as num).toDouble();
    }

    // 3. Update installer record
    await db.update(
      'installers',
      {'total_billed_amount': total},
      where: 'id = ?',
      whereArgs: [installerId],
    );
  }

  /// إعادة حساب إجمالي المبلغ المفوتر لجميع الفنيين
  Future<void> recalculateAllInstallersBilledAmount() async {
    final db = await getDatabase();
    try {
      final installers = await db.query('installers');
      for (final installer in installers) {
        final id = installer['id'] as int;
        await updateInstallerBilledAmount(id);
      }
      print('✅ تم إعادة حساب المبلغ المفوتر لـ ${installers.length} فني');
    } catch (e) {
      print('❌ خطأ في إعادة حساب المبلغ المفوتر: $e');
    }
  }
}
