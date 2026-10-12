// lib/inventory/product_entry_mode.dart
//
// ⚙️ واجهة «إدخال البضاعة» التي تفتح دائماً: الجديدة (بطاقة المادة) أو القديمة.
// تُختار من: الإعدادات ← الواجهة ← إدخال البضاعة. إعداد لكل جهاز.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/product_entry_screen.dart';
import 'item_card_editor_screen.dart';

class ProductEntryMode {
  ProductEntryMode._();
  static const _k = 'product_entry_classic';

  static Future<bool> classic() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(_k) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setClassic(bool v) async =>
      (await SharedPreferences.getInstance()).setBool(_k, v);
}

/// يفتح الواجهة المختارة في الإعدادات (المسار /product_entry)
class ProductEntryRouter extends StatelessWidget {
  const ProductEntryRouter({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: ProductEntryMode.classic(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return snap.data! ? const ProductEntryScreen() : const ItemCardEditorScreen();
      },
    );
  }
}

/// بطاقة الإعدادات: اختيار واجهة إدخال البضاعة
class ProductEntryModeTile extends StatefulWidget {
  const ProductEntryModeTile({super.key});

  @override
  State<ProductEntryModeTile> createState() => _ProductEntryModeTileState();
}

class _ProductEntryModeTileState extends State<ProductEntryModeTile> {
  bool? _classic;

  @override
  void initState() {
    super.initState();
    ProductEntryMode.classic().then((v) {
      if (mounted) setState(() => _classic = v);
    });
  }

  Future<void> _set(bool v) async {
    setState(() => _classic = v);
    await ProductEntryMode.setClassic(v);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(v
          ? 'إدخال البضاعة يفتح الآن بالواجهة القديمة.'
          : 'إدخال البضاعة يفتح الآن بالواجهة الجديدة (بطاقة المادة).'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final v = _classic;
    return Column(children: [
      RadioListTile<bool>(
        contentPadding: EdgeInsets.zero,
        title: const Text('الواجهة الجديدة (بطاقة المادة)'),
        subtitle: const Text('كل بيانات المادة في شاشة واحدة: الوحدات والأسعار والباركود والمخزن', style: TextStyle(fontSize: 12)),
        value: false,
        groupValue: v,
        onChanged: v == null ? null : (x) => _set(false),
      ),
      const Divider(height: 1),
      RadioListTile<bool>(
        contentPadding: EdgeInsets.zero,
        title: const Text('الواجهة القديمة'),
        subtitle: const Text('نموذج الإدخال السابق كما اعتدت عليه', style: TextStyle(fontSize: 12)),
        value: true,
        groupValue: v,
        onChanged: v == null ? null : (x) => _set(true),
      ),
    ]);
  }
}
