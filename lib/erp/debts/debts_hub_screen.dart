// lib/erp/debts/debts_hub_screen.dart
//
// 💼 مركز الديون والتحصيل: مؤشرات سريعة + كل أدوات الإداري للديون.

import 'package:flutter/material.dart';

import '../../accounting/screens/acc_ui.dart';
import '../../models/app_user.dart';
import '../erp_common.dart';
import '../erp_ui.dart';
import '../reports/finance_reports.dart';
import 'customer_card_screen.dart';
import 'customer_statement_screen.dart';
import 'debt_reports_screen.dart';
import 'due_items_screen.dart';
import 'due_items_service.dart';
import 'receipt_screen.dart';
import '../../screens/debt_reminders_screen.dart'; // 📅

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
      // المحصّل = تسديدات فعلية فقط (نقد/شيك)؛ لا الخصومات ولا المرتجعات ولا تعديلات القوائم
      final m = await db.rawQuery('''
        SELECT COALESCE(SUM(-t.amount_changed), 0) AS c FROM transactions t
        LEFT JOIN customer_tx_ext x ON x.transaction_uuid = t.transaction_uuid
        WHERE t.amount_changed < 0 AND COALESCE(t.is_deleted, 0) = 0 AND t.transaction_date >= ?
          AND t.transaction_type = 'manual_payment'
          AND COALESCE(x.kind, 'cash') IN ('cash', 'cheque')
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
      title: 'التحصيل والتقارير',
      subtitle: 'جزء من سجل الديون: الوصولات • الاستحقاقات • التقارير',
      icon: Icons.account_balance_wallet_outlined,
      actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      headerExtra: Wrap(spacing: 10, runSpacing: 10, children: [
        StatCard(label: 'ديون العملاء', value: fmtMoney(_receivable), hint: '${fmtQty(_debtors)} عميل مدين', icon: Icons.people, color: ErpColors.orange),
        StatCard(label: 'المحصّل هذا الشهر', value: fmtMoney(_monthCollected), icon: Icons.savings, color: ErpColors.green),
        StatCard(label: 'استحقاقات متأخرة', value: fmtMoney(_due['overdue'] ?? 0), icon: Icons.warning_amber, color: ErpColors.red,
            onTap: () => _go(const DueItemsScreen())),
        StatCard(label: 'تجاوزوا السقف', value: fmtQty(_over), icon: Icons.block, color: ErpColors.purple,
            onTap: () => _go(const OverLimitScreen())),
      ]),
      body: HubSections(sections: [
        HubSection('الوصولات', [
          HubTile('وصل قبض', Icons.receipt_long, ErpColors.green, () => _go(const ReceiptScreen()),
              subtitle: 'من عميل أو عدة عملاء، بخصم وعملة', permission: AppPermissions.collection),
          HubTile('سجل الوصولات', Icons.history_edu, ErpColors.navy, () => _go(const ReceiptsListScreen()),
              subtitle: 'كل وصولات القبض وإعادة طباعتها', permission: AppPermissions.collection),
          HubTile('الاستحقاقات', Icons.event_note, ErpColors.gold, () => _go(const DueItemsScreen()),
              subtitle: 'شيكات، كمبيالات، أقساط', permission: AppPermissions.collection),
          // 📅 تذكير فقط (لا يغيّر الرصيد): أيام تختارها + أشخاص تطالبهم
          HubTile('مواعيد المطالبة', Icons.event_repeat_rounded, const Color(0xFF4F46E5),
              () => _go(const DebtRemindersScreen()),
              subtitle: 'تذكير بأيام تختارها (1، 2، 5…) لعدة أشخاص عند التشغيل'),
        ]),
        HubSection('العملاء', [
          HubTile('كشف حساب عميل', Icons.list_alt, ErpColors.blue, () => _go(const CustomerStatementScreen()),
              subtitle: 'فترة، شهري، موضّح، مطابقة'),
          HubTile('دليل العملاء', Icons.contacts_outlined, ErpColors.cyan, () => _go(const CustomersDirectoryScreen()),
              subtitle: 'البطاقات، المجموعات، المناطق', permission: AppPermissions.customerCard),
        ]),
        HubSection('تقارير الديون', [
          HubTile('أرصدة الديون', Icons.balance_rounded, ErpColors.navy, () => _go(const PartyBalancesScreen()),
              subtitle: 'العملاء والموردون مع تسديد سريع', permission: AppPermissions.debtReports),
          HubTile('أعمار الديون', Icons.hourglass_bottom, ErpColors.red, () => _go(const AgingScreen()),
              subtitle: 'منذ متى لم يسدد', permission: AppPermissions.debtReports),
          HubTile('نسب التحصيل', Icons.percent, ErpColors.purple, () => _go(const CollectionReportScreen()),
              permission: AppPermissions.debtReports),
          HubTile('المتجاوزون للسقف', Icons.block, ErpColors.red, () => _go(const OverLimitScreen()),
              permission: AppPermissions.debtReports),
        ]),
      ]),
    );
  }
}
