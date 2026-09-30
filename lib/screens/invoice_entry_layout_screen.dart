// lib/screens/invoice_entry_layout_screen.dart
//
// 🧩 تصميم جدول شاشة «إنشاء فاتورة»: أي الأعمدة تظهر وعرض كل عمود، مع معاينة حيّة.
// (الإعدادات ← الفاتورة والطباعة ← أعمدة شاشة إنشاء الفاتورة)

import 'package:flutter/material.dart';

import '../models/invoice_entry_layout.dart';

class InvoiceEntryLayoutScreen extends StatefulWidget {
  const InvoiceEntryLayoutScreen({super.key});

  @override
  State<InvoiceEntryLayoutScreen> createState() => _InvoiceEntryLayoutScreenState();
}

class _InvoiceEntryLayoutScreenState extends State<InvoiceEntryLayoutScreen> {
  late Map<String, int> _flex;
  late Set<String> _hidden;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    InvoiceEntryLayout.load().then((l) {
      if (!mounted) return;
      setState(() {
        _flex = {for (final k in InvoiceEntryLayout.keys) k: l.f(k)};
        _hidden = {...l.hidden};
        _loading = false;
      });
    });
  }

  Future<void> _save() async {
    await InvoiceEntryLayout(flex: _flex, hidden: _hidden).save();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('حُفظ تخطيط الجدول — يظهر في شاشة «إنشاء فاتورة» عند فتحها'),
      backgroundColor: Colors.green,
    ));
    Navigator.pop(context);
  }

  void _reset() => setState(() {
        _flex = {...InvoiceEntryLayout.defaultFlex};
        _hidden = {};
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AppBar(
        title: const Text('أعمدة شاشة إنشاء الفاتورة'),
        actions: [
          TextButton.icon(onPressed: _loading ? null : _reset, icon: const Icon(Icons.restart_alt), label: const Text('الافتراضي')),
          const SizedBox(width: 8),
          FilledButton.icon(onPressed: _loading ? null : _save, icon: const Icon(Icons.save), label: const Text('حفظ')),
          const SizedBox(width: 12),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'اختر الأعمدة الظاهرة في جدول المواد وعرض كل عمود. التفاصيل والعدد ونوع البيع والسعر والإجمالي ضرورية ولا تُخفى. '
                  'إخفاء عمود «الخصم» يُخفي أيضاً حقل الخصم وزر الهدية من شريط الإدخال.',
                  style: TextStyle(color: Colors.black54, height: 1.5),
                ),
                const SizedBox(height: 16),
                // معاينة حيّة
                const Text('معاينة', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                _preview(),
                const SizedBox(height: 20),
                for (final k in InvoiceEntryLayout.keys) _columnTile(k),
              ],
            ),
    );
  }

  Widget _preview() {
    final shown = InvoiceEntryLayout.keys.where((k) => !_hidden.contains(k)).toList();
    Widget row(Map<String, String> cells, {bool header = false}) => Container(
          decoration: BoxDecoration(
            color: header ? Colors.grey.shade200 : Colors.white,
            border: Border.all(color: Colors.grey.shade400),
          ),
          child: Row(children: [
            for (final k in shown)
              Expanded(
                flex: _flex[k]!,
                child: Container(
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(border: Border(left: BorderSide(color: Colors.grey.shade300))),
                  child: Text(cells[k] ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: header ? FontWeight.bold : null, fontSize: 13)),
                ),
              ),
          ]),
        );
    return Column(children: [
      row(InvoiceEntryLayout.headers, header: true),
      row(const {
        'index': '1',
        'details': 'قاطع 32 أمبير',
        'qty': '10',
        'saleType': 'قطعة',
        'price': '9,000',
        'discount': '10%',
        'units': '',
        'total': '90,000',
      }),
      row(const {
        'index': '2',
        'details': 'لمبة LED 20 واط',
        'qty': '2',
        'saleType': 'كرتون',
        'price': '0',
        'discount': 'هدية',
        'units': '24',
        'total': '0',
      }),
    ]);
  }

  Widget _columnTile(String k) {
    final canHide = InvoiceEntryLayout.hideable.contains(k);
    final visible = !_hidden.contains(k);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(children: [
          Checkbox(
            value: visible,
            onChanged: canHide
                ? (v) => setState(() {
                      if (v == true) {
                        _hidden.remove(k);
                      } else {
                        _hidden.add(k);
                      }
                    })
                : null,
          ),
          SizedBox(
            width: 190,
            child: Text(InvoiceEntryLayout.labels[k]!,
                style: TextStyle(fontWeight: FontWeight.w600, color: visible ? Colors.black87 : Colors.grey)),
          ),
          const Text('العرض', style: TextStyle(color: Colors.black54)),
          Expanded(
            child: Slider(
              value: _flex[k]!.toDouble(),
              min: 1,
              max: 12,
              divisions: 11,
              label: '${_flex[k]}',
              onChanged: visible ? (v) => setState(() => _flex[k] = v.round()) : null,
            ),
          ),
          SizedBox(width: 28, child: Text('${_flex[k]}', textAlign: TextAlign.center)),
          if (!canHide)
            const Tooltip(message: 'عمود ضروري لإدخال السطر', child: Icon(Icons.lock_outline, size: 16, color: Colors.grey)),
        ]),
      ),
    );
  }
}
