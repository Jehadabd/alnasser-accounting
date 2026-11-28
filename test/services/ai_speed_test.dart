// test/services/ai_speed_test.dart
//
// ⚡ سرعة قراءة الفاتورة بالذكاء الاصطناعي ورسائلها — بكود البرنامج نفسه:
//   • Gemini 3 فما بعد: «تفكير قليل»؛ ونموذج يرفضه يُعاد طلبه بلا هذا الإعداد.
//   • حد صريح للرد عند OpenRouter/Groq (بلا حد: «402 رصيد غير كافٍ»).
//   • المهلة: لا يُعاد طلب استغرقها كاملة — النموذج التالي مباشرة.
//   • نموذج غير موجود (404) لا يُجرَّب في المرة التالية.
//   • المطابِق نص فقط (لا رفع ثانٍ للصور).
//   • تصغير الصور الكبيرة قبل الرفع، وتقدير الزمن يتعلّم من الزمن الفعلي.

import 'dart:convert';
import 'dart:typed_data';

import 'package:alnaser/models/product.dart';
import 'package:alnaser/owner/ai_invoice/ai_invoice_engine.dart';
import 'package:alnaser/owner/ai_invoice/ai_purchase_invoice_screen.dart' show AiReadEstimate;
import 'package:alnaser/services/ai_models/ai_image_prep.dart';
import 'package:alnaser/services/ai_models/ai_models_config.dart';
import 'package:alnaser/services/ai_models/ai_router.dart';
import 'package:alnaser/services/ai_models/ai_vision_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

AiKey _k(String id, AiProvider p) => AiKey(id: id, provider: p, key: 'key-$id-0123456789');

http.Response _openAi(Object content) => http.Response(
    jsonEncode({
      'choices': [
        {'message': {'content': content is String ? content : jsonEncode(content)}}
      ]
    }),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  setUp(() {
    AiRouter.resetForTest();
    AiRouter.retryDelay = Duration.zero;
    AiRouter.maxQuotaWait = Duration.zero;
    AiVisionClient.clientForTest = null;
  });

  group('⚡ تفكير قليل لـ Gemini 3', () {
    test('Gemini 3.x فقط', () {
      expect(AiVisionClient.usesThinkingLevel(AiProvider.gemini, 'gemini-3.8-flash'), isTrue);
      expect(AiVisionClient.usesThinkingLevel(AiProvider.gemini, 'gemini-3.5-flash-lite'), isTrue);
      expect(AiVisionClient.usesThinkingLevel(AiProvider.gemini, 'gemini-2.5-flash'), isFalse);
      expect(AiVisionClient.usesThinkingLevel(AiProvider.gemini, 'gemini-flash-latest'), isFalse);
      expect(AiVisionClient.usesThinkingLevel(AiProvider.groq, 'gemini-3-x'), isFalse);
    });

    test('يُرسل thinkingLevel=low، ويُعاد الطلب بلا تفكير إن رفضه النموذج', () async {
      final bodies = <String>[];
      AiVisionClient.clientForTest = MockClient((req) async {
        final b = utf8.decode(req.bodyBytes);
        bodies.add(b);
        if (b.contains('thinkingConfig')) {
          return http.Response(jsonEncode({'error': {'message': 'Thinking level is not supported for this model.'}}), 400);
        }
        return http.Response(
            jsonEncode({
              'candidates': [
                {'content': {'parts': [{'text': '{"line_items":[]}'}]}}
              ]
            }),
            200);
      });
      final t = await AiVisionClient.complete(provider: AiProvider.gemini, model: 'gemini-3.8-flash', apiKey: 'k', prompt: 'p');
      expect(t, '{"line_items":[]}');
      expect(bodies.length, 2);
      expect(bodies.first, contains('"thinkingLevel":"low"'));
      expect(bodies.last, isNot(contains('thinkingConfig')));
    });

    test('2.5 بلا thinkingConfig أصلاً', () {
      final b = jsonEncode(AiVisionClient.geminiBody('p', const []));
      expect(b, isNot(contains('thinkingConfig')));
    });
  });

  test('OpenRouter/Groq: حد صريح للرد', () {
    expect(AiVisionClient.openAiBody('m', 'p', const [])['max_tokens'], 8192);
  });

  group('🔀 الموجّه', () {
    final a = AiModelEntry(provider: AiProvider.gemini, model: 'a');
    final b = AiModelEntry(provider: AiProvider.groq, model: 'b');
    final keys = {
      AiProvider.gemini: [_k('g1', AiProvider.gemini)],
      AiProvider.groq: [_k('q1', AiProvider.groq)],
    };

    test('انتهت المهلة ⇒ النموذج التالي مباشرة (بلا إعادة الطلب نفسه)', () async {
      final calls = <String>[];
      final r = await AiRouter.run(
        chain: [a, b],
        keys: keys,
        send: (e, k) async {
          calls.add(e.model);
          if (e.model == 'a') throw AiCallException(AiErrorKind.timeout, 'انتهت المهلة');
          return 'ok';
        },
      );
      expect(calls, ['a', 'b']);
      expect(r.entry.model, 'b');
    });

    test('نموذج غير موجود (404) ⇒ لا يُجرَّب في القراءة التالية', () async {
      final calls = <String>[];
      Future<String> send(AiModelEntry e, AiKey k) async {
        calls.add(e.model);
        if (e.model == 'a') throw AiCallException(AiErrorKind.notFound, '404');
        return 'ok';
      }

      await AiRouter.run(chain: [a, b], keys: keys, send: send);
      await AiRouter.run(chain: [a, b], keys: keys, send: send);
      expect(calls, ['a', 'b', 'b']);
      await AiRouter.clearRests();
      await AiRouter.run(chain: [a, b], keys: keys, send: send);
      expect(calls.last, 'b');
      expect(calls[3], 'a'); // بعد «أعد التجربة» يُجرَّب من جديد
    });
  });

  test('⏱️ مهلة القراءة حسب الصفحات: 60 + 20 لكل صفحة، بين 60 و170', () {
    AiBlob im() => AiBlob(Uint8List.fromList([1]), 'image/png');
    expect(AiInvoiceEngine.readTimeout([im()]), const Duration(seconds: 80));
    expect(AiInvoiceEngine.readTimeout([im(), im(), im()]), const Duration(seconds: 120));
    expect(AiInvoiceEngine.readTimeout(List.generate(10, (_) => im())), const Duration(seconds: 170));
  });

  test('🧠 المطابِق نص فقط: الصورة تُرفع مرة واحدة (للقارئ)', () async {
    SharedPreferences.setMockInitialValues({});
    AiModelsStore.memorySecureForTest = {};
    AiModelsStore.resetForTest();
    await AiModelsStore.saveConfig(AiModelsConfig(models: [AiModelEntry(provider: AiProvider.groq, model: 'q')]));
    await AiModelsStore.addKey(AiProvider.groq, 'gsk_test_0123456789');
    final bodies = <String>[];
    AiVisionClient.clientForTest = MockClient((req) async {
      final body = utf8.decode(req.bodyBytes);
      bodies.add(body);
      if (bodies.length == 1) {
        return _openAi({
          'line_items': [
            {'row_no': 1, 'original_name': 'مصباح ليد 12 واط', 'qty': 2, 'price': 1000, 'amount': 2000}
          ],
          'rows_count': 1,
        });
      }
      return _openAi({
        'lines': [
          {'i': 0, 'matched_product_id': 3, 'confidence': 0.95, 'reason': 'تطابق'}
        ]
      });
    });
    final products = [
      Product(id: 3, name: 'مصباح ليد 12 واط', unit: 'piece', unitPrice: 0, price1: 0, createdAt: DateTime(2026), lastModifiedAt: DateTime(2026)),
    ];
    final r = await AiInvoiceEngine.run(
      bytes: Uint8List.fromList([137, 80, 78, 71]),
      mimeType: 'image/png',
      products: products,
      aliases: const [],
      supplierId: null,
    );
    expect(bodies.length, 2);
    expect(bodies.first, contains('image_url'));
    expect(bodies.last, isNot(contains('image_url')));
    expect(r.lines.single.productId, 3);
  });

  group('🗜️ تصغير الصور', () {
    test('صورة كبيرة ⇒ أطول ضلع 2400 وحجم أصغر', () {
      final big = img.Image(width: 3600, height: 2400);
      for (var y = 0; y < big.height; y += 1) {
        for (var x = 0; x < big.width; x += 1) {
          big.setPixelRgb(x, y, (x * 7 + y * 3) % 256, (x * 5) % 256, (y * 11) % 256);
        }
      }
      final src = Uint8List.fromList(img.encodeJpg(big, quality: 98));
      final out = AiImagePrep.shrinkBytesForTest(src);
      expect(out, isNotNull);
      expect(out!.length, lessThan(src.length));
      final d = img.decodeImage(out)!;
      expect(d.width, 2400);
      expect(d.height, 1600);
    });

    test('ملف ليس صورة أو صغير ⇒ يبقى كما هو', () async {
      expect(AiImagePrep.shrinkBytesForTest(Uint8List.fromList([1, 2, 3])), isNull);
      final small = AiBlob(Uint8List.fromList([137, 80, 78, 71]), 'image/png');
      expect(identical(await AiImagePrep.shrink(small), small), isTrue);
      final pdf = AiBlob(Uint8List(800 * 1024), 'application/pdf');
      expect(identical(await AiImagePrep.shrink(pdf), pdf), isTrue);
    });
  });

  group('⏱️ تقدير الزمن يتعلّم', () {
    test('بلا تاريخ ⇒ التقدير الافتراضي؛ بعده يقترب من الفعلي مع هامش', () {
      expect(AiReadEstimate.estimateFrom(null, 1), AiReadEstimate.seconds(1));
      var ema = AiReadEstimate.nextEma(null, 70, 1);
      expect(ema, 70);
      expect(AiReadEstimate.estimateFrom(ema, 1), 81); // 70 × 1.15
      ema = AiReadEstimate.nextEma(ema, 40, 1);
      expect(ema, closeTo(59.5, 0.01)); // 70×0.65 + 40×0.35
      // صفحتان ⇒ 1.6 وحدة
      expect(AiReadEstimate.estimateFrom(50, 2), (50 * 1.6 * 1.15).round());
    });
  });
}
