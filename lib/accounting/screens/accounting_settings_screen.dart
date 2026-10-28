// lib/accounting/screens/accounting_settings_screen.dart
//
// ⚙️ إعدادات المحاسبة: مطابقة المخزون، فحص السلامة، وعرض سعر الدولار المعتمد.
//
// سعر الصرف لم يعد يُكتب هنا: كان هذا الحقل يحفظ إعداداً قديماً (usd_rate) لا
// يقرؤه البرنامج إلا إن لم يوجد سجل في «العملات وأسعار الصرف» — والسجل موجود
// دائماً، فكان الحفظ هنا بلا أثر. المكان الوحيد للسعر الآن شاشة العملات.

import 'package:flutter/material.dart';

import '../../erp/accounting_plus/currency_voucher_screens.dart' show CurrenciesScreen;
import '../../erp/currency_service.dart';
import '../../erp/erp_ui.dart';
import '../../models/app_user.dart';
import '../../services/database_service.dart';
import '../accounting_reports.dart';
import '../posting_engine.dart';
import 'acc_ui.dart';

class AccountingSettingsScreen extends StatefulWidget {
  const AccountingSettingsScreen({super.key});

  @override
  State<AccountingSettingsScreen> createState() => _AccountingSettingsScreenState();
}

class _AccountingSettingsScreenState extends State<AccountingSettingsScreen> {
  bool _busy = false;
  String? _busyLabel;
  List<String>? _problems;
  DateTime? _checkedAt;
  double? _usd;
  DateTime? _usdSince;
  String? _alignResult;

  @override
  void initState() {
    super.initState();
    _loadRate();
  }

  Future<void> _loadRate() async {
    try {
      final db = await DatabaseService().database;
      final r = await CurrencyService.rateAt(db, 'USD', DateTime.now());
      final h = await CurrencyService().history(code: 'USD');
      DateTime? since;
      if (h.isNotEmpty) since = DateTime.tryParse('${h.first['rate_date']}');
      if (mounted) {
        setState(() {
          _usd = r;
          _usdSince = since;
        });
      }
    } catch (_) {}
  }

  Future<void> _openCurrencies() async {
    if (!requirePermission(context, AppPermissions.currencies)) return;
    await Navigator.push(context, accRoute<void>(const CurrenciesScreen()));
    _loadRate();
  }

  Future<void> _alignInventory() async {
    if (!canRunPosting) {
      showError(context, 'هذه العملية تُنفَّذ على حاسبة السيرفر');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => ErpDialog(
        title: 'مطابقة المخزون',
        icon: Icons.inventory_2_rounded,
        color: AccColors.orange,
        width: 520,
        content: const Text(
          'سيُضبط رصيد حساب «مخزون البضاعة» ليساوي قيمة البضاعة الموجودة الآن '
          '(الكمية × سعر الكلفة لكل مادة)، والفرق يُسجَّل في «الأرصدة الافتتاحية».\n\n'
          'استعملها مرة عند بدء العمل بالمحاسبة، وبعد كل جرد فعلي. يمكن تكرارها بأمان: '
          'القيد يُستبدل ولا يتكرر.',
          style: TextStyle(height: 1.7),
        ),
        actions: erpDialogActions(ctx, ok: 'طابق الآن', color: AccColors.orange, icon: Icons.inventory_rounded),
      ),
    );
    if (ok != true) return;
    setState(() {
      _busy = true;
      _busyLabel = 'جارٍ مطابقة المخزون…';
    });
    try {
      await PostingEngine().syncAll();
      final diff = await PostingEngine().alignInventoryToStockValue();
      if (mounted) {
        setState(() => _alignResult = 'آخر مطابقة: ${TimeOfDay.now().format(context)} — التعديل ${fmtMoney(diff)}');
        showOk(context, 'تمت المطابقة — التعديل ${fmtMoney(diff)}');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyLabel = null;
        });
      }
    }
  }

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _busyLabel = 'جارٍ فحص الدفتر…';
    });
    try {
      if (canRunPosting) await PostingEngine().syncAll();
      final p = await AccountingReports().integrityCheck();
      if (mounted) {
        setState(() {
          _problems = p;
          _checkedAt = DateTime.now();
        });
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyLabel = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ErpPage(
      title: 'إعدادات المحاسبة',
      subtitle: 'سعر الدولار المعتمد • مطابقة المخزون • فحص سلامة الدفتر',
      icon: Icons.tune_rounded,
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(padding: const EdgeInsets.fromLTRB(4, 12, 4, 24), children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              child: _busy
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: Row(children: [
                        const SizedBox(
                            width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                        const SizedBox(width: 10),
                        Text(_busyLabel ?? 'جارٍ العمل…', style: const TextStyle(color: AccColors.navy)),
                      ]),
                    )
                  : const SizedBox(width: double.infinity),
            ),
            // ── سعر الدولار (عرض فقط) ──
            FadeSlideIn(
              index: 0,
              child: ErpSection(
                title: 'سعر صرف الدولار',
                icon: Icons.currency_exchange_rounded,
                color: AccColors.green,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [AccColors.navy, AccColors.blue]),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('1 دولار =', style: TextStyle(color: Colors.white70, fontSize: 12)),
                        Text(
                          _usd == null ? '…' : '${fmtMoney(_usd!)} د.ع',
                          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
                        ),
                      ]),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        _usdSince == null
                            ? 'السعر المعتمد اليوم في كل الحسابات.'
                            : 'السعر المعتمد اليوم — نافذ من ${fmtDate(_usdSince!)}.',
                        style: const TextStyle(color: AccColors.muted, height: 1.6),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AccColors.soft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.info_outline_rounded, size: 18, color: AccColors.navy),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'لسعر الصرف مكان واحد: «العملات وأسعار الصرف». هناك يُسجَّل كل سعر بتاريخه، '
                          'فتُقيَّم مستندات كل يوم بسعر يومها ولا يتغير الماضي عند تغيير سعر اليوم.',
                          style: TextStyle(fontSize: 12.5, height: 1.6, color: AccColors.text),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: AccColors.green),
                    onPressed: _openCurrencies,
                    icon: const Icon(Icons.trending_up_rounded),
                    label: const Text('تغيير السعر من «العملات وأسعار الصرف»'),
                  ),
                ]),
              ),
            ),
            // ── مطابقة المخزون ──
            FadeSlideIn(
              index: 1,
              child: ErpSection(
                title: 'مطابقة المخزون مع البضاعة الموجودة',
                icon: Icons.inventory_2_rounded,
                color: AccColors.orange,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text(
                    'المشتريات القديمة غير المسجّلة تجعل رصيد المخزون في الدفتر سالباً. '
                    'هذه الأداة تصححه بقيد واحد.',
                    style: TextStyle(height: 1.6),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: AccColors.orange),
                    onPressed: _busy ? null : _alignInventory,
                    icon: const Icon(Icons.inventory_rounded),
                    label: const Text('طابق المخزون الآن'),
                  ),
                  if (_alignResult != null) ...[
                    const SizedBox(height: 10),
                    StatusBadge(_alignResult!, color: AccColors.green),
                  ],
                  if (!canRunPosting) ...[
                    const SizedBox(height: 10),
                    const Text('تُنفَّذ على حاسبة السيرفر فقط.',
                        style: TextStyle(fontSize: 12.5, color: AccColors.muted)),
                  ],
                ]),
              ),
            ),
            // ── فحص السلامة ──
            FadeSlideIn(
              index: 2,
              child: ErpSection(
                title: 'فحص سلامة الدفتر',
                icon: Icons.verified_rounded,
                color: AccColors.green,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text(
                    'يتحقق أن ميزان المراجعة متوازن وأن ذمم العملاء في الدفتر = مجموع أرصدة سجل الديون.',
                    style: TextStyle(height: 1.6),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _check,
                    icon: const Icon(Icons.fact_check_rounded),
                    label: const Text('افحص الآن'),
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: _problems == null
                        ? const SizedBox.shrink()
                        : Padding(
                            key: ValueKey(_checkedAt),
                            padding: const EdgeInsets.only(top: 12),
                            child: _problems!.isEmpty
                                ? Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFECFDF5),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: const Color(0xFFA7F3D0)),
                                    ),
                                    child: const Row(children: [
                                      Icon(Icons.check_circle_rounded, color: AccColors.green),
                                      SizedBox(width: 8),
                                      Expanded(
                                        child: Text('الدفتر سليم ومطابق لسجل الديون',
                                            style: TextStyle(color: AccColors.green, fontWeight: FontWeight.w800)),
                                      ),
                                    ]),
                                  )
                                : Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFEF2F2),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: const Color(0xFFFECACA)),
                                    ),
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      for (final p in _problems!)
                                        Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 2),
                                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                            const Icon(Icons.error_outline_rounded, size: 18, color: AccColors.red),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(p,
                                                  style: const TextStyle(color: AccColors.red, height: 1.5)),
                                            ),
                                          ]),
                                        ),
                                    ]),
                                  ),
                          ),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
