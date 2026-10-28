// lib/widgets/item_code_keyboard_tile.dart
//
// ⚙️ الإعدادات ← الواجهة: «رمز المادة بالإنجليزية تلقائياً»

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../services/product_codes.dart' show ItemCodeKeyboard;

class ItemCodeKeyboardTile extends StatefulWidget {
  const ItemCodeKeyboardTile({super.key});

  @override
  State<ItemCodeKeyboardTile> createState() => _ItemCodeKeyboardTileState();
}

class _ItemCodeKeyboardTileState extends State<ItemCodeKeyboardTile> {
  @override
  Widget build(BuildContext context) {
    final windows = !kIsWeb && Platform.isWindows;
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('الكتابة في «رمز المادة» بالإنجليزية تلقائياً',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      subtitle: Text(
        windows
            ? 'في جدول إنشاء فاتورة: عند دخول خانة الرمز تتحول لوحة المفاتيح للإنجليزية، '
                'وعند الخروج منها تعود للغة التي كانت (عربية أو إنجليزية) — بلا Alt+Shift.'
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
