// lib/screens/alerts_display_dialog.dart
//
// 🔔 نافذة تنبيهات المخزون (عند التشغيل حسب إعداد التكرار، أو «عرض الآن» من إعدادات
// التنبيهات): مواد أوشكت على النفاد، مواد صلاحيتها قريبة، ومواد راكدة.
//   • الأرقام في رأس النافذة هي نفسها أزرار التبديل بين الأقسام.
//   • الترتيب: الأخطر أولاً (الأقل نسبةً إلى حد التنبيه، الأقرب انتهاءً، الأكبر رصيداً راكداً).
//   • بحث بالاسم داخل القسم.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../accounting/screens/acc_ui.dart' show fmtMoney;
import '../models/product.dart';
import '../widgets/app_dialog_shell.dart';
import 'alert_settings_screen.dart';

const _violet = Color(0xFF5B21B6);
const _red = Color(0xFFB91C1C);
const _orange = Color(0xFFC2410C);
const _amber = Color(0xFFB45309);
const _text = Color(0xFF1E293B);
const _muted = Color(0xFF64748B);
const _line = Color(0xFFE6EBF2);

enum _Kind { low, expiry, stagnant }

class AlertsDisplayDialog extends StatefulWidget {
  final List<Product> lowStockProducts;
  final List<Product> stagnantProducts;
  final List<Product> expiryProducts;

  const AlertsDisplayDialog({
    super.key,
    required this.lowStockProducts,
    required this.stagnantProducts,
    required this.expiryProducts,
  });

  @override
  State<AlertsDisplayDialog> createState() => _AlertsDisplayDialogState();
}

class _AlertsDisplayDialogState extends State<AlertsDisplayDialog> {
  late _Kind _kind;
  String _q = '';
  static final _date = DateFormat('yyyy/MM/dd', 'en_US');

  @override
  void initState() {
    super.initState();
    _kind = widget.lowStockProducts.isNotEmpty
        ? _Kind.low
        : (widget.expiryProducts.isNotEmpty ? _Kind.expiry : _Kind.stagnant);
  }

  List<Product> _source(_Kind k) => switch (k) {
        _Kind.low => widget.lowStockProducts,
        _Kind.expiry => widget.expiryProducts,
        _Kind.stagnant => widget.stagnantProducts,
      };

  static double _ratio(Product p) {
    final t = p.alertQuantity ?? 0;
    return t <= 0 ? 0 : p.stockQuantity / t;
  }

  List<Product> get _items {
    final q = _q.trim();
    final list = [
      for (final p in _source(_kind))
        if (q.isEmpty || p.name.contains(q)) p,
    ];
    switch (_kind) {
      case _Kind.low:
        list.sort((a, b) => _ratio(a).compareTo(_ratio(b)));
      case _Kind.expiry:
        list.sort((a, b) => (a.expiryDate ?? DateTime(9999)).compareTo(b.expiryDate ?? DateTime(9999)));
      case _Kind.stagnant:
        list.sort((a, b) => b.stockQuantity.compareTo(a.stockQuantity));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.lowStockProducts.length + widget.expiryProducts.length + widget.stagnantProducts.length;
    final items = _items;
    return AppDialogShell(
      icon: Icons.notifications_active_rounded,
      color: _violet,
      title: 'تنبيهات المخزون',
      subtitle: total == 0 ? 'لا تنبيهات الآن' : '$total تنبيه — اضغط الرقم لعرض قسمه',
      onClose: () => Navigator.pop(context),
      maxWidth: 760,
      headerExtra: Wrap(spacing: 8, runSpacing: 8, children: [
        HeaderStat(
          value: fmtMoney(widget.lowStockProducts.length),
          label: 'أوشكت على النفاد',
          icon: Icons.inventory_2_rounded,
          selected: _kind == _Kind.low,
          onTap: () => setState(() => _kind = _Kind.low),
        ),
        HeaderStat(
          value: fmtMoney(widget.expiryProducts.length),
          label: 'صلاحيتها قريبة',
          icon: Icons.event_busy_rounded,
          selected: _kind == _Kind.expiry,
          onTap: () => setState(() => _kind = _Kind.expiry),
        ),
        HeaderStat(
          value: fmtMoney(widget.stagnantProducts.length),
          label: 'راكدة +30 يوماً',
          icon: Icons.hourglass_bottom_rounded,
          selected: _kind == _Kind.stagnant,
          onTap: () => setState(() => _kind = _Kind.stagnant),
        ),
      ]),
      body: SizedBox(
        height: 440,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _q = v),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'ابحث باسم المادة في هذا القسم',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _line)),
                enabledBorder:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _line)),
              ),
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: items.isEmpty
                  ? _empty(key: ValueKey('e$_kind$_q'))
                  : ListView.separated(
                      key: ValueKey('l$_kind'),
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _card(items[i]),
                    ),
            ),
          ),
        ]),
      ),
      actions: [
        TextButton.icon(
          onPressed: () {
            final nav = Navigator.of(context);
            nav.pop();
            nav.push(MaterialPageRoute(builder: (_) => const AlertSettingsScreen()));
          },
          icon: const Icon(Icons.tune_rounded, size: 18),
          label: const Text('إعدادات التنبيهات'),
        ),
        const Spacer(),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: _violet, minimumSize: const Size(120, 46)),
          onPressed: () => Navigator.pop(context),
          child: const Text('حسناً'),
        ),
      ],
    );
  }

  Widget _empty({Key? key}) {
    final text = _q.trim().isNotEmpty
        ? 'لا مادة بهذا الاسم في هذا القسم'
        : switch (_kind) {
            _Kind.low => 'لا مواد أوشكت على النفاد',
            _Kind.expiry => 'لا مواد صلاحيتها قريبة',
            _Kind.stagnant => 'لا مواد راكدة',
          };
    return Center(
      key: key,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(22)),
          child: const Icon(Icons.check_circle_rounded, size: 40, color: Color(0xFF059669)),
        ),
        const SizedBox(height: 12),
        Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _muted)),
      ]),
    );
  }

  Widget _card(Product p) {
    final unit = p.translatedUnit;
    late final Color c;
    late final Widget badge;
    late final String line;
    Widget? bar;
    switch (_kind) {
      case _Kind.low:
        final t = p.alertQuantity ?? 0;
        final r = _ratio(p).clamp(0.0, 1.0);
        c = p.stockQuantity <= 0 ? _red : (r < 0.5 ? _orange : _amber);
        badge = _badge(p.stockQuantity <= 0 ? 'نفدت' : 'متوفر ${fmtMoney(p.stockQuantity)} $unit', c);
        line = 'حد التنبيه ${fmtMoney(t)} ${p.alertUnit ?? unit}';
        bar = ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(value: r, minHeight: 6, color: c, backgroundColor: const Color(0xFFEEF2F7)),
        );
      case _Kind.expiry:
        final days = p.expiryDate == null ? null : p.expiryDate!.difference(DateTime.now()).inDays;
        c = days == null ? _muted : (days <= 7 ? _red : (days <= 30 ? _orange : _amber));
        badge = _badge(days == null ? 'بلا تاريخ' : (days <= 0 ? 'تنتهي اليوم' : 'بعد $days يوماً'), c);
        line = 'تنتهي ${p.expiryDate == null ? '—' : _date.format(p.expiryDate!)} • المتوفر ${fmtMoney(p.stockQuantity)} $unit';
      case _Kind.stagnant:
        c = _amber;
        badge = _badge('${fmtMoney(p.stockQuantity)} $unit', c);
        line = 'لم تُبع منذ أكثر من 30 يوماً';
    }
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _line),
        boxShadow: const [BoxShadow(color: Color(0x080F172A), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 5, color: c),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(
                    child: Text(p.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: _text)),
                  ),
                  const SizedBox(width: 8),
                  badge,
                ]),
                const SizedBox(height: 4),
                Text(line, style: const TextStyle(fontSize: 12.5, color: _muted)),
                if (bar != null) ...[const SizedBox(height: 8), bar],
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _badge(String text, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: c)),
      );
}
