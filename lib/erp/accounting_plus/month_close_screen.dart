// lib/erp/accounting_plus/month_close_screen.dart
//
// ✅ شاشة «جاهزية إقفال الشهر»: اختر الشهر ← افحص ← صحّح ← ثبّت الإدخالات.
// الفحوص في [MonthCloseReadiness] (قراءة فقط)، والتثبيت بـ PeriodLock.setLockDate
// الموجودة، بعد التأكيد ولمن له صلاحية «تثبيت الإدخالات».

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../accounting/screens/acc_ui.dart' show requirePermission;
import '../../models/app_user.dart';
import '../../widgets/settings_kit.dart';
import '../erp_common.dart' show PeriodLock;
import 'month_close_readiness.dart';

class MonthCloseScreen extends StatefulWidget {
  const MonthCloseScreen({super.key});

  @override
  State<MonthCloseScreen> createState() => _MonthCloseScreenState();
}

class _MonthCloseScreenState extends State<MonthCloseScreen> {
  static const _months = [
    'كانون الثاني', 'شباط', 'آذار', 'نيسان', 'أيار', 'حزيران',
    'تموز', 'آب', 'أيلول', 'تشرين الأول', 'تشرين الثاني', 'كانون الأول',
  ];

  late DateTime _month = () {
    final n = DateTime.now();
    return DateTime(n.year, n.month - 1, 1); // الشهر السابق
  }();
  List<ReadinessCheck>? _checks;
  String? _step;
  bool _busy = false;
  DateTime? _lock;

  DateTime get _next => DateTime(_month.year, _month.month + 1, 1);
  String _label(DateTime m) => '${_months[m.month - 1]} ${m.year}';
  bool get _locked => _lock != null && !_lock!.isBefore(_next);

  @override
  void initState() {
    super.initState();
    _loadLock();
  }

  Future<void> _loadLock() async {
    final l = await PeriodLock.lockDate();
    if (mounted) setState(() => _lock = l);
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _checks = null;
    });
    try {
      final r = await MonthCloseReadiness.run(_month, progress: (s) {
        if (mounted) setState(() => _step = s);
      });
      if (mounted) setState(() => _checks = r);
    } catch (e) {
      if (mounted) setToast(context, 'تعذّر الفحص: $e', error: true);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _step = null;
        });
      }
    }
  }

  Future<void> _lockMonth() async {
    if (!requirePermission(context, AppPermissions.periodClose)) return;
    final checks = _checks ?? const <ReadinessCheck>[];
    final warns = checks.where((c) => c.level == CheckLevel.warn).toList();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('تثبيت الإدخالات حتى نهاية ${_label(_month)}؟'),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('لن يُسمح بإضافة أو تعديل أو حذف أي مستند بتاريخ قبل '
                '${DateFormat('yyyy/MM/dd').format(_next)} (فواتير، سندات، مستندات مخزنية...). '
                'يمكن إلغاء التثبيت لاحقاً من «تثبيت وإقفال السنة» لمن له الصلاحية.'),
            if (warns.isNotEmpty) ...[
              const SizedBox(height: 10),
              SetBanner('ملاحظات لم تُعالج:\n${warns.map((w) => '• ${w.title}: ${w.detail}').join('\n')}',
                  kind: SetBannerKind.warn),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تثبيت')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await PeriodLock.setLockDate(_next);
      await _loadLock();
      if (mounted) setToast(context, 'ثُبّتت الإدخالات حتى نهاية ${_label(_month)}');
    } catch (e) {
      if (mounted) setToast(context, 'تعذّر التثبيت: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final checks = _checks;
    final fails = checks?.where((c) => c.level == CheckLevel.fail).length ?? 0;
    final warns = checks?.where((c) => c.level == CheckLevel.warn).length ?? 0;
    final now = DateTime.now();
    final options = [for (var i = 0; i < 12; i++) DateTime(now.year, now.month - i, 1)];
    return SettingsScaffold(
      title: 'جاهزية إقفال الشهر',
      icon: Icons.fact_check_rounded,
      subtitle: 'فحص قبل تثبيت الإدخالات — لا يغيّر أي رقم',
      maxWidth: 900,
      children: [
        SetHero(
          icon: Icons.fact_check_rounded,
          color: kSetNavy,
          title: _label(_month),
          text: 'تُفحص القيود وتوازنها، وأرصدة العملاء والموردين مقابل دفاترهم، والفواتير المعلّقة، '
              'والمواد السالبة، وعدّ الدرج، ومطابقة البنك. ثم تثبّت الإدخالات حتى نهاية الشهر.',
          status: Wrap(spacing: 8, runSpacing: 6, children: [
            SetStatusPill(
              _lock == null ? 'لا تثبيت حالياً' : 'مثبّت حتى ${DateFormat('yyyy/MM/dd').format(_lock!)}',
              ok: _locked,
            ),
            if (checks != null)
              SetStatusPill(
                fails > 0 ? '$fails خطأ يمنع الإقفال' : (warns > 0 ? '$warns ملاحظة' : 'جاهز للإقفال'),
                ok: fails == 0 && warns == 0,
              ),
          ]),
        ),
        SetCard(
          title: 'الشهر',
          icon: Icons.calendar_month_rounded,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
              DropdownButton<DateTime>(
                value: options.firstWhere((m) => m.year == _month.year && m.month == _month.month, orElse: () => options[1]),
                items: [for (final m in options) DropdownMenuItem(value: m, child: Text(_label(m)))],
                onChanged: _busy
                    ? null
                    : (m) => setState(() {
                          _month = m ?? _month;
                          _checks = null;
                        }),
              ),
              FilledButton.icon(
                onPressed: _busy ? null : _run,
                icon: _busy
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.play_arrow_rounded),
                label: Text(_busy ? (_step ?? 'جارٍ الفحص...') : 'ابدأ الفحص'),
              ),
            ]),
          ),
        ),
        if (checks != null) ...[
          for (final c in checks) _checkTile(c),
          const SizedBox(height: 6),
          if (_locked)
            const SetBanner('هذا الشهر مثبّت بالفعل.', kind: SetBannerKind.ok)
          else if (fails > 0)
            const SetBanner('صحّح الأخطاء (باللون الأحمر) ثم أعد الفحص — لا يُثبَّت شهر فيه خطأ حسابي.',
                kind: SetBannerKind.error)
          else
            SetPrimaryButton(
              label: 'تثبيت الإدخالات حتى نهاية ${_label(_month)}',
              icon: Icons.lock_rounded,
              color: kSetGreen,
              onPressed: _lockMonth,
            ),
        ],
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _checkTile(ReadinessCheck c) {
    final (IconData icon, Color color) = switch (c.level) {
      CheckLevel.ok => (Icons.check_circle_rounded, kSetGreen),
      CheckLevel.warn => (Icons.error_outline_rounded, kSetOrange),
      CheckLevel.fail => (Icons.cancel_rounded, kSetRed),
      CheckLevel.na => (Icons.remove_circle_outline_rounded, kSetMuted),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.level == CheckLevel.ok || c.level == CheckLevel.na ? kSetBorder : color.withValues(alpha: 0.4)),
      ),
      clipBehavior: Clip.antiAlias,
      // ListTile يرسم خلفيته وأثر الضغط على أقرب Material — بدونه تخفيها خلفية الصندوق (تحذير Flutter)
      child: Material(
        type: MaterialType.transparency,
        child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Icon(icon, color: color),
          title: Text(c.title, style: const TextStyle(fontWeight: FontWeight.w800, color: kSetText)),
          subtitle: Text(c.level == CheckLevel.na ? 'لا ينطبق — ${c.detail}' : c.detail,
              style: TextStyle(fontSize: 12.5, color: c.level == CheckLevel.ok ? kSetMuted : color)),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final i in c.items) Text('• $i', style: const TextStyle(fontSize: 12.5, color: kSetText, height: 1.6)),
          ],
        ),
      ),
      ),
    );
  }
}
