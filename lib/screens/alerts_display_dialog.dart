// lib/screens/alerts_display_dialog.dart
//
// 🔔 نافذة التنبيهات (عند التشغيل حسب إعداد التكرار، أو «عرض الآن» من إعدادات
// التنبيهات): استحقاقات العملاء التي حلّت (📅 DueAlerts)، ومواد أوشكت على النفاد،
// ومواد صلاحيتها قريبة، ومواد راكدة.
//   • الاستحقاقات: قسط أو شيك أو كمبيالة — اليوم، والمتأخر، وباقي الشهر — حسب إعدادات
//     «المطالبة بالديون» (DueAlertSettings). الضغط على الاستحقاق يفتح بطاقة العميل.
//   • الأرقام في رأس النافذة هي نفسها أزرار التبديل بين الأقسام.
//   • الترتيب: الأخطر أولاً (الأقل نسبةً إلى حد التنبيه، الأقرب انتهاءً، الأكبر رصيداً راكداً).
//   • بحث بالاسم داخل القسم.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../accounting/screens/acc_ui.dart' show fmtMoney;
import '../erp/debts/customer_card_screen.dart';
import '../models/product.dart';
import '../services/due_alerts.dart';
import '../widgets/app_dialog_shell.dart';
import 'alert_settings_screen.dart';

const _violet = Color(0xFF5B21B6);
const _red = Color(0xFFB91C1C);
const _orange = Color(0xFFC2410C);
const _amber = Color(0xFFB45309);
const _text = Color(0xFF1E293B);
const _muted = Color(0xFF64748B);
const _line = Color(0xFFE6EBF2);

enum _Kind { dues, low, expiry, stagnant }

class AlertsDisplayDialog extends StatefulWidget {
  final List<Product> lowStockProducts;
  final List<Product> stagnantProducts;
  final List<Product> expiryProducts;

  /// 📅 الاستحقاقات حسب إعدادات «المطالبة بالديون».
  final List<DueAlert> dueAlerts;

  /// عدد من أُخفي لأن رسالة واتساب وصلته بعد حلول استحقاقه.
  final int dueWaHidden;

  const AlertsDisplayDialog({
    super.key,
    required this.lowStockProducts,
    required this.stagnantProducts,
    required this.expiryProducts,
    this.dueAlerts = const [],
    this.dueWaHidden = 0,
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
    _kind = widget.dueAlerts.isNotEmpty
        ? _Kind.dues
        : widget.lowStockProducts.isNotEmpty
            ? _Kind.low
            : (widget.expiryProducts.isNotEmpty ? _Kind.expiry : _Kind.stagnant);
  }

  List<Product> _source(_Kind k) => switch (k) {
        _Kind.dues => const <Product>[],
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
      case _Kind.dues:
        break;
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
    final total = widget.dueAlerts.length +
        widget.lowStockProducts.length +
        widget.expiryProducts.length +
        widget.stagnantProducts.length;
    final items = _items;
    final q = _q.trim();
    final dues = [
      for (final d in widget.dueAlerts)
        if (q.isEmpty || d.customerName.contains(q)) d,
    ]; // الأقدم أولاً (مرتبة من المصدر)
    final isDues = _kind == _Kind.dues;
    final empty = isDues ? dues.isEmpty : items.isEmpty;
    return AppDialogShell(
      icon: Icons.notifications_active_rounded,
      color: _violet,
      title: 'التنبيهات',
      subtitle: total == 0 ? 'لا تنبيهات الآن' : '$total تنبيه — اضغط الرقم لعرض قسمه',
      onClose: () => Navigator.pop(context),
      maxWidth: 760,
      headerExtra: Wrap(spacing: 8, runSpacing: 8, children: [
        HeaderStat(
          value: fmtMoney(widget.dueAlerts.length),
          label: 'استحقاقات',
          icon: Icons.event_note_rounded,
          selected: _kind == _Kind.dues,
          onTap: () => setState(() => _kind = _Kind.dues),
        ),
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
                hintText: isDues ? 'ابحث باسم العميل' : 'ابحث باسم المادة في هذا القسم',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _line)),
                enabledBorder:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _line)),
              ),
            ),
          ),
          if (isDues && widget.dueWaHidden > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Row(children: [
                const Icon(Icons.chat_rounded, size: 16, color: Color(0xFF16A34A)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('${widget.dueWaHidden} استحقاقاً آخر لا يظهر: أصحابها وصلتهم رسالة واتساب بعد حلوله '
                      '(يُغيَّر من إعدادات التنبيهات).',
                      style: const TextStyle(fontSize: 12, color: _muted)),
                ),
              ]),
            ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: empty
                  ? _empty(key: ValueKey('e$_kind$_q'))
                  : ListView.separated(
                      key: ValueKey('l$_kind'),
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                      itemCount: isDues ? dues.length : items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => isDues ? _dueCard(dues[i]) : _card(items[i]),
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
        ? (_kind == _Kind.dues ? 'لا عميل بهذا الاسم' : 'لا مادة بهذا الاسم في هذا القسم')
        : switch (_kind) {
            _Kind.dues => 'لا استحقاقات تحتاج مطالبة',
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
      case _Kind.dues: // لا يحدث: الاستحقاقات لها _dueCard
        c = _muted;
        badge = const SizedBox.shrink();
        line = '';
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
        final days = p.expiryDate?.difference(DateTime.now()).inDays;
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

  /// 📅 بطاقة استحقاق: العميل، نوعه ورقمه، المتبقي، والتأخر. الضغط يفتح بطاقة العميل.
  Widget _dueCard(DueAlert d) {
    const teal = Color(0xFF0F766E);
    final c = d.upcoming ? teal : (d.daysLate >= 30 ? _red : (d.daysLate >= 7 ? _orange : _amber));
    final when = d.upcoming ? 'بعد ${d.daysUntil} يوماً' : (d.daysLate == 0 ? 'اليوم' : 'متأخر ${d.daysLate} يوماً');
    final inst = d.installmentNo != null && (d.installmentsTotal ?? 0) > 1 ? ' (${d.installmentNo}/${d.installmentsTotal})' : '';
    final cur = d.currency == 'IQD' ? 'دينار' : d.currency;
    final line = '${d.kindLabel} رقم ${d.dueNo}$inst • ${d.upcoming ? 'يستحق' : 'استحق'} ${_date.format(d.dueDate)}'
        '${d.phone.isEmpty ? '' : ' • ${d.phone}'}';
    return Semantics(
      button: true,
      label: '${d.customerName}، ${fmtMoney(d.remaining)} $cur، $when',
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            final nav = Navigator.of(context);
            nav.pop();
            nav.push(MaterialPageRoute(builder: (_) => CustomerCardScreen(customerId: d.customerId)));
          },
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
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
                          child: Text(d.customerName.isEmpty ? 'عميل' : d.customerName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: _text)),
                        ),
                        if (d.waSentAt != null) ...[
                          const SizedBox(width: 6),
                          _badge('وصلته رسالة واتساب ${_date.format(d.waSentAt!)}', const Color(0xFF16A34A)),
                        ],
                        const SizedBox(width: 8),
                        _badge(when, c),
                      ]),
                      const SizedBox(height: 4),
                      Row(children: [
                        Expanded(child: Text(line, style: const TextStyle(fontSize: 12.5, color: _muted))),
                        const SizedBox(width: 8),
                        Text('${fmtMoney(d.remaining)} $cur',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: c)),
                      ]),
                    ]),
                  ),
                ),
                const Padding(
                  padding: EdgeInsetsDirectional.only(end: 8),
                  child: Icon(Icons.chevron_left_rounded, color: _muted),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _badge(String text, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: c)),
      );
}
