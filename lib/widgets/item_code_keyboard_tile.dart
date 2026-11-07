// lib/widgets/item_code_keyboard_tile.dart
//
// ⚙️ الإعدادات ← الواجهة: «رمز المادة بالإنجليزية تلقائياً»

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../services/keyboard_layout/keyboard_layout.dart';
import '../services/product_codes.dart' show ItemCodeKeyboard;

class ItemCodeKeyboardTile extends StatefulWidget {
  const ItemCodeKeyboardTile({super.key});

  @override
  State<ItemCodeKeyboardTile> createState() => _ItemCodeKeyboardTileState();
}

class _ItemCodeKeyboardTileState extends State<ItemCodeKeyboardTile> {
  String? _test;
  bool _testing = false;

  Future<void> _runTest() async {
    setState(() {
      _testing = true;
      _test = null;
    });
    final r = await KeyboardLayoutSwitcher.selfTest();
    if (mounted) {
      setState(() {
        _testing = false;
        _test = r;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final windows = !kIsWeb && Platform.isWindows;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      _switch(windows),
      if (windows)
        Row(children: [
          OutlinedButton.icon(
            onPressed: _testing ? null : _runTest,
            icon: _testing
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.science_outlined, size: 18),
            label: const Text('اختبار التحويل'),
          ),
          const SizedBox(width: 10),
          if (_test != null)
            Expanded(
              child: Text(_test!,
                  style: TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: _test!.startsWith('يعمل') ? const Color(0xFF047857) : const Color(0xFFB45309))),
            ),
        ]),
    ]);
  }

  Widget _switch(bool windows) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('الكتابة في «رمز المادة» بالإنجليزية تلقائياً',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      subtitle: Text(
        windows
            ? 'في خانة «رمز المادة» (جدول إنشاء فاتورة، وإدخال البضاعة، وبطاقة المادة): عند دخولها '
                'تتحول لوحة المفاتيح للإنجليزية، وعند الخروج تعود اللغة التي كانت — بلا Alt+Shift. '
                'مطفأ = تبقى اللغة كما هي.'
            : 'متاح على ويندوز فقط.',
        style: const TextStyle(fontSize: 12),
      ),
      value: ItemCodeKeyboard.forceEnglish,
      onChanged: !windows
          ? null
          : (v) async {
              await ItemCodeKeyboard.set(v);
              if (mounted) setState(() {});
            },
    );
  }
}
