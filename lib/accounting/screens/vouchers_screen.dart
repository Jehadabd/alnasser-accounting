// lib/accounting/screens/vouchers_screen.dart
//
// 🧾 السندات: قائمة + إنشاء (مصروف، إيراد، صرف، قبض، تحويل، رصيد افتتاحي).
//
//   • VouchersScreen — فترة بأزرار سريعة، ملخّص المقبوض/المدفوع في الرأس،
//     فلترة بالنوع (مع العدد) وبحث، وبطاقة لكل سند (طباعة/حذف).
//   • showVoucherTypePicker — نافذة «سند جديد»: ست بطاقات بألوان وأرقام 1–6.
//   • VoucherFormScreen — نموذج السند: تبديل النوع من الرأس، مبلغ كبير مع
//     التفقيط، الصناديق كبطاقات بأرصدتها، الحساب ببحث، ومعاينة القيد.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../erp/accounting_plus/voucher_pdf.dart';
import '../../erp/arabic_words.dart';
import '../../erp/erp_common.dart' show confirmDialog, parseMoney;
import '../../erp/erp_ui.dart';
import '../../models/app_user.dart';
import '../../services/auth_service.dart';
import '../../widgets/formatters.dart';
import '../ledger.dart';
import '../vouchers_service.dart';
import 'acc_ui.dart';

// ═══════════════════════════ هوية كل نوع ═══════════════════════════

class VoucherStyle {
  const VoucherStyle({
    required this.icon,
    required this.color,
    required this.hint,
    required this.effect,
    required this.flow,
  });
  final IconData icon;
  final Color color;

  /// أمثلة قصيرة لما يُسجَّل بهذا النوع.
  final String hint;

  /// أثره على الصندوق بكلمات.
  final String effect;

  /// +1 يدخل الصندوق، ‎-1 يخرج منه، 0 تحويل بين صندوقين.
  final int flow;
}

const Map<VoucherType, VoucherStyle> voucherStyles = {
  VoucherType.expense: VoucherStyle(
    icon: Icons.receipt_long_rounded,
    color: Color(0xFFDC2626),
    hint: 'إيجار، رواتب، كهرباء، نقل، ضيافة…',
    effect: 'يخرج من الصندوق',
    flow: -1,
  ),
  VoucherType.income: VoucherStyle(
    icon: Icons.savings_rounded,
    color: Color(0xFF059669),
    hint: 'إيراد غير المبيعات: عمولة، إيجار مستلم…',
    effect: 'يدخل الصندوق',
    flow: 1,
  ),
  VoucherType.payment: VoucherStyle(
    icon: Icons.outbox_rounded,
    color: Color(0xFFEA580C),
    hint: 'دفع لأي حساب: مسحوبات، سلفة موظف، شراء أصل…',
    effect: 'يخرج من الصندوق',
    flow: -1,
  ),
  VoucherType.receipt: VoucherStyle(
    icon: Icons.move_to_inbox_rounded,
    color: Color(0xFF0D9488),
    hint: 'قبض من أي حساب: رأس مال، استرداد سلفة…',
    effect: 'يدخل الصندوق',
    flow: 1,
  ),
  VoucherType.transfer: VoucherStyle(
    icon: Icons.swap_horiz_rounded,
    color: Color(0xFF2563EB),
    hint: 'نقل مبلغ من صندوق أو بنك إلى آخر',
    effect: 'المجموع لا يتغير',
    flow: 0,
  ),
  VoucherType.opening: VoucherStyle(
    icon: Icons.flag_rounded,
    color: Color(0xFF7C3AED),
    hint: 'المبلغ الموجود فعلاً في الدرج عند بدء العمل',
    effect: 'مرة واحدة لكل صندوق',
    flow: 1,
  ),
};

VoucherStyle voucherStyle(VoucherType t) => voucherStyles[t]!;

IconData _flowIcon(int flow) => flow > 0
    ? Icons.south_west_rounded
    : flow < 0
        ? Icons.north_east_rounded
        : Icons.sync_alt_rounded;

// ═══════════════════════════ نافذة «سند جديد» ═══════════════════════════

const _digitKeys = [
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
];
const _numpadKeys = [
  LogicalKeyboardKey.numpad1,
  LogicalKeyboardKey.numpad2,
  LogicalKeyboardKey.numpad3,
  LogicalKeyboardKey.numpad4,
  LogicalKeyboardKey.numpad5,
  LogicalKeyboardKey.numpad6,
];

/// يعرض أنواع السندات كبطاقات ويعيد النوع المختار (أو null).
Future<VoucherType?> showVoucherTypePicker(BuildContext context) {
  const types = VoucherType.values;
  return showDialog<VoucherType>(
    context: context,
    builder: (ctx) => CallbackShortcuts(
      bindings: {
        for (var i = 0; i < types.length && i < _digitKeys.length; i++) ...{
          SingleActivator(_digitKeys[i]): () => Navigator.pop(ctx, types[i]),
          SingleActivator(_numpadKeys[i]): () => Navigator.pop(ctx, types[i]),
        },
      },
      child: Focus(
        autofocus: true,
        child: ErpDialog(
          title: 'سند جديد',
          subtitle: 'اختر نوع السند — أو اضغط رقمه من لوحة المفاتيح',
          icon: Icons.post_add_rounded,
          width: 700,
          content: LayoutBuilder(builder: (context, c) {
            final cols = c.maxWidth >= 560 ? 3 : (c.maxWidth >= 360 ? 2 : 1);
            const gap = 12.0;
            final w = (c.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(spacing: gap, runSpacing: gap, children: [
              for (var i = 0; i < types.length; i++)
                SizedBox(
                  width: w,
                  child: FadeSlideIn(
                    index: i,
                    child: _TypeCard(
                      type: types[i],
                      number: i + 1,
                      onTap: () => Navigator.pop(ctx, types[i]),
                    ),
                  ),
                ),
            ]);
          }),
        ),
      ),
    ),
  );
}

class _TypeCard extends StatefulWidget {
  const _TypeCard({required this.type, required this.number, required this.onTap});
  final VoucherType type;
  final int number;
  final VoidCallback onTap;
  @override
  State<_TypeCard> createState() => _TypeCardState();
}

class _TypeCardState extends State<_TypeCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final s = voucherStyle(widget.type);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: _hover ? 1.025 : 1,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: _hover ? s.color.withValues(alpha: 0.20) : const Color(0x0A0F172A),
                blurRadius: _hover ? 18 : 6,
                offset: Offset(0, _hover ? 8 : 2),
              ),
            ],
          ),
          child: Material(
            color: _hover ? Color.alphaBlend(s.color.withValues(alpha: 0.05), Colors.white) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: _hover ? s.color : ErpColors.border, width: _hover ? 1.6 : 1),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.onTap,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: _hover ? s.color : s.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(s.icon, color: _hover ? Colors.white : s.color, size: 24),
                    ),
                    const Spacer(),
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: ErpColors.bg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: ErpColors.border),
                      ),
                      child: Text('${widget.number}',
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: ErpColors.muted)),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  Text(voucherTypeLabels[widget.type]!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: ErpColors.text)),
                  const SizedBox(height: 3),
                  SizedBox(
                    height: 34,
                    child: Text(s.hint,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: ErpColors.muted, height: 1.4)),
                  ),
                  const SizedBox(height: 10),
                  _FlowChip(s),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FlowChip extends StatelessWidget {
  const _FlowChip(this.s);
  final VoucherStyle s;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: s.color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(_flowIcon(s.flow), size: 14, color: s.color),
          const SizedBox(width: 5),
          Text(s.effect, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: s.color)),
        ]),
      );
}

// ═══════════════════════════ قائمة السندات ═══════════════════════════

class VouchersScreen extends StatefulWidget {
  const VouchersScreen({super.key, this.initialNew = false});

  /// يفتح نموذج سند مصروف مباشرة (للتوافق؛ مركز المحاسبة يفتح النموذج بنفسه).
  final bool initialNew;

  @override
  State<VouchersScreen> createState() => _VouchersScreenState();
}

class _VouchersScreenState extends State<VouchersScreen> {
  final _svc = VouchersService();
  DateTime? _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  VoucherType? _type;
  String _q = '';
  List<Map<String, Object?>> _rows = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.initialNew) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _new(VoucherType.expense));
    }
  }

  /// كل أنواع الفترة دفعة واحدة؛ الفلترة بالنوع والبحث محلياً (فورية + أعداد لكل نوع).
  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await _svc.list(from: _from, to: _to);
      if (mounted) setState(() => _rows = r);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static VoucherType _typeOf(Map<String, Object?> v) => VoucherType.values.byName(v['voucher_type'] as String);

  List<Map<String, Object?>> get _shown {
    Iterable<Map<String, Object?>> it = _rows;
    if (_type != null) it = it.where((v) => v['voucher_type'] == _type!.name);
    final q = _q.trim();
    if (q.isNotEmpty) {
      it = it.where((v) => '${v['voucher_number']} ${v['description'] ?? ''} ${v['account_name'] ?? ''} '
              '${v['cash_box_name'] ?? ''} ${v['to_cash_box_name'] ?? ''} ${v['reference'] ?? ''}'
          .contains(q));
    }
    return it.toList();
  }

  Future<void> _new([VoucherType? type]) async {
    if (!requirePermission(context, AppPermissions.accountingPost)) return;
    final t = type ?? await showVoucherTypePicker(context);
    if (t == null || !mounted) return;
    final saved = await Navigator.push<bool>(context, accRoute(VoucherFormScreen(type: t)));
    if (!mounted) return;
    if (saved == true) showOk(context, 'حُفظ ${voucherTypeLabels[t]}');
    _load();
  }

  Future<void> _delete(Map<String, Object?> v) async {
    if (!requirePermission(context, AppPermissions.accountingPost)) return;
    final ok = await confirmDialog(
      context,
      'حذف السند',
      'حذف ${voucherTypeLabels[_typeOf(v)]} رقم ${v['voucher_number']} بمبلغ ${fmtMoney((v['amount'] as num))}؟\n'
          'سيُحذف قيده من الدفتر ويبقى السند محفوظاً في السجل كـ«محذوف».',
      ok: 'حذف',
      color: AccColors.red,
    );
    if (!ok) return;
    try {
      await _svc.delete(v['id'] as int, userId: AuthService().currentUser?.id);
      if (mounted) showOk(context, 'حُذف السند');
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Widget _summary(List<Map<String, Object?>> rows) {
    double inn = 0, out = 0;
    for (final v in rows) {
      final a = (v['amount'] as num).toDouble();
      switch (_typeOf(v)) {
        case VoucherType.income || VoucherType.receipt:
          inn += a;
        case VoucherType.expense || VoucherType.payment:
          out += a;
        case VoucherType.transfer || VoucherType.opening:
          break;
      }
    }
    return Wrap(spacing: 10, runSpacing: 8, children: [
      HeaderStat(
          label: 'المقبوض', value: fmtMoney(inn), icon: Icons.south_west_rounded, accent: const Color(0xFF6EE7B7)),
      HeaderStat(
          label: 'المدفوع', value: fmtMoney(out), icon: Icons.north_east_rounded, accent: const Color(0xFFFCA5A5)),
      HeaderStat(
        label: 'الصافي',
        value: fmtMoney(inn - out),
        icon: Icons.balance_rounded,
        tooltip: 'المقبوض − المدفوع (بلا التحويلات والأرصدة الافتتاحية)',
      ),
      HeaderStat(label: 'عدد السندات', value: '${rows.length}', icon: Icons.tag_rounded),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    final counts = <VoucherType, int>{};
    for (final v in _rows) {
      final t = _typeOf(v);
      counts[t] = (counts[t] ?? 0) + 1;
    }
    return ErpPage(
      title: 'السندات',
      subtitle: 'قبض • صرف • مصروف • إيراد • تحويل • رصيد افتتاحي',
      icon: Icons.description_rounded,
      actions: [
        IconButton(tooltip: 'تحديث', icon: const Icon(Icons.refresh_rounded), onPressed: _loading ? null : _load),
      ],
      headerExtra: Align(alignment: AlignmentDirectional.centerStart, child: _summary(shown)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _new(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('سند جديد'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1240),
          child: Column(children: [
            PeriodBar(
              from: _from,
              to: _to,
              onChanged: (f, t) {
                setState(() {
                  _from = f;
                  _to = t;
                });
                _load();
              },
            ),
            LayoutBuilder(builder: (context, c) {
              final wide = c.maxWidth >= 900;
              final filters = SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  children: [
                    _FilterPill(
                      label: 'الكل',
                      count: _rows.length,
                      icon: Icons.apps_rounded,
                      color: AccColors.navy,
                      selected: _type == null,
                      onTap: () => setState(() => _type = null),
                    ),
                    for (final t in VoucherType.values)
                      _FilterPill(
                        label: voucherTypeLabels[t]!,
                        count: counts[t] ?? 0,
                        icon: voucherStyle(t).icon,
                        color: voucherStyle(t).color,
                        selected: _type == t,
                        onTap: () => setState(() => _type = _type == t ? null : t),
                      ),
                  ],
                ),
              );
              final search = SearchBox(
                hint: 'بحث برقم السند أو البيان أو الحساب…',
                onChanged: (v) => setState(() => _q = v),
              );
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: wide
                    ? Row(children: [
                        Expanded(child: filters),
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 14),
                          child: SizedBox(width: 300, child: search),
                        ),
                      ])
                    : Column(children: [
                        filters,
                        Padding(padding: const EdgeInsets.fromLTRB(14, 8, 14, 0), child: search),
                      ]),
              );
            }),
            SizedBox(
              height: 2,
              child: _loading ? const LinearProgressIndicator(minHeight: 2) : null,
            ),
            Expanded(
              child: shown.isEmpty && !_loading
                  ? EmptyState(
                      _rows.isEmpty ? 'لا توجد سندات في هذه الفترة' : 'لا توجد نتائج مطابقة',
                      icon: Icons.receipt_long_outlined,
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 96),
                      itemCount: shown.length,
                      itemBuilder: (_, i) {
                        final v = shown[i];
                        final row = _VoucherRow(
                          v: v,
                          onPrint: () => VoucherPdf.printVoucher(context, v['id'] as int),
                          onDelete: () => _delete(v),
                        );
                        return i < 14 ? FadeSlideIn(key: ValueKey(v['id']), index: i, child: row) : row;
                      },
                    ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _FilterPill extends StatefulWidget {
  const _FilterPill({
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final int count;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  @override
  State<_FilterPill> createState() => _FilterPillState();
}

class _FilterPillState extends State<_FilterPill> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final sel = widget.selected;
    final c = widget.color;
    final empty = widget.count == 0 && !sel;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8, top: 2, bottom: 2),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: empty ? 0.55 : 1,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              padding: const EdgeInsetsDirectional.fromSTEB(10, 0, 8, 0),
              decoration: BoxDecoration(
                color: sel ? c : (_hover ? Color.alphaBlend(c.withValues(alpha: 0.06), Colors.white) : Colors.white),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: sel ? c : (_hover ? c.withValues(alpha: 0.5) : ErpColors.border)),
                boxShadow: sel ? [BoxShadow(color: c.withValues(alpha: 0.25), blurRadius: 10, offset: const Offset(0, 3))] : const [],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(widget.icon, size: 17, color: sel ? Colors.white : c),
                const SizedBox(width: 7),
                Text(widget.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                      color: sel ? Colors.white : ErpColors.text,
                    )),
                const SizedBox(width: 7),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                  decoration: BoxDecoration(
                    color: sel ? Colors.white.withValues(alpha: 0.22) : c.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('${widget.count}',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: sel ? Colors.white : c)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _VoucherRow extends StatefulWidget {
  const _VoucherRow({required this.v, required this.onPrint, required this.onDelete});
  final Map<String, Object?> v;
  final VoidCallback onPrint;
  final VoidCallback onDelete;
  @override
  State<_VoucherRow> createState() => _VoucherRowState();
}

class _VoucherRowState extends State<_VoucherRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final v = widget.v;
    final t = VoucherType.values.byName(v['voucher_type'] as String);
    final s = voucherStyle(t);
    final amount = (v['amount'] as num).toDouble();
    final date = DateTime.parse(v['voucher_date'] as String);
    final desc = ((v['description'] as String?) ?? '').trim();
    final ref = ((v['reference'] as String?) ?? '').trim();
    final target = t == VoucherType.transfer
        ? '${v['cash_box_name'] ?? ''}  ←  ${v['to_cash_box_name'] ?? ''}'
        : [v['account_name'], v['cash_box_name']]
            .where((x) => x != null && '$x'.trim().isNotEmpty)
            .join('  •  ');
    final amountColor = s.flow > 0
        ? const Color(0xFF047857)
        : s.flow < 0
            ? const Color(0xFFB91C1C)
            : AccColors.navy;
    final sign = s.flow > 0 ? '+' : (s.flow < 0 ? '−' : '');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _hover ? s.color.withValues(alpha: 0.45) : ErpColors.border),
            boxShadow: [
              BoxShadow(
                color: _hover ? s.color.withValues(alpha: 0.12) : const Color(0x080F172A),
                blurRadius: _hover ? 14 : 6,
                offset: Offset(0, _hover ? 5 : 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 6, 10),
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: s.color.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(s.icon, color: s.color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(
                      child: Text(voucherTypeLabels[t]!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: ErpColors.text)),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                      decoration: BoxDecoration(color: ErpColors.bg, borderRadius: BorderRadius.circular(6)),
                      child: Text('#${v['voucher_number']}',
                          textDirection: TextDirection.ltr,
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: ErpColors.muted)),
                    ),
                    if (ref.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text('مرجع: $ref',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11.5, color: ErpColors.muted)),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 3),
                  if (target.isNotEmpty)
                    Text(target,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, color: ErpColors.muted)),
                  if (desc.isNotEmpty)
                    Text(desc,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, color: ErpColors.text)),
                ]),
              ),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('$sign${fmtMoney(amount)}',
                    textDirection: TextDirection.ltr,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: amountColor)),
                const SizedBox(height: 2),
                Text(fmtDate(date),
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(fontSize: 11.5, color: ErpColors.muted)),
              ]),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'طباعة السند',
                icon: const Icon(Icons.print_outlined, color: ErpColors.navy),
                onPressed: widget.onPrint,
              ),
              IconButton(
                tooltip: 'حذف',
                icon: Icon(Icons.delete_outline_rounded, color: _hover ? AccColors.red : ErpColors.muted),
                onPressed: widget.onDelete,
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════ نموذج السند ═══════════════════════════════

class VoucherFormScreen extends StatefulWidget {
  const VoucherFormScreen({
    super.key,
    required this.type,
    this.initialCashBoxId,
    this.initialAccountId,
    this.initialDescription,
  });
  final VoucherType type;

  /// قيم أولية (من قوالب السندات).
  final int? initialCashBoxId;
  final int? initialAccountId;
  final String? initialDescription;

  @override
  State<VoucherFormScreen> createState() => _VoucherFormScreenState();
}

class _VoucherFormScreenState extends State<VoucherFormScreen> {
  final _svc = VouchersService();
  final _ledger = Ledger();
  final _amount = TextEditingController();
  final _desc = TextEditingController();
  final _ref = TextEditingController();
  final _amountFocus = FocusNode();
  late VoucherType _type = widget.type;
  DateTime _date = DateTime.now();
  List<CashBox> _boxes = const [];
  Map<int, double> _bal = const {};
  List<Account> _allAccounts = const [];
  CashBox? _box;
  CashBox? _toBox;
  Account? _account;
  bool _saving = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _amount.addListener(_onAmount);
    _init();
  }

  void _onAmount() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _amount.removeListener(_onAmount);
    _amount.dispose();
    _desc.dispose();
    _ref.dispose();
    _amountFocus.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final boxes = await _svc.cashBoxes();
      final bal = await _svc.cashBoxBalances();
      final all = await _ledger.postableAccounts(excludeControl: true);
      if (!mounted) return;
      setState(() {
        _boxes = boxes;
        _bal = bal;
        _allAccounts = all;
        _box = boxes.isEmpty ? null : boxes.first;
        for (final b in boxes) {
          if (b.id == widget.initialCashBoxId) _box = b;
        }
        for (final a in _accountsFor(_type)) {
          if (a.id == widget.initialAccountId) _account = a;
        }
        if (widget.initialDescription != null && _desc.text.isEmpty) _desc.text = widget.initialDescription!;
        _ready = true;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _ready = true);
        showError(context, e);
      }
    }
  }

  List<Account> _accountsFor(VoucherType t) {
    final boxAccIds = _boxes.map((b) => b.accountId).toSet();
    return switch (t) {
      VoucherType.expense => _allAccounts.where((a) => a.type == 'expense').toList(),
      VoucherType.income => _allAccounts.where((a) => a.type == 'revenue').toList(),
      _ => _allAccounts.where((a) => !boxAccIds.contains(a.id)).toList(),
    };
  }

  bool get _needsAccount => _type != VoucherType.transfer && _type != VoucherType.opening;

  String get _accountLabel => switch (_type) {
        VoucherType.expense => 'نوع المصروف',
        VoucherType.income => 'نوع الإيراد',
        VoucherType.payment => 'الحساب المدفوع له',
        VoucherType.receipt => 'الحساب المقبوض منه',
        _ => 'الحساب',
      };

  String get _boxLabel => switch (_type) {
        VoucherType.transfer => 'من الصندوق',
        VoucherType.expense || VoucherType.payment => 'يُدفع من',
        _ => 'يُقبض في',
      };

  void _setType(VoucherType t) {
    if (t == _type) return;
    setState(() {
      _type = t;
      final a = _account;
      if (a != null && !_accountsFor(t).any((x) => x.id == a.id)) _account = null;
      if (t != VoucherType.transfer) _toBox = null;
    });
  }

  Future<void> _pickAccount() async {
    final s = voucherStyle(_type);
    final a = await pickFromList<Account>(
      context,
      title: _accountLabel,
      subtitle: 'ابحث بالاسم أو برقم الحساب',
      items: _accountsFor(_type),
      labelOf: (a) => '${a.code}  ${a.name}',
      detailOf: (a) => a.typeLabel,
      icon: Icons.account_tree_rounded,
      color: s.color,
    );
    if (a != null && mounted) setState(() => _account = a);
  }

  /// Enter في حقل المبلغ: يفتح اختيار الحساب إن لم يُختر، وإلا يحفظ.
  void _onAmountSubmitted() {
    if (_needsAccount && _account == null && _accountsFor(_type).length > 12) {
      _pickAccount();
    } else {
      _save();
    }
  }

  Future<void> _save({bool again = false}) async {
    if (_saving) return;
    final amount = parseMoney(_amount.text) ?? 0;
    if (_box == null) {
      showError(context, 'اختر الصندوق');
      return;
    }
    if (amount <= 0) {
      showError(context, 'أدخل المبلغ');
      _amountFocus.requestFocus();
      return;
    }
    if (_needsAccount && _account == null) {
      showError(context, 'اختر $_accountLabel');
      return;
    }
    if (_type == VoucherType.transfer && _toBox == null) {
      showError(context, 'اختر الصندوق المحوَّل إليه');
      return;
    }
    setState(() => _saving = true);
    try {
      await _svc.create(
        type: _type,
        amount: amount,
        date: _date,
        cashBoxId: _box!.id,
        toCashBoxId: _type == VoucherType.transfer ? _toBox?.id : null,
        accountId: _needsAccount ? _account?.id : null,
        description: _desc.text.trim(),
        reference: _ref.text.trim(),
        userId: AuthService().currentUser?.id,
      );
      if (!mounted) return;
      if (!again) {
        Navigator.pop(context, true);
        return;
      }
      showOk(context, 'حُفظ ${voucherTypeLabels[_type]} — أدخل السند التالي');
      _amount.clear();
      _desc.clear();
      _ref.clear();
      _amountFocus.requestFocus();
      final bal = await _svc.cashBoxBalances();
      if (mounted) setState(() => _bal = bal);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ─────────────────────────── أجزاء النموذج ───────────────────────────

  Widget _boxPicker({
    required CashBox? selected,
    required ValueChanged<CashBox> onPick,
    required Color color,
    int? exclude,
  }) {
    final list = _boxes.where((b) => b.id != exclude).toList();
    if (list.isEmpty) {
      return const Text('لا يوجد صندوق آخر', style: TextStyle(color: ErpColors.muted));
    }
    if (list.length > 8) {
      return DropdownButtonFormField<CashBox>(
        initialValue: list.contains(selected) ? selected : null,
        isExpanded: true,
        decoration: const InputDecoration(prefixIcon: Icon(Icons.account_balance_wallet_rounded)),
        items: [
          for (final b in list)
            DropdownMenuItem(value: b, child: Text('${b.name}   (${fmtMoney(_bal[b.id] ?? 0)})')),
        ],
        onChanged: (b) {
          if (b != null) onPick(b);
        },
      );
    }
    return Wrap(spacing: 10, runSpacing: 10, children: [
      for (final b in list)
        ChoiceTile(
          width: 220,
          dense: true,
          title: b.name,
          subtitle: 'الرصيد: ${fmtMoney(_bal[b.id] ?? 0)}',
          icon: b.kind == 'bank' ? Icons.account_balance_rounded : Icons.payments_rounded,
          selected: selected?.id == b.id,
          color: color,
          onTap: () => onPick(b),
        ),
    ]);
  }

  Widget _accountPicker(VoucherStyle s) {
    final accs = _accountsFor(_type);
    if (accs.isEmpty) {
      return Text(
        _type == VoucherType.expense
            ? 'لا توجد حسابات مصاريف — أضفها من «شجرة الحسابات»'
            : _type == VoucherType.income
                ? 'لا توجد حسابات إيرادات — أضفها من «شجرة الحسابات»'
                : 'لا توجد حسابات متاحة',
        style: const TextStyle(color: AccColors.orange),
      );
    }
    // قائمة قصيرة (مثل أنواع المصاريف): بطاقات بنقرة واحدة
    if (accs.length <= 12) {
      return Wrap(spacing: 8, runSpacing: 8, children: [
        for (final a in accs)
          ChoiceTile(
            width: 200,
            dense: true,
            title: a.name,
            subtitle: a.code,
            selected: _account?.id == a.id,
            color: s.color,
            onTap: () => setState(() => _account = a),
          ),
      ]);
    }
    final a = _account;
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: a == null ? ErpColors.border : s.color, width: a == null ? 1 : 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _pickAccount,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: s.color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
              child: Icon(a == null ? Icons.search_rounded : Icons.account_tree_rounded, size: 18, color: s.color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: a == null
                  ? Text('اضغط لاختيار $_accountLabel (${accs.length} حساب)',
                      style: const TextStyle(color: ErpColors.muted, fontSize: 14))
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(a.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: ErpColors.text)),
                      Text('${a.code} • ${a.typeLabel}', style: const TextStyle(fontSize: 12, color: ErpColors.muted)),
                    ]),
            ),
            const Icon(Icons.unfold_more_rounded, color: ErpColors.muted),
          ]),
        ),
      ),
    );
  }

  Widget _entryPreview(VoucherStyle s) {
    final box = _box?.name ?? 'الصندوق';
    final acc = _account?.name ?? _accountLabel;
    final (dr, cr) = switch (_type) {
      VoucherType.expense || VoucherType.payment => (acc, box),
      VoucherType.income || VoucherType.receipt => (box, acc),
      VoucherType.opening => (box, 'الأرصدة الافتتاحية'),
      VoucherType.transfer => (_toBox?.name ?? 'الصندوق المستلم', box),
    };
    Widget side(String label, String name, Color c) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.withValues(alpha: 0.35)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('$label: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: c)),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ErpColors.text)),
            ),
          ]),
        );
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.menu_book_rounded, size: 18, color: ErpColors.muted),
          SizedBox(width: 6),
          Text('القيد الذي سيُسجَّل', style: TextStyle(fontSize: 12.5, color: ErpColors.muted, fontWeight: FontWeight.w600)),
        ]),
        side('مدين', dr, const Color(0xFF047857)),
        const Icon(Icons.arrow_back_rounded, size: 16, color: ErpColors.muted),
        side('دائن', cr, const Color(0xFFB91C1C)),
      ],
    );
  }

  Widget _bottomBar(VoucherStyle s) => SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: ErpColors.border)),
            boxShadow: [BoxShadow(color: Color(0x0F0F172A), blurRadius: 12, offset: Offset(0, -4))],
          ),
          // heightFactor: 1 — الشريط السفلي يأخذ ارتفاع محتواه فقط (Center وحده يتمدد لكامل الشاشة)
          child: Align(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Row(children: [
                Expanded(
                  child: Tooltip(
                    message: 'Ctrl + S',
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: s.color, minimumSize: const Size(0, 50)),
                      onPressed: _saving || !_ready ? null : () => _save(),
                      icon: _saving
                          ? const SizedBox(
                              width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.check_rounded),
                      label: Text('حفظ ${voucherTypeLabels[_type]}'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Tooltip(
                  message: 'Ctrl + Enter',
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 50)),
                    onPressed: _saving || !_ready ? null : () => _save(again: true),
                    icon: const Icon(Icons.playlist_add_rounded),
                    label: const Text('حفظ وسند آخر'),
                  ),
                ),
              ]),
            ),
          ),
        ),
      );

  Widget _headerTypes() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (final t in VoucherType.values)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: _HeaderTypeTab(type: t, selected: t == _type, onTap: () => _setType(t)),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = voucherStyle(_type);
    final amount = parseMoney(_amount.text) ?? 0;
    final boxBal = _box == null ? 0.0 : (_bal[_box!.id] ?? 0);
    final overdraw = s.flow < 0 || _type == VoucherType.transfer ? amount > boxBal + 0.004 && amount > 0 : false;

    var i = 0;
    Widget panel(String key, Widget child, {Color? tint}) =>
        FadeSlideIn(key: ValueKey(key), index: i++, child: _Panel(tint: tint, child: child));

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () => _save(),
        const SingleActivator(LogicalKeyboardKey.enter, control: true): () => _save(again: true),
        const SingleActivator(LogicalKeyboardKey.numpadEnter, control: true): () => _save(again: true),
      },
      child: ErpPage(
        title: voucherTypeLabels[_type]!,
        subtitle: s.hint,
        icon: s.icon,
        headerExtra: _headerTypes(),
        bottom: _bottomBar(s),
        body: !_ready
            ? const Center(child: CircularProgressIndicator())
            : _boxes.isEmpty
                ? const EmptyState('لا يوجد صندوق فعّال — أضف صندوقاً من «الصناديق والبنوك»',
                    icon: Icons.account_balance_wallet_outlined)
                : Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 24), children: [
                        // المبلغ
                        panel('amount', Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          _PanelTitle('المبلغ', Icons.payments_rounded, s.color),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _amount,
                            focusNode: _amountFocus,
                            autofocus: true,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [ThousandSeparatorDecimalInputFormatter()],
                            textDirection: TextDirection.ltr,
                            textAlign: TextAlign.right,
                            onSubmitted: (_) => _onAmountSubmitted(),
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              color: s.color,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                            decoration: InputDecoration(
                              hintText: '0',
                              suffixText: 'د.ع',
                              suffixStyle: const TextStyle(fontSize: 15, color: ErpColors.muted, fontWeight: FontWeight.w700),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(color: s.color, width: 2),
                              ),
                            ),
                          ),
                          AnimatedSize(
                            duration: const Duration(milliseconds: 180),
                            alignment: AlignmentDirectional.topStart,
                            child: amount > 0
                                ? Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(ArabicWords.money(amount),
                                        style: const TextStyle(fontSize: 12.5, color: ErpColors.muted, height: 1.5)),
                                  )
                                : const SizedBox(width: double.infinity),
                          ),
                        ])),
                        // الصندوق
                        panel('box', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          _PanelTitle(_boxLabel, Icons.account_balance_wallet_rounded, s.color),
                          const SizedBox(height: 10),
                          _boxPicker(
                            selected: _box,
                            color: s.color,
                            onPick: (b) => setState(() {
                              _box = b;
                              if (_toBox?.id == b.id) _toBox = null;
                            }),
                          ),
                          if (overdraw)
                            Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Row(children: [
                                const Icon(Icons.warning_amber_rounded, size: 18, color: AccColors.orange),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text('المبلغ أكبر من رصيد «${_box!.name}» في الدفتر (${fmtMoney(boxBal)})',
                                      style: const TextStyle(fontSize: 12.5, color: AccColors.orange)),
                                ),
                              ]),
                            ),
                          if (_type == VoucherType.transfer) ...[
                            const SizedBox(height: 16),
                            _PanelTitle('إلى الصندوق', Icons.south_west_rounded, s.color),
                            const SizedBox(height: 10),
                            _boxPicker(
                              selected: _toBox,
                              color: s.color,
                              exclude: _box?.id,
                              onPick: (b) => setState(() => _toBox = b),
                            ),
                          ],
                        ])),
                        // الحساب
                        if (_needsAccount)
                          panel('account', Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            _PanelTitle(_accountLabel, Icons.account_tree_rounded, s.color,
                                trailing: _accountsFor(_type).length > 12
                                    ? null
                                    : TextButton.icon(
                                        onPressed: _pickAccount,
                                        icon: const Icon(Icons.search_rounded, size: 18),
                                        label: const Text('بحث'),
                                      )),
                            const SizedBox(height: 10),
                            _accountPicker(s),
                          ])),
                        // التفاصيل
                        panel('details', Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          _PanelTitle('التفاصيل', Icons.notes_rounded, s.color),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _desc,
                            decoration: const InputDecoration(
                              labelText: 'البيان',
                              prefixIcon: Icon(Icons.short_text_rounded),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(children: [
                            Expanded(
                              child: TextField(
                                controller: _ref,
                                decoration: const InputDecoration(
                                  labelText: 'رقم مرجعي (وصل/فاتورة خارجية) — اختياري',
                                  prefixIcon: Icon(Icons.tag_rounded),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            DatePill(
                              label: 'التاريخ',
                              value: _date,
                              help: 'تاريخ السند',
                              onPicked: (d) => setState(() => _date = d),
                            ),
                          ]),
                        ])),
                        // معاينة القيد
                        panel('entry', _entryPreview(s), tint: const Color(0xFFF8FAFD)),
                      ]),
                    ),
                  ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.tint});
  final Widget child;
  final Color? tint;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: tint ?? Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: ErpColors.border),
          boxShadow: const [BoxShadow(color: Color(0x080F172A), blurRadius: 10, offset: Offset(0, 3))],
        ),
        child: child,
      );
}

class _PanelTitle extends StatelessWidget {
  const _PanelTitle(this.text, this.icon, this.color, {this.trailing});
  final String text;
  final IconData icon;
  final Color color;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Row(children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: ErpColors.text)),
        ),
        if (trailing != null) trailing!,
      ]);
}

/// تبويب نوع السند داخل الرأس المتدرّج.
class _HeaderTypeTab extends StatefulWidget {
  const _HeaderTypeTab({required this.type, required this.selected, required this.onTap});
  final VoucherType type;
  final bool selected;
  final VoidCallback onTap;
  @override
  State<_HeaderTypeTab> createState() => _HeaderTypeTabState();
}

class _HeaderTypeTabState extends State<_HeaderTypeTab> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final s = voucherStyle(widget.type);
    final sel = widget.selected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: sel ? Colors.white : Colors.white.withValues(alpha: _hover ? 0.18 : 0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: sel ? 0 : 0.16)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(s.icon, size: 17, color: sel ? s.color : Colors.white),
            const SizedBox(width: 7),
            Text(voucherTypeLabels[widget.type]!,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                  color: sel ? s.color : Colors.white,
                )),
          ]),
        ),
      ),
    );
  }
}
