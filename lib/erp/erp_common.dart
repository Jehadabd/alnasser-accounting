// lib/erp/erp_common.dart
//
// أدوات مشتركة لكل ميزات النسخة المحاسبية الموسّعة.

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../accounting/ledger.dart';
import '../accounting/screens/acc_ui.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';

class ErpException implements Exception {
  ErpException(this.message);
  final String message;
  @override
  String toString() => message;
}

Future<Database> erpDb() => DatabaseService().database;

/// اسم المستخدم الحالي (للسجلات).
String currentUserName() => AuthService().currentUser?.username ?? 'admin';
int? currentUserId() => AuthService().currentUser?.id;

double d0(Object? v) => (v as num?)?.toDouble() ?? 0.0;

/// تحويل نص مكتوب بفواصل الآلاف إلى رقم.
double? parseMoney(String? s) {
  if (s == null) return null;
  final t = s.replaceAll(',', '').replaceAll('٬', '').trim();
  if (t.isEmpty) return null;
  return double.tryParse(_toLatinDigits(t));
}

String _toLatinDigits(String s) {
  const ar = '٠١٢٣٤٥٦٧٨٩';
  final b = StringBuffer();
  for (final ch in s.split('')) {
    final i = ar.indexOf(ch);
    b.write(i >= 0 ? '$i' : (ch == '٫' ? '.' : ch));
  }
  return b.toString();
}

/// الرقم التالي لمستند (أكبر رقم + 1) — يُستدعى داخل المعاملة نفسها.
Future<int> nextDocNumber(DatabaseExecutor db, String table, String column,
    {String? where, List<Object?>? args}) async {
  final r = await db.rawQuery(
      'SELECT COALESCE(MAX($column), 0) + 1 AS n FROM $table${where == null ? '' : ' WHERE $where'}',
      args);
  return (r.first['n'] as num).toInt();
}

String isoDay(DateTime d) => DateTime(d.year, d.month, d.day).toIso8601String();
String isoDayAfter(DateTime d) =>
    DateTime(d.year, d.month, d.day).add(const Duration(days: 1)).toIso8601String();

DateTime parseDate(Object? v) {
  final s = v as String?;
  if (s == null || s.isEmpty) return DateTime.now();
  return DateTime.tryParse(s) ?? DateTime.now();
}

// ═══════════════════════════ تثبيت الإدخالات ═══════════════════════════

/// «تثبيت الإدخالات» (مثل الإداري): لا يُعدَّل ولا يُحذف ولا يُضاف أي مستند
/// بتاريخ قبل تاريخ التثبيت.
class PeriodLock {
  PeriodLock._();

  static const String settingKey = 'lock_date';

  static Future<DateTime?> lockDate([DatabaseExecutor? db]) async {
    try {
      final d = db ?? await erpDb();
      final v = await Ledger.getSetting(d, settingKey);
      if (v == null || v.isEmpty) return null;
      return DateTime.tryParse(v);
    } catch (_) {
      return null;
    }
  }

  static Future<void> setLockDate(DateTime? date) async {
    final d = await erpDb();
    await Ledger.setSetting(d, settingKey, date == null ? '' : isoDay(date));
  }

  /// true إن كان التاريخ داخل فترة مثبّتة (قبل تاريخ التثبيت).
  static Future<bool> isLocked(DateTime date, [DatabaseExecutor? db]) async {
    final lock = await lockDate(db);
    if (lock == null) return false;
    final day = DateTime(date.year, date.month, date.day);
    return day.isBefore(lock);
  }

  /// يرمي استثناءً إن كان التاريخ مثبّتاً.
  static Future<void> assertOpen(DateTime date, [DatabaseExecutor? db]) async {
    final lock = await lockDate(db);
    if (lock == null) return;
    final day = DateTime(date.year, date.month, date.day);
    if (day.isBefore(lock)) {
      throw ErpException(
          'الفترة مثبّتة حتى ${fmtDate(lock)} — لا يمكن إضافة أو تعديل أو حذف مستند بتاريخ ${fmtDate(day)}');
    }
  }

  /// للواجهات: يعرض رسالة ويعيد false إن كان التاريخ مثبّتاً.
  static Future<bool> guard(BuildContext context, DateTime? date) async {
    if (date == null) return true;
    try {
      await assertOpen(date);
      return true;
    } catch (e) {
      if (context.mounted) showError(context, e);
      return false;
    }
  }
}

// ═══════════════════════════ عناصر واجهة صغيرة ═══════════════════════════

/// حقل رقمي بسيط.
class MoneyField extends StatelessWidget {
  const MoneyField({
    super.key,
    required this.controller,
    required this.label,
    this.onChanged,
    this.enabled = true,
    this.width,
    this.autofocus = false,
  });
  final TextEditingController controller;
  final String label;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final double? width;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final f = TextField(
      controller: controller,
      enabled: enabled,
      autofocus: autofocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textDirection: TextDirection.ltr,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
        filled: true,
        fillColor: Colors.white,
      ),
      onChanged: onChanged,
    );
    return width == null ? f : SizedBox(width: width, child: f);
  }
}

/// حقل نصي بسيط.
class TextBox extends StatelessWidget {
  const TextBox({
    super.key,
    required this.controller,
    required this.label,
    this.width,
    this.maxLines = 1,
    this.onChanged,
    this.enabled = true,
  });
  final TextEditingController controller;
  final String label;
  final double? width;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final f = TextField(
      controller: controller,
      maxLines: maxLines,
      enabled: enabled,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
        filled: true,
        fillColor: Colors.white,
      ),
      onChanged: onChanged,
    );
    return width == null ? f : SizedBox(width: width, child: f);
  }
}

/// زر تاريخ.
class DateButton extends StatelessWidget {
  const DateButton({super.key, required this.label, required this.value, required this.onChanged});
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        icon: const Icon(Icons.event, size: 18),
        label: Text('$label: ${value == null ? '—' : fmtDate(value!)}'),
        onPressed: () async {
          final d = await showDatePicker(
            context: context,
            initialDate: value ?? DateTime.now(),
            firstDate: DateTime(2015),
            lastDate: DateTime(2100),
          );
          if (d != null) onChanged(d);
        },
      );
}

/// سؤال تأكيد.
Future<bool> confirmDialog(BuildContext context, String title, String message,
    {String ok = 'تأكيد', Color? color}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: color ?? AccColors.navy, foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// إدخال رقم في مربع حوار.
Future<double?> askNumber(BuildContext context, String title,
    {String label = 'القيمة', double? initial}) async {
  final c = TextEditingController(text: initial == null ? '' : fmtMoney(initial));
  final r = await showDialog<double>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: MoneyField(controller: c, label: label, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, parseMoney(c.text)),
          child: const Text('موافق'),
        ),
      ],
    ),
  );
  return r;
}

/// إدخال نص في مربع حوار.
Future<String?> askText(BuildContext context, String title, {String label = '', String? initial}) async {
  final c = TextEditingController(text: initial ?? '');
  final r = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('موافق')),
      ],
    ),
  );
  return r;
}

/// شبكة أزرار لمراكز الميزات (نفس شكل مركز المحاسبة).
class HubTile {
  const HubTile(this.title, this.icon, this.color, this.onTap, {this.subtitle, this.permission});
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String? subtitle;
  final String? permission;
}

class HubGrid extends StatelessWidget {
  const HubGrid({super.key, required this.tiles});
  final List<HubTile> tiles;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final cols = width > 1200 ? 5 : width > 900 ? 4 : width > 600 ? 3 : 2;
    return GridView.count(
      padding: const EdgeInsets.all(12),
      crossAxisCount: cols,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.25,
      children: [
        for (final t in tiles)
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                if (t.permission != null && !requirePermission(context, t.permission!)) return;
                t.onTap();
              },
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: t.color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(t.icon, color: t.color, size: 28),
                    ),
                    const SizedBox(height: 8),
                    Text(t.title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    if (t.subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(t.subtitle!,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: AccColors.muted)),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// جدول بيانات بسيط قابل للتمرير أفقياً وعمودياً.
class SimpleTable extends StatelessWidget {
  const SimpleTable({
    super.key,
    required this.headers,
    required this.rows,
    this.numericColumns = const {},
    this.onRowTap,
    this.footer,
  });
  final List<String> headers;
  final List<List<String>> rows;
  final Set<int> numericColumns;
  final void Function(int index)? onRowTap;
  final List<String>? footer;

  @override
  Widget build(BuildContext context) {
    DataCell cell(String s, int col, {bool bold = false}) => DataCell(
          Text(s,
              textDirection: numericColumns.contains(col) ? TextDirection.ltr : null,
              style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
        );
    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(AccColors.navy.withOpacity(0.08)),
          columnSpacing: 22,
          showCheckboxColumn: false,
          columns: [
            for (var i = 0; i < headers.length; i++)
              DataColumn(
                label: Text(headers[i], style: const TextStyle(fontWeight: FontWeight.bold)),
                numeric: numericColumns.contains(i),
              ),
          ],
          rows: [
            for (var r = 0; r < rows.length; r++)
              DataRow(
                onSelectChanged: onRowTap == null ? null : (_) => onRowTap!(r),
                cells: [for (var c = 0; c < headers.length; c++) cell(c < rows[r].length ? rows[r][c] : '', c)],
              ),
            if (footer != null)
              DataRow(
                color: WidgetStateProperty.all(Colors.grey.shade100),
                cells: [for (var c = 0; c < headers.length; c++) cell(c < footer!.length ? footer![c] : '', c, bold: true)],
              ),
          ],
        ),
      ),
    );
  }
}

String fmtQty(num v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(3).replaceAll(RegExp(r'0+$'), '');
