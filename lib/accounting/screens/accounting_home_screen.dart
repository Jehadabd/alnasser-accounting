// lib/accounting/screens/accounting_home_screen.dart
//
// 🏛️ مركز المحاسبة: مدخل كل الشاشات المحاسبية + حالة الترحيل.

import 'package:flutter/material.dart';

import '../../models/app_user.dart';
import '../accounting_reports.dart';
import '../posting_engine.dart';
import 'acc_ui.dart';
import 'account_statement_screen.dart';
import 'balance_sheet_screen.dart';
import 'cash_boxes_screen.dart';
import 'chart_of_accounts_screen.dart';
import 'income_statement_screen.dart';
import 'journal_screen.dart';
import 'accounting_settings_screen.dart';
import 'trial_balance_screen.dart';
import '../../inventory/item_card_screen.dart';
import '../../inventory/purchase_return_screen.dart';
import '../../org/screens/branches_warehouses_screen.dart';
import 'vouchers_screen.dart';
import '../../erp/accounting_plus/currency_voucher_screens.dart';
import '../../erp/accounting_plus/period_screens.dart';
import '../../erp/debts/receipt_screen.dart';
import '../../erp/debts/debts_hub_screen.dart';
import '../../erp/inventory/inventory_hub_screen.dart';

class AccountingHomeScreen extends StatefulWidget {
  const AccountingHomeScreen({super.key});

  @override
  State<AccountingHomeScreen> createState() => _AccountingHomeScreenState();
}

class _AccountingHomeScreenState extends State<AccountingHomeScreen> {
  bool _posting = false;
  String? _status;
  List<String> _problems = const [];

  @override
  void initState() {
    super.initState();
    _post(silent: true);
  }

  Future<void> _post({bool silent = false}) async {
    if (!canRunPosting) {
      setState(() => _status = 'هذا الجهاز طرفية — السيرفر يرحّل القيود تلقائياً');
      await _check();
      return;
    }
    setState(() {
      _posting = true;
      _status = 'جارٍ الترحيل...';
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
          builder: (_) => AlertDialog(
            title: const Text('مستندات لم تُرحَّل'),
            content: SizedBox(
              width: 500,
              child: ListView(shrinkWrap: true, children: s.errors.map(Text.new).toList()),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('حسناً')),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _status = 'فشل الترحيل: $e');
    } finally {
      if (mounted) setState(() => _posting = false);
    }
    await _check();
  }

  Future<void> _check() async {
    try {
      final p = await AccountingReports().integrityCheck();
      if (mounted) setState(() => _problems = p);
    } catch (_) {}
  }

  void _open(Widget screen, {String? permission}) {
    if (permission != null && !requirePermission(context, permission)) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  Widget _tile(String title, IconData icon, Color color, VoidCallback onTap,
      {String? subtitle}) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color, size: 28),
                  ),
                  const SizedBox(height: 10),
                  Text(title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(subtitle,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12, color: AccColors.muted)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final cols = width > 1200 ? 5 : width > 900 ? 4 : width > 600 ? 3 : 2;
    return Scaffold(
      backgroundColor: AccColors.bg,
      appBar: accAppBar('المحاسبة', actions: [
        IconButton(
          tooltip: 'ترحيل الآن',
          icon: _posting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.sync),
          onPressed: _posting ? null : () => _post(),
        ),
      ]),
      body: Column(
        children: [
          if (_status != null)
            Container(
              width: double.infinity,
              color: AccColors.navy.withOpacity(0.06),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(_status!, style: const TextStyle(color: AccColors.navy)),
            ),
          for (final p in _problems)
            Container(
              width: double.infinity,
              color: const Color(0xFFFFF3E0),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(children: [
                const Icon(Icons.warning_amber, color: AccColors.orange),
                const SizedBox(width: 8),
                Expanded(child: Text(p)),
              ]),
            ),
          Expanded(
            child: GridView.count(
              padding: const EdgeInsets.all(12),
              crossAxisCount: cols,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.25,
              children: [
                _tile('سند مصروف', Icons.receipt_long, AccColors.red,
                    () => _open(const VouchersScreen(initialNew: true), permission: AppPermissions.accountingPost),
                    subtitle: 'إيجار، رواتب، كهرباء...'),
                _tile('السندات', Icons.description, AccColors.orange,
                    () => _open(const VouchersScreen(), permission: AppPermissions.accounting),
                    subtitle: 'قبض، صرف، تحويل'),
                _tile('الصناديق', Icons.account_balance_wallet, AccColors.green,
                    () => _open(const CashBoxesScreen(), permission: AppPermissions.accounting)),
                _tile('القيود اليومية', Icons.menu_book, AccColors.blue,
                    () => _open(const JournalScreen(), permission: AppPermissions.accounting)),
                _tile('شجرة الحسابات', Icons.account_tree, AccColors.purple,
                    () => _open(const ChartOfAccountsScreen(), permission: AppPermissions.accounting)),
                _tile('كشف حساب', Icons.list_alt, AccColors.navy,
                    () => _open(const AccountStatementScreen(), permission: AppPermissions.accounting)),
                _tile('ميزان المراجعة', Icons.balance, AccColors.cyan,
                    () => _open(const TrialBalanceScreen(), permission: AppPermissions.accounting)),
                _tile('قائمة الدخل', Icons.trending_up, AccColors.green,
                    () => _open(const IncomeStatementScreen(), permission: AppPermissions.viewCostProfit),
                    subtitle: 'الأرباح والخسائر'),
                _tile('الميزانية العمومية', Icons.account_balance, AccColors.navy,
                    () => _open(const BalanceSheetScreen(), permission: AppPermissions.viewCostProfit)),
                _tile('مرتجع مشتريات', Icons.assignment_return, AccColors.orange,
                    () => _open(const PurchaseReturnScreen(), permission: AppPermissions.suppliers),
                    subtitle: 'إرجاع بضاعة للمورد'),
                _tile('بطاقات المواد', Icons.inventory, AccColors.cyan,
                    () => _open(const ItemCardsListScreen(), permission: AppPermissions.itemCard)),
                _tile('الفروع والمخازن', Icons.warehouse, AccColors.green,
                    () => _open(const BranchesWarehousesScreen(), permission: AppPermissions.manageBranches),
                    subtitle: 'والتحويلات المخزنية'),
                _tile('سند قيد مركّب', Icons.call_split, AccColors.navy,
                    () => _open(const CompoundVouchersScreen(), permission: AppPermissions.accountingPost),
                    subtitle: 'عدة حسابات وعملات'),
                _tile('قوالب السندات', Icons.bookmarks, AccColors.blue,
                    () => _open(const VoucherTemplatesScreen(), permission: AppPermissions.accountingPost)),
                _tile('وصل قبض', Icons.receipt, AccColors.green,
                    () => _open(const ReceiptScreen(), permission: AppPermissions.collection),
                    subtitle: 'من عميل أو عدة عملاء'),
                _tile('التحصيل والديون', Icons.request_quote, AccColors.red,
                    () => _open(const DebtsHubScreen(), permission: AppPermissions.collection)),
                _tile('المخزون', Icons.warehouse_outlined, AccColors.purple,
                    () => _open(const InventoryHubScreen(), permission: AppPermissions.inventoryDocs),
                    subtitle: 'مستندات، جرد، تصنيع'),
                _tile('العملات', Icons.currency_exchange, AccColors.green,
                    () => _open(const CurrenciesScreen(), permission: AppPermissions.currencies)),
                _tile('التثبيت والإقفال', Icons.lock_clock, AccColors.purple,
                    () => _open(const PeriodCloseScreen(), permission: AppPermissions.periodClose),
                    subtitle: 'إقفال السنة المالية'),
                _tile('فروقات العملة', Icons.swap_horiz, AccColors.orange,
                    () => _open(const FxRevaluationScreen(), permission: AppPermissions.periodClose)),
                _tile('الحسابات النوعية', Icons.workspaces, AccColors.cyan,
                    () => _open(const AccountGroupsScreen(), permission: AppPermissions.accounting)),
                _tile('المحاسبة المتقدمة', Icons.apps, AccColors.navy,
                    () => _open(const AccountingPlusHubScreen(), permission: AppPermissions.accounting),
                    subtitle: 'كل الأدوات'),
                _tile('إعدادات المحاسبة', Icons.tune, AccColors.muted,
                    () => _open(const AccountingSettingsScreen(), permission: AppPermissions.accountingPost),
                    subtitle: 'سعر الصرف، مطابقة المخزون'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
