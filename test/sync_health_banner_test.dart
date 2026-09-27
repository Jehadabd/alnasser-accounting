// شريط تنبيهات صحة المزامنة: لا شيء حين يكون كل شيء سليماً، والتنبيهات
// تظهر بعناوينها، وتنبيه الدمج يُخفى بزر «تمت المراجعة».
//   flutter test test/sync_health_banner_test.dart

import 'package:alnaser/services/firebase_sync/sync_health.dart';
import 'package:alnaser/widgets/sync_health_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget app() => const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: SyncHealthBanner()),
        ),
      );

  testWidgets('لا شريط حين يكون كل شيء سليماً، ويظهر التنبيه ويُخفى تنبيه الدمج', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.byType(Container), findsNothing);

    SyncHealth.setDeviceVersions(older: ['حاسوب المخزن'], newer: const []);
    await SyncHealth.addMergeNotice(id: 'prod_x', productName: 'سكر');
    await tester.pumpAndSettle();
    expect(find.textContaining('حاسوب المخزن'), findsOneWidget);
    expect(find.textContaining('«سكر»'), findsOneWidget);
    // التنبيه الذي يزول بزوال سببه لا زر له؛ تنبيه الدمج له زر
    expect(find.text('تمت المراجعة'), findsOneWidget);

    await tester.tap(find.text('تمت المراجعة'));
    await tester.pumpAndSettle();
    expect(find.textContaining('«سكر»'), findsNothing);
    expect(find.textContaining('حاسوب المخزن'), findsOneWidget);

    SyncHealth.setDeviceVersions(older: const [], newer: const []);
    await tester.pumpAndSettle();
    expect(find.textContaining('حاسوب المخزن'), findsNothing);
  });
}
