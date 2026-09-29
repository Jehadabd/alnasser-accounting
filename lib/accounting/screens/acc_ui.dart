// lib/accounting/screens/acc_ui.dart
//
// عناصر واجهة مشتركة لشاشات المحاسبة (هوية «سهل»: كحلي + سماوي).

import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../lan/lan_settings.dart';
import '../../services/auth_service.dart';

class AccColors {
  static const navy = Color(0xFF0F3460);
  static const navyDark = Color(0xFF020F2B);
  static const blue = Color(0xFF2563EB);
  static const cyan = Color(0xFF00B4D8);
  static const bg = Color(0xFFF8F9FA);
  static const text = Color(0xFF1F2937);
  static const muted = Color(0xFF6C757D);
  static const green = Color(0xFF047857);
  static const red = Color(0xFFB91C1C);
  static const orange = Color(0xFFC2410C);
  static const purple = Color(0xFF6B21A8);
}

final NumberFormat _money = NumberFormat('#,##0.##', 'en');
final DateFormat _date = DateFormat('yyyy/MM/dd', 'en_US');

String fmtMoney(num v) => _money.format(v);
String fmtDate(DateTime d) => _date.format(d);

/// مبلغ ملوّن: أحمر للسالب.
class MoneyText extends StatelessWidget {
  const MoneyText(this.value, {super.key, this.bold = false, this.size});
  final double value;
  final bool bold;
  final double? size;
  @override
  Widget build(BuildContext context) => Text(
        fmtMoney(value),
        textDirection: TextDirection.ltr,
        style: TextStyle(
          color: value < -0.004 ? AccColors.red : AccColors.text,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          fontSize: size,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
}

/// شريط العنوان الموحّد.
PreferredSizeWidget accAppBar(String title, {List<Widget>? actions}) => AppBar(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      backgroundColor: AccColors.navy,
      foregroundColor: Colors.white,
      centerTitle: true,
      actions: actions,
    );

/// اختيار فترة (من/إلى) بأزرار سريعة.
class PeriodBar extends StatelessWidget {
  const PeriodBar({
    super.key,
    required this.from,
    required this.to,
    required this.onChanged,
    this.showFrom = true,
  });
  final DateTime? from;
  final DateTime to;
  final bool showFrom;
  final void Function(DateTime? from, DateTime to) onChanged;

  Future<DateTime?> _pick(BuildContext context, DateTime initial) => showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime(2015),
        lastDate: DateTime(2100),
      );

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    Widget chip(String label, DateTime? f, DateTime t) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: ActionChip(label: Text(label), onPressed: () => onChanged(f, t)),
        );
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 6,
        children: [
          if (showFrom)
            OutlinedButton.icon(
              icon: const Icon(Icons.date_range, size: 18),
              label: Text('من: ${from == null ? 'البداية' : fmtDate(from!)}'),
              onPressed: () async {
                final d = await _pick(context, from ?? DateTime(now.year, 1, 1));
                if (d != null) onChanged(d, to);
              },
            ),
          OutlinedButton.icon(
            icon: const Icon(Icons.event, size: 18),
            label: Text('${showFrom ? 'إلى' : 'حتى'}: ${fmtDate(to)}'),
            onPressed: () async {
              final d = await _pick(context, to);
              if (d != null) onChanged(from, d);
            },
          ),
          if (showFrom) ...[
            chip('اليوم', DateTime(now.year, now.month, now.day), now),
            chip('هذا الشهر', DateTime(now.year, now.month, 1), now),
            chip('هذه السنة', DateTime(now.year, 1, 1), now),
            chip('الكل', null, now),
          ],
        ],
      ),
    );
  }
}

/// بطاقة قسم بعنوان.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.child, this.color});
  final String title;
  final Widget child;
  final Color? color;
  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        margin: const EdgeInsets.all(8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: (color ?? AccColors.navy).withOpacity(0.08),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Text(title,
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: color ?? AccColors.navy, fontSize: 16)),
            ),
            child,
          ],
        ),
      );
}

/// صف (اسم ← مبلغ).
class AmountRow extends StatelessWidget {
  const AmountRow(this.label, this.value, {super.key, this.bold = false, this.indent = 0});
  final String label;
  final double value;
  final bool bold;
  final int indent;
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(right: 16.0 + indent * 16, left: 16, top: 6, bottom: 6),
        child: Row(
          children: [
            Expanded(
                child: Text(label,
                    style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal))),
            MoneyText(value, bold: bold),
          ],
        ),
      );
}

void showError(BuildContext context, Object e) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(e.toString()),
    backgroundColor: AccColors.red,
  ));
}

void showOk(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    backgroundColor: AccColors.green,
  ));
}

/// فحص صلاحية مع رسالة. يعيد true إن كان مسموحاً.
bool requirePermission(BuildContext context, String key) {
  if (AuthService().hasPermission(key)) return true;
  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
    content: Text('ليس لديك صلاحية لهذه العملية'),
    backgroundColor: AccColors.red,
  ));
  return false;
}

/// على الطرفية لا يعمل محرك الترحيل — السيرفر يرحّل تلقائياً كل دقيقتين.
bool get canRunPosting => AppNetworkMode.ownsDatabase;
