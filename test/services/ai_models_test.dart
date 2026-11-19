// test/services/ai_models_test.dart
//
// 🤖 نماذج الذكاء الاصطناعي لفاتورة الشراء — بكود البرنامج نفسه:
//   • تصنيف الأخطاء (حصة/مفتاح/لا يقرأ الصور/غير موجود/خصوصية OpenRouter).
//   • قائمة نماذج OpenRouter: المجاني الذي يقرأ الصور فقط.
//   • الموجّه: مفتاح آخر عند نفاد الحصة، نموذج آخر عند رفض الطلب، إعادة مرة عند انشغال
//     الخادم، دورة واحدة وحدّ محاولات، والمفتاح المُستراح لا يُجرَّب.
//   • المرشحون محلياً، رسائل التعلّم، دمج دفعات الصفحات، وتطبيق رد المطابِق.
//   • تشغيل كامل بالتعاون بين نموذجين على خادم وهمي (القارئ ← المطابِق ← فرض ما تعلّمناه).
//   • درجة الفاتورة التجريبية.
// التشغيل: flutter test test/services/ai_models_test.dart

import 'dart:convert';
import 'dart:typed_data';

import 'package:alnaser/models/product.dart';
import 'package:alnaser/owner/ai_invoice/ai_alias_store.dart';
import 'package:alnaser/owner/ai_invoice/ai_invoice_engine.dart';
import 'package:alnaser/owner/ai_invoice/ai_invoice_service.dart';
import 'package:alnaser/services/ai_models/ai_model_probe.dart';
import 'package:alnaser/services/ai_models/ai_models_config.dart';
import 'package:alnaser/services/ai_models/ai_router.dart';
import 'package:alnaser/services/ai_models/ai_vision_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Product _p(int id, String name, {String unit = 'piece', String? hierarchy, double? cost}) => Product(
      id: id,
      name: name,
      unit: unit,
      unitPrice: 0,
      price1: 0,
      costPrice: cost,
      unitHierarchy: hierarchy,
      createdAt: DateTime(2026),
      lastModifiedAt: DateTime(2026),
    );

AiInvoiceLine _line(String name, {double qty = 1, double price = 1000, double amount = 1000}) => AiInvoiceLine(
      originalName: name,
      cleanName: name,
      qty: qty,
      price: price,
      amount: amount,
      saleUnit: '',
      unitType: 'piece',
      unitsCount: 1,
    );

AiKey _k(String id, AiProvider p) => AiKey(id: id, provider: p, key: 'key-$id-0123456789');

void main() {
  setUp(() {
    AiRouter.resetForTest();
    AiRouter.retryDelay = Duration.zero;
    AiVisionClient.clientForTest = null;
  });

  group('تصنيف الأخطاء', () {
    test('429 يومية ودقيقة، 402 رصيد، 401 مفتاح', () {
      final d = AiVisionClient.classify(429, '{"error":{"message":"Quota exceeded for GenerateRequestsPerDayPerProject"}}');
      expect(d.kind, AiErrorKind.quota);
      expect(d.daily, isTrue);
      final m = AiVisionClient.classify(429, '{"error":{"message":"rate limit per minute"}}');
      expect(m.kind, AiErrorKind.quota);
      expect(m.daily, isFalse);
      expect(AiVisionClient.classify(402, '{}').kind, AiErrorKind.quota);
      expect(AiVisionClient.classify(401, '{}').kind, AiErrorKind.auth);
    });

    test('نموذج لا يقرأ الصور، غير موجود، أكبر من حده، وخصوصية OpenRouter', () {
      expect(AiVisionClient.classify(400, '{"error":{"message":"This model does not support image input"}}').kind,
          AiErrorKind.notVision);
      expect(AiVisionClient.classify(404, '{"error":{"message":"model not found"}}').kind, AiErrorKind.notFound);
      expect(AiVisionClient.classify(400, '{"error":{"message":"maximum context length is 8192"}}').kind, AiErrorKind.tooLarge);
      final priv = AiVisionClient.classify(404, '{"error":{"message":"No endpoints found matching your data policy"}}');
      expect(priv.kind, AiErrorKind.notFound);
      expect(priv.message, contains('Privacy'));
      expect(AiVisionClient.classify(503, '').kind, AiErrorKind.server);
    });
  });

  test('OpenRouter: المجاني الذي يقرأ الصور فقط، بترتيب الأفضلية', () {
    final body = jsonEncode({
      'data': [
        {
          'id': 'baidu/ernie-5.5-flash-preview:free',
          'architecture': {'input_modalities': ['text']},
          'pricing': {'prompt': '0', 'completion': '0'}
        },
        {
          'id': 'nvidia/nemotron-3.5-super-vl:free',
          'architecture': {'input_modalities': ['text', 'image']},
          'pricing': {'prompt': '0', 'completion': '0'}
        },
        {
          'id': 'openai/gpt-paid',
          'architecture': {'input_modalities': ['text', 'image']},
          'pricing': {'prompt': '0.000002', 'completion': '0.00001'}
        },
        {
          'id': 'google/gemma-4-31b-it:free',
          'architecture': {'input_modalities': ['text', 'image']},
          'pricing': {'prompt': '0', 'completion': '0'}
        },
        {'id': 'openrouter/free', 'architecture': {'input_modalities': ['text', 'image']}},
      ]
    });
    final c = AiVisionClient.candidates(AiVisionClient.parseModels(AiProvider.openrouter, body));
    expect(c.map((m) => m.id), ['google/gemma-4-31b-it:free', 'nvidia/nemotron-3.5-super-vl:free']);
  });

  test('صيغة الطلب: Gemini يرسل PDF، وغيره صوراً بصيغة data: — ولا PDF لـ OpenRouter أبداً', () async {
    final g = AiVisionClient.geminiBody('p', [AiBlob(Uint8List.fromList([1, 2]), 'application/pdf')]);
    expect(jsonEncode(g), contains('application/pdf'));
    final o = AiVisionClient.openAiBody('m', 'p', [AiBlob(Uint8List.fromList([1, 2]), 'image/png')]);
    expect(jsonEncode(o), contains('data:image/png;base64,'));
    await expectLater(
      AiVisionClient.complete(
          provider: AiProvider.openrouter,
          model: 'x',
          apiKey: 'k',
          prompt: 'p',
          files: [AiBlob(Uint8List.fromList([1]), 'application/pdf')]),
      throwsA(isA<AiCallException>()),
    );
  });

  group('الموجّه', () {
    final a = AiModelEntry(provider: AiProvider.gemini, model: 'a');
    final b = AiModelEntry(provider: AiProvider.groq, model: 'b');
    final keys = {
      AiProvider.gemini: [_k('g1', AiProvider.gemini), _k('g2', AiProvider.gemini)],
      AiProvider.groq: [_k('q1', AiProvider.groq)],
      AiProvider.openrouter: <AiKey>[],
    };

    test('نفدت حصة المفتاح الأول ⇒ الثاني للنموذج نفسه، والمفتاح الأول يُستراح', () async {
      final calls = <String>[];
      final r = await AiRouter.run(
        chain: [a, b],
        keys: keys,
        send: (e, k) async {
          calls.add('${e.model}/${k.id}');
          if (k.id == 'g1') throw AiCallException(AiErrorKind.quota, 'q', daily: true);
          return 'ok';
        },
      );
      expect(r.entry.model, 'a');
      expect(calls, ['a/g1', 'a/g2']);
      final again = <String>[];
      await AiRouter.run(chain: [a], keys: keys, send: (e, k) async {
        again.add(k.id);
        return 'ok';
      });
      expect(again, ['g2']); // g1 في استراحة
    });

    test('طلب مرفوض ⇒ النموذج التالي مباشرة (بلا تجربة المفتاح الثاني)', () async {
      final calls = <String>[];
      final r = await AiRouter.run(
        chain: [a, b],
        keys: keys,
        send: (e, k) async {
          calls.add('${e.model}/${k.id}');
          if (e.model == 'a') throw AiCallException(AiErrorKind.notVision, 'لا يقرأ الصور');
          return 'ok';
        },
      );
      expect(r.entry.model, 'b');
      expect(calls, ['a/g1', 'b/q1']);
    });

    test('خادم مشغول ⇒ إعادة بالمفتاح نفسه مرة واحدة ثم التالي؛ ورد غير صالح ⇒ النموذج التالي', () async {
      final calls = <String>[];
      final r = await AiRouter.run(
        chain: [a, b],
        keys: keys,
        send: (e, k) async {
          calls.add('${e.model}/${k.id}');
          if (e.model == 'a' && k.id == 'g1') throw AiCallException(AiErrorKind.server, 's');
          if (e.model == 'a' && k.id == 'g2') throw AiBadOutput('ليس JSON');
          return 'ok';
        },
      );
      expect(calls, ['a/g1', 'a/g1', 'a/g2', 'b/q1']);
      expect(r.entry.model, 'b');
    });

    test('دورة واحدة فقط وحد المحاولات، ورسالة فيها كل محاولة', () async {
      var n = 0;
      try {
        await AiRouter.run(
          chain: [a, b],
          keys: keys,
          maxAttempts: 3,
          send: (e, k) async {
            n++;
            throw AiCallException(AiErrorKind.auth, 'مرفوض');
          },
        );
        fail('يجب أن يفشل');
      } on AiRouterException catch (e) {
        expect(n, 3);
        expect(e.attempts, hasLength(3));
        expect(e.toString(), contains('مرفوض'));
      }
    });

    test('بلا نموذج له مفتاح: رسالة توجّه إلى الإعدادات', () async {
      expect(() => AiRouter.run(chain: const [], keys: keys, send: (e, k) async => ''),
          throwsA(isA<AiRouterException>().having((e) => e.message, 'm', contains('الإعدادات'))));
    });
  });

  group('المرشحون والتعلّم', () {
    final products = [
      _p(1, 'سيمنس 2×1.5 بيرلي', unit: 'meter', hierarchy: jsonEncode([{'unit_name': 'لفة', 'quantity': 80}])),
      _p(2, 'سيمنس 2×2.5 بيرلي', unit: 'meter'),
      _p(3, 'مصباح ليد 12 واط'),
      _p(4, 'بلك ابيض'),
    ];

    test('ما تعلّمناه أولاً، والمقاس المختلف أضعف، وخطأ الإملاء يُلتقط', () {
      final aliases = [AiAlias(supplierId: 7, alias: 'B2-1.5-80XW', productId: 1, hits: 3)];
      final c1 = AiInvoiceEngine.candidatesFor(_line('B2-1.5-80XW'), products, aliases, 7);
      expect(c1.first.product.id, 1);
      expect(c1.first.why, 'تعلّم سابق');

      final c2 = AiInvoiceEngine.candidatesFor(_line('سيمس 1.5*2 بيرلي'), products, const [], 7);
      expect(c2.first.product.id, 1); // 1.5 و 2 متفقان
      final s2 = c2.firstWhere((c) => c.product.id == 2, orElse: () => c2.first);
      if (s2.product.id == 2) expect(s2.score, lessThan(c2.first.score));

      final c3 = AiInvoiceEngine.candidatesFor(_line('مصباح لييد 12 واط'), products, const [], null);
      expect(c3.first.product.id, 3);
    });

    test('رسائل التعلّم: «ظهر هذا الاسم فغيّره المستخدم إلى هذه المادة» — مرشحو الفاتورة أولاً', () {
      final aliases = [
        AiAlias(supplierId: 9, alias: 'لمبة', productId: 3, hits: 5),
        AiAlias(supplierId: 7, alias: 'B2-1.5', productId: 1, hits: 2),
      ];
      final cands = [
        [AiCandidate(products[0], 1, '')]
      ];
      final msgs = AiInvoiceEngine.learningMessages(aliases, 7, 'شركة النور', products, cands);
      expect(msgs.first, contains('ظهر «B2-1.5» في فاتورة «شركة النور» فغيّره المستخدم إلى «سيمنس 2×1.5 بيرلي»'));
      expect(msgs.last, contains('عند مورد آخر'));
    });

    test('المطابِق: يُقبل من المرشحين فقط، والتصحيح المتسق فقط', () {
      final lines = [_line('a'), _line('b', qty: 2, price: 1500, amount: 300)];
      final cands = [
        [AiCandidate(products[0], 1, '')],
        [AiCandidate(products[2], 1, '')],
      ];
      AiInvoiceEngine.applyMatcher(
          lines,
          {
            'lines': [
              {'i': 0, 'matched_product_id': 4, 'confidence': 0.99}, // من خارج المرشحين
              {
                'i': 1,
                'matched_product_id': 3,
                'confidence': 0.9,
                'sale_unit': 'كرتون',
                'units_count': 20,
                'fix': {'qty': 2, 'price': 1500, 'amount': 3000}
              },
            ]
          },
          cands);
      expect(lines[0].productId, isNull);
      expect(lines[0].reason, contains('خارج المرشحين'));
      expect(lines[1].productId, 3);
      expect(lines[1].saleUnit, 'كرتون');
      expect(lines[1].unitsCount, 20);
      expect(lines[1].amount, 3000);
      expect(lines[1].note, contains('صحّح المطابِق'));

      final bad = [_line('c', qty: 1, price: 100, amount: 100)];
      AiInvoiceEngine.applyMatcher(
          bad,
          {
            'lines': [
              {'i': 0, 'matched_product_id': null, 'fix': {'qty': 5, 'price': 100, 'amount': 900}}
            ]
          },
          [const []]);
      expect(bad[0].qty, 1); // تصحيح غير متسق يُرفض
    });

    test('دمج دفعات الصفحات (Groq: 3 صور في الطلب)', () {
      final m = AiInvoiceEngine.mergeChunks([
        {
          'supplier_name': 'النور',
          'invoice_number': '55',
          'line_items': [
            {'name': 'a'}
          ]
        },
        {
          'line_items': [
            {'name': 'b'}
          ],
          'totals': {'grand_total': '12,000'},
          'status': 'دين'
        },
      ]);
      expect((m['line_items'] as List).length, 2);
      expect(m['supplier_name'], 'النور');
      expect((m['totals'] as Map)['grand_total'], '12,000');
      expect(m['status'], 'دين');
    });
  });

  test('تشغيل كامل: قارئ Groq ← مطابِق Gemini ← ما تعلّمناه أقوى', () async {
    SharedPreferences.setMockInitialValues({});
    AiModelsStore.memorySecureForTest = {};
    AiModelsStore.resetForTest();
    await AiModelsStore.saveConfig(AiModelsConfig(models: [
      AiModelEntry(provider: AiProvider.groq, model: 'qwen/qwen3.8-27b', label: 'Qwen'),
      AiModelEntry(provider: AiProvider.gemini, model: 'gemini-3.8-flash', label: 'Gemini'),
    ]));
    await AiModelsStore.addKey(AiProvider.groq, 'gsk_test_0123456789');
    await AiModelsStore.addKey(AiProvider.gemini, 'AIza_test_0123456789');

    final products = [
      _p(1, 'سيمنس 2×1.5 بيرلي', unit: 'meter', hierarchy: jsonEncode([{'unit_name': 'لفة', 'quantity': 80}])),
      _p(3, 'مصباح ليد 12 واط'),
      _p(5, 'بلك ابيض 16 امبير'),
    ];
    final aliases = [AiAlias(supplierId: 7, alias: 'PLG W16', productId: 5, hits: 2)];
    final prompts = <String>[];
    AiVisionClient.clientForTest = MockClient((req) async {
      final body = utf8.decode(req.bodyBytes);
      if (req.url.host == 'api.groq.com') {
        prompts.add('reader:$body');
        expect(body, isNot(contains('سيمنس 2×1.5 بيرلي'))); // القارئ لا يرى قائمة المواد
        return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': jsonEncode({
                      'supplier_name': 'النور',
                      'line_items': [
                        {'original_name': 'Berly 80M 1.5*2 سيمس', 'name': 'سيمس 1.5*2 بيرلي', 'qty': 2, 'price': 42000, 'amount': 84000, 'sale_unit': 'لفة', 'units_count': 80},
                        {'original_name': 'LED 12W', 'name': 'مصباح 12 واط', 'qty': 10, 'price': 1500, 'amount': 15000},
                        {'original_name': 'PLG W16', 'name': 'PLG W16', 'qty': 5, 'price': 750, 'amount': 3750},
                      ],
                      'totals': {'grand_total': 102750},
                    })
                  }
                }
              ]
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }
      // المطابِق Gemini: يرى المرشحين ورسائل التعلّم
      prompts.add('matcher:$body');
      expect(body, contains('رسائل التعلّم'));
      expect(body, contains('PLG W16'));
      return http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {
                      'text': jsonEncode({
                        'lines': [
                          {'i': 0, 'matched_product_id': 1, 'confidence': 0.95, 'reason': 'Berly=بيرلي', 'sale_unit': 'لفة', 'units_count': 80},
                          {'i': 1, 'matched_product_id': 3, 'confidence': 0.9, 'reason': 'LED=ليد'},
                          {'i': 2, 'matched_product_id': 3, 'confidence': 0.6, 'reason': 'خطأ من النموذج'},
                        ]
                      })
                    }
                  ]
                }
              }
            ]
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });

    final statuses = <String>[];
    final r = await AiInvoiceEngine.run(
      bytes: Uint8List.fromList([137, 80, 78, 71]),
      mimeType: 'image/png',
      products: products,
      aliases: aliases,
      supplierId: 7,
      supplierName: 'النور',
      onStatus: statuses.add,
    );
    expect(prompts.first, startsWith('reader:'));
    expect(prompts.last, startsWith('matcher:'));
    expect(r.lines.map((l) => l.productId), [1, 3, 5]); // السطر الثالث: ما تعلّمناه يغلب النموذج
    expect(r.lines[2].source, AiMatchSource.learned);
    expect(r.lines[0].unitsCount, 80);
    expect(r.model, 'قرأها Qwen • طابقها Gemini');
    expect(r.engineNote, isEmpty);
    expect(statuses.any((s) => s.contains('يطابق المواد')), isTrue);
  });

  test('المطابِق فشل ⇒ تبقى القراءة وتُطابَق الأسطر محلياً مع ملاحظة', () async {
    SharedPreferences.setMockInitialValues({});
    AiModelsStore.memorySecureForTest = {};
    AiModelsStore.resetForTest();
    await AiModelsStore.saveConfig(AiModelsConfig(models: [AiModelEntry(provider: AiProvider.groq, model: 'q')]));
    await AiModelsStore.addKey(AiProvider.groq, 'gsk_test_0123456789');
    var calls = 0;
    AiVisionClient.clientForTest = MockClient((req) async {
      calls++;
      if (calls == 1) {
        return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': jsonEncode({
                      'line_items': [
                        {'original_name': 'مصباح ليد 12 واط', 'qty': 1, 'price': 1000, 'amount': 1000}
                      ]
                    })
                  }
                }
              ]
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }
      return http.Response('{"error":{"message":"rate limit"}}', 429);
    });
    final r = await AiInvoiceEngine.run(
      bytes: Uint8List.fromList([1]),
      mimeType: 'image/png',
      products: [_p(3, 'مصباح ليد 12 واط')],
      aliases: const [],
      supplierId: null,
    );
    expect(r.lines.single.productId, 3); // الاسم نفسه
    expect(r.engineNote, contains('طابقتُ محلياً'));
  });

  test('درجة الفاتورة التجريبية', () {
    final perfect = jsonEncode({
      'lines': [
        for (final l in AiModelProbe.lines) {'name': l[0], 'qty': l[1], 'price': l[2], 'amount': l[3]}
      ],
      'total': AiModelProbe.grandTotal,
    });
    expect(AiModelProbe.score(perfect), AiModelProbe.maxScore);
    final misread = jsonEncode({
      'lines': [
        {'qty': 10, 'price': 1.5, 'amount': 15}, // فاصل الآلاف قُرئ كسراً
        {'qty': 3, 'price': '42,000', 'amount': '126,000'},
        {'qty': 24, 'price': 750, 'amount': 18000},
      ],
      'total': 159000,
    });
    expect(AiModelProbe.score(misread), 8);
    expect(AiModelProbe.score('ليس JSON'), 0);
  });
}
