// test/barcode/scan_burst_test.dart
//
// تمييز قارئ الباركود عن كتابة الإنسان، وقراءة الحروف من موضع المفتاح لا من لغة الكتابة.

import 'package:alnaser/services/barcode/scan_burst.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Duration ms(int v) => Duration(milliseconds: v);

void main() {
  ScanBurstDetector det() => ScanBurstDetector(maxGap: ms(40), minLength: 4);

  /// يكتب [s] بفاصل [gap] بدءاً من [t0] ويعيد الخطوات والوقت التالي.
  (List<BurstStep>, int) type(ScanBurstDetector d, String s, {int t0 = 1000, int gap = 10}) {
    final out = <BurstStep>[];
    var t = t0;
    for (final c in s.split('')) {
      out.add(d.char(c, c, ms(t)));
      t += gap;
    }
    return (out, t);
  }

  test('القارئ: رشقة سريعة ثم Enter ⇒ رمز، وكل حرف بعد الأول محجوز', () {
    final d = det();
    final (steps, t) = type(d, '6281000000017');
    expect(steps.first.snapshot, isTrue);
    expect(steps.first.swallow, isFalse); // الأول يمر (لا نعرف بعد من يكتب)
    expect(steps.skip(1).every((s) => s.swallow), isTrue);
    final end = d.terminator(ms(t));
    expect(end.code, '6281000000017');
    expect(end.swallow, isTrue); // Enter لا يصل للخانة
    expect(d.active, isFalse);
  });

  test('الإنسان: كتابة بطيئة لا تُحجز ولا تُعدّ رمزاً', () {
    final d = det();
    final (steps, t) = type(d, '1234', gap: 150);
    expect(steps.every((s) => !s.swallow && s.flush.isEmpty), isTrue);
    final end = d.terminator(ms(t));
    expect(end.code, isNull);
    expect(end.swallow, isFalse); // Enter يصل للخانة كالمعتاد
  });

  test('إنسان كتب حرفين بسرعة صدفة: الحرف المحجوز يُعاد للخانة ولا يضيع', () {
    final d = det();
    d.char('a', 'a', ms(1000));
    expect(d.char('b', 'b', ms(1020)).swallow, isTrue);
    final next = d.char('c', 'c', ms(1200)); // توقف ⇒ كتابة إنسان
    expect(next.flush, 'b');
    expect(next.snapshot, isTrue);
    expect(next.swallow, isFalse);
  });

  test('رمز قصير أقل من الحد الأدنى + Enter ⇒ ليس رمزاً، والمحجوز يُعاد', () {
    final d = det();
    final (_, t) = type(d, 'ab');
    final end = d.terminator(ms(t));
    expect(end.code, isNull);
    expect(end.flush, 'b');
    expect(end.swallow, isFalse);
  });

  test('Enter متأخر بعد رشقة سريعة ⇒ ليس رمزاً', () {
    final d = det();
    final (_, t) = type(d, '12345678');
    final end = d.terminator(ms(t + 200));
    expect(end.code, isNull);
    expect(end.flush, '2345678');
  });

  test('مفتاح آخر (سهم/حذف) يقطع الرشقة ويعيد المحجوز', () {
    final d = det();
    type(d, 'xyz');
    final o = d.other();
    expect(o.flush, 'yz');
    expect(d.active, isFalse);
  });

  test('قارئ بلا Enter: 8 حروف فأكثر ثم توقف ⇒ رمز', () {
    final d = det();
    final (_, t) = type(d, '12345678');
    expect(d.idle(ms(t + 5)).code, isNull); // لم يحن التوقف بعد
    final st = d.idle(ms(t + 200));
    expect(st.code, '12345678');
    expect(st.flush, isEmpty);
  });

  test('بلا Enter وقصير ⇒ كتابة إنسان: يُعاد المحجوز', () {
    final d = det();
    final (_, t) = type(d, '12345');
    final st = d.idle(ms(t + 200));
    expect(st.code, isNull);
    expect(st.flush, '2345');
  });

  test('الحرف المكتوب بالعربية يُعاد كما هو، والرمز من موضع المفتاح', () {
    final d = det();
    d.char('a', 'ش', ms(1000));
    d.char('b', 'لا', ms(1010));
    d.char('c', 'ؤ', ms(1020));
    d.char('1', '1', ms(1030));
    expect(d.firstTyped, 'ش');
    expect(d.terminator(ms(1040)).code, 'abc1');
  });

  test('رشقة أطول من 64 حرفاً ليست مسحاً', () {
    final d = det();
    final (steps, _) = type(d, List.filled(70, '7').join());
    expect(steps[64].swallow, isFalse); // بعد الحد تبدأ رشقة جديدة
    expect(steps[64].flush.length, 63);
  });

  test('ساعة رجعت للخلف لا تكسر الحساب', () {
    final d = det();
    d.char('1', '1', ms(1000));
    expect(d.char('2', '2', ms(990)).swallow, isTrue);
  });

  group('حروف المفاتيح على التخطيط الإنجليزي', () {
    test('أرقام وحروف ورموز', () {
      expect(usKeyChar(PhysicalKeyboardKey.digit1, shift: false), '1');
      expect(usKeyChar(PhysicalKeyboardKey.digit0, shift: false), '0');
      expect(usKeyChar(PhysicalKeyboardKey.digit0, shift: true), ')');
      expect(usKeyChar(PhysicalKeyboardKey.digit2, shift: true), '@');
      expect(usKeyChar(PhysicalKeyboardKey.keyA, shift: false), 'a');
      expect(usKeyChar(PhysicalKeyboardKey.keyZ, shift: true), 'Z');
      expect(usKeyChar(PhysicalKeyboardKey.minus, shift: false), '-');
      expect(usKeyChar(PhysicalKeyboardKey.slash, shift: false), '/');
      expect(usKeyChar(PhysicalKeyboardKey.period, shift: false), '.');
      expect(usKeyChar(PhysicalKeyboardKey.numpad7, shift: false), '7');
      expect(usKeyChar(PhysicalKeyboardKey.numpad0, shift: false), '0');
      expect(usKeyChar(PhysicalKeyboardKey.numpadDecimal, shift: false), '.');
    });

    test('مفاتيح ليست حروفاً', () {
      expect(usKeyChar(PhysicalKeyboardKey.enter, shift: false), isNull);
      expect(usKeyChar(PhysicalKeyboardKey.arrowLeft, shift: false), isNull);
      expect(usKeyChar(PhysicalKeyboardKey.backspace, shift: false), isNull);
      expect(usKeyChar(PhysicalKeyboardKey.f2, shift: false), isNull);
    });

    test('الإنهاء والتعديل', () {
      expect(isScanTerminator(PhysicalKeyboardKey.enter), isTrue);
      expect(isScanTerminator(PhysicalKeyboardKey.numpadEnter), isTrue);
      expect(isScanTerminator(PhysicalKeyboardKey.tab), isTrue);
      expect(isScanTerminator(PhysicalKeyboardKey.keyA), isFalse);
      expect(isScanModifier(PhysicalKeyboardKey.shiftLeft), isTrue);
      expect(isScanModifier(PhysicalKeyboardKey.capsLock), isTrue);
      expect(isScanModifier(PhysicalKeyboardKey.keyA), isFalse);
    });
  });
}
