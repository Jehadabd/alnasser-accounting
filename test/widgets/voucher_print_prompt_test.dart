// test/widgets/voucher_print_prompt_test.dart
//
// 🖨️ سؤال طباعة السند (نافذة ما بعد الحفظ نفسها التي تظهر بعد تسديد دين): يعرض عنوان
// السند ورقمه والمبلغ وبياناته وسؤاله، و«طباعة» = 'print' و«لا، شكراً» = null.

import 'package:alnaser/widgets/after_save_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// يفتح النافذة ويعيد قائمة تُملأ بالاختيار عند إغلاقها.
Future<List<String?>> _open(WidgetTester tester) async {
  final results = <String?>[];
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async => results.add(await showAfterSaveDialog(
              context,
              title: 'سند قبض — تسديد فاتورة آجلة رقم 7',
              subtitle: 'الفاتورة 120  •  حساب العميل 75,000 ← 0',
              amount: '75,000 دينار',
              actions: const [kAfterSavePrint, kAfterSaveWa],
              question: 'ماذا تريد أن تفعل بالسند؟',
            )),
            child: const Text('افتح'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('افتح'));
  await tester.pumpAndSettle();
  return results;
}

void main() {
  testWidgets('يعرض السند وسؤاله، و«طباعة» يعيد print', (tester) async {
    final results = await _open(tester);
    expect(find.text('سند قبض — تسديد فاتورة آجلة رقم 7'), findsOneWidget);
    expect(find.text('75,000 دينار'), findsOneWidget);
    expect(find.text('ماذا تريد أن تفعل بالسند؟'), findsOneWidget);
    await tester.tap(find.text('طباعة'));
    await tester.pumpAndSettle();
    expect(results, ['print']);
  });

  testWidgets('«لا، شكراً» يغلق بلا طباعة', (tester) async {
    final results = await _open(tester);
    await tester.tap(find.text('لا، شكراً'));
    await tester.pumpAndSettle();
    expect(results, [null]);
  });
}
