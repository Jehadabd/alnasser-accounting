// lib/erp/debts/debts_hub_screen.dart
//
// 💼 مركز الديون والتحصيل: مؤشرات سريعة + كل أدوات الإداري للديون.

import 'package:flutter/material.dart';

import '../../accounting/screens/acc_ui.dart';
import '../../models/app_user.dart';
import '../erp_common.dart';
import '../erp_ui.dart';
import 'customer_card_screen.dart';
import 'customer_statement_screen.dart';
import 'debt_reports_screen.dart';
import 'due_items_screen.dart';
import 'due_items_service.dart';
import 'receipt_screen.dart';

class DebtsHubScreen extends StatefulWidget {
  const DebtsHubScreen({super.key});
  @override
  State<DebtsHubScreen> createState() => _DebtsHubScreenState();
}

class _DebtsHubScreenState extends State<DebtsHubScreen> {
  double _receivable = 0;
  int _debtors = 0;
  double _monthCollected = 0;
  Map<String, double> _due = const {};
  int _over = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final db = await erpDb();
      final r = await db.rawQuery('''
        SELECT COALESCE(SUM(CASE WHEN current_total_debt > 0 THEN current_total_debt ELSE 0 END), 0) AS ar,
               SUM(CASE WHEN current_total_debt > 0.5 THEN 1 ELSE 0 END) AS n
        FROM customers WHERE COALESCE(is_deleted, 0) = 0
      ''');
      final now = DateTime.now();
      final m = await db.rawQuery('''
        SELECT COALESCE(SUM(-amount_changed), 0) AS c FROM transactions
        WHERE amount_changed < 0 AND COALESCE(is_deleted, 0) = 0 AND transaction_date >= ?
      ''', [isoDay(DateTime(now.year, now.month, 1))]);
      final o = await db.rawQuery('''
        SELECT COUNT(*) AS n FROM customers c JOIN customer_ext x ON x.customer_id = c.id
        WHERE COALESCE(x.credit_limit, 0) > 0 AND c.current_total_debt > x.credit_limit
          AND COALESCE(c.is_deleted, 0) = 0
      ''');
      final due = await DueItemsService().dashboard();
      if (!mounted) return;
      setState(() {
        _receivable = d0(r.first['ar']);
        _debtors = ((r.first['n'] as num?) ?? 0).toInt();
        _monthCollected = d0(m.first['c']);
        _due = due;
        _over = ((o.first['n'] as num?) ?? 0).toInt();
      });
    } catch (_) {}
  }

  void _go(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w)).then((_) => _load());

  @override
  Widget build(BuildContext context) {
    return ErpPage(
      title: 'الديون والتحصيل',
      subtitle: 'وصولات القبض، الاستحقاقات، أعمار الديون، المطابقة',
      icon: Icons.account_balance_wallet_outlined,
      actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      headerExtra: Wrap(spacing: 10, runSpacing: 10, children: [
        StatCard(label: 'ديون العملاء', value: fmtMoney(_receivable), hint: '$_debtors عميل مدين', icon: Icons.people, color: ErpColors.orange),
        StatCard(label: 'المحصّل هذا الشهر', value: fmtMoney(_monthCollected), icon: Icons.savings, color: ErpColors.green),
        StatCard(label: 'استحقاقات متأخرة', value: fmtMoney(_due['overdue'] ?? 0), icon: Icons.warning_amber, color: ErpColors.red,
            onTap: () => _go(const DueItemsScreen())),
        StatCard(label: 'تجاوزوا السقف', value: '$_over', icon: Icons.block, color: ErpColors.purple,
            onTap: () => _go(const OverLimitScreen())),
      ]),
      body: HubGrid(tiles: [
        HubTile('وصل قبض', Icons.receipt_long, ErpColors.green, () => _go(const ReceiptScreen()),
            subtitle: 'مفرد أو مركّب، بحسم وعملة', permission: AppPermissions.collection),
        HubTile('سجل الوصولات', Icons.history_edu, ErpColors.navy, () => _go(const ReceiptsListScreen()),
            permission: AppPermissions.collection),
        HubTile('دفعة لمورد', Icons.outbox, ErpColors.orange, () => _go(const SupplierPaymentScreen()),
            subtitle: 'نقداً، شيك، خصم مكتسب', permission: AppPermissions.suppliers),
        HubTile('الاستحقاقات', Icons.event_note, ErpColors.gold, () => _go(const DueItemsScreen()),
            subtitle: 'شيكات، كمبيالات، أقساط', permission: AppPermissions.collection),
        HubTile('كشف حساب عميل', Icons.list_alt, ErpColors.blue, () => _go(const CustomerStatementScreen()),
            subtitle: 'فترة، شهري، موضّح، مطابقة'),
        HubTile('دليل العملاء', Icons.contacts_outlined, ErpColors.cyan, () => _go(const CustomersDirectoryScreen()),
            subtitle: 'البطاقات، المجموعات، المناطق', permission: AppPermissions.customerCard),
        HubTile('أعمار الديون', Icons.hourglass_bottom, ErpColors.red, () => _go(const AgingScreen()),
            subtitle: 'العملاء والموردون', permission: AppPermissions.debtReports),
        HubTile('نسب التحصيل', Icons.percent, ErpColors.purple, () => _go(const CollectionReportScreen()),
            permission: AppPermissions.debtReports),
        HubTile('الفواتير غير المسددة', Icons.receipt_outlined, ErpColors.orange, () => _go(const OpenInvoicesScreen()),
            permission: AppPermissions.debtReports),
        HubTile('المتجاوزون للسقف', Icons.block, ErpColors.red, () => _go(const OverLimitScreen()),
            permission: AppPermissions.debtReports),
      ]),
    );
  }
}
