// lib/erp/erp_common.dart
//
// أدوات مشتركة لكل ميزات النسخة المحاسبية الموسّعة.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;

import 'activity/activity_log.dart';
import 'package:sqflite/sqflite.dart';

import '../accounting/ledger.dart';
import '../accounting/screens/acc_ui.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../widgets/formatters.dart';
import 'erp_kit.dart';

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
    ActivityLog.log(date == null ? 'إلغاء' : 'تعديل', 'تثبيت الإدخالات',
        date == null ? 'إلغاء تثبيت الإدخالات' : 'تثبيت كل ما قبل ${fmtDate(date)}');
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
      inputFormatters: [ThousandSeparatorDecimalInputFormatter(allowNegative: true)],
      textDirection: TextDirection.ltr,
      decoration: InputDecoration(labelText: label, isDense: true, filled: true, fillColor: Colors.white),
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
      decoration: InputDecoration(labelText: label, isDense: true, filled: true, fillColor: Colors.white),
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

  // نفس زر التاريخ في شاشات المحاسبة: بطاقة صغيرة والتاريخ بالأرقام (yyyy/MM/dd)
  @override
  Widget build(BuildContext context) => DatePill(
        label: label,
        value: value,
        emptyText: '—',
        onPicked: onChanged,
      );
}

/// سؤال تأكيد.
Future<bool> confirmDialog(BuildContext context, String title, String message,
    {String ok = 'تأكيد', Color? color}) async {
  final c = color ?? AccColors.navy;
  final danger = c == AccColors.red;
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => ErpDialog(
      title: title,
      icon: danger ? Icons.warning_amber_rounded : Icons.help_outline_rounded,
      color: c,
      width: 440,
      content: Text(message, style: const TextStyle(fontSize: 14, height: 1.6)),
      actions: erpDialogActions(ctx, ok: ok, color: c, icon: danger ? Icons.delete_outline_rounded : Icons.check_rounded),
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
    builder: (ctx) => ErpDialog(
      title: title,
      icon: Icons.dialpad_rounded,
      width: 400,
      content: MoneyField(controller: c, label: label, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(ctx, parseMoney(c.text)), child: const Text('موافق')),
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
    builder: (ctx) => ErpDialog(
      title: title,
      icon: Icons.edit_note_rounded,
      width: 420,
      content: TextField(
        controller: c,
        autofocus: true,
        decoration: InputDecoration(labelText: label),
        onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('موافق')),
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

/// مجموعة أزرار بعنوان داخل مركز (مثل قوائم الإداري وسهل).
class HubSection {
  const HubSection(this.title, this.tiles, {this.subtitle});
  final String title;
  final List<HubTile> tiles;
  final String? subtitle;
}

/// مركز مقسّم إلى مجموعات بعناوين؛ كل مجموعة شبكة أزرار.
class HubSections extends StatelessWidget {
  const HubSections({super.key, required this.sections});
  final List<HubSection> sections;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        for (final s in sections)
          if (s.tiles.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
              child: Row(children: [
                Container(width: 4, height: 18, decoration: BoxDecoration(color: AccColors.navy, borderRadius: BorderRadius.circular(4))),
                const SizedBox(width: 8),
                Text(s.title,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, color: AccColors.text)),
                const SizedBox(width: 10),
                const Expanded(child: Divider(color: Color(0xFFE3E9F1))),
              ]),
            ),
            HubGrid(tiles: s.tiles, shrinkWrap: true),
          ],
      ],
    );
  }
}

class HubGrid extends StatelessWidget {
  const HubGrid({super.key, required this.tiles, this.shrinkWrap = false});
  final List<HubTile> tiles;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 360,
        mainAxisExtent: 86,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
      ),
      itemCount: tiles.length,
      itemBuilder: (context, i) => _HubTileCard(tile: tiles[i]),
    );
  }
}

class _HubTileCard extends StatefulWidget {
  const _HubTileCard({required this.tile});
  final HubTile tile;
  @override
  State<_HubTileCard> createState() => _HubTileCardState();
}

class _HubTileCardState extends State<_HubTileCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tile;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: _hover
              ? [BoxShadow(color: t.color.withValues(alpha: 0.16), blurRadius: 16, offset: const Offset(0, 6))]
              : const [BoxShadow(color: Color(0x080F172A), blurRadius: 6, offset: Offset(0, 2))],
        ),
        child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: _hover ? t.color.withValues(alpha: 0.45) : const Color(0xFFE3E9F1)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              if (t.permission != null && !requirePermission(context, t.permission!)) return;
              t.onTap();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _hover ? t.color : t.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(t.icon, color: _hover ? Colors.white : t.color, size: 25),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: AccColors.text)),
                      if (t.subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(t.subtitle!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, height: 1.35, color: AccColors.muted)),
                        ),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
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
          headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F4F9)),
          headingTextStyle: const TextStyle(fontWeight: FontWeight.w800, color: AccColors.navy, fontSize: 13),
          dividerThickness: 0.6,
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

final NumberFormat _qtyFmt = NumberFormat('#,##0.###', 'en');

/// كمية بفواصل الآلاف (حتى 3 مراتب عشرية).
String fmtQty(num v) => _qtyFmt.format(v);
