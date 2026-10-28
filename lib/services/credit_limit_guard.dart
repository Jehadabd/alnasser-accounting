// lib/services/credit_limit_guard.dart
//
// 🚫 سقف الدين — يُفرض لحظة الحفظ:
//   • فاتورة آجلة جديدة: الرصيد + (مجموعها − المدفوع منها).
//   • تعديل فاتورة آجلة: الزيادة فقط (الجديد − ما هو مسجّل لها في المعاملات فعلاً).
//   • إضافة دين يدوي، أو تعديل معاملة دين بزيادتها.
//   • بيع آجل في الكاشير.
// إن تجاوز الرصيد الناتج سقف العميل (بطاقة العميل ← سقف الدين) يُمنع الحفظ، إلا
// بموافقة المدير: المدير المسجّل دخوله يؤكد بنفسه، وغيره يحتاج كلمة سر المدير.
// كل تجاوز يُسجَّل في سجل النشاط. العميل بلا سقف (فارغ أو صفر) لا يُقيَّد.
// لا يغيّر هذا الملف أي رقم — يقرأ فقط ويقرر هل يستمر الحفظ.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:sqflite/sqflite.dart';

import '../erp/activity/activity_log.dart';
import 'auth_service.dart';
import 'database/business/customer_name_rule.dart';
import 'database/business/invoice_debt_reconciler.dart';
import 'database_service.dart';

class CreditLimitGuard {
  CreditLimitGuard._();

  static final _nf = NumberFormat('#,##0', 'en_US');
  static String _m(num v) => _nf.format(v.round());

  /// سقف دين العميل (null = بلا سقف).
  static Future<double?> limitOf(DatabaseExecutor db, int customerId) async {
    try {
      final r = await db.rawQuery('SELECT credit_limit FROM customer_ext WHERE customer_id = ? LIMIT 1', [customerId]);
      final v = r.isEmpty ? null : (r.first['credit_limit'] as num?)?.toDouble();
      return (v == null || v <= 0) ? null : v;
    } catch (_) {
      return null; // لا جدول بطاقات بعد
    }
  }

  /// معرّف العميل الفعّال بهذا الاسم (null = عميل جديد أو نقدي).
  static Future<int?> customerIdByName(DatabaseExecutor db, String name) async {
    final n = name.trim();
    if (n.isEmpty || n == 'عميل نقدي') return null;
    try {
      final row = await CustomerNameRule.findActive(db, n);
      return (row?['id'] as num?)?.toInt();
    } catch (_) {
      return null;
    }
  }

  /// ما سيُضاف إلى دين العميل بحفظ فاتورة: الجديد − المسجّل لها فعلاً (عند التعديل).
  static Future<double> invoiceIncrease(
    DatabaseExecutor db, {
    required int customerId,
    required bool credit,
    required double total,
    required double paid,
    int? editInvoiceId,
  }) async {
    final newPart = credit ? (total - paid).clamp(0, double.infinity).toDouble() : 0.0;
    var oldPart = 0.0;
    if (editInvoiceId != null) {
      try {
        oldPart = await InvoiceDebtReconciler.recordedContribution(db, editInvoiceId, customerId);
      } catch (_) {}
    }
    return newPart - oldPart;
  }

  /// رسالة المنع إن تجاوز [increase] سقف العميل، وإلا null.
  static Future<String?> violation(DatabaseExecutor db, {required int customerId, required double increase}) async {
    if (increase <= 0.5) return null; // لا زيادة على الدين
    final limit = await limitOf(db, customerId);
    if (limit == null) return null;
    final r = await db.rawQuery('SELECT name, current_total_debt FROM customers WHERE id = ? LIMIT 1', [customerId]);
    if (r.isEmpty) return null;
    final balance = (r.first['current_total_debt'] as num?)?.toDouble() ?? 0;
    final projected = balance + increase;
    if (projected <= limit + 0.5) return null;
    return 'سقف دين «${r.first['name']}» ${_m(limit)} دينار.\n'
        'رصيده الآن ${_m(balance)} + هذه العملية ${_m(increase)} = ${_m(projected)} '
        '(أكثر من السقف بـ ${_m(projected - limit)}).';
  }

  /// يقرر هل يستمر الحفظ: true = استمر (لا تجاوز، أو وافق المدير).
  static Future<bool> enforce(
    BuildContext context, {
    required int? customerId,
    required double increase,
    required String what,
  }) async {
    if (customerId == null || increase <= 0.5) return true;
    final db = await DatabaseService().database;
    final msg = await violation(db, customerId: customerId, increase: increase);
    if (msg == null) return true;
    if (!context.mounted) return false;
    final ok = await ManagerOverride.ask(context, title: 'لا يمكن الحفظ — تجاوز سقف الدين', message: msg);
    if (ok) {
      ActivityLog.log('تجاوز سقف الدين', what, msg.replaceAll('\n', ' ')).catchError((_) {});
    }
    return ok;
  }
}

/// موافقة المدير على عملية ممنوعة: المدير المسجّل يؤكد، وغيره يُدخل كلمة سر المدير.
class ManagerOverride {
  ManagerOverride._();

  static Future<bool> _checkAdminPassword(String pw) async {
    if (pw.isEmpty) return false;
    final auth = AuthService();
    for (final u in await auth.getAllUsers()) {
      if (u.isAdmin && u.id != null && await auth.checkPassword(u.id!, pw)) return true;
    }
    return false;
  }

  static Future<bool> ask(BuildContext context, {required String title, required String message}) async {
    final auth = AuthService();
    // بلا مستخدمين أصلاً (البرنامج بلا تسجيل دخول): صاحب الجهاز هو المدير
    final isAdmin = auth.isAdmin || !(await auth.hasAnyUsers());
    if (!context.mounted) return false;
    final pw = TextEditingController();
    String? error;
    final r = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Row(children: [
            const Icon(Icons.block_rounded, color: Colors.red),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 17))),
          ]),
          content: SizedBox(
            width: 440,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(message, style: const TextStyle(height: 1.6)),
              const SizedBox(height: 14),
              Text(
                isAdmin ? 'أنت المدير: يمكنك السماح بهذه العملية استثناءً.' : 'الاستثناء للمدير فقط — أدخل كلمة سر المدير للسماح:',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if (!isAdmin) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: pw,
                  obscureText: true,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'كلمة سر المدير',
                    errorText: error,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    prefixIcon: const Icon(Icons.lock_rounded),
                  ),
                  onSubmitted: (_) async {
                    final ok = await _checkAdminPassword(pw.text);
                    if (!ctx.mounted) return;
                    if (ok) {
                      Navigator.pop(ctx, true);
                    } else {
                      setD(() => error = 'كلمة السر غير صحيحة');
                    }
                  },
                ),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء الحفظ')),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
              onPressed: () async {
                if (isAdmin) {
                  Navigator.pop(ctx, true);
                  return;
                }
                final ok = await _checkAdminPassword(pw.text);
                if (!ctx.mounted) return;
                if (ok) {
                  Navigator.pop(ctx, true);
                } else {
                  setD(() => error = 'كلمة السر غير صحيحة');
                }
              },
              icon: const Icon(Icons.admin_panel_settings_rounded, size: 18),
              label: const Text('السماح (مدير)'),
            ),
          ],
        ),
      ),
    );
    pw.dispose();
    return r == true;
  }
}
