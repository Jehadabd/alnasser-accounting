// screens/home_screen.dart
//
// 📒 سجل الديون — قائمة العملاء بأرصدتهم:
//   • شريط ملخص: مجموع الديون وعدد المدينين، والأرصدة الدائنة (لهم).
//   • بحث بالكلمات (أي عدد مسافات وأي ترتيب) بالاسم أو الهاتف.
//   • الترتيب كشرائح ظاهرة (كان مخفياً في قائمة).
//   • بطاقة لكل عميل: الحرف الأول، الاسم، الهاتف والعنوان، والرصيد بحالته
//     (عليه / له / مسدَّد) — الضغط يفتح بطاقة العميل.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:provider/provider.dart';

import '../accounting/screens/acc_ui.dart' show accAppBar, requireAnyPermission;
import '../erp/debts/debts_hub_screen.dart';
import '../models/app_settings.dart';
import '../models/app_user.dart' show AppPermissions;
import '../models/customer.dart';
import '../providers/app_provider.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../services/debt_report_service.dart';
import '../services/settings_manager.dart';
import '../widgets/app_side_nav.dart';
import 'add_customer_screen.dart';
import 'customer_details_screen.dart';
import 'overdue_debts_screen.dart';
import 'saved_invoices_screen.dart';

// أسماء أنواع الترتيب بالعربية
String getSortTypeName(CustomerSortType type) {
  switch (type) {
    case CustomerSortType.alphabetical:
      return 'أبجدي';
    case CustomerSortType.lastDebtAdded:
      return 'آخر إضافة دين';
    case CustomerSortType.lastPayment:
      return 'آخر تسديد';
    case CustomerSortType.lastTransaction:
      return 'آخر معاملة';
    case CustomerSortType.highestDebt:
      return 'الأكبر مبلغاً';
  }
}

class _K {
  static const bg = Color(0xFFF3F6FB);
  static const navy = Color(0xFF0F3460);
  static const text = Color(0xFF1E293B);
  static const muted = Color(0xFF64748B);
  static const border = Color(0xFFE3E9F1);
  static const debt = Color(0xFFB91C1C);
  static const credit = Color(0xFF047857);
  static const settled = Color(0xFF64748B);
}

final NumberFormat _money = NumberFormat('#,##0', 'en_US');

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  bool _showScrollToTop = false;
  AppSettings? _appSettings;

  // ملخص كل العملاء (لا الصفحة المحمّلة فقط)
  double _ar = 0, _cr = 0;
  int _debtors = 0, _creditors = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadSettings();
    _loadSummary();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final app = context.read<AppProvider>();
      // تصفية البحث عند الدخول حتى لا يبقى فلتر قديم
      _searchController.clear();
      app.setSearchQuery('');
      app.initialize();
    });
  }

  Future<void> _loadSettings() async {
    final settings = await SettingsManager.getAppSettings();
    if (mounted) setState(() => _appSettings = settings);
  }

  Future<void> _loadSummary() async {
    if (!AuthService().isAdmin) return;
    try {
      final db = await DatabaseService().database;
      final r = await db.rawQuery(
          'SELECT COALESCE(SUM(CASE WHEN current_total_debt > 0 THEN current_total_debt ELSE 0 END), 0) AS ar, '
          'COALESCE(SUM(CASE WHEN current_total_debt > 0 THEN 1 ELSE 0 END), 0) AS n, '
          'COALESCE(SUM(CASE WHEN current_total_debt < 0 THEN -current_total_debt ELSE 0 END), 0) AS cr, '
          'COALESCE(SUM(CASE WHEN current_total_debt < 0 THEN 1 ELSE 0 END), 0) AS ncr '
          'FROM customers WHERE COALESCE(is_deleted, 0) = 0');
      if (!mounted || r.isEmpty) return;
      setState(() {
        _ar = (r.first['ar'] as num?)?.toDouble() ?? 0;
        _debtors = (r.first['n'] as num?)?.toInt() ?? 0;
        _cr = (r.first['cr'] as num?)?.toDouble() ?? 0;
        _creditors = (r.first['ncr'] as num?)?.toInt() ?? 0;
      });
    } catch (_) {}
  }

  void _onScroll() {
    final shouldShow = _scrollController.offset > 300;
    if (shouldShow != _showScrollToTop) setState(() => _showScrollToTop = shouldShow);
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      final app = context.read<AppProvider>();
      if (app.hasMoreData && !app.isLoadingMore) app.loadMoreCustomers();
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openOverdue() async {
    final months = await pickOverdueMonths(context);
    if (months != null && mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => OverdueDebtsScreen(initialMonths: months)));
    }
  }

  Future<void> _sharePdf() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('جاري إعداد تقرير الديون...')));
    try {
      await DebtReportService.generateAndShareReport();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('خطأ في إنشاء التقرير: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);
    return Scaffold(
      backgroundColor: _K.bg,
      appBar: accAppBar(
        'سجل الديون',
        icon: Icons.menu_book_rounded,
        subtitle: 'حسابات العملاء: من عليه، ومن له، ومن سدّد',
        actions: [
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            icon: const Icon(Icons.request_quote_rounded),
            label: const Text('التحصيل والتقارير'),
            onPressed: () {
              if (!requireAnyPermission(
                  context, const [AppPermissions.collection, AppPermissions.debtReports, AppPermissions.debtRegister])) {
                return;
              }
              Navigator.push(context, MaterialPageRoute(builder: (_) => const DebtsHubScreen()));
            },
          ),
          IconButton(
            tooltip: 'المتأخرون عن السداد',
            icon: const Icon(Icons.warning_amber_rounded, color: Colors.white),
            onPressed: _openOverdue,
          ),
          PopupMenuButton<String>(
            tooltip: 'المزيد',
            icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
            onSelected: (v) {
              switch (v) {
                case 'pdf':
                  _sharePdf();
                  break;
                case 'saved':
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const SavedInvoicesScreen()));
                  break;
                case 'ai':
                  Navigator.pushNamed(context, '/ai_chat');
                  break;
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: 'pdf',
                  child: ListTile(leading: Icon(Icons.picture_as_pdf_rounded), title: Text('مشاركة الديون PDF'), dense: true)),
              PopupMenuItem(
                  value: 'saved',
                  child: ListTile(leading: Icon(Icons.receipt_long_rounded), title: Text('الفواتير المحفوظة'), dense: true)),
              PopupMenuItem(
                  value: 'ai',
                  child: ListTile(leading: Icon(Icons.chat_bubble_outline_rounded), title: Text('اسأل الذكاء الاصطناعي'), dense: true)),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Row(children: [
        if (_appSettings != null && AppSideNav.shouldShow(context, _appSettings!))
          const AppSideNav(currentRoute: '/debt_register'),
        Expanded(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: provider.isLoading
                  ? const Center(child: CircularProgressIndicator(color: _K.navy))
                  : Column(children: [
                      // 🔒 مجموع الديون للمدير فقط
                      if (AuthService().isAdmin)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                          child: _summary(),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: _searchBox(provider),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                        child: _sortChips(provider),
                      ),
                      Expanded(
                        child: provider.customers.isEmpty
                            ? _empty(provider)
                            : RefreshIndicator(
                                onRefresh: () async {
                                  await provider.refreshCustomers();
                                  await _loadSummary();
                                },
                                child: ListView.builder(
                                  controller: _scrollController,
                                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 96),
                                  itemCount: provider.customers.length + (provider.isLoadingMore ? 1 : 0),
                                  itemBuilder: (context, index) {
                                    if (index == provider.customers.length) {
                                      return const Padding(
                                        padding: EdgeInsets.all(16),
                                        child: Center(child: CircularProgressIndicator()),
                                      );
                                    }
                                    return CustomerListTile(
                                      customer: provider.customers[index],
                                      onReturn: _loadSummary,
                                    );
                                  },
                                ),
                              ),
                      ),
                    ]),
            ),
          ),
        ),
      ]),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (_showScrollToTop)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: FloatingActionButton.small(
                heroTag: 'scroll_to_top',
                tooltip: 'العودة للأعلى',
                backgroundColor: Colors.white,
                foregroundColor: _K.navy,
                onPressed: () => _scrollController.animateTo(0,
                    duration: const Duration(milliseconds: 500), curve: Curves.easeOutCubic),
                child: const Icon(Icons.keyboard_arrow_up_rounded, size: 28),
              ),
            ),
          FloatingActionButton.extended(
            heroTag: 'add_customer',
            backgroundColor: _K.navy,
            foregroundColor: Colors.white,
            tooltip: 'إضافة عميل جديد',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddCustomerScreen()))
                .then((_) => _loadSummary()),
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('عميل جديد', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _summary() {
    Widget tile(String label, String value, String hint, IconData icon, Color c) => Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _K.border),
            ),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: c, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: const TextStyle(fontSize: 12.5, color: _K.muted, fontWeight: FontWeight.w600)),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(value,
                        textDirection: TextDirection.ltr,
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: c)),
                  ),
                  Text(hint, style: const TextStyle(fontSize: 11.5, color: _K.muted)),
                ]),
              ),
            ]),
          ),
        );
    return Row(children: [
      tile('مجموع الديون على العملاء', _money.format(_ar), '$_debtors عميل مدين', Icons.trending_up_rounded, _K.debt),
      const SizedBox(width: 12),
      tile('أرصدة دائنة (لهم)', _money.format(_cr), '$_creditors عميل', Icons.savings_rounded, _K.credit),
    ]);
  }

  Widget _searchBox(AppProvider provider) {
    return TextField(
      controller: _searchController,
      onChanged: provider.setSearchQuery,
      style: const TextStyle(fontSize: 16),
      decoration: InputDecoration(
        hintText: 'ابحث بالاسم أو رقم الهاتف — كلمة أو أكثر بأي ترتيب',
        prefixIcon: const Icon(Icons.search_rounded, color: _K.navy),
        suffixIcon: provider.searchQuery.isNotEmpty
            ? IconButton(
                tooltip: 'مسح',
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  _searchController.clear();
                  provider.setSearchQuery('');
                },
              )
            : null,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _K.border)),
        enabledBorder:
            OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _K.border)),
        focusedBorder:
            OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _K.navy, width: 1.6)),
      ),
    );
  }

  Widget _sortChips(AppProvider provider) {
    const order = [
      (CustomerSortType.alphabetical, Icons.sort_by_alpha_rounded),
      (CustomerSortType.highestDebt, Icons.trending_up_rounded),
      (CustomerSortType.lastDebtAdded, Icons.add_circle_outline_rounded),
      (CustomerSortType.lastPayment, Icons.payments_outlined),
      (CustomerSortType.lastTransaction, Icons.history_rounded),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        const Text('الترتيب:', style: TextStyle(color: _K.muted, fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        for (final o in order)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 6),
            child: ChoiceChip(
              avatar: Icon(o.$2, size: 16, color: provider.currentSortType == o.$1 ? Colors.white : _K.muted),
              label: Text(getSortTypeName(o.$1)),
              selected: provider.currentSortType == o.$1,
              showCheckmark: false,
              selectedColor: _K.navy,
              backgroundColor: Colors.white,
              side: BorderSide(color: provider.currentSortType == o.$1 ? _K.navy : _K.border),
              labelStyle: TextStyle(
                color: provider.currentSortType == o.$1 ? Colors.white : _K.text,
                fontWeight: FontWeight.w700,
              ),
              onSelected: (_) => provider.setSortType(o.$1),
            ),
          ),
      ]),
    );
  }

  Widget _empty(AppProvider provider) {
    final searching = provider.searchQuery.trim().isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(searching ? Icons.person_search_rounded : Icons.menu_book_rounded, size: 56, color: _K.border),
          const SizedBox(height: 12),
          Text(searching ? 'لا عميل يطابق «${provider.searchQuery.trim()}»' : 'لا عملاء في السجل بعد',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _K.text)),
          const SizedBox(height: 4),
          Text(
            searching ? 'جرّب جزءاً من الاسم أو آخر أرقام الهاتف.' : 'أضف عميلاً بزر «عميل جديد».',
            style: const TextStyle(color: _K.muted),
          ),
        ]),
      ),
    );
  }
}

/// بطاقة عميل في السجل.
class CustomerListTile extends StatefulWidget {
  final Customer customer;
  final VoidCallback? onReturn;

  const CustomerListTile({super.key, required this.customer, this.onReturn});

  @override
  State<CustomerListTile> createState() => _CustomerListTileState();
}

class _CustomerListTileState extends State<CustomerListTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.customer;
    final debt = c.currentTotalDebt;
    final owes = debt > 0.5;
    final hasCredit = debt < -0.5;
    final color = owes ? _K.debt : (hasCredit ? _K.credit : _K.settled);
    final status = owes ? 'عليه' : (hasCredit ? 'له' : 'مسدَّد');
    final initial = c.name.trim().isEmpty ? '؟' : c.name.trim().substring(0, 1);
    final details = [
      if ((c.phone ?? '').trim().isNotEmpty) c.phone!.trim(),
      if ((c.address ?? '').trim().isNotEmpty) c.address!.trim(),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: _hover ? color.withValues(alpha: 0.16) : const Color(0x0A0F172A),
                blurRadius: _hover ? 16 : 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: _hover ? color.withValues(alpha: 0.45) : _K.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerDetailsScreen(customer: c))).then((_) {
                  if (!context.mounted) return;
                  // تحديث بصمت مع الحفاظ على موضع التمرير
                  Provider.of<AppProvider>(context, listen: false).refreshCustomers();
                  widget.onReturn?.call();
                });
              },
              child: Container(
                decoration: BoxDecoration(border: BorderDirectional(start: BorderSide(color: color, width: 4))),
                padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                child: Row(children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: color.withValues(alpha: 0.10),
                    child: Text(initial, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(c.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _K.text)),
                      const SizedBox(height: 2),
                      Text(details.isEmpty ? 'لا رقم هاتف' : details.join(' • '),
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: _K.muted)),
                    ]),
                  ),
                  const SizedBox(width: 10),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(20)),
                      child: Text(status, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: color)),
                    ),
                    const SizedBox(height: 4),
                    Text(_money.format(debt.abs()),
                        textDirection: TextDirection.ltr,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color)),
                  ]),
                  const SizedBox(width: 6),
                  const Icon(Icons.chevron_right_rounded, color: _K.muted),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
