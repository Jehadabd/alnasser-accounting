import 'package:alnaser/owner/wa_auto/wa_usage_mark.dart';
import 'package:flutter_test/flutter_test.dart';

WaUsage _u(DateTime first, DateTime last, String mode, int sends, {int events = 1}) => WaUsage(
    first: first, last: last, firstMode: mode, firstUser: 'u', modes: {mode}, events: events, sends: sends);

void main() {
  test('الدمج يحتفظ بأقدم بداية وأحدث استعمال وأكبر عدّاد — لا ينقص شيئاً', () {
    final a = _u(DateTime(2026, 1, 1), DateTime(2026, 2, 1), 'desktop', 10, events: 3);
    final b = _u(DateTime(2026, 3, 1), DateTime(2026, 6, 1), 'server', 4, events: 5);
    final m = WaUsage.merge([null, b, a])!;
    expect(m.first, DateTime(2026, 1, 1));
    expect(m.firstMode, 'desktop');
    expect(m.last, DateTime(2026, 6, 1));
    expect(m.modes, {'desktop', 'server'});
    expect(m.sends, 10);
    expect(m.events, 5);
  });

  test('لا علامة في أي مكان ⇒ null', () {
    expect(WaUsage.merge([null, null]), isNull);
    expect(WaUsage.fromJson('not json'), isNull);
  });

  test('تُحفظ وتُقرأ كما هي', () {
    final a = _u(DateTime(2026, 1, 1, 10), DateTime(2026, 2, 1), 'server', 7);
    final back = WaUsage.fromJson('{"first":"2026-01-01T10:00:00.000","last":"2026-02-01T00:00:00.000",'
        '"firstMode":"server","firstUser":"u","modes":["server"],"events":1,"sends":7}')!;
    expect(back.toJson(), a.toJson());
  });
}
