// lib/erp/erp_settings_screen.dart
//
// ⚙️ إعدادات الطباعة والمخزون (مثل «إعدادات الفرع والطباعة» في سهل):
//   • نوع طباعة فاتورة البيع الافتراضي: A4 أو حرارية 80mm.
//   • أبعاد ملصق الباركود بالمليمتر وطابعة الملصقات.
//   • حسابا فروقات الجرد: الزيادة والعجز.
//   • باركود الميزان.
// الإعدادات لا تغيّر أي قيد سابق: حسابات الجرد تُثبَّت على كل مستند عند إنشائه.

import 'package:flutter/material.dart';

import '../accounting/ledger.dart';
import '../accounting/screens/acc_ui.dart';
import '../models/app_user.dart';
import '../services/auth_service.dart';
import 'erp_common.dart';
import 'erp_ui.dart';
import 'inventory/barcode_labels.dart';
import 'inventory/stock_docs_service.dart';
import 'pickers.dart';
import 'pos/scale_barcode.dart';
import 'sales/roll_invoice_pdf.dart';

class ErpSettingsScreen extends StatefulWidget {
  const ErpSettingsScreen({super.key});
  @override
  State<ErpSettingsScreen> createState() => _ErpSettingsScreenState();
}

class _ErpSettingsScreenState extends State<ErpSettingsScreen> {
  String _print = 'a4';
  LabelOptions? _label;
  Account? _gain, _loss;
  ScaleSettings? _scale;
  final _lw = TextEditingController();
  final _lh = TextEditingController();
  final _prefix = TextEditingController();
  final _plu = TextEditingController();
  final _val = TextEditingController();
  bool _saving = false;

  bool get _canAcc => AuthService().hasPermission(AppPermissions.accountingPost);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await InvoicePrintFormat.get();
    final l = await LabelOptions.loadDefaults();
    final (g, lo) = await CountAccounts.get();
    final led = Ledger();
    final ga = g == null ? null : await led.accountById(g);
    final la = lo == null ? null : await led.accountById(lo);
    final sc = await ScaleSettings.load();
    if (!mounted) return;
    setState(() {
      _print = p;
      _label = l;
      _gain = ga;
      _loss = la;
      _scale = sc;
      _lw.text = fmtQty(l.labelWidth);
      _lh.text = fmtQty(l.labelHeight);
      _prefix.text = sc.prefix;
      _plu.text = '${sc.pluLength}';
      _val.text = '${sc.valueLength}';
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await InvoicePrintFormat.set(_print);
      final l = _label!;
      l.labelWidth = (double.tryParse(_lw.text) ?? l.labelWidth).clamp(15, 200).toDouble();
      l.labelHeight = (double.tryParse(_lh.text) ?? l.labelHeight).clamp(10, 200).toDouble();
      await l.saveDefaults();
      if (_canAcc) await CountAccounts.set(_gain?.id, _loss?.id);
      final s = _scale!;
      s
        ..prefix = _prefix.text.trim()
        ..pluLength = int.tryParse(_plu.text.trim()) ?? 5
        ..valueLength = int.tryParse(_val.text.trim()) ?? 5;
      await s.save();
      if (mounted) showOk(context, 'حُفظت الإعدادات');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<Account?> _pickAcc(String title, String type) async {
    final a = await Pickers.account(context, title: title, type: type);
    return a;
  }

  @override
  Widget build(BuildContext context) {
    if (_label == null || _scale == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return ErpPage(
      title: 'إعدادات الطباعة والمخزون',
      subtitle: 'نوع طباعة الفاتورة • ملصقات الباركود • حسابات الجرد • الميزان',
      icon: Icons.tune_rounded,
      bottom: SafeArea(
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            const Spacer(),
            PrimaryButton(label: 'حفظ كل الإعدادات', icon: Icons.save_rounded, busy: _saving, onPressed: _save),
          ]),
        ),
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        ErpSection(
          title: 'طباعة فاتورة البيع',
          icon: Icons.print_rounded,
          child: Wrap(spacing: 12, runSpacing: 12, children: [
            _choice('a4', 'قياسية A4', Icons.description_outlined),
            _choice('80mm', 'حرارية 80mm', Icons.receipt_long_outlined),
          ]),
        ),
        ErpSection(
          title: 'ملصقات الباركود',
          icon: Icons.qr_code_2_rounded,
          color: ErpColors.purple,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            FieldGrid(children: [
              SizedBox(width: 170, child: TextField(controller: _lw, keyboardType: TextInputType.number, decoration: _dec('عرض الملصق (مم)'))),
              SizedBox(width: 170, child: TextField(controller: _lh, keyboardType: TextInputType.number, decoration: _dec('ارتفاع الملصق (مم)'))),
            ]),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('طابعة ملصقات (ملصق لكل صفحة)'),
              subtitle: const Text('أطفئه للطباعة على ورقة A4 بعدة أعمدة'),
              value: _label!.labelPrinter,
              onChanged: (v) => setState(() => _label!.labelPrinter = v),
            ),
          ]),
        ),
        ErpSection(
          title: 'حسابات فروقات الجرد',
          icon: Icons.fact_check_rounded,
          color: ErpColors.orange,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (!_canAcc)
              const Text('تحتاج صلاحية «السندات والقيود» لتغيير الحسابات', style: TextStyle(color: ErpColors.muted)),
            Wrap(spacing: 12, runSpacing: 12, children: [
              _accBtn('حساب زيادة الجرد', _gain, 'revenue', (a) => setState(() => _gain = a)),
              _accBtn('حساب عجز الجرد', _loss, 'expense', (a) => setState(() => _loss = a)),
            ]),
            const SizedBox(height: 8),
            const Text('فارغ = «فروقات جرد المخزون». التغيير يسري على مستندات الجرد الجديدة فقط.',
                style: TextStyle(color: ErpColors.muted, fontSize: 12)),
          ]),
        ),
        ErpSection(
          title: 'باركود الميزان',
          icon: Icons.scale_rounded,
          color: ErpColors.cyan,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            FieldGrid(children: [
              SizedBox(width: 120, child: TextField(controller: _prefix, decoration: _dec('البادئة'))),
              SizedBox(width: 170, child: TextField(controller: _plu, keyboardType: TextInputType.number, decoration: _dec('أرقام رمز المادة'))),
              SizedBox(width: 170, child: TextField(controller: _val, keyboardType: TextInputType.number, decoration: _dec('أرقام القيمة'))),
              DropBox<double>(
                label: 'القيمة تمثّل',
                value: _scale!.divisor,
                items: const [
                  DropdownMenuItem(value: 1000, child: Text('الوزن بالغرام')),
                  DropdownMenuItem(value: 1, child: Text('العدد (قطع)')),
                ],
                onChanged: (v) => setState(() => _scale!.divisor = v ?? 1000),
              ),
            ]),
            const SizedBox(height: 6),
            const Text('مثال: 2 12345 00750 C ⇒ بادئة 2، رمز المادة 12345، القيمة 750.',
                style: TextStyle(color: ErpColors.muted, fontSize: 12)),
          ]),
        ),
      ]),
    );
  }

  InputDecoration _dec(String l) =>
      InputDecoration(labelText: l, border: const OutlineInputBorder(), isDense: true, filled: true, fillColor: Colors.white);

  Widget _choice(String v, String label, IconData icon) {
    final sel = _print == v;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => setState(() => _print = v),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 200,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: sel ? ErpColors.navy.withOpacity(.08) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: sel ? ErpColors.navy : ErpColors.border, width: sel ? 2 : 1),
        ),
        child: Row(children: [
          Icon(icon, color: sel ? ErpColors.navy : ErpColors.muted, size: 30),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: TextStyle(fontWeight: sel ? FontWeight.bold : FontWeight.normal))),
          if (sel) const Icon(Icons.check_circle, color: ErpColors.navy),
        ]),
      ),
    );
  }

  Widget _accBtn(String label, Account? a, String type, ValueChanged<Account?> set) => Row(mainAxisSize: MainAxisSize.min, children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.account_tree_outlined),
          label: Text(a == null ? '$label: الافتراضي' : '$label: ${a.code} ${a.name}'),
          onPressed: !_canAcc
              ? null
              : () async {
                  final x = await _pickAcc(label, type);
                  if (x != null) set(x);
                },
        ),
        if (a != null && _canAcc) IconButton(icon: const Icon(Icons.close), onPressed: () => set(null)),
      ]);
}
