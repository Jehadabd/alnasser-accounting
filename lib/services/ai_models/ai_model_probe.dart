// lib/services/ai_models/ai_model_probe.dart
//
// 🧪 اختبار النماذج: فاتورة تجريبية صغيرة معروفة الأرقام (3 أسطر + المجموع) تُرسم PDF
// ثم تُحوَّل صورة PNG، ويُطلب من النموذج قراءتها. الدرجة = كم رقماً قرأه صحيحاً من 10
// (الكمية والسعر والمبلغ لكل سطر + المجموع). النموذج الذي لا يقرأ الصور يُرفض.
// الترتيب: الدرجة، ثم السرعة. لا يُختبر إلا أفضل 5 نماذج مرشحة (كل اختبار يستهلك الحصة).

import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../owner/ai_invoice/ai_invoice_service.dart';
import 'ai_models_config.dart';
import 'ai_vision_client.dart';

class AiProbeResult {
  AiProbeResult({
    required this.provider,
    required this.model,
    this.name = '',
    this.score = 0,
    this.total = AiModelProbe.maxScore,
    this.ms = 0,
    this.ok = false,
    this.note = '',
  });
  final AiProvider provider;
  final String model;
  final String name;
  final int score;
  final int total;
  final int ms;

  /// نجح الاتصال وقرأ الصورة (ولو بأخطاء).
  final bool ok;
  final String note;

  bool get passed => ok && score >= (total * 0.8).ceil();
}

class AiProviderTest {
  AiProviderTest(this.results, {this.error});
  final List<AiProbeResult> results;
  final String? error;
}

class AiModelProbe {
  AiModelProbe._();

  static const maxScore = 10;

  /// [الاسم, الكمية, السعر, المبلغ]
  static const lines = [
    ['LED Bulb 12W', 10, 1500, 15000],
    ['Cable 2x1.5 80M', 3, 42000, 126000],
    ['Socket White', 24, 750, 18000],
  ];
  static const grandTotal = 159000;

  static const prompt = 'Read this purchase invoice image carefully. Numbers use a comma as thousands separator. '
      'Return ONLY a JSON object, no other text: '
      '{"lines":[{"name":"","qty":0,"price":0,"amount":0}],"total":0}';

  static Uint8List? _png;

  /// للاختبارات (الرسم يحتاج منصة).
  @visibleForTesting
  static Uint8List? pngForTest;

  static String _f(num n) => n.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');

  /// صورة الفاتورة التجريبية (PNG).
  static Future<Uint8List> testInvoicePng() async {
    final t = pngForTest;
    if (t != null) return t;
    if (_png != null) return _png!;
    final doc = pw.Document();
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a5,
      build: (c) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text('Purchase Invoice No. 1042', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text('Date: 2026-11-19   Currency: IQD'),
        pw.SizedBox(height: 12),
        pw.TableHelper.fromTextArray(
          headers: const ['Item', 'Qty', 'Price', 'Amount'],
          data: [
            for (final l in lines) [l[0], '${l[1]}', _f(l[2] as num), _f(l[3] as num)],
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Text('Total: ${_f(grandTotal)}', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
      ]),
    ));
    final pdf = await doc.save();
    await for (final page in Printing.raster(pdf, dpi: 120)) {
      _png = await page.toPng();
      break;
    }
    if (_png == null) throw Exception('تعذّر رسم الفاتورة التجريبية');
    return _png!;
  }

  /// درجة رد النموذج من 10.
  @visibleForTesting
  static int score(String text) {
    Map<String, dynamic> j;
    try {
      j = AiInvoiceService.decodeJson(text);
    } catch (_) {
      return 0;
    }
    double n(Object? v) => v is num ? v.toDouble() : (double.tryParse('${v ?? ''}'.replaceAll(',', '')) ?? -1);
    final got = <List<double>>[];
    final items = j['lines'] ?? j['line_items'] ?? j['items'];
    if (items is List) {
      for (final x in items) {
        if (x is Map) got.add([n(x['qty'] ?? x['quantity']), n(x['price'] ?? x['unit_price']), n(x['amount'] ?? x['total'])]);
      }
    }
    var s = 0;
    final used = <int>{};
    for (final e in lines) {
      final want = [(e[1] as num).toDouble(), (e[2] as num).toDouble(), (e[3] as num).toDouble()];
      var best = -1, bestHits = 0;
      for (var i = 0; i < got.length; i++) {
        if (used.contains(i)) continue;
        var hits = 0;
        for (var f = 0; f < 3; f++) {
          if ((got[i][f] - want[f]).abs() < 0.01) hits++;
        }
        if (hits > bestHits) {
          bestHits = hits;
          best = i;
        }
      }
      if (best >= 0) used.add(best);
      s += bestHits;
    }
    final total = n(j['total'] ?? (j['totals'] is Map ? (j['totals'] as Map)['grand_total'] : null));
    if ((total - grandTotal).abs() < 0.01) s++;
    return s;
  }

  /// يختبر نموذجاً واحداً.
  static Future<AiProbeResult> probe(AiProvider provider, String model, String apiKey, {String name = ''}) async {
    final png = await testInvoicePng();
    final sw = Stopwatch()..start();
    try {
      final text = await AiVisionClient.complete(
        provider: provider,
        model: model,
        apiKey: apiKey,
        prompt: prompt,
        files: [AiBlob(png, 'image/png')],
        timeout: const Duration(seconds: 90),
      );
      sw.stop();
      final sc = score(text);
      return AiProbeResult(
        provider: provider,
        model: model,
        name: name,
        score: sc,
        ms: sw.elapsedMilliseconds,
        ok: true,
        note: sc == 0 ? 'لم يقرأ أرقام الفاتورة' : (sc < maxScore ? 'أخطأ في ${maxScore - sc} من $maxScore أرقام' : 'قرأ كل الأرقام'),
      );
    } on AiCallException catch (e) {
      sw.stop();
      return AiProbeResult(provider: provider, model: model, name: name, ms: sw.elapsedMilliseconds, note: e.message);
    } catch (e) {
      sw.stop();
      return AiProbeResult(provider: provider, model: model, name: name, ms: sw.elapsedMilliseconds, note: '$e');
    }
  }

  /// ترتيب النتائج: الأعلى درجة، ثم الأسرع، والفاشل آخراً.
  static List<AiProbeResult> rank(List<AiProbeResult> r) => List.of(r)
    ..sort((a, b) {
      if (a.ok != b.ok) return a.ok ? -1 : 1;
      if (a.score != b.score) return b.score.compareTo(a.score);
      return a.ms.compareTo(b.ms);
    });

  /// يجلب نماذج المزوّد، ويختبر أفضل [top] مرشحين بهذا المفتاح، ويرتّبهم.
  static Future<AiProviderTest> testProvider(AiProvider provider, String apiKey,
      {int top = 5, void Function(String status)? onStatus}) async {
    try {
      if (provider == AiProvider.openrouter) {
        onStatus?.call('التحقق من المفتاح…');
        await AiVisionClient.checkOpenRouterKey(apiKey);
      }
      onStatus?.call('جلب قائمة النماذج…');
      final all = await AiVisionClient.listModels(provider, apiKey);
      final cands = AiVisionClient.candidates(all).take(top).toList();
      if (cands.isEmpty) {
        return AiProviderTest(const [],
            error: provider == AiProvider.openrouter
                ? 'لا يوجد الآن نموذج مجاني يقرأ الصور في OpenRouter'
                : 'لم أجد نموذجاً يقرأ الصور لهذا المفتاح');
      }
      final results = <AiProbeResult>[];
      for (var i = 0; i < cands.length; i++) {
        final c = cands[i];
        onStatus?.call('اختبار ${i + 1} من ${cands.length}: ${c.name.isEmpty ? c.id : c.name}…');
        results.add(await probe(provider, c.id, apiKey, name: c.name));
        // المفتاح نفسه مرفوض: لا فائدة من بقية الاختبارات
        if (results.last.note.contains('المفتاح')) break;
      }
      return AiProviderTest(rank(results));
    } on AiCallException catch (e) {
      return AiProviderTest(const [], error: e.message);
    } catch (e) {
      return AiProviderTest(const [], error: '$e');
    }
  }
}
