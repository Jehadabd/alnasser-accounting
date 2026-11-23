// lib/erp/reports/vouchers_summary_report.dart
//
// 🧾 «ملخص السندات — أين خرج المال وأين دخل؟» (التقارير ← المالية)
//
// لصاحب المحل: في فترة يختارها (هذا الشهر افتراضياً) كل سندات الصندوق مجمّعة:
//   • نوع السند (مصروف، صرف، إيراد، قبض، تحويل، رصيد افتتاحي) ← مجموعه وعدده.
//   • داخل كل نوع: الحساب (كهرباء، أجور، مسحوبات المالك...) ← مجموعه ونسبته.
//   • كل سند بسطر: رقمه، تاريخه، مبلغه، صندوقه، بيانه.
// «مسحوبات المالك» تظهر بطاقة مستقلة لأنها ليست مصروفاً (لا تنقص الربح).
//
// للقراءة فقط: يقرأ جدول السندات نفسه الذي تعرضه شاشة «السندات» (غير المحذوفة)،
// فالأرقام تطابقها حرفياً. المبلغ بالدينار (ما يُقيَّد في الدفتر)، والسند بالدولار
// يُعرض معه مبلغه الأجنبي.

import 'package:flutter/material.dart';

import '../../accounting/ledger.dart' show roundMoney;
import '../../accounting/screens/acc_ui.dart';
import '../../accounting/vouchers_service.dart' show VoucherType, voucherTypeLabels;
import '../erp_common.dart';
import '../erp_ui.dart';
import '../report_export.dart';
import 'voucher_details_sheet.dart';

class VouchersSummaryScreen extends StatefulWidget {
  const VouchersSummaryScreen({super.key, this.from, this.to, this.onlyType, this.drawingsOnly = false});

  /// الفترة (من التقرير الدوري مثلاً)؛ بدونها: هذا الشهر.
  final DateTime? from;
  final DateTime? to;

  /// 🔎 من البحث الذكي: نوع واحد (سند قبض مثلاً) أو مسحوبات المالك فقط — يُلغى بزر «كل السندات».
  final VoucherType? onlyType;
  final bool drawingsOnly;

  @override
  State<VouchersSummaryScreen> createState() => _VouchersSummaryScreenState();
}

/// مجموعة سندات (حساب واحد داخل نوع واحد).
class _Group {
  _Group(this.title);
  final String title;
  final List<Map<String, Object?>> rows = [];
  double total = 0;
}

class _TypeBlock {
  _TypeBlock(this.type);
  final VoucherType type;
  final Map<String, _Group> groups = {};
  double total = 0;
  int count = 0;
  List<_Group> get sorted => groups.values.toList()..sort((a, b) => b.total.compareTo(a.total));
}

class _VouchersSummaryScreenState extends State<VouchersSummaryScreen> {
  late DateTime _from;
  late DateTime _to;
  bool _loading = true;
  String? _error;
  List<Map<String, Object?>> _rows = const [];
  final Map<VoucherType, _TypeBlock> _blocks = {};
  double _drawings = 0;
  int _drawingsCount = 0;
  VoucherType? _only;
  bool _drawingsOnly = false;

  // ترتيب العرض: ما خرج أولاً ثم ما دخل
  static const _order = [
    VoucherType.expense,
    VoucherType.payment,
    VoucherType.income,
    VoucherType.receipt,
    VoucherType.transfer,
    VoucherType.opening,
  ];

  static const _colors = {
    VoucherType.expense: ErpColors.red,
    VoucherType.payment: ErpColors.orange,
    VoucherType.income: ErpColors.green,
    VoucherType.receipt: ErpColors.blue,
    VoucherType.transfer: ErpColors.navy,
    VoucherType.opening: ErpColors.muted,
  };

  static const _icons = {
    VoucherType.expense: Icons.receipt_long_rounded,
    VoucherType.payment: Icons.outbox_rounded,
    VoucherType.income: Icons.savings_rounded,
    VoucherType.receipt: Icons.move_to_inbox_rounded,
    VoucherType.transfer: Icons.swap_horiz_rounded,
    VoucherType.opening: Icons.flag_rounded,
  };

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = widget.from ?? DateTime(now.year, now.month, 1);
    _to = widget.to ?? now;
    _drawingsOnly = widget.drawingsOnly;
    _only = widget.drawingsOnly ? VoucherType.payment : widget.onlyType;
    _load();
  }

  bool _shown(VoucherType t) => _only == null || _only == t;

  void _setRange(DateTime from, DateTime to) {
    _from = from;
    _to = to;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = await erpDb();
      final types = _order.map((t) => "'${t.name}'").join(', ');
      final rows = await db.rawQuery('''
        SELECT v.id, v.voucher_number, v.voucher_type, v.voucher_date, v.amount, v.description,
               v.currency, v.fc_amount,
               a.name AS account_name, a.system_key AS account_key,
               b.name AS box_name, tb.name AS to_box_name
        FROM vouchers v
        LEFT JOIN accounts a ON a.id = v.account_id
        LEFT JOIN cash_boxes b ON b.id = v.cash_box_id
        LEFT JOIN cash_boxes tb ON tb.id = v.to_cash_box_id
        WHERE v.is_deleted = 0 AND v.voucher_type IN ($types)
          AND v.voucher_date >= ? AND v.voucher_date < ?
        ORDER BY v.voucher_date DESC, v.id DESC''', [isoDay(_from), isoDayAfter(_to)]);
      _build(rows);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _build(List<Map<String, Object?>> rows) {
    _blocks.clear();
    _drawings = 0;
    _drawingsCount = 0;
    for (final r in rows) {
      final type = VoucherType.values.byName(r['voucher_type'] as String);
      final amt = d0(r['amount']);
      final block = _blocks.putIfAbsent(type, () => _TypeBlock(type));
      final key = _groupTitle(type, r);
      final g = block.groups.putIfAbsent(key, () => _Group(key));
      g.rows.add(r);
      g.total = roundMoney(g.total + amt);
      block.total = roundMoney(block.total + amt);
      block.count++;
      if (type == VoucherType.payment && r['account_key'] == 'owner_drawings') {
        _drawings = roundMoney(_drawings + amt);
        _drawingsCount++;
      }
    }
  }

  static String _groupTitle(VoucherType t, Map<String, Object?> r) => switch (t) {
        VoucherType.transfer => '${r['box_name'] ?? '—'} ← ${r['to_box_name'] ?? '—'}',
        VoucherType.opening => '${r['box_name'] ?? '—'}',
        _ => '${r['account_name'] ?? 'بلا حساب'}',
      };

  double _sum(Iterable<VoucherType> ts) => roundMoney(ts.fold(0.0, (s, t) => s + (_blocks[t]?.total ?? 0)));

  String _amountText(Map<String, Object?> r) {
    final cur = '${r['currency'] ?? 'IQD'}';
    final fc = d0(r['fc_amount']);
    final iqd = fmtMoney(d0(r['amount']));
    return cur != 'IQD' && fc != 0 ? '$iqd  ($cur ${fmtMoney(fc)})' : iqd;
  }

  @override
  Widget build(BuildContext context) {
    final out = _sum(const [VoucherType.expense, VoucherType.payment]);
    final inn = _sum(const [VoucherType.income, VoucherType.receipt]);
    final expense = _blocks[VoucherType.expense]?.total ?? 0;
    return ErpPage(
      title: 'ملخص السندات',
      subtitle: 'أين خرج المال وأين دخل؟ ${fmtDate(_from)} — ${fmtDate(_to)}',
      icon: Icons.summarize_rounded,
      actions: [
        IconButton(tooltip: 'تحديث', onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ...exportActions(context,
            title: 'ملخص السندات',
            subtitle: () => '${fmtDate(_from)} — ${fmtDate(_to)}',
            headers: () => ['التاريخ', 'النوع', 'الرقم', 'الحساب', 'المبلغ', 'الصندوق', 'البيان'],
            rows: () => [
                  for (final r in _rows)
                    [
                      fmtDate(parseDate(r['voucher_date'])),
                      voucherTypeLabels[VoucherType.values.byName(r['voucher_type'] as String)] ?? '',
                      '${r['voucher_number'] ?? ''}',
                      _groupTitle(VoucherType.values.byName(r['voucher_type'] as String), r),
                      _amountText(r),
                      '${r['box_name'] ?? ''}',
                      '${r['description'] ?? ''}',
                    ],
                ],
            footer: () => ['الخارج (مصروف + صرف)', '', '', '', fmtMoney(out), '', 'الداخل: ${fmtMoney(inn)}']),
      ],
      headerExtra: Wrap(spacing: 10, runSpacing: 10, children: [
        StatCard(label: 'خرج من الصناديق', hint: 'مصاريف + صرف', value: fmtMoney(out), icon: Icons.north_east_rounded, color: ErpColors.red),
        StatCard(label: 'منها مصاريف', hint: 'تنقص الربح', value: fmtMoney(expense), icon: Icons.receipt_long_rounded, color: ErpColors.orange),
        StatCard(
            label: 'مسحوبات المالك',
            hint: _drawingsCount == 0 ? 'لا سحب في الفترة' : '$_drawingsCount سند — لا تنقص الربح',
            value: fmtMoney(_drawings),
            icon: Icons.person_rounded,
            color: ErpColors.navy),
        StatCard(label: 'دخل إلى الصناديق', hint: 'إيراد + قبض', value: fmtMoney(inn), icon: Icons.south_west_rounded, color: ErpColors.green),
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('تعذّر التحميل: $_error', style: const TextStyle(color: ErpColors.red)))
              : ListView(padding: const EdgeInsets.only(bottom: 24), children: [
                  _periodBar(),
                  if (_only != null) _filterBar(),
                  if (_rows.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(
                          child: Text('لا توجد سندات في هذه الفترة', style: TextStyle(color: ErpColors.muted))),
                    ),
                  for (final t in _order)
                    if (_blocks[t] != null && _shown(t)) _typeSection(_visible(_blocks[t]!)),
                  if (_only != null && (_blocks[_only!] == null || _visible(_blocks[_only!]!).count == 0) && _rows.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(28),
                      child: Center(
                        child: Text(
                            'لا ${_drawingsOnly ? 'مسحوبات للمالك' : voucherTypeLabels[_only!]} في هذه الفترة',
                            style: const TextStyle(color: ErpColors.muted)),
                      ),
                    ),
                ]),
    );
  }

  /// المسحوبات فقط: نفس كتلة «سند صرف» لكن بحساب مسحوبات المالك وحده.
  _TypeBlock _visible(_TypeBlock b) {
    if (!_drawingsOnly || b.type != VoucherType.payment) return b;
    final x = _TypeBlock(b.type);
    for (final g in b.groups.entries) {
      final rows = g.value.rows.where((r) => r['account_key'] == 'owner_drawings').toList();
      if (rows.isEmpty) continue;
      final ng = _Group(g.key)..rows.addAll(rows);
      ng.total = roundMoney(rows.fold(0.0, (s, r) => s + d0(r['amount'])));
      x.groups[g.key] = ng;
      x.total = roundMoney(x.total + ng.total);
      x.count += rows.length;
    }
    return x;
  }

  /// شريط الفلتر القادم من البحث: ماذا يُعرض الآن + زر لعرض كل الأنواع.
  Widget _filterBar() {
    final c = _colors[_only] ?? ErpColors.navy;
    final label = _drawingsOnly ? 'مسحوبات المالك فقط' : '${voucherTypeLabels[_only]} فقط';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.withValues(alpha: 0.35)),
        ),
        child: Row(children: [
          Icon(Icons.filter_alt_rounded, color: c, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text('يُعرض: $label', style: TextStyle(fontWeight: FontWeight.w800, color: c))),
          TextButton.icon(
            onPressed: () => setState(() {
              _only = null;
              _drawingsOnly = false;
            }),
            icon: const Icon(Icons.clear_all_rounded, size: 18),
            label: const Text('كل السندات'),
          ),
        ]),
      ),
    );
  }

  Widget _periodBar() {
    final now = DateTime.now();
    final lastMonthStart = DateTime(now.year, now.month - 1, 1);
    final lastMonthEnd = DateTime(now.year, now.month, 0);
    Widget chip(String label, DateTime f, DateTime t) {
      final on = isoDay(_from) == isoDay(f) && isoDay(_to) == isoDay(t);
      return ChoiceChip(label: Text(label), selected: on, onSelected: (_) => _setRange(f, t));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
        chip('هذا الشهر', DateTime(now.year, now.month, 1), now),
        chip('الشهر الماضي', lastMonthStart, lastMonthEnd),
        chip('هذه السنة', DateTime(now.year, 1, 1), now),
        DateButton(label: 'من', value: _from, onChanged: (d) => _setRange(d, _to)),
        DateButton(label: 'إلى', value: _to, onChanged: (d) => _setRange(_from, d)),
      ]),
    );
  }

  Widget _typeSection(_TypeBlock b) {
    final c = _colors[b.type] ?? ErpColors.navy;
    return ErpSection(
      title: '${voucherTypeLabels[b.type]}  •  ${b.count} سند',
      icon: _icons[b.type],
      color: c,
      trailing: Text(fmtMoney(b.total), style: TextStyle(fontWeight: FontWeight.w800, color: c, fontSize: 15)),
      child: Column(children: [
        for (final g in b.sorted) _groupTile(g, b.total, c),
      ]),
    );
  }

  Widget _groupTile(_Group g, double typeTotal, Color c) {
    final pct = typeTotal <= 0 ? 0.0 : (g.total / typeTotal).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: c.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 12),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            title: Row(children: [
              Expanded(
                child: Text(g.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              Text('${g.rows.length} سند', style: const TextStyle(color: ErpColors.muted, fontSize: 12)),
              const SizedBox(width: 12),
              Text(fmtMoney(g.total), style: TextStyle(fontWeight: FontWeight.w800, color: c)),
            ]),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(value: pct.toDouble(), minHeight: 6, color: c, backgroundColor: ErpColors.bg),
                  ),
                ),
                const SizedBox(width: 8),
                Text('${(pct * 100).toStringAsFixed(1)}٪', style: const TextStyle(fontSize: 11.5, color: ErpColors.muted)),
              ]),
            ),
            children: [
              // كل سند بسطر — اضغط لتفاصيله كاملة (من أين، من أنشأه، قيده) وطباعته
              for (final r in g.rows)
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => showVoucherDetails(context, r['id'] as int),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    child: Row(children: [
                      SizedBox(
                        width: 86,
                        child: Text(fmtDate(parseDate(r['voucher_date'])), style: const TextStyle(fontSize: 12.5, color: ErpColors.muted)),
                      ),
                      SizedBox(width: 54, child: Text('#${r['voucher_number'] ?? ''}', style: const TextStyle(fontSize: 12.5))),
                      Expanded(
                        child: Text(
                          ['${r['description'] ?? ''}'.trim(), '${r['box_name'] ?? ''}'.trim()].where((x) => x.isNotEmpty).join(' — '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(_amountText(r), style: TextStyle(fontWeight: FontWeight.w800, color: c)),
                      const Icon(Icons.chevron_left_rounded, color: ErpColors.muted),
                    ]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
