// lib/screens/report_search_screen.dart
//
// 🔎 «البحث في التقارير» — اكتب أي شيء فتظهر تقاريره:
//   • اسم مادة ← تقرير بضاعتها، اسم عميل ← تقاريره، موظف ← مبيعاته، مؤسس ← نقاطه (حساب المالك)،
//     مورد ← كشف حسابه، رقم فاتورة أو باركود ← الفاتورة أو المادة.
//   • كلام بالمعنى: «الربح»، «كم بعت»، «سند قبض»، «الضمان»، «أثر الدولار»، «مقارنة»، «مسحوبات»…
//     (المحرّك: services/report_search_engine.dart — مرادفات وتوحيد الكتابة وتسامح مع خطأ حرف).
//   • الفترة من الكلام نفسه: «2025»، «هذه السنة»، «الشهر الماضي»، «شباط 2024»، «أمس».
// 🔐 لا يظهر إلا ما يملك المستخدم صلاحيته. للقراءة فقط: يفتح التقارير الموجودة ولا يغيّر شيئاً.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../accounting/screens/acc_ui.dart' show accRoute;
import '../accounting/screens/balance_sheet_screen.dart';
import '../accounting/screens/income_statement_screen.dart';
import '../accounting/screens/trial_balance_screen.dart';
import '../accounting/vouchers_service.dart' show VoucherType;
import '../erp/control/control_screens.dart' show ControlHubScreen;
import '../erp/debts/debt_reports_screen.dart' show AgingScreen, CollectionReportScreen;
import '../erp/debts/receipt_screen.dart' show ReceiptsListScreen;
import '../erp/hr/hr_screen.dart';
import '../erp/inventory/inventory_reports_screen.dart';
import '../erp/purchases/supplier_statement_screen.dart';
import '../erp/reports/finance_reports.dart';
import '../erp/reports/vouchers_summary_report.dart';
import '../erp/warranty/warranty_screens.dart' show WarrantyHubScreen;
import '../models/app_user.dart';
import '../owner/founders_screen.dart' show FoundersScreen, FounderDetailsScreen;
import '../owner/owner_access.dart';
import '../radar/radar_screen.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../services/report_search_engine.dart';
import '../widgets/report_kit.dart';
import 'custom_range_report_screen.dart';
import 'day_close_screen.dart';
import 'employee_sales_screen.dart';
import 'invoice_details_screen.dart';
import 'people_reports_screen.dart';
import 'person_details_screen.dart';
import 'product_report_details_screen.dart';
import 'product_reports_screen.dart';
import 'returns_report_screen.dart';

// ═══════════════════════════ التقارير التي يصل إليها البحث ═══════════════════════════

class _Target {
  const _Target(this.title, this.subtitle, this.icon, this.color, this.page,
      {this.perm, this.allowed, this.usesPeriod = false, this.route});
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Widget Function(ReportPeriod? p)? page;
  final String? perm;
  final bool Function()? allowed;

  /// يقبل الفترة المكتوبة في البحث (سنة، شهر…).
  final bool usesPeriod;

  /// شاشة مسمّاة بدل صفحة (لوحة المؤشرات).
  final String? route;

  bool get ok => (perm == null || AuthService().hasPermission(perm!)) && (allowed?.call() ?? true);
}

bool _salesOk() => CustomRangeReportScreen.allowed();
bool _profitOk() => _salesOk() && AuthService().hasPermission(AppPermissions.viewCostProfit);

Widget _range(ReportPeriod? p, [String? focus]) => CustomRangeReportScreen(from: p?.from, to: p?.to, focus: focus);

final Map<String, _Target> _targets = {
  'profit': _Target('الأرباح', 'صافي الربح والهامش للفترة، مع ما دخل الصندوق فعلاً', Icons.trending_up_rounded, kSetGreen,
      (p) => _range(p), allowed: _profitOk, usesPeriod: true),
  'sales': _Target('المبيعات', 'الفواتير والمبيعات والأرباح لأي فترة', Icons.insights_rounded, const Color(0xFF4F46E5),
      (p) => _range(p), allowed: _salesOk, usesPeriod: true),
  'income_statement': _Target('قائمة الدخل', 'الإيرادات − الكلفة − المصاريف = صافي الربح', Icons.stacked_line_chart_rounded,
      kSetGreen, (p) => const IncomeStatementScreen(), perm: AppPermissions.viewCostProfit),
  'balance_sheet': _Target('الميزانية العمومية', 'الأصول والخصوم وحقوق الملكية', Icons.account_balance_rounded, kSetNavy,
      (p) => const BalanceSheetScreen(), perm: AppPermissions.viewCostProfit),
  'trial_balance': _Target('ميزان المراجعة', 'رصيد كل حساب محاسبي: مدين ودائن', Icons.balance_rounded,
      const Color(0xFF0891B2), (p) => const TrialBalanceScreen(), perm: AppPermissions.accounting),
  'sales_detail': _Target('تقرير المبيعات التفصيلي', 'كل فاتورة بسطر: المدفوع والمتبقي والربح، مع التصدير',
      Icons.receipt_long_rounded, const Color(0xFF0E7C61), (p) => const SalesDetailReportScreen(),
      perm: AppPermissions.viewCostProfit),
  'expenses': _Target('تحليل المصاريف', 'أين ذهبت الأموال؟ كهرباء، أجور، إيجار…', Icons.pie_chart_rounded, kSetRed,
      (p) => const ExpenseAnalysisScreen(), perm: AppPermissions.accounting),
  'vouchers': _Target('ملخص السندات', 'كل سند مصروف وصرف وقبض وإيراد بحسابه', Icons.summarize_rounded, kSetNavy,
      (p) => VouchersSummaryScreen(from: p?.from, to: p?.to), perm: AppPermissions.accounting, usesPeriod: true),
  'vouchers_receipt': _Target('سندات القبض', 'كل سند قبض في الفترة: من أي حساب ولأي صندوق', Icons.move_to_inbox_rounded,
      kSetBlue, (p) => VouchersSummaryScreen(from: p?.from, to: p?.to, onlyType: VoucherType.receipt),
      perm: AppPermissions.accounting, usesPeriod: true),
  'vouchers_payment': _Target('سندات الصرف', 'ما صُرف من الصناديق لأي حساب', Icons.outbox_rounded, kSetOrange,
      (p) => VouchersSummaryScreen(from: p?.from, to: p?.to, onlyType: VoucherType.payment),
      perm: AppPermissions.accounting, usesPeriod: true),
  'vouchers_expense': _Target('سندات المصروف', 'المصاريف التي تنقص الربح', Icons.receipt_long_rounded, kSetRed,
      (p) => VouchersSummaryScreen(from: p?.from, to: p?.to, onlyType: VoucherType.expense),
      perm: AppPermissions.accounting, usesPeriod: true),
  'vouchers_income': _Target('سندات الإيراد', 'إيرادات من خارج المبيعات', Icons.savings_rounded, kSetGreen,
      (p) => VouchersSummaryScreen(from: p?.from, to: p?.to, onlyType: VoucherType.income),
      perm: AppPermissions.accounting, usesPeriod: true),
  'drawings': _Target('مسحوبات المالك', 'ما سحبه المالك من الصناديق — لا ينقص الربح', Icons.person_rounded, kSetNavy,
      (p) => VouchersSummaryScreen(from: p?.from, to: p?.to, drawingsOnly: true),
      perm: AppPermissions.accounting, usesPeriod: true),
  'receipts_list': _Target('وصولات القبض من العملاء', 'كل تسديد من عميل، وإعادة طباعة الوصل', Icons.history_edu_rounded,
      const Color(0xFF047857), (p) => const ReceiptsListScreen(), perm: AppPermissions.collection),
  'cash': _Target('حركة الصندوق', 'الوارد والصادر والرصيد', Icons.account_balance_wallet_outlined, kSetGreen,
      (p) => const CashMovementScreen(), perm: AppPermissions.accounting),
  'returns': _Target('مرتجعات الفواتير', 'كل مستند مرتجع: من أي فاتورة، لمن، نقداً أو من الدين', Icons.assignment_return_rounded,
      kSetRed, (p) => ReturnsReportScreen(from: p?.from, to: p?.to), perm: AppPermissions.repReturns, usesPeriod: true),
  'warranty_returns': _Target('مرتجعات الضمان', 'المواد التي رجعت بسبب الضمان: كم مرة وكم رُدّ', Icons.verified_user_rounded,
      kRepPurple, (p) => ReturnsReportScreen(from: p?.from ?? DateTime(DateTime.now().year, 1, 1), to: p?.to, warrantyOnly: true),
      perm: AppPermissions.repReturns, usesPeriod: true),
  'warranty_hub': _Target('الضمان والصيانة', 'القطع المعطوبة عند الصيانة حتى تعود لأصحابها', Icons.build_circle_rounded,
      const Color(0xFF7C3AED), (p) => const WarrantyHubScreen(), perm: AppPermissions.salesDocs),
  'usd': _Target('أثر سعر الدولار', 'كم أثّر تغيّر سعر الصرف على كلفتك وربحك', Icons.currency_exchange_rounded,
      const Color(0xFF0E7490), (p) => _range(p, 'usd'), allowed: _salesOk, usesPeriod: true),
  'compare': _Target('المقارنة', 'الفترة مقابل السابقة: الشهر الماضي، نفس الشهر من السنة الماضية…', Icons.compare_arrows_rounded,
      const Color(0xFF4F46E5), (p) => _range(p, 'compare'), allowed: _salesOk, usesPeriod: true),
  'trend': _Target('تحليل التوجهات', 'منحنى المبيعات بالساعة واليوم والشهر — متى تبيع أكثر', Icons.show_chart_rounded,
      const Color(0xFF2563EB), (p) => _range(p, 'trend'), allowed: _salesOk, usesPeriod: true),
  'extras': _Target('ماذا حدث في الفترة؟', 'ملخص بالكلام + المال الفعلي وتغيّر الديون', Icons.lightbulb_rounded, kRepAmber,
      (p) => _range(p, 'extras'), allowed: _salesOk, usesPeriod: true),
  'manual': _Target('خارج الفواتير', 'ديون أُضيفت يدوياً وتسديدات لا ترتبط بفاتورة', Icons.edit_note_rounded, kRepPurple,
      (p) => _range(p, 'manual'), allowed: _salesOk, usesPeriod: true),
  'channels': _Target('المبيعات حسب نوع البيع', 'نقدي، آجل، توصيل… ومرتجعاتها', Icons.call_split_rounded, kSetBlue,
      (p) => _range(p, 'channels'), allowed: _salesOk, usesPeriod: true),
  'top_products': _Target('الأكثر مبيعاً', 'أعلى المواد والعملاء في الفترة', Icons.emoji_events_rounded, kRepAmber,
      (p) => _range(p, 'top'), allowed: _salesOk, usesPeriod: true),
  'top_customers': _Target('أكبر العملاء', 'أعلى العملاء والمواد في الفترة', Icons.workspace_premium_rounded, kSetBlue,
      (p) => _range(p, 'top'), allowed: _salesOk, usesPeriod: true),
  'day_close': _Target('إقفال اليوم', 'ما يجب أن يكون في الدرج ومطابقته مع المعدود', Icons.point_of_sale_rounded,
      const Color(0xFF0F766E), (p) => const DayCloseScreen(), perm: AppPermissions.repDaily),
  'products': _Target('تقارير البضاعة', 'كل مادة أو قسم: الكمية والمبيعات والكلفة والربح', Icons.inventory_2_rounded, kSetGreen,
      (p) => const ProductReportsScreen(), perm: AppPermissions.repProducts),
  'people': _Target('تقارير الأشخاص', 'كل عميل: السنوات ← الأشهر ← الفواتير', Icons.people_alt_rounded, kSetBlue,
      (p) => const PeopleReportsScreen(), perm: AppPermissions.repPeople),
  'employees': _Target('مبيعات الموظفين', 'من باع كم: الفواتير والنقد والدين والمرتجعات', Icons.badge_rounded,
      const Color(0xFF0F766E), (p) => EmployeeSalesScreen(from: p?.from, to: p?.to),
      perm: AppPermissions.repEmployees, usesPeriod: true),
  'hr': _Target('الموارد البشرية', 'الحضور، السلف، الرواتب', Icons.groups_2_rounded, kSetNavy, (p) => const HrScreen(),
      perm: AppPermissions.manageUsers),
  'founders': _Target('تقارير المؤسسين', 'النقاط والترتيب والمبيعات والجوائز', Icons.engineering_rounded,
      const Color(0xFFD97706), (p) => const FoundersScreen(), perm: AppPermissions.repFounders, allowed: () => OwnerAccess.enabled),
  'radar': _Target('رادار التاجر', 'بيع تحت الكلفة، هبوط الربح، السيولة القادمة، ماذا تشتري', Icons.radar_rounded,
      const Color(0xFF0E7490), (p) => const RadarScreen(), perm: AppPermissions.viewCostProfit),
  'control': _Target('الرقابة والأدوات المالية', 'عجز الدرج، فواتير أُنقصت بعد طباعتها، نقطة التعادل', Icons.shield_rounded,
      kSetRed, (p) => const ControlHubScreen(), perm: AppPermissions.viewCostProfit),
  'dashboard': _Target('لوحة المؤشرات', 'كل المؤشرات المهمة في صفحة واحدة', Icons.dashboard_rounded, const Color(0xFF1B6CA8),
      null, perm: AppPermissions.dashboard, route: '/dashboard'),
  'inventory': _Target('قيمة المخزون', 'كم تساوي بضاعتك الآن بالكلفة وبسعر البيع', Icons.account_balance_wallet_rounded,
      kSetGreen, (p) => const InventoryReportsScreen(initial: 'valuation'), perm: AppPermissions.inventoryReports),
  'stagnant': _Target('المواد الراكدة', 'بضاعة لم تتحرك منذ مدة', Icons.hourglass_bottom_rounded, kSetOrange,
      (p) => const InventoryReportsScreen(initial: 'stagnant'), perm: AppPermissions.inventoryReports),
  'limits': _Target('النواقص وحدود الطلب', 'ما نفد وما نزل تحت الحد الأدنى', Icons.warning_amber_rounded, kSetRed,
      (p) => const InventoryReportsScreen(initial: 'limits'), perm: AppPermissions.inventoryReports),
  'expiring': _Target('الصلاحية', 'مواد قاربت أو تجاوزت تاريخ الانتهاء', Icons.event_busy_rounded, kRepAmber,
      (p) => const InventoryReportsScreen(initial: 'expiring'), perm: AppPermissions.inventoryReports),
  'debts': _Target('أرصدة الديون', 'العملاء والموردون: كم لك وكم عليك', Icons.account_balance_wallet_rounded, kSetNavy,
      (p) => const PartyBalancesScreen(), perm: AppPermissions.debtReports),
  'aging': _Target('أعمار الديون', 'منذ متى لم يسدد كل عميل', Icons.hourglass_bottom_rounded, kSetRed,
      (p) => const AgingScreen(), perm: AppPermissions.debtReports),
  'collection': _Target('نسب التحصيل', 'كم حصّلت مما عليهم', Icons.percent_rounded, kRepPurple,
      (p) => const CollectionReportScreen(), perm: AppPermissions.debtReports),
};

/// عند كتابة فترة فقط («2025»، «الشهر الماضي») — أهم تقارير تلك الفترة.
const _periodDefaults = ['sales', 'profit', 'returns', 'vouchers', 'compare', 'usd'];

// ═══════════════════════════ فهرس الأسماء (يُحمَّل مرة) ═══════════════════════════

enum _Kind { product, customer, supplier, employee, founder }

class _Ent {
  _Ent(this.kind, this.id, this.name, this.sub, {this.key, this.phone}) : norm = ArabicNorm.normalize(name);
  final _Kind kind;
  final int? id;
  final String name;
  final String sub;

  /// اسم الدخول للموظف.
  final String? key;
  final String? phone;
  final String norm;
}

class _Index {
  _Index(this.byKind, this.barcodes);
  final Map<_Kind, List<_Ent>> byKind;
  final Map<String, int> barcodes; // باركود ← رقم المادة

  static _Index? _cache;
  static DateTime? _at;

  static Future<_Index> load() async {
    final c = _cache;
    if (c != null && _at != null && DateTime.now().difference(_at!).inMinutes < 3) return c;
    final db = await DatabaseService().database;
    Future<List<Map<String, Object?>>> q(String sql, [String? fallback]) async {
      try {
        return await db.rawQuery(sql);
      } catch (_) {
        if (fallback == null) return const [];
        try {
          return await db.rawQuery(fallback);
        } catch (_) {
          return const [];
        }
      }
    }

    String s(Object? v) => (v ?? '').toString().trim();
    final auth = AuthService();
    final map = <_Kind, List<_Ent>>{for (final k in _Kind.values) k: <_Ent>[]};
    final barcodes = <String, int>{};

    if (auth.hasPermission(AppPermissions.repProducts)) {
      for (final r in await q('SELECT id, name, barcode FROM products WHERE is_deleted IS NULL OR is_deleted = 0',
          'SELECT id, name, barcode FROM products')) {
        if (s(r['name']).isEmpty) continue;
        map[_Kind.product]!.add(_Ent(_Kind.product, r['id'] as int?, s(r['name']), s(r['barcode'])));
        if (s(r['barcode']).isNotEmpty && r['id'] is int) barcodes[s(r['barcode'])] = r['id'] as int;
      }
      for (final r in await q('SELECT barcode, product_id FROM product_barcodes')) {
        if (s(r['barcode']).isNotEmpty && r['product_id'] is int) barcodes[s(r['barcode'])] = r['product_id'] as int;
      }
    }
    if (auth.hasPermission(AppPermissions.repPeople)) {
      for (final r in await q('SELECT id, name, phone FROM customers WHERE is_deleted IS NULL OR is_deleted = 0',
          'SELECT id, name, phone FROM customers')) {
        if (s(r['name']).isEmpty) continue;
        map[_Kind.customer]!.add(_Ent(_Kind.customer, r['id'] as int?, s(r['name']), s(r['phone']), phone: s(r['phone'])));
      }
    }
    if (auth.hasPermission(AppPermissions.suppliers)) {
      for (final r in await q('SELECT id, name, phone FROM suppliers')) {
        if (s(r['name']).isEmpty || r['id'] is! int) continue;
        map[_Kind.supplier]!.add(_Ent(_Kind.supplier, r['id'] as int, s(r['name']), s(r['phone']), phone: s(r['phone'])));
      }
    }
    if (auth.hasPermission(AppPermissions.repEmployees) || auth.hasPermission(AppPermissions.manageUsers)) {
      final hr = <String, Map<String, Object?>>{}; // اسم الدخول ← موظف الموارد البشرية
      final hrRows = await q('SELECT id, name, job, username FROM hr_employees');
      for (final r in hrRows) {
        if (s(r['username']).isNotEmpty) hr[s(r['username']).toLowerCase()] = r;
      }
      final seen = <String>{};
      for (final r in await q('SELECT username, display_name, role FROM users', 'SELECT username, role FROM users')) {
        final u = s(r['username']);
        if (u.isEmpty) continue;
        final h = hr[u.toLowerCase()];
        final shown = s(h?['name']).isNotEmpty ? s(h?['name']) : (s(r['display_name']).isNotEmpty ? s(r['display_name']) : u);
        map[_Kind.employee]!.add(_Ent(_Kind.employee, h?['id'] as int?, shown,
            [if (s(h?['job']).isNotEmpty) s(h?['job']), 'اسم الدخول: $u'].join(' • '), key: u));
        seen.add(u.toLowerCase());
        // يُبحث باسم الدخول أيضاً
        if (shown != u) map[_Kind.employee]!.add(_Ent(_Kind.employee, h?['id'] as int?, u, 'اسم الدخول لـ $shown', key: u));
      }
      for (final r in hrRows) {
        if (s(r['name']).isEmpty || seen.contains(s(r['username']).toLowerCase())) continue;
        map[_Kind.employee]!.add(_Ent(_Kind.employee, r['id'] as int?, s(r['name']),
            [if (s(r['job']).isNotEmpty) s(r['job']), 'بلا حساب دخول — من الموارد البشرية'].join(' • ')));
      }
    }
    if (OwnerAccess.enabled && auth.hasPermission(AppPermissions.repFounders)) {
      for (final r in await q('SELECT id, name, phone FROM installers')) {
        if (s(r['name']).isEmpty) continue;
        map[_Kind.founder]!.add(_Ent(_Kind.founder, r['id'] as int?, s(r['name']), s(r['phone'])));
      }
    }
    _at = DateTime.now();
    return _cache = _Index(map, barcodes);
  }
}

// ═══════════════════════════ الشاشة ═══════════════════════════

class ReportSearchScreen extends StatefulWidget {
  const ReportSearchScreen({super.key, this.initialQuery});
  final String? initialQuery;

  /// فتح البحث من أي شاشة (مع انتقال ناعم).
  static Future<void> open(BuildContext context, {String? query}) =>
      Navigator.push(context, accRoute(ReportSearchScreen(initialQuery: query)));

  @override
  State<ReportSearchScreen> createState() => _ReportSearchScreenState();
}

class _Hits {
  const _Hits({this.query, this.intents = const [], this.ents = const {}, this.invoices = const []});
  final ReportQuery? query;
  final List<String> intents;
  final Map<_Kind, List<_Ent>> ents;
  final List<Map<String, Object?>> invoices;
  bool get isEmpty => intents.isEmpty && invoices.isEmpty && ents.values.every((l) => l.isEmpty);
}

class _ReportSearchScreenState extends State<ReportSearchScreen> {
  static const _recentKey = 'report_search_recent';
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  _Index? _index;
  _Hits _hits = const _Hits();
  List<String> _recent = const [];
  final Set<_Kind> _expanded = {};
  int _token = 0;

  @override
  void initState() {
    super.initState();
    _ctrl.text = widget.initialQuery ?? '';
    _loadRecent();
    _Index.load().then((i) {
      if (!mounted) return;
      _index = i;
      _run();
    }).catchError((_) {
      if (mounted) setState(() => _index = _Index({for (final k in _Kind.values) k: <_Ent>[]}, const {}));
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    try {
      final p = await SharedPreferences.getInstance();
      final r = p.getStringList(_recentKey) ?? const [];
      if (mounted) setState(() => _recent = r);
    } catch (_) {}
  }

  Future<void> _remember() async {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    final list = [t, ..._recent.where((x) => x != t)].take(8).toList();
    _recent = list;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_recentKey, list);
    } catch (_) {}
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 160), _run);
    setState(() {}); // زر المسح
  }

  void _set(String text) {
    _ctrl.text = text;
    _ctrl.selection = TextSelection.collapsed(offset: text.length);
    _expanded.clear();
    _run();
  }

  // ───────────────────────── البحث ─────────────────────────

  void _run() {
    final text = _ctrl.text.trim();
    final idx = _index;
    if (text.isEmpty || idx == null) {
      setState(() => _hits = const _Hits());
      return;
    }
    final q = ReportQuery.parse(text);
    var intents = [
      for (final h in ReportCatalog.match(q, limit: 10))
        if (_targets[h.id]?.ok ?? false) h.id,
    ];
    if (q.words.isEmpty && q.period != null) {
      intents = [for (final id in _periodDefaults) if (_targets[id]!.ok) id];
    }
    // «الأكثر مبيعاً» و«أكبر العملاء» نفس البطاقة — لا تكرار
    if (intents.contains('top_products') && intents.contains('top_customers')) intents.remove('top_customers');

    // كلمات الاسم: بلا كلمات المعنى («ربح أحمد» ← أحمد)، وإن لم يبقَ شيء فكلها
    final nameWords = q.words.where((w) => !ReportCatalog.isConcept(w)).toList();
    final words = nameWords.isEmpty ? q.words : nameWords;
    final ents = <_Kind, List<_Ent>>{};
    for (final k in _Kind.values) {
      final scored = <(double, _Ent)>[];
      for (final e in idx.byKind[k]!) {
        var sc = words.isEmpty ? 0.0 : ReportCatalog.normalizedNameScore(words, e.norm);
        // رقم هاتف أو باركود
        for (final n in q.numbers) {
          if (n.length >= 5 && (e.phone ?? '').replaceAll(RegExp(r'\D'), '').contains(n)) sc = sc < 2.5 ? 2.5 : sc;
          if (k == _Kind.product && n.length >= 4 && e.sub == n) sc = 4;
        }
        if (sc > 0) scored.add((sc, e));
      }
      if (k == _Kind.product) {
        for (final n in q.numbers) {
          final id = idx.barcodes[n];
          if (id == null || scored.any((x) => x.$2.id == id)) continue;
          for (final e in idx.byKind[k]!) {
            if (e.id == id) scored.add((4.0, e));
          }
        }
      }
      scored.sort((a, b) => b.$1.compareTo(a.$1));
      // اسم الدخول والاسم المعروض للموظف نفسه ← مرة واحدة
      final keys = <String>{};
      ents[k] = [
        for (final x in scored)
          if (k != _Kind.employee || x.$2.key == null || keys.add(x.$2.key!)) x.$2,
      ].take(40).toList();
    }
    final t = ++_token;
    setState(() => _hits = _Hits(query: q, intents: intents, ents: ents));
    _findInvoices(q, t);
  }

  /// رقم فاتورة (أو سنة قد تكون رقم فاتورة).
  Future<void> _findInvoices(ReportQuery q, int t) async {
    if (!_salesOk()) return;
    final nums = [...q.numbers, if (q.period?.year != null && q.words.isEmpty) '${q.period!.year}'];
    if (nums.isEmpty) return;
    try {
      final db = await DatabaseService().database;
      final out = <Map<String, Object?>>[];
      for (final n in nums.take(3)) {
        final rows = await db.rawQuery('''
          SELECT id, invoice_number, invoice_date, customer_name, COALESCE(total_amount, 0) AS total
          FROM invoices
          WHERE (is_deleted IS NULL OR is_deleted = 0) AND (invoice_number = ? OR id = ?)
          ORDER BY id DESC LIMIT 5''', [n, int.tryParse(n) ?? -1]);
        for (final r in rows) {
          if (!out.any((x) => x['id'] == r['id'])) out.add(r);
        }
      }
      if (!mounted || t != _token || out.isEmpty) return;
      setState(() => _hits = _Hits(query: _hits.query, intents: _hits.intents, ents: _hits.ents, invoices: out));
    } catch (_) {}
  }

  // ───────────────────────── الفتح ─────────────────────────

  int? get _year {
    final p = _hits.query?.period;
    if (p == null) return null;
    return p.year ?? (p.from.year == p.to.year ? p.from.year : null);
  }

  Future<void> _push(Widget page) async {
    _remember();
    await Navigator.push(context, accRoute(page));
  }

  void _openTarget(String id) {
    final t = _targets[id]!;
    if (t.route != null) {
      _remember();
      Navigator.of(context).pushNamed(t.route!);
      return;
    }
    _push(t.page!(_hits.query?.period));
  }

  void _openEnt(_Ent e) {
    final p = _hits.query?.period;
    switch (e.kind) {
      case _Kind.product:
        _push(ProductReportDetailsScreen(productId: e.id, productName: e.name, initialYear: _year));
        break;
      case _Kind.customer:
        _push(PersonDetailsScreen.fromReport(customerId: e.id, name: e.name, phone: e.phone, initialYear: _year));
        break;
      case _Kind.supplier:
        _push(SupplierStatementScreen(supplierId: e.id!, supplierName: e.name));
        break;
      case _Kind.employee:
        if (e.key != null && AuthService().hasPermission(AppPermissions.repEmployees)) {
          final now = DateTime.now();
          _push(EmployeeSalesScreen(from: p?.from ?? DateTime(now.year, 1, 1), to: p?.to ?? now, focusUser: e.key));
        } else if (AuthService().hasPermission(AppPermissions.manageUsers)) {
          _push(const HrScreen());
        } else {
          setToast(context, 'لا صلاحية لتقارير الموظفين', error: true);
        }
        break;
      case _Kind.founder:
        _push(FounderDetailsScreen(founderName: e.name));
        break;
    }
  }

  void _openInvoice(Map<String, Object?> r) => _push(InvoiceDetailsScreen(invoiceId: r['id'] as int));

  /// Enter: أول نتيجة.
  void _openFirst() {
    final h = _hits;
    if (h.intents.isNotEmpty) return _openTarget(h.intents.first);
    for (final k in _Kind.values) {
      final l = h.ents[k] ?? const [];
      if (l.isNotEmpty) return _openEnt(l.first);
    }
    if (h.invoices.isNotEmpty) _openInvoice(h.invoices.first);
  }

  // ───────────────────────── الواجهة ─────────────────────────

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.maybePop(context)},
      child: Scaffold(
        backgroundColor: kSetBg,
        body: Column(children: [
          _header(),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              child: _index == null
                  ? const Center(key: ValueKey('loading'), child: CircularProgressIndicator())
                  : _ctrl.text.trim().isEmpty
                      ? _idle()
                      : _results(),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _header() {
    final period = _hits.query?.period;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0F3460), Color(0xFF4F46E5), Color(0xFF6D28D9)],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
        boxShadow: [BoxShadow(color: Color(0x332E1065), blurRadius: 24, offset: Offset(0, 8))],
      ),
      child: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 16, 18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  IconButton(
                    tooltip: 'رجوع',
                    onPressed: () => Navigator.maybePop(context),
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  ),
                  const SizedBox(width: 4),
                  const Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('البحث في التقارير',
                          style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900)),
                      SizedBox(height: 2),
                      Text('اكتب بكلامك: مادة، عميل، موظف، الربح، سند قبض، الضمان، أثر الدولار، 2025…',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Color(0xCCFFFFFF), fontSize: 12.5)),
                    ]),
                  ),
                ]),
                const SizedBox(height: 12),
                Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    child: TextField(
                      controller: _ctrl,
                      focusNode: _focus,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      onChanged: _onChanged,
                      onSubmitted: (_) => _openFirst(),
                      style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600, color: kSetText),
                      decoration: InputDecoration(
                        hintText: 'ماذا تريد أن ترى؟',
                        hintStyle: const TextStyle(color: kSetMuted, fontWeight: FontWeight.w500),
                        prefixIcon: const Icon(Icons.manage_search_rounded, color: kRepPurple, size: 26),
                        suffixIcon: _ctrl.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'مسح',
                                onPressed: () {
                                  _set('');
                                  _focus.requestFocus();
                                },
                                icon: const Icon(Icons.close_rounded, color: kSetMuted),
                              ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                      ),
                    ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  child: period == null
                      ? const SizedBox(width: double.infinity)
                      : Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(30),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                              ),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                const Icon(Icons.event_rounded, size: 16, color: Colors.white),
                                const SizedBox(width: 6),
                                Text('الفترة: ${period.label}',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5)),
                                Text('  ${repDate(period.from)} — ${repDate(period.to)}',
                                    style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 11.5)),
                              ]),
                            ),
                          ),
                        ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  // ── قبل الكتابة: اقتراحات وآخر عمليات البحث ──
  Widget _idle() {
    const ideas = <(String, IconData)>[
      ('الربح هذه السنة', Icons.trending_up_rounded),
      ('كم بعت الشهر الماضي', Icons.insights_rounded),
      ('سند قبض', Icons.move_to_inbox_rounded),
      ('مرتجعات الضمان', Icons.verified_user_rounded),
      ('أثر الدولار', Icons.currency_exchange_rounded),
      ('مقارنة', Icons.compare_arrows_rounded),
      ('مسحوبات المالك', Icons.person_rounded),
      ('المصاريف', Icons.pie_chart_rounded),
      ('المواد الراكدة', Icons.hourglass_bottom_rounded),
      ('أعمار الديون', Icons.hourglass_top_rounded),
    ];
    final visible = [
      for (final i in ideas)
        if (ReportCatalog.match(ReportQuery.parse(i.$1), limit: 1).any((h) => _targets[h.id]?.ok ?? false)) i,
    ];
    return ListView(
      key: const ValueKey('idle'),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      children: [
        _Constrain(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (_recent.isNotEmpty) ...[
              _sectionTitle('بحثت مؤخراً', Icons.history_rounded, kSetMuted),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final r in _recent)
                  InputChip(
                    label: Text(r),
                    avatar: const Icon(Icons.history_rounded, size: 16),
                    onPressed: () => _set(r),
                    onDeleted: () async {
                      setState(() => _recent = [..._recent]..remove(r));
                      try {
                        final p = await SharedPreferences.getInstance();
                        await p.setStringList(_recentKey, _recent);
                      } catch (_) {}
                    },
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: kSetBorder),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
              ]),
              const SizedBox(height: 22),
            ],
            _sectionTitle('جرّب', Icons.auto_awesome_rounded, kRepPurple),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final i in visible)
                ActionChip(
                  avatar: Icon(i.$2, size: 17, color: kRepPurple),
                  label: Text(i.$1, style: const TextStyle(fontWeight: FontWeight.w700)),
                  onPressed: () => _set(i.$1),
                  backgroundColor: Colors.white,
                  side: BorderSide(color: kRepPurple.withValues(alpha: 0.25)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
            ]),
            const SizedBox(height: 26),
            _tip(),
          ]),
        ),
      ],
    );
  }

  Widget _tip() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: kSetBorder),
        ),
        child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.tips_and_updates_rounded, color: kRepAmber, size: 20),
            SizedBox(width: 8),
            Text('كيف يفهمك البحث؟', style: TextStyle(fontWeight: FontWeight.w900, color: kSetText)),
          ]),
          SizedBox(height: 10),
          _TipLine('اسم مادة أو عميل أو موظف أو مورد', 'يفتح تقاريره مباشرة — ولو كتبت جزءاً من الاسم أو أخطأت بحرف'),
          _TipLine('كلام بالمعنى', '«الأرباح» و«كم ربحت» و«الفائدة» توصل إلى التقرير نفسه'),
          _TipLine('أضف الفترة', '«2025»، «هذه السنة»، «الشهر الماضي»، «شباط 2024»، «أمس»'),
          _TipLine('اجمعها', '«ربح أحمد 2024» ← تقرير أحمد على سنة 2024'),
          _TipLine('رقم', 'رقم فاتورة، باركود مادة، أو رقم هاتف عميل'),
        ]),
      );

  // ── النتائج ──
  Widget _results() {
    final h = _hits;
    final q = h.query;
    if (q == null) return const SizedBox.shrink(key: ValueKey('none'));
    if (h.isEmpty) return _empty(q);
    var i = 0; // لتتابع الظهور
    final children = <Widget>[];
    if (h.intents.isNotEmpty) {
      children.add(_sectionTitle('التقارير', Icons.insights_rounded, kRepPurple, count: h.intents.length));
      for (final id in h.intents) {
        final t = _targets[id]!;
        children.add(_Appear(
          index: i++,
          child: _ResultTile(
            icon: t.icon,
            color: t.color,
            title: t.title,
            subtitle: t.subtitle,
            badge: t.usesPeriod && q.period != null ? q.period!.label : null,
            onTap: () => _openTarget(id),
          ),
        ));
      }
    }
    if (h.invoices.isNotEmpty) {
      children.add(_sectionTitle('فواتير', Icons.receipt_long_rounded, kSetNavy, count: h.invoices.length));
      for (final r in h.invoices) {
        final date = DateTime.tryParse('${r['invoice_date']}');
        children.add(_Appear(
          index: i++,
          child: _ResultTile(
            icon: Icons.receipt_long_rounded,
            color: kSetNavy,
            title: 'فاتورة ${r['invoice_number'] ?? '#${r['id']}'} — ${r['customer_name'] ?? ''}',
            subtitle: [if (date != null) repDate(date), repMoney((r['total'] as num?) ?? 0)].join(' • '),
            onTap: () => _openInvoice(r),
          ),
        ));
      }
    }
    const meta = <_Kind, (String, IconData, Color, String)>{
      _Kind.product: ('مواد', Icons.inventory_2_rounded, kSetGreen, 'تقرير البضاعة'),
      _Kind.customer: ('عملاء', Icons.person_rounded, kSetBlue, 'تقارير العميل'),
      _Kind.employee: ('موظفون', Icons.badge_rounded, Color(0xFF0F766E), 'مبيعاته'),
      _Kind.founder: ('مؤسسون', Icons.engineering_rounded, Color(0xFFD97706), 'نقاطه ومبيعاته'),
      _Kind.supplier: ('موردون', Icons.local_shipping_rounded, kSetOrange, 'كشف الحساب'),
    };
    for (final k in meta.keys) {
      final list = h.ents[k] ?? const <_Ent>[];
      if (list.isEmpty) continue;
      final m = meta[k]!;
      final open = _expanded.contains(k);
      final shown = open ? list : list.take(5).toList();
      children.add(_sectionTitle(m.$1, m.$2, m.$3, count: list.length));
      for (final e in shown) {
        children.add(_Appear(
          index: i++,
          child: _ResultTile(
            letter: e.name.characters.first,
            color: m.$3,
            title: e.name,
            subtitle: e.sub.isEmpty ? m.$4 : e.sub,
            badge: _badgeFor(k, m.$4),
            onTap: () => _openEnt(e),
          ),
        ));
      }
      if (list.length > 5) {
        children.add(Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: () => setState(() => open ? _expanded.remove(k) : _expanded.add(k)),
            icon: Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded),
            label: Text(open ? 'أقل' : 'عرض ${list.length - 5} أكثر'),
          ),
        ));
      }
    }
    return ListView(
      key: ValueKey('r-${q.normalized}'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
      children: [_Constrain(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children))],
    );
  }

  String? _badgeFor(_Kind k, String what) {
    final y = _year;
    if (y == null) return null;
    if (k == _Kind.product || k == _Kind.customer) return '$what • $y';
    if (k == _Kind.employee) return _hits.query?.period?.label;
    return null;
  }

  Widget _empty(ReportQuery q) => ListView(
        key: ValueKey('empty-${q.normalized}'),
        padding: const EdgeInsets.fromLTRB(16, 40, 16, 32),
        children: [
          _Constrain(
            child: Column(children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(color: kRepPurple.withValues(alpha: 0.08), shape: BoxShape.circle),
                child: const Icon(Icons.search_off_rounded, size: 42, color: kRepPurple),
              ),
              const SizedBox(height: 14),
              Text('لم أجد شيئاً لـ «${q.raw.trim()}»',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: kSetText)),
              const SizedBox(height: 6),
              const Text('جرّب كلمة أخرى بنفس المعنى، أو جزءاً من الاسم، أو امسح الفترة.',
                  textAlign: TextAlign.center, style: TextStyle(color: kSetMuted)),
              const SizedBox(height: 22),
              _tip(),
            ]),
          ),
        ],
      );

  Widget _sectionTitle(String t, IconData icon, Color c, {int? count}) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
        child: Row(children: [
          Icon(icon, size: 18, color: c),
          const SizedBox(width: 8),
          Text(t, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: kSetText)),
          if (count != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
              child: Text('$count', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: c)),
            ),
          ],
        ]),
      );
}

// ═══════════════════════════ قطع الواجهة ═══════════════════════════

class _Constrain extends StatelessWidget {
  const _Constrain({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 920), child: child));
}

class _TipLine extends StatelessWidget {
  const _TipLine(this.title, this.text);
  final String title;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Icon(Icons.circle, size: 6, color: kRepPurple),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(TextSpan(children: [
              TextSpan(text: '$title: ', style: const TextStyle(fontWeight: FontWeight.w800, color: kSetText)),
              TextSpan(text: text, style: const TextStyle(color: kSetMuted)),
            ])),
          ),
        ]),
      );
}

/// ظهور متتابع ناعم (انزلاق خفيف + شفافية).
class _Appear extends StatelessWidget {
  const _Appear({required this.index, required this.child});
  final int index;
  final Widget child;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 180 + (index.clamp(0, 12) * 35)),
        curve: Curves.easeOutCubic,
        builder: (context, t, c) => Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, (1 - t) * 10), child: c),
        ),
        child: child,
      );
}

/// سطر نتيجة: أيقونة متدرجة (أو أول حرف من الاسم) + عنوان + شرح + شارة الفترة.
class _ResultTile extends StatefulWidget {
  const _ResultTile({
    this.icon,
    this.letter,
    required this.color,
    required this.title,
    required this.subtitle,
    this.badge,
    required this.onTap,
  });
  final IconData? icon;
  final String? letter;
  final Color color;
  final String title;
  final String subtitle;
  final String? badge;
  final VoidCallback onTap;

  @override
  State<_ResultTile> createState() => _ResultTileState();
}

class _ResultTileState extends State<_ResultTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.color;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          transform: Matrix4.translationValues(0, _hover ? -2 : 0, 0),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _hover ? c.withValues(alpha: 0.45) : kSetBorder),
            boxShadow: [
              BoxShadow(
                color: (_hover ? c : const Color(0xFF0F172A)).withValues(alpha: _hover ? 0.13 : 0.035),
                blurRadius: _hover ? 18 : 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Semantics(
              button: true,
              label: widget.title,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: widget.onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  child: Row(children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: widget.icon != null
                            ? LinearGradient(
                                colors: [c, Color.alphaBlend(Colors.white24, c)],
                                begin: AlignmentDirectional.topStart,
                                end: AlignmentDirectional.bottomEnd,
                              )
                            : null,
                        color: widget.icon == null ? c.withValues(alpha: 0.12) : null,
                        borderRadius: BorderRadius.circular(widget.icon != null ? 13 : 22),
                      ),
                      child: widget.icon != null
                          ? Icon(widget.icon, color: Colors.white, size: 23)
                          : Text(widget.letter ?? '؟',
                              style: TextStyle(color: c, fontWeight: FontWeight.w900, fontSize: 18)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: kSetText)),
                        const SizedBox(height: 2),
                        Text(widget.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.3, color: kSetMuted)),
                      ]),
                    ),
                    if (widget.badge != null) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        flex: 0,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: c.withValues(alpha: 0.09),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(widget.badge!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: c)),
                        ),
                      ),
                    ],
                    const SizedBox(width: 6),
                    AnimatedSlide(
                      duration: const Duration(milliseconds: 150),
                      offset: Offset(_hover ? -0.2 : 0, 0),
                      child: Icon(Icons.arrow_forward_ios_rounded, size: 14, color: _hover ? c : const Color(0xFFB8C2CF)),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// شريط بحث مضغوط يُوضع أعلى مركز التقارير — يفتح شاشة البحث.
class ReportSearchBar extends StatelessWidget {
  const ReportSearchBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => ReportSearchScreen.open(context),
            child: Ink(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: kRepPurple.withValues(alpha: 0.22)),
                boxShadow: [BoxShadow(color: kRepPurple.withValues(alpha: 0.07), blurRadius: 16, offset: const Offset(0, 5))],
              ),
              child: Row(children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF4F46E5), kRepPurple]),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(Icons.manage_search_rounded, color: Colors.white, size: 21),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('ابحث في التقارير',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: kSetText)),
                    SizedBox(height: 2),
                    Text('مادة، عميل، موظف، الربح، سند قبض، الضمان، أثر الدولار، مقارنة، 2025…',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.3, color: kSetMuted)),
                  ]),
                ),
                const Icon(Icons.keyboard_return_rounded, color: Color(0xFFB8C2CF), size: 18),
              ]),
            ),
          ),
      ),
    );
  }
}
