// lib/erp/control/fixed_assets_screens.dart
//
// 🏢 شاشات الأصول الثابتة: السجل، إضافة أصل، الاستبعاد، وإهلاك شهر بمعاينة قبل الترحيل.

import 'package:flutter/material.dart';

import '../../accounting/screens/acc_ui.dart' show fmtMoney, fmtDate, showError, showOk;
import '../erp_common.dart';
import '../erp_kit.dart' show erpDialogActions;
import '../erp_ui.dart';
import '../pickers.dart' show CashBoxDropdown;
import 'depreciation_math.dart';
import 'fixed_assets_service.dart';

class FixedAssetsScreen extends StatefulWidget {
  const FixedAssetsScreen({super.key});
  @override
  State<FixedAssetsScreen> createState() => _FixedAssetsScreenState();
}

class _FixedAssetsScreenState extends State<FixedAssetsScreen> {
  List<FixedAsset> _assets = const [];
  List<DepreciationRun> _runs = const [];
  double _ledgerAcc = 0;
  bool _loading = true;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final a = await FixedAssetsService.list();
      final r = await FixedAssetsService.runs();
      final l = await FixedAssetsService.ledgerAccumulated();
      if (!mounted) return;
      setState(() {
        _assets = a;
        _runs = r;
        _ledgerAcc = l;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showError(context, e);
    }
  }

  Future<void> _add() async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const FixedAssetEditor()));
    if (ok == true) _load();
  }

  Future<void> _runMonth() async {
    final now = DateTime.now();
    final prev = DateTime(now.year, now.month - 1, 1);
    final c = TextEditingController(text: periodOf(prev));
    final period = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إهلاك شهر'),
        content: TextField(
          controller: c,
          decoration: const InputDecoration(labelText: 'الشهر (YYYY-MM)', hintText: '2026-10'),
          textDirection: TextDirection.ltr,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('معاينة')),
        ],
      ),
    );
    c.dispose();
    if (period == null || period.isEmpty || !mounted) return;
    try {
      final preview = await FixedAssetsService.preview(period);
      if (!mounted) return;
      if (preview.isEmpty) {
        showError(context, 'لا يوجد ما يُهلك في $period');
        return;
      }
      final total = preview.fold<double>(0, (s, p) => s + p.$2);
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('إهلاك $period — ${fmtMoney(total)}'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final p in preview)
                  ListTile(
                    dense: true,
                    title: Text(p.$1.name),
                    trailing: Text(fmtMoney(p.$2), textDirection: TextDirection.ltr),
                    subtitle: Text('المجمّع ${fmtMoney(p.$1.accumulated)} من ${fmtMoney(p.$1.cost - p.$1.salvage)}'),
                  ),
                const SizedBox(height: 8),
                Text(
                  'قيد واحد بتاريخ ${fmtDate(periodEnd(period))}: مدين مصروف الإهلاك / دائن مجمع الإهلاك بـ ${fmtMoney(total)}.',
                  style: const TextStyle(fontSize: 12.5, color: ErpColors.muted),
                ),
              ]),
            ),
          ),
          actions: erpDialogActions(ctx, ok: 'ترحيل الإهلاك'),
        ),
      );
      if (go != true) return;
      await FixedAssetsService.runPeriod(period);
      if (mounted) showOk(context, 'رُحّل إهلاك $period');
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _assetMenu(FixedAsset a, String action) async {
    try {
      switch (action) {
        case 'rename':
          final n = await askText(context, 'اسم الأصل', label: 'الاسم', initial: a.name);
          if (n == null || n.trim().isEmpty) return;
          await FixedAssetsService.rename(a.id, name: n, category: a.category, notes: a.notes);
        case 'delete':
          final ok = await confirmDialog(context, 'حذف الأصل',
              'يُحذف «${a.name}» وقيد شرائه (إن وُجد) في الترحيل التالي. لا يُحذف أصل عليه إهلاك.',
              ok: 'حذف', color: ErpColors.red);
          if (!ok) return;
          await FixedAssetsService.delete(a.id);
        case 'dispose':
          if (!mounted) return;
          await _dispose(a);
        case 'undispose':
          final ok = await confirmDialog(context, 'إلغاء الاستبعاد', 'يعود «${a.name}» قائماً ويُحذف قيد استبعاده.');
          if (!ok) return;
          await FixedAssetsService.undispose(a.id);
        case 'schedule':
          if (!mounted) return;
          await _schedule(a);
          return;
      }
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _dispose(FixedAsset a) async {
    DateTime on = DateTime.now();
    int? box;
    final amt = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('استبعاد/بيع «${a.name}»'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('الكلفة ${fmtMoney(a.cost)} • المجمّع ${fmtMoney(a.accumulated)} • الدفترية ${fmtMoney(a.book)}'),
              const SizedBox(height: 10),
              DateButton(label: 'تاريخ الاستبعاد', value: on, onChanged: (d) => setD(() => on = d)),
              const SizedBox(height: 10),
              MoneyField(controller: amt, label: 'المبلغ المقبوض (0 = تالف/هدية)'),
              const SizedBox(height: 10),
              CashBoxDropdown(value: box, width: 380, label: 'الصندوق المقبوض فيه', onChanged: (b) => setD(() => box = b?.id)),
              const SizedBox(height: 8),
              const Text('أشهر الإهلاك قبل شهر الاستبعاد يجب أن تُرحَّل أولاً ليكون الربح/الخسارة صحيحاً.',
                  style: TextStyle(fontSize: 12, color: ErpColors.muted)),
            ]),
          ),
          actions: erpDialogActions(ctx, ok: 'استبعاد'),
        ),
      ),
    );
    final proceeds = parseMoney(amt.text) ?? 0;
    amt.dispose();
    if (ok != true) return;
    await FixedAssetsService.dispose(a.id, on: on, proceeds: proceeds, boxId: proceeds > 0 ? box : null);
    if (mounted) {
      final g = disposalGain(cost: a.cost, accumulated: a.accumulated, proceeds: proceeds);
      showOk(context, g >= 0 ? 'استُبعد بربح ${fmtMoney(g)}' : 'استُبعد بخسارة ${fmtMoney(-g)}');
    }
  }

  Future<void> _schedule(FixedAsset a) async {
    final rows = <List<String>>[];
    var acc = 0.0;
    var p = periodStart(a.depStart);
    for (var i = 0; i < a.lifeMonths && i < 600; i++) {
      final period = periodOf(p);
      final amt = depreciationFor(
          period: period,
          startPeriod: a.depStart,
          cost: a.cost,
          salvage: a.salvage,
          lifeMonths: a.lifeMonths,
          accumulated: acc);
      if (amt <= 0) break;
      acc += amt;
      rows.add([period, fmtMoney(amt), fmtMoney(acc), fmtMoney(a.cost - acc)]);
      p = DateTime(p.year, p.month + 1, 1);
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('جدول إهلاك «${a.name}»'),
        content: SizedBox(
          width: 520,
          height: 460,
          child: SimpleTable(
            headers: const ['الشهر', 'القسط', 'المجمّع', 'الدفترية'],
            numericColumns: const {1, 2, 3},
            rows: rows,
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = _assets.where((a) => !a.disposed).toList();
    final cost = active.fold<double>(0, (s, a) => s + a.cost);
    final acc = active.fold<double>(0, (s, a) => s + a.accumulated);
    final registerAcc = _assets.fold<double>(0, (s, a) => s + (a.disposed ? 0 : a.accumulated));
    return ErpPage(
      title: 'الأصول الثابتة والإهلاك',
      subtitle: 'سجل الأصول، قيمتها الدفترية، وإهلاكها الشهري',
      icon: Icons.domain_rounded,
      actions: [
        IconButton(tooltip: 'إهلاك شهر', icon: const Icon(Icons.trending_down_rounded), onPressed: _runMonth),
        IconButton(tooltip: 'تحديث', icon: const Icon(Icons.refresh_rounded), onPressed: _load),
      ],
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        backgroundColor: ErpColors.navy,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('أصل جديد'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.fromLTRB(0, 0, 0, 90), children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(spacing: 10, runSpacing: 10, children: [
                  StatCard(label: 'كلفة الأصول القائمة', value: fmtMoney(cost), icon: Icons.domain_rounded),
                  StatCard(label: 'مجمع الإهلاك', value: fmtMoney(acc), icon: Icons.trending_down_rounded, color: ErpColors.orange),
                  StatCard(label: 'القيمة الدفترية', value: fmtMoney(cost - acc), icon: Icons.account_balance_wallet_rounded, color: ErpColors.green),
                  StatCard(
                    label: 'مجمع الإهلاك في الدفتر',
                    value: fmtMoney(_ledgerAcc),
                    icon: Icons.menu_book_rounded,
                    color: (registerAcc - _ledgerAcc).abs() < 1 ? ErpColors.purple : ErpColors.red,
                    hint: (registerAcc - _ledgerAcc).abs() < 1
                        ? 'مطابق للسجل'
                        : 'يختلف عن السجل — شغّل الترحيل من المحاسبة (المستبعد يُقفل مجمّعه)',
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: SegmentedButton<int>(
                  segments: [
                    ButtonSegment(value: 0, label: Text('الأصول (${_assets.length})'), icon: const Icon(Icons.domain_rounded)),
                    ButtonSegment(value: 1, label: Text('الإهلاك (${_runs.length})'), icon: const Icon(Icons.history_rounded)),
                  ],
                  selected: {_tab},
                  onSelectionChanged: (s) => setState(() => _tab = s.first),
                ),
              ),
              if (_tab == 0)
                if (_assets.isEmpty)
                  const EmptyState('لا أصول بعد — أضف المعدات والأثاث والسيارات', icon: Icons.domain_rounded)
                else
                  for (final a in _assets)
                    Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12), side: const BorderSide(color: ErpColors.border)),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: (a.disposed ? ErpColors.muted : ErpColors.gold).withValues(alpha: 0.14),
                          child: Text('${a.no}', style: TextStyle(color: a.disposed ? ErpColors.muted : ErpColors.gold, fontSize: 12)),
                        ),
                        title: Text('${a.name}${a.category == null ? '' : ' — ${a.category}'}',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, decoration: a.disposed ? TextDecoration.lineThrough : null)),
                        subtitle: Text([
                          'الكلفة ${fmtMoney(a.cost)}',
                          'المجمّع ${fmtMoney(a.accumulated)}',
                          'الدفترية ${fmtMoney(a.book)}',
                          '${fmtMoney(a.monthly)} شهرياً لـ ${a.lifeMonths} شهراً من ${a.depStart}',
                          AssetFunding.label(a.funding),
                          if (a.disposed) 'مستبعد ${a.disposedOn == null ? '' : fmtDate(a.disposedOn!)} بـ ${fmtMoney(a.disposalAmount ?? 0)}',
                          if (!a.disposed && a.fullyDepreciated) 'مُهلك بالكامل',
                        ].join(' • ')),
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) => _assetMenu(a, v),
                          itemBuilder: (_) => [
                            const PopupMenuItem(value: 'schedule', child: Text('جدول الإهلاك')),
                            const PopupMenuItem(value: 'rename', child: Text('تعديل الاسم')),
                            if (!a.disposed) const PopupMenuItem(value: 'dispose', child: Text('استبعاد / بيع')),
                            if (a.disposed) const PopupMenuItem(value: 'undispose', child: Text('إلغاء الاستبعاد')),
                            if (!a.disposed) const PopupMenuItem(value: 'delete', child: Text('حذف (إدخال خاطئ)')),
                          ],
                        ),
                      ),
                    ),
              if (_tab == 1)
                if (_runs.isEmpty)
                  const EmptyState('لا إهلاك مرحّل بعد — اضغط «إهلاك شهر» في الأعلى', icon: Icons.history_rounded)
                else
                  for (final r in _runs)
                    ListTile(
                      leading: Icon(r.status == 'posted' ? Icons.check_circle_rounded : Icons.block_rounded,
                          color: r.status == 'posted' ? ErpColors.green : ErpColors.muted),
                      title: Text('إهلاك ${r.period} — ${fmtMoney(r.total)}',
                          style: TextStyle(decoration: r.status == 'posted' ? null : TextDecoration.lineThrough)),
                      subtitle: Text('${r.createdBy ?? ''} • ${fmtDate(r.createdAt)}${r.status == 'posted' ? '' : ' • ملغى'}'),
                      trailing: r.status != 'posted'
                          ? null
                          : IconButton(
                              tooltip: 'إلغاء',
                              icon: const Icon(Icons.block_rounded, color: ErpColors.red),
                              onPressed: () async {
                                final ok = await confirmDialog(context, 'إلغاء إهلاك ${r.period}',
                                    'يُحذف قيده في الترحيل التالي ويعود المجمّع كما كان.',
                                    ok: 'إلغاء الإهلاك', color: ErpColors.red);
                                if (!ok) return;
                                try {
                                  await FixedAssetsService.voidRun(r.id);
                                  _load();
                                } catch (e) {
                                  if (context.mounted) showError(context, e);
                                }
                              },
                            ),
                    ),
            ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// إضافة أصل
// ════════════════════════════════════════════════════════════════════

class FixedAssetEditor extends StatefulWidget {
  const FixedAssetEditor({super.key});
  @override
  State<FixedAssetEditor> createState() => _FixedAssetEditorState();
}

class _FixedAssetEditorState extends State<FixedAssetEditor> {
  final _name = TextEditingController();
  final _category = TextEditingController();
  final _cost = TextEditingController();
  final _salvage = TextEditingController();
  final _years = TextEditingController(text: '5');
  final _notes = TextEditingController();
  DateTime _acquired = DateTime.now();
  String _funding = AssetFunding.already;
  int? _box;
  int? _account;
  List<Map<String, Object?>> _accounts = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    FixedAssetsService.assetAccounts().then((a) {
      if (!mounted) return;
      setState(() {
        _accounts = a;
        _account = a.isEmpty ? null : a.first['id'] as int;
      });
    });
  }

  @override
  void dispose() {
    for (final c in [_name, _category, _cost, _salvage, _years, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final years = parseMoney(_years.text) ?? 0;
    setState(() => _busy = true);
    try {
      await FixedAssetsService.create(
        name: _name.text,
        category: _category.text,
        acquiredOn: _acquired,
        cost: parseMoney(_cost.text) ?? 0,
        salvage: parseMoney(_salvage.text) ?? 0,
        lifeMonths: (years * 12).round(),
        assetAccountId: _account,
        funding: _funding,
        fundingBoxId: _box,
        notes: _notes.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cost = parseMoney(_cost.text) ?? 0;
    final salvage = parseMoney(_salvage.text) ?? 0;
    final months = ((parseMoney(_years.text) ?? 0) * 12).round();
    final monthly = monthlyDepreciation(cost: cost, salvage: salvage, lifeMonths: months);
    return ErpPage(
      title: 'أصل ثابت جديد',
      icon: Icons.domain_add_rounded,
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        ErpSection(
          title: 'بيانات الأصل',
          icon: Icons.info_outline_rounded,
          child: FieldGrid(children: [
            TextBox(controller: _name, label: 'الاسم (مولدة، سيارة، رفوف...)', width: 320),
            TextBox(controller: _category, label: 'الفئة (اختياري)', width: 200),
            DateButton(label: 'تاريخ الشراء', value: _acquired, onChanged: (d) => setState(() => _acquired = d)),
            MoneyField(controller: _cost, label: 'الكلفة', width: 200, onChanged: (_) => setState(() {})),
            MoneyField(controller: _salvage, label: 'قيمة الخردة في النهاية', width: 200, onChanged: (_) => setState(() {})),
            MoneyField(controller: _years, label: 'العمر بالسنوات', width: 160, onChanged: (_) => setState(() {})),
            if (_accounts.isNotEmpty)
              DropBox<int>(
                label: 'حساب الأصل',
                value: _account,
                width: 260,
                items: [
                  for (final a in _accounts)
                    DropdownMenuItem(value: a['id'] as int, child: Text('${a['code']} - ${a['name']}')),
                ],
                onChanged: (v) => setState(() => _account = v),
              ),
            TextBox(controller: _notes, label: 'ملاحظات', width: 320),
          ]),
        ),
        ErpSection(
          title: 'كيف دُفع ثمنه؟',
          icon: Icons.payments_rounded,
          child: RadioGroup<String>(
            groupValue: _funding,
            onChanged: (v) => setState(() => _funding = v ?? _funding),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final f in [AssetFunding.already, AssetFunding.box, AssetFunding.opening])
              RadioListTile<String>(
                value: f,
                title: Text(AssetFunding.label(f)),
                subtitle: Text(switch (f) {
                  AssetFunding.already => 'سجّلت شراءه بسند صرف على حساب الأصل — لا قيد جديد (منعاً للازدواج)',
                  AssetFunding.box => 'قيد: مدين حساب الأصل / دائن الصندوق',
                  _ => 'أصل يملكه المحل قبل البرنامج — قيد: مدين حساب الأصل / دائن الأرصدة الافتتاحية',
                }),
              ),
            if (_funding == AssetFunding.box)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: CashBoxDropdown(value: _box, width: 320, onChanged: (b) => setState(() => _box = b?.id)),
              ),
          ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            monthly > 0
                ? 'الإهلاك: ${fmtMoney(monthly)} شهرياً لمدة $months شهراً، يبدأ من ${periodOf(_acquired)}. لا يُرحَّل إلا بضغطة «إهلاك شهر».'
                : 'اكتب الكلفة والعمر لترى القسط الشهري.',
            style: const TextStyle(color: ErpColors.muted),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: PrimaryButton(label: 'حفظ الأصل', icon: Icons.save_rounded, busy: _busy, onPressed: _save),
          ),
        ),
      ]),
    );
  }
}
