// test/services/ai_invoice_pos_extras_test.dart
//
// بكود البرنامج نفسه:
//   📅 الصلاحية في فاتورة المورد: تطبيع كل صيغها، وقراءتها لكل سطر (فارغة إن لم تُكتب)
//   🖼️ فاتورة من عدة صور: تُقرأ كلها فاتورةً واحدة (دفعات بحد المزوّد ثم دمج الأسطر)
//   🙈 رسائل القراءة بلا اسم نموذج أو مزوّد
//   ⏳ تقدير مدة القراءة من عدد الصفحات
//   🆕 تعريف المادة الجديدة من سطرها عند الحفظ (الوحدة الأصغر، التعبئة، الكلفة، الصلاحية)
//   🧩 أعمدة سلة الكاشير وعرضها وعرض مساحة السلة
// التشغيل: flutter test test/services/ai_invoice_pos_extras_test.dart

import 'dart:convert';
import 'dart:typed_data';

import 'package:alnaser/owner/ai_invoice/ai_invoice_engine.dart';
import 'package:alnaser/owner/ai_invoice/ai_invoice_service.dart';
import 'package:alnaser/owner/ai_invoice/ai_purchase_invoice_screen.dart' show AiReadEstimate;
import 'package:alnaser/owner/ai_invoice/ai_purchase_prefill.dart';
import 'package:alnaser/screens/pos/pos_cart_layout.dart';
import 'package:alnaser/screens/purchase_new_item_spec.dart';
import 'package:alnaser/services/ai_models/ai_models_config.dart';
import 'package:alnaser/services/ai_models/ai_router.dart';
import 'package:alnaser/services/ai_models/ai_vision_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('📅 الصلاحية', () {
    test('كل الصيغ ⇒ yyyy-MM-dd، والشهر بلا يوم من أوله', () {
      final n = AiInvoiceService.normalizeExpiry;
      expect(n('2028-09-01'), '2028-09-01');
      expect(n('2028/9/1'), '2028-09-01');
      expect(n('01/09/2028'), '2028-09-01'); // كما في فاتورة الصيدلية: يوم/شهر/سنة
      expect(n('1-3-2027'), '2027-03-01');
      expect(n('01.04.2029'), '2029-04-01');
      expect(n('09/2028'), '2028-09-01');
      expect(n('2028-09'), '2028-09-01');
      expect(n('9/28'), '2028-09-01');
      expect(n('٠١/٠٩/٢٠٢٨'), '2028-09-01');
      expect(n('2028-09-01T00:00:00'), '2028-09-01');
    });

    test('فارغ أو نص أو تاريخ مستحيل ⇒ null (العمود يبقى فارغاً)', () {
      final n = AiInvoiceService.normalizeExpiry;
      for (final v in [null, '', 'null', '-', '—', 'CF0352', '31/02/2028', '13/2028', '01/09/1990', 'A5D62']) {
        expect(n(v), isNull, reason: '$v');
      }
    });

    test('القراءة تحمل صلاحية كل سطر، وغير المكتوبة null', () {
      final r = AiInvoiceService.parse({
        'line_items': [
          {'name': 'ACETAMOL COLD&FLU', 'qty': 3, 'price': 1735, 'amount': 5205, 'expiry': '2028-09-01'},
          {'name': 'AMOCLAN 400MG', 'qty': 3, 'price': 10430, 'amount': 31290, 'expiry': null},
          {'name': 'CONGESTOP', 'qty': 2, 'price': 6300, 'amount': 12600, 'exp_date': '01/07/2027'},
        ],
      });
      expect(r.lines.map((l) => l.expiry), ['2028-09-01', null, '2027-07-01']);
    });

    test('التعليمات تطلب الصلاحية ولا تخلطها برقم الدفعة', () {
      final reader = AiInvoiceEngine.buildReaderPrompt();
      expect(reader, contains('"expiry": null'));
      expect(reader, contains('B.No'));
      final full = AiInvoiceService.buildPrompt(products: const [], aliases: const [], supplierId: null);
      expect(full, contains('"expiry": null'));
      expect(full, contains('عمود «هدية»'));
    });
  });

  group('🖼️ عدة صور ورسائل بلا اسم نموذج', () {
    setUp(() {
      AiRouter.resetForTest();
      AiRouter.retryDelay = Duration.zero;
      AiRouter.maxQuotaWait = Duration.zero;
      AiVisionClient.clientForTest = null;
    });

    test('4 صور ⇒ دفعتان بحد Groq (3 + 1) وتُدمج الأسطر، والرسائل بلا اسم', () async {
      SharedPreferences.setMockInitialValues({});
      AiModelsStore.memorySecureForTest = {};
      AiModelsStore.resetForTest();
      await AiModelsStore.saveConfig(
          AiModelsConfig(models: [AiModelEntry(provider: AiProvider.groq, model: 'qwen/vision-x', label: 'Qwen')]));
      await AiModelsStore.addKey(AiProvider.groq, 'gsk_test_0123456789');
      final imagesPerCall = <int>[];
      AiVisionClient.clientForTest = MockClient((req) async {
        final body = utf8.decode(req.bodyBytes);
        final n = RegExp(r'"image_url":\{').allMatches(body).length; // مفتاح الصورة لا قيمة «type»
        imagesPerCall.add(n);
        final first = imagesPerCall.length == 1;
        return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': jsonEncode({
                      'line_items': [
                        first
                            ? {'original_name': 'XQZ-1', 'qty': 2, 'price': 1000, 'amount': 2000, 'expiry': '01/02/2028'}
                            : {'original_name': 'XQZ-2', 'qty': 1, 'price': 500, 'amount': 500},
                      ],
                    })
                  }
                }
              ]
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      });
      final statuses = <String>[];
      Uint8List img(int b) => Uint8List.fromList([137, 80, 78, 71, b]);
      final r = await AiInvoiceEngine.run(
        bytes: img(1),
        mimeType: 'image/png',
        moreImages: [AiBlob(img(2), 'image/png'), AiBlob(img(3), 'image/png'), AiBlob(img(4), 'image/png')],
        products: const [],
        aliases: const [],
        supplierId: null,
        onStatus: statuses.add,
      );
      expect(imagesPerCall, [3, 1]); // كل الصور قُرئت
      expect(r.lines.map((l) => l.originalName), ['XQZ-1', 'XQZ-2']);
      expect(r.lines.first.expiry, '2028-02-01');
      expect(r.lines.last.expiry, isNull);
      expect(statuses, isNotEmpty);
      for (final s in statuses) {
        expect(s, isNot(contains('Qwen')));
        expect(s, isNot(contains('qwen')));
        expect(s, isNot(contains('Groq')));
      }
    });

    test('رسالة انتظار المزوّد تفقد اسمه وتبقي المدة', () {
      expect(AiInvoiceEngine.waitStatus('انتظار حد الدقيقة في Groq (12 ثانية)…'), 'ينتظر قليلاً (12 ثانية)…');
      expect(AiInvoiceEngine.waitStatus('Gemini مشغول'), 'ينتظر قليلاً…');
    });
  });

  group('⏳ تقدير المدة', () {
    test('عدد صفحات PDF من بنيته، والمدة تكبر مع الصفحات ولها حد', () {
      final pdf = Uint8List.fromList(latin1.encode(
          '%PDF-1.4 1 0 obj <</Type /Pages /Count 3>> 2 0 obj <</Type /Page>> 3 0 obj <</Type/Page >> 4 0 obj <</Type /Page>>'));
      expect(AiReadEstimate.pdfPages(pdf), 3);
      expect(AiReadEstimate.pdfPages(Uint8List.fromList([1, 2, 3])), 1);
      expect(AiReadEstimate.seconds(1), 32);
      expect(AiReadEstimate.seconds(3), greaterThan(AiReadEstimate.seconds(1)));
      expect(AiReadEstimate.seconds(100), 240);
    });
  });

  group('🆕 مادة جديدة من سطرها', () {
    test('الوحدة المختارة بتعبئة 1 = أصغر وحدة، والكلفة والصلاحية منها', () {
      final p = PurchaseNewItemSpec.build(
        name: ' LIBRAX 5/2.5MG 30 DRAGEES ',
        unitName: 'علبة',
        factor: 1,
        baseCostIqd: 7250,
        expiryDate: '2028-03-01',
        now: DateTime(2026, 11, 27),
      )!;
      expect(p.name, 'LIBRAX 5/2.5MG 30 DRAGEES');
      expect(p.unit, 'علبة');
      expect(jsonDecode(p.unitHierarchy!), isEmpty);
      expect(p.costPrice, 7250);
      expect(p.price1, 0); // سعر البيع يُكتب بعد نجاح الفاتورة بمساره المعتاد
      expect(p.stockQuantity, 0); // الكمية تدخل مع الفاتورة نفسها
      expect(p.hasExpiry, isTrue);
      expect(p.alertUnit, 'علبة');
    });

    test('كرتون × 24 ⇒ الأصغر قطعة والكرتون فوقها، والقطعة تُخزَّن piece', () {
      final p = PurchaseNewItemSpec.build(name: 'كوب ماء', unitName: 'كرتون', factor: 24, baseCostIqd: 250)!;
      expect(p.unit, 'piece');
      expect(jsonDecode(p.unitHierarchy!), [
        {'unit_name': 'كرتون', 'quantity': 24},
      ]);
      expect(p.costPrice, 250);
      expect(p.hasExpiry, isFalse);
      expect(PurchaseNewItemSpec.storedUnit('متر'), 'meter');
    });

    test('وحدات المراجعة إن عُرّفت تُعتمد كما هي', () {
      const plan = AiUnitPlan(baseUnit: 'قطعة', levels: [
        {'unit_name': 'باكيت', 'quantity': 10},
        {'unit_name': 'كرتون', 'quantity': 10},
      ], baseCost: 10);
      final p = PurchaseNewItemSpec.build(name: 'x', unitName: 'كرتون', factor: 100, baseCostIqd: 10, plan: plan)!;
      expect(jsonDecode(p.unitHierarchy!), [
        {'unit_name': 'باكيت', 'quantity': 10},
        {'unit_name': 'كرتون', 'quantity': 10},
      ]);
    });

    test('متناقض أو بلا اسم ⇒ لا تعريف تلقائي (يطلب «عرّفها»)', () {
      expect(PurchaseNewItemSpec.build(name: 'x', unitName: 'قطعة', factor: 12, baseCostIqd: 1), isNull);
      expect(PurchaseNewItemSpec.build(name: '  ', unitName: 'علبة', factor: 1, baseCostIqd: 1), isNull);
      expect(PurchaseNewItemSpec.build(name: 'x', unitName: '', factor: 1, baseCostIqd: 0)!.unit, 'piece');
      expect(PurchaseNewItemSpec.build(name: 'x', unitName: 'علبة', factor: 1, baseCostIqd: 0)!.costPrice, isNull);
    });
  });

  group('🧩 سلة الكاشير', () {
    test('الافتراضي: الأعمدة الأساسية، والاسم يملأ الباقي', () {
      final l = PosCartLayout();
      expect(l.visibleKeys, ['index', 'name', 'unit', 'price', 'qty', 'total']);
      final cols = l.resolve(600);
      expect(cols.values.fold<double>(0, (a, b) => a + b), 600);
      expect(cols['name'], 600 - (34 + 86 + 92 + 104 + 96));
    });

    test('الأعمدة الضرورية لا تُخفى، والعرض مقيّد بحدوده', () {
      final l = PosCartLayout(hidden: {'price', 'qty', 'unit'}, widths: {'qty': 10, 'total': 9999});
      expect(l.show('price'), isTrue);
      expect(l.show('qty'), isTrue);
      expect(l.show('unit'), isFalse);
      expect(l.w('qty'), PosCartLayout.minWidths['qty']);
      expect(l.w('total'), PosCartLayout.maxWidth);
    });

    test('أعمدة أعرض من السلة ⇒ لا تنكمش (تمرير أفقي)', () {
      final l = PosCartLayout(hidden: {}, widths: {'name': 200});
      final cols = l.resolve(300);
      expect(cols.length, 8);
      expect(cols['name'], 200);
    });

    test('عرض السلة: المحفوظ ضمن حدود الشاشة، والإعادة للافتراضي', () {
      final l = PosCartLayout(cartWidth: 900);
      // 1400 − 176 أقسام − 300 أقل مساحة للمواد = 924
      expect(l.resolveCartWidth(1400, fallback: 420, reserved: 176), 900);
      expect(l.resolveCartWidth(1100, fallback: 420, reserved: 176), 1100 - 176 - 300);
      expect(PosCartLayout(cartWidth: 100).resolveCartWidth(1400, fallback: 420), PosCartLayout.minCartWidth);
      expect(l.copyWith(resetCartWidth: true).resolveCartWidth(1400, fallback: 420), 420);
    });

    test('يُحفظ ويُقرأ كما هو', () async {
      SharedPreferences.setMockInitialValues({});
      await PosCartLayout(hidden: {'unit'}, widths: {'price': 120}, rowHeight: 52, cartWidth: 520).save();
      PosCartLayout.current = PosCartLayout();
      final l = await PosCartLayout.load();
      expect(l.show('unit'), isFalse);
      expect(l.w('price'), 120);
      expect(l.rowHeight, 52);
      expect(l.cartWidth, 520);
      expect(PosCartLayout.fromJson(const {}).cartWidth, isNull);
    });
  });
}
