// lib/widgets/invoice_auto_print_tile.dart
//
// 🖨️ الإعدادات ← الفاتورة والطباعة: «الطباعة التلقائية» — المفتاح نفسه الذي في
// «المزيد» بشاشة الفاتورة (invoice_auto_print_after_save)، لهذا الجهاز.
//   مفعّلة: تُطبع الفاتورة بعد الحفظ، وزر «طباعة» يرسلها فوراً إلى الطابعة
//           (المختارة هنا، وإلا طابعة ويندوز الافتراضية) بلا نوافذ.
//   مطفأة: زر «طباعة» يفتح الفاتورة PDF في العارض (إيدج عادة) لتطبعها منه.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class InvoiceAutoPrintTile extends StatefulWidget {
  const InvoiceAutoPrintTile({super.key});

  @override
  State<InvoiceAutoPrintTile> createState() => _InvoiceAutoPrintTileState();
}

class _InvoiceAutoPrintTileState extends State<InvoiceAutoPrintTile> {
  static const _key = 'invoice_auto_print_after_save';
  bool _on = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _on = p.getBool(_key) ?? false);
    });
  }

  Future<void> _set(bool v) async {
    await (await SharedPreferences.getInstance()).setBool(_key, v);
    if (mounted) setState(() => _on = v);
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: _on,
      onChanged: _set,
      title: const Text('الطباعة التلقائية', style: TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        _on
            ? 'تُطبع الفاتورة بعد الحفظ، وزر «طباعة» يرسلها فوراً إلى الطابعة المختارة أدناه '
                '(وإلا طابعة ويندوز الافتراضية) بلا أي نافذة.'
            : 'زر «طباعة» يفتح الفاتورة PDF في المتصفح لتطبعها منه، ولا تُطبع بعد الحفظ.',
        style: const TextStyle(fontSize: 12, height: 1.5),
      ),
    );
  }
}
