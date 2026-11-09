// lib/wa_messages/wa_phone_book_screen.dart
//
// 📒 قائمة «أرقام واتساب المؤكَّدة»: لمن تُرسل المستندات مباشرة بلا سؤال. حذف رقم ⇒ يُسأل عنه
// في الإرسال القادم.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../widgets/settings_kit.dart';
import 'wa_phone_book.dart';

class WaPhoneBookScreen extends StatefulWidget {
  const WaPhoneBookScreen({super.key});
  @override
  State<WaPhoneBookScreen> createState() => _WaPhoneBookScreenState();
}

class _WaPhoneBookScreenState extends State<WaPhoneBookScreen> {
  List<WaConfirmedPhone>? _list;
  static final _d = DateFormat('yyyy/MM/dd', 'en');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await WaPhoneBook.all();
    if (mounted) setState(() => _list = l);
  }

  Future<void> _remove(WaConfirmedPhone p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('حذف رقم ${p.name}؟'),
        content: Text('${p.phone}\nفي الإرسال القادم لهذا العميل يُسأل عن الرقم من جديد.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    await WaPhoneBook.remove(p.key);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = _list;
    return SettingsScaffold(
      title: 'أرقام واتساب المؤكَّدة',
      icon: Icons.verified_user_rounded,
      subtitle: 'تُرسل لهم الفواتير والكشوفات والسندات مباشرة',
      children: [
        const SetBanner('أول إرسال لكل عميل يُسأل فيه عن الرقم. بعد التأكيد يُرسل له مباشرة — إلا إذا '
            'ظهر للمستند رقم مختلف فيُسأل من جديد. لا يغيّر رقم العميل في سجل الديون.'),
        const SizedBox(height: 10),
        if (l == null)
          const LinearProgressIndicator()
        else if (l.isEmpty)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('لا أرقام مؤكَّدة بعد')))
        else
          for (final p in l)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(p.byCustomer ? Icons.person_rounded : Icons.person_outline_rounded),
              title: Text(p.name.isEmpty ? p.key : p.name),
              subtitle: Text([
                p.phone,
                if (!p.byCustomer) 'بالاسم (ليس عميلاً مسجّلاً)',
                if (p.at != null) 'أُكِّد ${_d.format(p.at!)}',
                if (p.by.isNotEmpty) p.by,
              ].join(' • '), textDirection: TextDirection.rtl),
              trailing: IconButton(
                tooltip: 'حذف — يُسأل عنه مرة أخرى',
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () => _remove(p),
              ),
            ),
        const SizedBox(height: 40),
      ],
    );
  }
}
