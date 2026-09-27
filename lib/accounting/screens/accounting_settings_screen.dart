// lib/accounting/screens/accounting_settings_screen.dart
//
// ⚙️ إعدادات المحاسبة: سعر صرف الدولار، مطابقة المخزون، فحص السلامة.

import 'package:flutter/material.dart';

import '../../services/database_service.dart';
import '../accounting_reports.dart';
import '../ledger.dart';
import '../posting_engine.dart';
import 'acc_ui.dart';

class AccountingSettingsScreen extends StatefulWidget {
  const AccountingSettingsScreen({super.key});

  @override
  State<AccountingSettingsScreen> createState() => _AccountingSettingsScreenState();
}

class _AccountingSettingsScreenState extends State<AccountingSettingsScreen> {
  final _rate = TextEditingController();
  bool _busy = false;
  List<String>? _problems;

  @override
  void initState() {
    super.initState();
    DatabaseService().database.then((db) async {
      final r = await Ledger.usdRate(db);
      if (mounted) _rate.text = r.toStringAsFixed(0);
    });
  }

  Future<void> _saveRate() async {
    final v = double.tryParse(_rate.text.replaceAll(',', ''));
    if (v == null || v <= 0) {
      showError(context, 'أدخل سعر صرف صحيحاً');
      return;
    }
    final db = await DatabaseService().database;
    await Ledger.setSetting(db, 'usd_rate', v.toString());
    if (canRunPosting) await PostingEngine().syncAll();
    if (mounted) showOk(context, 'حُفظ سعر الصرف وأُعيد تقييم حركات الموردين بالدولار');
  }

  Future<void> _alignInventory() async {
    if (!canRunPosting) {
      showError(context, 'هذه العملية تُنفَّذ على حاسبة السيرفر');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('مطابقة المخزون'),
        content: const Text(
          'سيُضبط رصيد حساب «مخزون البضاعة» ليساوي قيمة البضاعة الموجودة الآن '
          '(الكمية × سعر الكلفة لكل مادة)، والفرق يُسجَّل في «الأرصدة الافتتاحية».\n\n'
          'استعملها مرة عند بدء العمل بالمحاسبة، وبعد كل جرد فعلي. يمكن تكرارها بأمان: '
          'القيد يُستبدل ولا يتكرر.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('طابق الآن')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await PostingEngine().syncAll();
      final diff = await PostingEngine().alignInventoryToStockValue();
      if (mounted) showOk(context, 'تمت المطابقة — التعديل ${fmtMoney(diff)}');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _check() async {
    setState(() => _busy = true);
    try {
      if (canRunPosting) await PostingEngine().syncAll();
      final p = await AccountingReports().integrityCheck();
      if (mounted) setState(() => _problems = p);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AccColors.bg,
      appBar: accAppBar('إعدادات المحاسبة'),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(padding: const EdgeInsets.all(12), children: [
            if (_busy) const LinearProgressIndicator(),
            SectionCard(
              title: 'سعر صرف الدولار',
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _rate,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'دينار لكل دولار',
                          helperText: 'يُستعمل لتقييم ديون ومشتريات الموردين بالدولار في الدفتر'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(onPressed: _busy ? null : _saveRate, child: const Text('حفظ')),
                ]),
              ),
            ),
            SectionCard(
              title: 'مطابقة المخزون مع البضاعة الموجودة',
              color: AccColors.orange,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text(
                    'المشتريات القديمة غير المسجّلة تجعل رصيد المخزون في الدفتر سالباً. '
                    'هذه الأداة تصححه بقيد واحد.',
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: AccColors.orange),
                    onPressed: _busy ? null : _alignInventory,
                    icon: const Icon(Icons.inventory),
                    label: const Text('طابق المخزون الآن'),
                  ),
                ]),
              ),
            ),
            SectionCard(
              title: 'فحص سلامة الدفتر',
              color: AccColors.green,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('يتحقق أن ميزان المراجعة متوازن وأن ذمم العملاء في الدفتر = مجموع أرصدة سجل الديون.'),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _check,
                    icon: const Icon(Icons.verified),
                    label: const Text('افحص الآن'),
                  ),
                  if (_problems != null) ...[
                    const SizedBox(height: 12),
                    if (_problems!.isEmpty)
                      const Text('✓ الدفتر سليم ومطابق لسجل الديون',
                          style: TextStyle(color: AccColors.green, fontWeight: FontWeight.bold))
                    else
                      for (final p in _problems!)
                        Text('• $p', style: const TextStyle(color: AccColors.red)),
                  ],
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
