// lib/erp/accounting_plus/month_close_screen.dart
//
// ✅ شاشة «جاهزية إقفال الشهر»: اختر الشهر ← افحص ← صحّح ← ثبّت الإدخالات.
// الفحوص في [MonthCloseReadiness] (قراءة فقط)، والتثبيت بـ PeriodLock.setLockDate
// الموجودة، بعد التأكيد ولمن له صلاحية «تثبيت الإدخالات».

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../accounting/screens/acc_ui.dart' show requirePermission;
import '../../models/app_user.dart';
import '../../screens/day_close_screen.dart';
import '../../widgets/settings_kit.dart';
import '../control/bank_rec_screen.dart';
import '../control/control_screens.dart' show CashCountsScreen;
import '../erp_common.dart' show PeriodLock;
import 'month_close_readiness.dart';

/// شرح كل فحص بلغة بسيطة: ما هو، ولماذا يهم، وماذا تفعل.
class _Help {
  const _Help(this.what, this.fix);
  final String what;
  final String fix;
}

const _help = <String, _Help>{
  'القيود محدّثة': _Help(
    'كل فاتورة وسند ودفعة يُنشئ تلقائياً «قيداً» في الدفتر المحاسبي. هذا الفحص يتأكد أن لكل مستند قيده.',
    'افتح المستند المذكور وصحّحه (غالباً حقل ناقص)، ثم أعد الفحص.',
  ),
  'توازن القيود': _Help(
    'في كل قيد: المبلغ الداخل (مدين) يساوي المبلغ الخارج (دائن). قيد غير متوازن يعني خطأ في الأرقام.',
    'افتح «القيود اليومية» وابحث برقم القيد المذكور وصحّحه.',
  ),
  'أرصدة العملاء': _Help(
    'دين كل عميل في سجل الديون يجب أن يساوي مجموع معاملاته (فواتير، تسديدات، إضافات).',
    'افتح العميل المذكور وراجع معاملاته. البرنامج لا يغيّر أي دين تلقائياً.',
  ),
  'أرصدة الموردين': _Help(
    'رصيد كل مورد يجب أن يساوي مجموع دفتره (مشتريات ودفعات) لكل عملة.',
    'افتح المورد المذكور وراجع دفتره.',
  ),
  'فواتير معلّقة': _Help(
    'فواتير بتاريخ هذا الشهر لم تُحفظ نهائياً — لا تدخل في الأرباح ولا في الديون.',
    'افتحها من «الفواتير المعلّقة»: احفظها أو احذفها.',
  ),
  'مواد برصيد سالب': _Help(
    'مواد بِيع منها أكثر مما دخل المخزن — فتكلفة البيع والربح لها غير دقيقين.',
    'أدخل فاتورة الشراء الناقصة، أو صحّح الكمية من الجرد.',
  ),
  'عدّ الدرج': _Help(
    'في نهاية يوم البيع تعدّ النقود الموجودة فعلاً في الدرج (الصندوق) وتقارنها بما يقوله البرنامج، '
        'فيظهر أي عجز أو زيادة باسم المحاسب. يُسجَّل من شاشة «إقفال اليوم»، وسجلّه في «سجل عدّ الدرج».',
    'اضغط على أي يوم في القائمة لفتح «إقفال اليوم» على ذلك التاريخ وتسجيل العدّ. '
        'إن لم تكن تستعمل هذه الميزة فلا مشكلة — هي اختيارية.',
  ),
  'مطابقة البنك': _Help(
    'تقارن رصيد حسابك البنكي في البرنامج مع كشف الحساب الذي يعطيك إياه البنك لآخر يوم في الشهر. '
        'أي فرق يعني حركة نُسيت (عمولة، حوالة) أو سُجّلت خطأ.',
    'افتح «مطابقة البنك» ← مطابقة جديدة ← أدخل رصيد كشف البنك لآخر يوم في الشهر ← ضع علامة على الحركات الموجودة في الكشف. '
        'إن لم تكن تستعمل حساباً بنكياً فعلياً فلا مشكلة — هي اختيارية.',
  ),
};

class MonthCloseScreen extends StatefulWidget {
  const MonthCloseScreen({super.key});

  @override
  State<MonthCloseScreen> createState() => _MonthCloseScreenState();
}

class _MonthCloseScreenState extends State<MonthCloseScreen> {
  late DateTime _month = () {
    final n = DateTime.now();
    return DateTime(n.year, n.month - 1, 1); // الشهر السابق
  }();
  List<ReadinessCheck>? _checks;
  String? _step;
  bool _busy = false;
  DateTime? _lock;

  DateTime get _next => DateTime(_month.year, _month.month + 1, 1);
  String _label(DateTime m) => 'الشهر ${m.month}/${m.year}';
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
          title: 'اختر الشهر',
          subtitle: 'الشهر ${_month.month} من سنة ${_month.year}',
          icon: Icons.calendar_month_rounded,
          child: Padding(padding: const EdgeInsets.only(top: 10), child: _monthPicker()),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: SetPrimaryButton(
            label: _busy ? (_step ?? 'جارٍ الفحص...') : 'ابدأ فحص الشهر ${_month.month}/${_month.year}',
            icon: Icons.play_arrow_rounded,
            busy: _busy,
            onPressed: _busy ? null : _run,
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

  /// سنة بأسهم + 12 مربعاً مرقّماً. الأشهر المستقبلية معطّلة، والمثبّتة عليها قفل.
  Widget _monthPicker() {
    final now = DateTime.now();
    final year = _month.year;
    void pick(DateTime m) => setState(() {
          _month = m;
          _checks = null;
        });
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton(
          tooltip: 'السنة السابقة',
          onPressed: _busy ? null : () => pick(DateTime(year - 1, _month.month, 1)),
          icon: const Icon(Icons.chevron_right_rounded),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
          decoration: BoxDecoration(color: kSetNavy.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12)),
          child: Text('$year', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: kSetNavy)),
        ),
        IconButton(
          tooltip: 'السنة التالية',
          onPressed: _busy || year >= now.year
              ? null
              : () {
                  final m = DateTime(year + 1, _month.month, 1);
                  pick(m.isAfter(DateTime(now.year, now.month, 1)) ? DateTime(now.year, now.month, 1) : m);
                },
          icon: const Icon(Icons.chevron_left_rounded),
        ),
      ]),
      const SizedBox(height: 8),
      LayoutBuilder(builder: (context, c) {
        final perRow = c.maxWidth >= 560 ? 6 : 4;
        const gap = 8.0;
        final w = (c.maxWidth - gap * (perRow - 1)) / perRow;
        return Wrap(spacing: gap, runSpacing: gap, children: [
          for (var m = 1; m <= 12; m++) _monthCell(DateTime(year, m, 1), w, now, pick),
        ]);
      }),
      const SizedBox(height: 8),
      const Text('🔒 = شهر مثبّت (لا تُعدَّل مستنداته)', style: TextStyle(fontSize: 11.5, color: kSetMuted)),
    ]);
  }

  Widget _monthCell(DateTime m, double width, DateTime now, void Function(DateTime) pick) {
    final future = m.isAfter(DateTime(now.year, now.month, 1));
    final selected = m.year == _month.year && m.month == _month.month;
    final locked = _lock != null && !_lock!.isBefore(DateTime(m.year, m.month + 1, 1));
    final current = m.year == now.year && m.month == now.month;
    return SizedBox(
      width: width,
      height: 52,
      child: Material(
        color: selected ? kSetNavy : (future ? const Color(0xFFF1F5F9) : Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: selected ? kSetNavy : (current ? kSetBlue : kSetBorder), width: current && !selected ? 1.6 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: future || _busy ? null : () => pick(m),
          child: Stack(children: [
            Center(
              child: Text('${m.month}',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: selected ? Colors.white : (future ? const Color(0xFFCBD5E1) : kSetText),
                  )),
            ),
            if (locked)
              PositionedDirectional(
                top: 5,
                end: 6,
                child: Icon(Icons.lock_rounded, size: 13, color: selected ? Colors.white70 : kSetGreen),
              ),
          ]),
        ),
      ),
    );
  }

  /// ما يفتح لكل فحص (null = لا شاشة مباشرة).
  VoidCallback? _actionFor(ReadinessCheck c) => switch (c.title) {
        'عدّ الدرج' => () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CashCountsScreen())),
        'مطابقة البنك' => () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BankRecListScreen())),
        _ => null,
      };

  String? _actionLabel(ReadinessCheck c) => switch (c.title) {
        'عدّ الدرج' => 'سجل عدّ الدرج',
        'مطابقة البنك' => 'فتح مطابقة البنك',
        _ => null,
      };

  Widget _checkTile(ReadinessCheck c) {
    final (IconData icon, Color color, String badge) = switch (c.level) {
      CheckLevel.ok => (Icons.check_circle_rounded, kSetGreen, 'سليم'),
      CheckLevel.warn => (Icons.error_outline_rounded, kSetOrange, 'ملاحظة'),
      CheckLevel.fail => (Icons.cancel_rounded, kSetRed, 'خطأ'),
      CheckLevel.na => (Icons.remove_circle_outline_rounded, kSetMuted, 'لا ينطبق'),
    };
    final help = _help[c.title];
    final action = _actionFor(c);
    final isCashDays = c.title == 'عدّ الدرج' && c.level == CheckLevel.warn;
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
            initiallyExpanded: c.level == CheckLevel.fail || c.level == CheckLevel.warn,
            leading: Icon(icon, color: color),
            title: Row(children: [
              Expanded(child: Text(c.title, style: const TextStyle(fontWeight: FontWeight.w800, color: kSetText))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                child: Text(badge, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: color)),
              ),
            ]),
            subtitle: Text(c.detail, style: TextStyle(fontSize: 12.5, color: c.level == CheckLevel.ok ? kSetMuted : color)),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (help != null) ...[
                _explain(Icons.help_outline_rounded, 'ما هذا؟', help.what, kSetBlue),
                if (c.level == CheckLevel.warn || c.level == CheckLevel.fail || c.level == CheckLevel.na) ...[
                  const SizedBox(height: 8),
                  _explain(Icons.build_circle_outlined, 'ماذا أفعل؟', help.fix, color == kSetMuted ? kSetNavy : color),
                ],
              ],
              if (c.items.isNotEmpty) ...[
                const SizedBox(height: 10),
                if (isCashDays)
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final d in c.items)
                      ActionChip(
                        avatar: const Icon(Icons.point_of_sale_rounded, size: 16),
                        label: Text(d.replaceAll('-', '/')),
                        tooltip: 'إقفال اليوم ${d.replaceAll('-', '/')}',
                        onPressed: () {
                          final day = DateTime.tryParse(d);
                          Navigator.push(context, MaterialPageRoute(builder: (_) => DayCloseScreen(initialDate: day)));
                        },
                      ),
                  ])
                else
                  for (final i in c.items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text('• $i', style: const TextStyle(fontSize: 12.5, color: kSetText, height: 1.6)),
                    ),
              ],
              if (action != null) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: OutlinedButton.icon(
                    onPressed: action,
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: Text(_actionLabel(c) ?? 'فتح'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _explain(IconData icon, String title, String text, Color color) => Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(TextSpan(children: [
              TextSpan(text: '$title  ', style: TextStyle(fontWeight: FontWeight.w800, color: color)),
              TextSpan(text: text, style: const TextStyle(color: kSetText)),
            ]), style: const TextStyle(fontSize: 12.8, height: 1.6)),
          ),
        ]),
      );
}
