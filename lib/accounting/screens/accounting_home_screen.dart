// lib/accounting/screens/accounting_home_screen.dart
//
// 🏛️ مركز المحاسبة: مؤشرات سريعة في الرأس، إجراءات سريعة للسندات اليومية،
// ثم مدخل كل الشاشات المحاسبية في مجموعات + حالة الترحيل وسلامة الدفتر.

import 'package:flutter/material.dart';

import '../../erp/accounting_plus/currency_voucher_screens.dart';
import '../../erp/accounting_plus/period_screens.dart';
import '../../erp/erp_common.dart' show HubSection, HubTile;
import '../../erp/erp_ui.dart';
import '../../models/app_user.dart';
import '../accounting_reports.dart';
import '../posting_engine.dart';
import '../vouchers_service.dart';
import 'acc_ui.dart';
import 'account_statement_screen.dart';
import 'accounting_settings_screen.dart';
import 'cash_boxes_screen.dart';
import 'chart_of_accounts_screen.dart';
import 'journal_screen.dart';
import 'vouchers_screen.dart';

class AccountingHomeScreen extends StatefulWidget {
  const AccountingHomeScreen({super.key});

  /// 🧭 أزرار المركز — مصدر واحد للشاشة نفسها وللوحة الجانبية
  static List<HubSection> menu(BuildContext context, void Function(Widget) go) => [
      HubSection('العمل اليومي', [
        HubTile('السندات', Icons.description_rounded, AccColors.orange,
            () => go(const VouchersScreen()), permission: AppPermissions.accounting,
            subtitle: 'كل السندات: بحث، طباعة، حذف'),
        HubTile('سند قيد مركّب', Icons.call_split_rounded, AccColors.navy,
            () => go(const CompoundVouchersScreen()), permission: AppPermissions.accountingPost,
            subtitle: 'عدة حسابات وعملات'),
        HubTile('قوالب السندات', Icons.bookmarks_rounded, AccColors.blue,
            () => go(const VoucherTemplatesScreen()), permission: AppPermissions.accountingPost,
            subtitle: 'سندات متكررة بنقرة'),
        HubTile('الصناديق والبنوك', Icons.account_balance_wallet_rounded, AccColors.green,
            () => go(const CashBoxesScreen()), permission: AppPermissions.accounting,
            subtitle: 'الأرصدة وكشف الحركة'),
      ]),
      HubSection('الدفاتر', [
        HubTile('القيود اليومية', Icons.menu_book_rounded, AccColors.blue,
            () => go(const JournalScreen()), permission: AppPermissions.accounting,
            subtitle: 'تُولَّد تلقائياً + قيد يدوي'),
        HubTile('شجرة الحسابات', Icons.account_tree_rounded, AccColors.purple,
            () => go(const ChartOfAccountsScreen()), permission: AppPermissions.accounting,
            subtitle: 'الحسابات الرئيسية والفرعية'),
        HubTile('كشف حساب', Icons.list_alt_rounded, AccColors.navy,
            () => go(const AccountStatementScreen()), permission: AppPermissions.accounting,
            subtitle: 'أي حساب في الشجرة'),
        HubTile('الحسابات النوعية', Icons.workspaces_rounded, AccColors.cyan,
            () => go(const AccountGroupsScreen()), permission: AppPermissions.accounting),
      ]),
      HubSection('العملات والإقفال', [
        HubTile('العملات وأسعار الصرف', Icons.currency_exchange_rounded, AccColors.green,
            () => go(const CurrenciesScreen()), permission: AppPermissions.currencies,
            subtitle: 'المكان الوحيد لسعر الدولار'),
        HubTile('إعادة تقييم العملة', Icons.swap_horiz_rounded, AccColors.orange,
            () => go(const FxRevaluationScreen()), permission: AppPermissions.periodClose,
            subtitle: 'ذمم الموردين بالدولار'),
        HubTile('تثبيت وإقفال السنة', Icons.lock_clock_rounded, AccColors.purple,
            () => go(const PeriodCloseScreen()), permission: AppPermissions.periodClose,
            subtitle: 'منع التعديل على فترة سابقة'),
      ]),
      HubSection('أدوات', [
        HubTile('الملاحظات', Icons.sticky_note_2_rounded, ErpColors.gold, () => go(const NotesScreen())),
        HubTile('الحاسبة', Icons.calculate_rounded, AccColors.muted, () => showCalculator(context)),
        HubTile('إعدادات المحاسبة', Icons.tune_rounded, AccColors.muted,
            () => go(const AccountingSettingsScreen()), permission: AppPermissions.accountingPost,
            subtitle: 'مطابقة المخزون، فحص الدفتر'),
      ]),
      ];

  @override
  State<AccountingHomeScreen> createState() => _AccountingHomeScreenState();
}

class _AccountingHomeScreenState extends State<AccountingHomeScreen> {
  bool _posting = false;
  String? _status;
  List<String> _problems = const [];
  bool _checked = false;

  double? _cash;
  double? _expToday;
  double? _expMonth;

  @override
  void initState() {
    super.initState();
    _post(silent: true);
  }

  Future<void> _post({bool silent = false}) async {
    if (!canRunPosting) {
      setState(() => _status = 'هذا الجهاز طرفية — السيرفر يرحّل القيود تلقائياً');
      await _check();
      await _loadStats();
      return;
    }
    setState(() {
      _posting = true;
      _status = 'جارٍ الترحيل…';
    });
    try {
      final s = await PostingEngine().syncAll(progress: (m) {
        if (mounted) setState(() => _status = 'جارٍ ترحيل $m');
      });
      if (!mounted) return;
      setState(() => _status = 'آخر ترحيل: ${TimeOfDay.now().format(context)} — $s');
      if (s.errors.isNotEmpty && !silent) {
        showDialog<void>(
          context: context,
          builder: (ctx) => ErpDialog(
            title: 'مستندات لم تُرحَّل',
            subtitle: '${s.errors.length} مستند — صحّح المستند نفسه ثم رحّل من جديد',
            icon: Icons.error_outline_rounded,
            color: AccColors.red,
            width: 560,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final e in s.errors)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('• $e', style: const TextStyle(height: 1.5)),
                  ),
              ],
            ),
            actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('حسناً'))],
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _status = 'فشل الترحيل: $e');
    } finally {
      if (mounted) setState(() => _posting = false);
    }
    await _check();
    await _loadStats();
  }

  Future<void> _check() async {
    try {
      final p = await AccountingReports().integrityCheck();
      if (mounted) {
        setState(() {
          _problems = p;
          _checked = true;
        });
      }
    } catch (_) {}
  }

  /// مؤشرات الرأس: مجموع أرصدة الصناديق + سندات المصروف اليوم وهذا الشهر.
  Future<void> _loadStats() async {
    try {
      final svc = VouchersService();
      final bal = await svc.cashBoxBalances();
      final now = DateTime.now();
      final month = await svc.list(from: DateTime(now.year, now.month, 1), to: now, type: VoucherType.expense);
      final today = DateTime(now.year, now.month, now.day);
      double m = 0, t = 0;
      for (final v in month) {
        final a = (v['amount'] as num).toDouble();
        m += a;
        if (!DateTime.parse(v['voucher_date'] as String).isBefore(today)) t += a;
      }
      if (!mounted) return;
      setState(() {
        _cash = bal.values.fold<double>(0, (s, x) => s + x);
        _expMonth = m;
        _expToday = t;
      });
    } catch (_) {}
  }

  Future<void> _open(Widget screen, {String? permission}) async {
    if (permission != null && !requirePermission(context, permission)) return;
    await Navigator.push(context, accRoute<void>(screen));
    if (mounted) _loadStats();
  }

  /// يفتح نموذج السند مباشرة؛ الرجوع منه يعود إلى هنا (لا إلى قائمة السندات).
  Future<void> _newVoucher([VoucherType? type]) async {
    if (!requirePermission(context, AppPermissions.accountingPost)) return;
    final t = type ?? await showVoucherTypePicker(context);
    if (t == null || !mounted) return;
    final saved = await Navigator.push<bool>(context, accRoute<bool>(VoucherFormScreen(type: t)));
    if (!mounted) return;
    if (saved == true) showOk(context, 'حُفظ ${voucherTypeLabels[t]}');
    _loadStats();
  }

  String _m(double? v) => v == null ? '…' : fmtMoney(v);

  Widget _headerStats() {
    final ok = _problems.isEmpty;
    return Wrap(spacing: 10, runSpacing: 8, children: [
      HeaderStat(
        label: 'رصيد الصناديق',
        value: _m(_cash),
        icon: Icons.account_balance_wallet_rounded,
        accent: const Color(0xFF7DD3FC),
        tooltip: 'مجموع أرصدة الصناديق والبنوك في الدفتر',
        onTap: () => _open(const CashBoxesScreen(), permission: AppPermissions.accounting),
      ),
      HeaderStat(
        label: 'مصاريف اليوم',
        value: _m(_expToday),
        icon: Icons.receipt_long_rounded,
        accent: const Color(0xFFFCA5A5),
        tooltip: 'مجموع سندات المصروف لهذا اليوم',
        onTap: () => _open(const VouchersScreen(), permission: AppPermissions.accounting),
      ),
      HeaderStat(
        label: 'مصاريف هذا الشهر',
        value: _m(_expMonth),
        icon: Icons.calendar_view_month_rounded,
        accent: const Color(0xFFFDBA74),
        tooltip: 'مجموع سندات المصروف من أول الشهر',
        onTap: () => _open(const VouchersScreen(), permission: AppPermissions.accounting),
      ),
      HeaderStat(
        label: 'سلامة الدفتر',
        value: !_checked ? '…' : (ok ? 'سليم' : '${_problems.length} تنبيه'),
        icon: ok ? Icons.verified_rounded : Icons.warning_amber_rounded,
        accent: ok ? const Color(0xFF86EFAC) : const Color(0xFFFCD34D),
        tooltip: 'ميزان المراجعة متوازن وذمم العملاء = سجل الديون',
        onTap: () => _open(const AccountingSettingsScreen(), permission: AppPermissions.accountingPost),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final quick = <_QuickAction>[
      const _QuickAction(VoucherType.expense, 'F7'),
      const _QuickAction(VoucherType.receipt),
      const _QuickAction(VoucherType.payment),
      const _QuickAction(VoucherType.transfer),
    ];
    // تسلسل ظهور البطاقات: الإجراءات السريعة أولاً ثم المجموعات
    var n = quick.length + 1;
    const secIcons = [Icons.today_rounded, Icons.menu_book_rounded, Icons.currency_exchange_rounded, Icons.handyman_rounded];
    final menu = AccountingHomeScreen.menu(context, (w) => _open(w));
    final sections = <(String, IconData, List<_Tile>)>[
      for (var i = 0; i < menu.length; i++)
        (menu[i].title, secIcons[i % secIcons.length], [
          for (final t in menu[i].tiles)
            _Tile(t.title, t.icon, t.color, () {
              if (t.permission != null && !requirePermission(context, t.permission!)) return;
              t.onTap();
            }, subtitle: t.subtitle),
        ]),
    ];

    return ErpPage(
      title: 'المحاسبة',
      subtitle: _status ?? 'الدفتر • السندات • الصناديق • العملات والإقفال',
      icon: Icons.account_balance_rounded,
      actions: [
        IconButton(
          tooltip: canRunPosting ? 'ترحيل الآن' : 'تحديث',
          icon: _posting
              ? const SizedBox(
                  width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.sync_rounded),
          onPressed: _posting ? null : () => _post(),
        ),
      ],
      headerExtra: Align(alignment: AlignmentDirectional.centerStart, child: _headerStats()),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              if (_problems.isNotEmpty)
                FadeSlideIn(
                  child: _ProblemsCard(
                    problems: _problems,
                    onCheck: () => _open(const AccountingSettingsScreen(), permission: AppPermissions.accountingPost),
                  ),
                ),
              const _SectionHeader('إجراءات سريعة', Icons.bolt_rounded),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: LayoutBuilder(builder: (context, c) {
                  final cols = c.maxWidth >= 1000 ? 5 : (c.maxWidth >= 760 ? 3 : (c.maxWidth >= 420 ? 2 : 1));
                  const gap = 12.0;
                  final w = (c.maxWidth - gap * (cols - 1)) / cols;
                  return Wrap(spacing: gap, runSpacing: gap, children: [
                    for (var i = 0; i < quick.length; i++)
                      SizedBox(
                        width: w,
                        child: FadeSlideIn(
                          index: i,
                          child: _QuickCard(action: quick[i], onTap: () => _newVoucher(quick[i].type)),
                        ),
                      ),
                    SizedBox(
                      width: w,
                      child: FadeSlideIn(
                        index: quick.length,
                        child: _QuickCard(action: const _QuickAction(null), onTap: () => _newVoucher()),
                      ),
                    ),
                  ]);
                }),
              ),
              for (final (title, icon, tiles) in sections) ...[
                _SectionHeader(title, icon),
                GridView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 340,
                    mainAxisExtent: 82,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                  ),
                  children: [
                    for (final t in tiles) FadeSlideIn(index: n++, child: _HubCard(tile: t)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════ عناصر المركز ═══════════════════════════

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, this.icon);
  final String title;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 0),
        child: Row(children: [
          Icon(icon, size: 18, color: AccColors.navy),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, color: AccColors.text)),
          const SizedBox(width: 12),
          const Expanded(child: Divider(color: Color(0xFFE3E9F1))),
        ]),
      );
}

class _QuickAction {
  const _QuickAction(this.type, [this.shortcut]);

  /// null = «سند جديد…» (نافذة اختيار النوع).
  final VoucherType? type;
  final String? shortcut;
}

class _QuickCard extends StatefulWidget {
  const _QuickCard({required this.action, required this.onTap});
  final _QuickAction action;
  final VoidCallback onTap;
  @override
  State<_QuickCard> createState() => _QuickCardState();
}

class _QuickCardState extends State<_QuickCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.action.type;
    final s = t == null ? null : voucherStyle(t);
    final color = s?.color ?? AccColors.navy;
    final icon = s?.icon ?? Icons.post_add_rounded;
    final title = t == null ? 'سند جديد…' : voucherTypeLabels[t]!;
    final sub = t == null ? 'إيراد، رصيد افتتاحي، وكل الأنواع' : s!.hint;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        height: 128,
        transform: Matrix4.translationValues(0, _hover ? -3 : 0, 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            colors: [Color.alphaBlend(color.withValues(alpha: _hover ? 0.14 : 0.09), Colors.white), Colors.white],
            begin: AlignmentDirectional.topStart,
            end: AlignmentDirectional.bottomEnd,
          ),
          border: Border.all(color: _hover ? color.withValues(alpha: 0.55) : color.withValues(alpha: 0.22)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: _hover ? 0.22 : 0.08),
              blurRadius: _hover ? 22 : 10,
              offset: Offset(0, _hover ? 10 : 4),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: Icon(icon, color: Colors.white, size: 24),
                  ),
                  const Spacer(),
                  if (widget.action.shortcut != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: color.withValues(alpha: 0.30)),
                      ),
                      child: Text(widget.action.shortcut!,
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: color)),
                    ),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 160),
                    opacity: _hover ? 1 : 0,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(start: 6),
                      child: Icon(Icons.arrow_forward_rounded, size: 20, color: color),
                    ),
                  ),
                ]),
                const Spacer(),
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: AccColors.text)),
                const SizedBox(height: 2),
                Text(sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AccColors.muted)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _Tile {
  const _Tile(this.title, this.icon, this.color, this.onTap, {this.subtitle});
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String? subtitle;
}

class _HubCard extends StatefulWidget {
  const _HubCard({required this.tile});
  final _Tile tile;
  @override
  State<_HubCard> createState() => _HubCardState();
}

class _HubCardState extends State<_HubCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tile;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _hover ? -2 : 0, 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: _hover
              ? [BoxShadow(color: t.color.withValues(alpha: 0.18), blurRadius: 18, offset: const Offset(0, 8))]
              : const [BoxShadow(color: Color(0x080F172A), blurRadius: 6, offset: Offset(0, 2))],
        ),
        child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: _hover ? t.color.withValues(alpha: 0.5) : const Color(0xFFE3E9F1)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: t.onTap,
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 10, 12),
              child: Row(children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 170),
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _hover ? t.color : t.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(t.icon, color: _hover ? Colors.white : t.color, size: 24),
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
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, color: AccColors.muted)),
                        ),
                    ],
                  ),
                ),
                AnimatedSlide(
                  duration: const Duration(milliseconds: 170),
                  offset: Offset(_hover ? -0.15 : 0, 0),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 170),
                    opacity: _hover ? 1 : 0.35,
                    child: Icon(Icons.chevron_left_rounded, color: _hover ? t.color : AccColors.muted),
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

class _ProblemsCard extends StatelessWidget {
  const _ProblemsCard({required this.problems, required this.onCheck});
  final List<String> problems;
  final VoidCallback onCheck;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7ED),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFED7AA)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: AccColors.orange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(11)),
            child: const Icon(Icons.warning_amber_rounded, color: AccColors.orange),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('تنبيهات الدفتر',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: AccColors.orange)),
              const SizedBox(height: 4),
              for (final p in problems)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('• $p', style: const TextStyle(fontSize: 13, height: 1.5, color: AccColors.text)),
                ),
            ]),
          ),
          TextButton.icon(
            onPressed: onCheck,
            icon: const Icon(Icons.fact_check_rounded, size: 18),
            label: const Text('افحص'),
          ),
        ]),
      );
}
