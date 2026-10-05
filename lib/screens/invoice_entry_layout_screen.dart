// lib/screens/invoice_entry_layout_screen.dart
//
// 🧩 تصميم جدول شاشة «إنشاء فاتورة» على طريقة الإداري: أي الأعمدة تظهر، عرض كل
// عمود بالبكسل، ارتفاع السطر، وإظهار/إخفاء شريط الإدخال — مع معاينة حيّة.
// (الإعدادات ← الفاتورة والطباعة ← أعمدة شاشة إنشاء الفاتورة)

import 'package:flutter/material.dart';

import '../models/invoice_entry_layout.dart';

class InvoiceEntryLayoutScreen extends StatefulWidget {
  const InvoiceEntryLayoutScreen({super.key});

  @override
  State<InvoiceEntryLayoutScreen> createState() => _InvoiceEntryLayoutScreenState();
}

class _InvoiceEntryLayoutScreenState extends State<InvoiceEntryLayoutScreen> {
  late Map<String, double> _widths;
  late Set<String> _hidden;
  double _rowHeight = 34;
  bool _showEntryBar = true;
  bool _loading = true;

  // (خريطة غير ثابتة: مفاتيح double لا تصلح في const map)
  static final _rowHeights = <double, String>{30: 'مضغوط', 38: 'عادي', 46: 'واسع'};

  @override
  void initState() {
    super.initState();
    InvoiceEntryLayout.load().then((l) {
      if (!mounted) return;
      setState(() {
        _widths = {for (final k in InvoiceEntryLayout.keys) k: l.w(k)};
        _hidden = {...l.hidden};
        _rowHeight = l.rowHeight;
        _showEntryBar = l.showEntryBar;
        _loading = false;
      });
    });
  }

  InvoiceEntryLayout get _draft => InvoiceEntryLayout(
        widths: _widths,
        hidden: _hidden,
        rowHeight: _rowHeight,
        showEntryBar: _showEntryBar,
      );

  Future<void> _save() async {
    await _draft.save();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('حُفظ تخطيط الجدول — يظهر في شاشة «إنشاء فاتورة» عند فتحها'),
      backgroundColor: Colors.green,
    ));
    Navigator.pop(context);
  }

  void _reset() => setState(() {
        _widths = {...InvoiceEntryLayout.defaultWidths};
        _hidden = {...InvoiceEntryLayout.defaultHidden};
        _rowHeight = 34;
        _showEntryBar = true;
      });

  /// إظهار كل الأعمدة دفعة واحدة (مثل شاشة الإداري الممتلئة)
  void _showAll() => setState(() => _hidden = {});

  double get _totalWidth {
    final d = _draft;
    return d
        .visibleKeys(isViewOnly: false, canSeeCost: true)
        .fold<double>(0, (a, k) => a + d.w(k));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AppBar(
        title: const Text('أعمدة شاشة إنشاء الفاتورة'),
        actions: [
          TextButton.icon(
              onPressed: _loading ? null : _showAll,
              icon: const Icon(Icons.view_column),
              label: const Text('إظهار كل الأعمدة')),
          TextButton.icon(
              onPressed: _loading ? null : _reset, icon: const Icon(Icons.restart_alt), label: const Text('الافتراضي')),
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
                  'اختر الأعمدة الظاهرة في جدول المواد وعرض كل عمود بالبكسل. إذا زاد مجموع العروض عن عرض الشاشة '
                  'يظهر شريط تمرير أفقي أسفل الجدول (مثل الإداري)، وإن قلّ يتّسع «اسم المادة» ليملأ الباقي. '
                  'اسم المادة والكمية والوحدة والسعر والإجمالي ضرورية ولا تُخفى.',
                  style: TextStyle(color: Colors.black54, height: 1.5),
                ),
                const SizedBox(height: 16),
                _generalCard(),
                const SizedBox(height: 16),
                Row(children: [
                  const Text('معاينة', style: TextStyle(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Text('مجموع عرض الأعمدة: ${_totalWidth.round()} بكسل',
                      style: const TextStyle(color: Colors.black54, fontSize: 12)),
                ]),
                const SizedBox(height: 6),
                _preview(),
                const SizedBox(height: 20),
                for (final k in InvoiceEntryLayout.keys) _columnTile(k),
              ],
            ),
    );
  }

  Widget _generalCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const SizedBox(width: 130, child: Text('ارتفاع السطر', style: TextStyle(fontWeight: FontWeight.w600))),
            Wrap(spacing: 8, children: [
              for (final e in _rowHeights.entries)
                ChoiceChip(
                  label: Text('${e.value} (${e.key.round()})'),
                  selected: _rowHeight == e.key,
                  onSelected: (_) => setState(() => _rowHeight = e.key),
                ),
            ]),
          ]),
          const Divider(height: 18),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _showEntryBar,
            onChanged: (v) => setState(() => _showEntryBar = v),
            title: const Text('شريط الإدخال فوق الجدول', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text(
              'عند إيقافه تُكتب المواد مباشرة في آخر سطر فارغ من الجدول كما في الإداري، ويبقى للجدول ارتفاع أكبر.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _preview() {
    final d = _draft;
    final shown = d.visibleKeys(isViewOnly: false, canSeeCost: true);
    return LayoutBuilder(builder: (context, box) {
      final widths = d.resolve(box.maxWidth - 2, isViewOnly: false, canSeeCost: true);
      final tableWidth = widths.values.fold<double>(0, (a, b) => a + b) + 2;
      Widget row(Map<String, String> cells, {bool header = false}) => Container(
            decoration: BoxDecoration(
              color: header ? const Color(0xFFDDE3EA) : Colors.white,
              border: Border.all(color: Colors.grey.shade400, width: 0.5),
            ),
            child: Row(children: [
              for (final k in shown)
                Container(
                  width: widths[k],
                  height: header ? 28 : _rowHeight,
                  alignment: k == 'details' ? AlignmentDirectional.centerStart : Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(border: Border(left: BorderSide(color: Colors.grey.shade300))),
                  child: Text(
                    header ? InvoiceEntryLayout.headers[k]! : (cells[k] ?? ''),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: header ? FontWeight.bold : null,
                      fontSize: _rowHeight < 34 && !header ? 12 : 13,
                      color: !header && k == 'stock' && cells[k] == '0' ? Colors.red : null,
                    ),
                  ),
                ),
            ]),
          );
      final table = SizedBox(
        width: tableWidth,
        child: Column(children: [
          row(const {}, header: true),
          row(const {
            'index': '1',
            'code': '1024',
            'details': 'قاطع 32 أمبير',
            'qty': '10',
            'saleType': 'قطعة',
            'price': '9,000',
            'listPrice': '10,000',
            'discount': '10%',
            'units': '',
            'total': '90,000',
            'stock': '140',
            'cost': '7,500',
            'profit': '15,000',
          }),
          row(const {
            'index': '2',
            'code': '2210',
            'details': 'لمبة LED 20 واط',
            'qty': '2',
            'saleType': 'كرتون',
            'price': '0',
            'listPrice': '36,000',
            'discount': 'هدية',
            'units': '24',
            'total': '0',
            'stock': '0',
            'cost': '28,000',
            'profit': '-56,000',
          }),
          row(const {}),
        ]),
      );
      if (tableWidth <= box.maxWidth) return table;
      return Scrollbar(
        thumbVisibility: true,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(bottom: 10),
          child: table,
        ),
      );
    });
  }

  Widget _columnTile(String k) {
    final locked = InvoiceEntryLayout.required.contains(k);
    final visible = locked || !_hidden.contains(k);
    final width = _widths[k] ?? InvoiceEntryLayout.defaultWidths[k] ?? 80;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Row(children: [
          Checkbox(
            value: visible,
            onChanged: locked
                ? null
                : (v) => setState(() {
                      if (v == true) {
                        _hidden.remove(k);
                      } else {
                        _hidden.add(k);
                      }
                    }),
          ),
          SizedBox(
            width: 200,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(InvoiceEntryLayout.labels[k]!,
                  style: TextStyle(fontWeight: FontWeight.w600, color: visible ? Colors.black87 : Colors.grey)),
              if (InvoiceEntryLayout.costColumns.contains(k))
                const Text('يظهر فقط لمن لديه صلاحية رؤية الكلفة والأرباح',
                    style: TextStyle(fontSize: 11, color: Colors.orange)),
              if (k == 'discount')
                const Text('إخفاؤه يخفي أيضاً حقل الخصم وزر الهدية',
                    style: TextStyle(fontSize: 11, color: Colors.black45)),
            ]),
          ),
          const Text('العرض', style: TextStyle(color: Colors.black54)),
          Expanded(
            child: Slider(
              value: width.clamp(InvoiceEntryLayout.minWidth, InvoiceEntryLayout.maxWidth).toDouble(),
              min: InvoiceEntryLayout.minWidth,
              max: InvoiceEntryLayout.maxWidth,
              divisions: ((InvoiceEntryLayout.maxWidth - InvoiceEntryLayout.minWidth) / 2).round(),
              label: '${width.round()}',
              onChanged: visible ? (v) => setState(() => _widths[k] = v.roundToDouble()) : null,
            ),
          ),
          SizedBox(width: 56, child: Text('${width.round()} px', textAlign: TextAlign.center)),
          SizedBox(
            width: 24,
            child: locked
                ? const Tooltip(
                    message: 'عمود ضروري لإدخال السطر', child: Icon(Icons.lock_outline, size: 16, color: Colors.grey))
                : null,
          ),
        ]),
      ),
    );
  }
}
