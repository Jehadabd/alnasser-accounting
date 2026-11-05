// test/services/upload_eta_test.dart
// ⏱️ تقدير زمن الرفع: قيم أولى معقولة، ويتعلّم من القياس، ويُحفظ ويُقرأ.
// التشغيل: flutter test test/services/upload_eta_test.dart

import 'package:alnaser/services/upload_eta.dart';
import 'package:alnaser/services/upload_targets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const mb = 1024 * 1024;

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('defaults are positive and scale with size', () async {
    final e = await UploadEta.load();
    expect(e.estimateBuildMs(33 * mb), greaterThan(0));
    final small = e.estimateTargetMs(UploadTargets.dropbox, 1 * mb, withTelegram: false);
    final big = e.estimateTargetMs(UploadTargets.dropbox, 10 * mb, withTelegram: false);
    expect(big, greaterThan(small));
    // ديسكورد مع تيليجرام نسخة في الخلفية
    expect(e.estimateTargetMs(UploadTargets.discord, 10 * mb, withTelegram: true), lessThan(1000));
    expect(e.estimateInvoicesMs(0), 0);
  });

  test('learns from measurements and persists them', () async {
    final e = await UploadEta.load();
    e.recordBuild(dbBytes: 33 * mb, ms: 22000, compressed: 4 * mb);
    expect(e.estimateCompressed(33 * mb), closeTo(4 * mb, mb * 0.01));
    expect(e.estimateBuildMs(33 * mb), closeTo(22000, 5));
    e.recordTarget(UploadTargets.dropbox, ms: 4000 + 8000, compressed: 4 * mb, withTelegram: false);
    // الثابت 4000 + 2000 لكل ميغا ⇒ 4 ميغا = 12000
    expect(e.estimateTargetMs(UploadTargets.dropbox, 4 * mb, withTelegram: false), closeTo(12000, 5));
    e.recordInvoices(count: 10, ms: 5000);
    expect(e.estimateInvoicesMs(4), closeTo(2000, 1));
    await e.save();

    final again = await UploadEta.load();
    expect(again.estimateBuildMs(33 * mb), closeTo(22000, 5));
    expect(again.estimateTargetMs(UploadTargets.dropbox, 4 * mb, withTelegram: false), closeTo(12000, 5));
  });

  test('moving average follows newer speed', () async {
    final e = await UploadEta.load();
    e.recordInvoices(count: 1, ms: 1000);
    e.recordInvoices(count: 1, ms: 2000);
    // 1000×0.6 + 2000×0.4 = 1400
    expect(e.estimateInvoicesMs(1), 1400);
  });
}
