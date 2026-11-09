// lib/services/reports/employee_sales.dart
//
// 👷 مبيعات الموظفين: مجاميع كل موظف من محرك الأرقام الموحّد نفسه (SalesFacts و
// SalesTotals) — فمجموع الموظفين يساوي مجموع تقرير الفترة حرفياً، بلا قاعدة حساب ثانية.
//
// لمن يُنسب كل رقم:
//   • الفاتورة  ← من أنشأها (invoices.created_by_username).
//   • التعديل بالقلم ← صاحب الفاتورة الأصلية (فرق في بيعه هو).
//   • مستند المرتجع ← صاحب الفاتورة الأصلية إن عُرفت، وإلا من سجّل المرتجع.
//   • ما لا يُعرف صاحبه (فواتير قديمة قبل تسجيل المستخدم) ← «غير مسجّل».
// قراءة فقط: لا يكتب أي شيء.

import 'package:sqflite/sqflite.dart';

import 'sales_facts.dart';

class EmployeeSales {
  EmployeeSales(this.username, this.name, this.totals);

  /// اسم الدخول (أو [EmployeeSalesReport.unknown]).
  final String username;

  /// الاسم المعروض.
  final String name;
  final SalesTotals totals;
}

class EmployeeSalesReport {
  EmployeeSalesReport(this.rows, this.total);

  static const unknown = '';

  /// الموظفون مرتبون بصافي المبيعات (الأعلى أولاً).
  final List<EmployeeSales> rows;

  /// مجموع الفترة كلها (للتحقق: يساوي مجموع الصفوف).
  final SalesTotals total;

  /// دالة صافية: يوزّع وقائع الفترة على الموظفين.
  /// [creatorOf]: رقم الفاتورة ← اسم الدخول لمن أنشأها. [names]: اسم الدخول ← الاسم المعروض.
  static EmployeeSalesReport group(
    SalesFacts facts, {
    required Map<int, String> creatorOf,
    Map<String, String> names = const {},
  }) {
    final by = <String, SalesTotals>{};
    SalesTotals t(String? u) => by.putIfAbsent(_clean(u), SalesTotals.new);

    for (final i in facts.invoices) {
      t(creatorOf[i.id]).addInvoice(i);
    }
    for (final e in facts.edits) {
      t(creatorOf[e.invoiceId]).addEdit(e);
    }
    for (final r in facts.returns) {
      final orig = r.originalInvoiceId == null ? null : creatorOf[r.originalInvoiceId!];
      t(_clean(orig).isNotEmpty ? orig : r.createdBy).addReturn(r);
    }

    final rows = [
      for (final e in by.entries)
        EmployeeSales(e.key, e.key.isEmpty ? 'غير مسجّل' : (names[e.key]?.trim().isNotEmpty == true ? names[e.key]!.trim() : e.key),
            e.value),
    ]..sort((a, b) {
        if (a.username.isEmpty != b.username.isEmpty) return a.username.isEmpty ? 1 : -1; // «غير مسجّل» آخراً
        return b.totals.netSales.compareTo(a.totals.netSales);
      });
    return EmployeeSalesReport(rows, facts.totals());
  }

  static String _clean(String? u) => (u ?? '').trim();

  /// رقم الفاتورة ← من أنشأها، لكل الفواتير التي تمسّها الوقائع.
  static Future<Map<int, String>> creators(DatabaseExecutor db, SalesFacts facts) async {
    final ids = <int>{
      for (final i in facts.invoices) i.id,
      for (final e in facts.edits) e.invoiceId,
      for (final r in facts.returns)
        if (r.originalInvoiceId != null) r.originalInvoiceId!,
    }.toList();
    final out = <int, String>{};
    for (var k = 0; k < ids.length; k += 500) {
      final part = ids.sublist(k, k + 500 > ids.length ? ids.length : k + 500);
      final rows = await db.rawQuery(
        'SELECT id, created_by_username AS u FROM invoices WHERE id IN (${List.filled(part.length, '?').join(',')})',
        part,
      );
      for (final r in rows) {
        final u = (r['u'] as String?)?.trim() ?? '';
        if (u.isNotEmpty) out[(r['id'] as num).toInt()] = u;
      }
    }
    return out;
  }

  /// اسم الدخول ← الاسم المعروض (من جدول المستخدمين إن وُجد).
  static Future<Map<String, String>> displayNames(DatabaseExecutor db) async {
    try {
      final rows = await db.rawQuery('SELECT username, display_name FROM users');
      return {
        for (final r in rows)
          if ((r['username'] as String?)?.isNotEmpty == true)
            r['username'] as String: ((r['display_name'] as String?)?.trim().isNotEmpty == true
                ? (r['display_name'] as String).trim()
                : r['username'] as String),
      };
    } catch (_) {
      return const {};
    }
  }

  /// فواتير موظف في الفترة (للتفصيل) — من الوقائع نفسها.
  static List<SalesInvoiceFact> invoicesOf(SalesFacts facts, Map<int, String> creatorOf, String username) => [
        for (final i in facts.invoices)
          if (_clean(creatorOf[i.id]) == username) i,
      ]..sort((a, b) => b.date.compareTo(a.date));
}
