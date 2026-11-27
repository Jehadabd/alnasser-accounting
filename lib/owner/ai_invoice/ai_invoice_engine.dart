// lib/owner/ai_invoice/ai_invoice_engine.dart
//
// 🤖🤝 قراءة فاتورة المورد بنماذج متعددة (الإعدادات ← النظام والأدوات ← نماذج الذكاء الاصطناعي).
//
// التعاون بين نموذجين (الافتراضي):
//   1) القارئ: يرى الفاتورة (صورة، أو PDF لـ Gemini، أو صور صفحاته لغيره) ويستخرج الأسطر
//      كما هي — بلا قائمة موادنا، فالطلب صغير ويعمل مع أي مزوّد (Groq حدّه 8 آلاف توكن/دقيقة).
//      يُعطى أسماء هذا المورد السابقة ليقرأ خطه واختصاراته.
//   2) المرشحون محلياً (بلا إنترنت): لكل سطر أقرب 8 مواد من موادنا — ما تعلّمناه، الاسم
//      نفسه، الكلمات، تشابه الحروف (أخطاء الإملاء)، واتفاق أرقام المقاس.
//   3) المطابِق: يرى الفاتورة + ما استخرجه القارئ + مرشحي كل سطر + «رسائل التعلّم»
//      (مرة ظهر هذا الاسم عند هذا المورد فغيّره المستخدم إلى هذه المادة). يختار من
//      المرشحين فقط — لا يخترع مادة — ويضبط الوحدة والتعبئة من وحدات المادة عندنا.
//   4) فرض ما تعلّمناه والاسم المطابق حرفياً (AiInvoiceService.applyMatching) — أقوى من النموذج.
// إن فشل المطابِق: تبقى القراءة، وتُطابَق الأسطر محلياً، مع ملاحظة للمستخدم.
//
// بلا تعاون: نموذج واحد يرى الفاتورة وقائمة المواد كاملة (يناسب Gemini وسياقه الضخم).

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../models/product.dart';
import '../../services/ai_models/ai_models_config.dart';
import '../../services/ai_models/ai_pdf_pages.dart';
import '../../services/ai_models/ai_router.dart';
import '../../services/ai_models/ai_vision_client.dart';
import 'ai_alias_store.dart';
import 'ai_invoice_service.dart';

/// مرشح لسطر: مادة ودرجة قربها.
class AiCandidate {
  const AiCandidate(this.product, this.score, this.why);
  final Product product;
  final double score;
  final String why;
}

class AiInvoiceEngine {
  AiInvoiceEngine._();

  /// للاختبارات: بديل لتحويل PDF إلى صور (يحتاج منصة).
  @visibleForTesting
  static Future<List<AiBlob>> Function(Uint8List pdf)? pdfToImagesForTest;

  // ───────────────────────── التشغيل ─────────────────────────

  static Future<AiInvoiceResult> run({
    required Uint8List bytes,
    required String mimeType,
    required List<Product> products,
    required List<AiAlias> aliases,
    required int? supplierId,
    String supplierName = '',
    void Function(String status)? onStatus,
    /// 🖼️ صور إضافية (فاتورة من عدة صفحات مصوّرة). تُهمل إن كان الملف الأول PDF.
    List<AiBlob> moreImages = const [],
  }) async {
    final cfg = await AiModelsStore.config();
    final keys = await AiModelsStore.keysByProvider();
    final chain = await AiModelsStore.usableChain();
    final file = AiBlob(bytes, mimeType);
    final images = file.isPdf ? const <AiBlob>[] : [file, ...moreImages.where((b) => !b.isPdf)];
    final pageCache = <AiBlob>[];
    // ⏳ رسائل الانتظار بلا اسم نموذج أو مزوّد — المستخدم يرى ما يحدث والمدة فقط
    void wait(String raw) => onStatus?.call(waitStatus(raw));

    Future<List<AiBlob>> filesFor(AiModelEntry e) async {
      if (!file.isPdf) return images;
      if (e.provider.nativePdf) return [file];
      if (pageCache.isNotEmpty) return pageCache;
      onStatus?.call('يجهّز صفحات الملف…');
      final conv = pdfToImagesForTest;
      final pages = conv != null ? await conv(bytes) : await AiPdfPages.forProvider(file, nativePdf: false);
      if (pages.isEmpty) throw AiCallException(AiErrorKind.badRequest, 'تعذّر تحويل الـ PDF إلى صور');
      pageCache.addAll(pages);
      return pageCache;
    }

    // ── نموذج واحد بقائمة المواد كاملة
    if (!cfg.collaboration) {
      final prompt = AiInvoiceService.buildPrompt(products: products, aliases: aliases, supplierId: supplierId, supplierName: supplierName);
      final r = await AiRouter.run(
        chain: ordered(chain, cfg.readerId),
        keys: keys,
        onTry: (e) => onStatus?.call('يقرأ الفاتورة ويطابقها…'),
        onWait: wait,
        send: (e, k) async => _readAll(e, k, prompt, await filesFor(e)),
      );
      final result = AiInvoiceService.parse(AiInvoiceService.decodeJson(r.text));
      AiInvoiceService.applyMatching(result.lines, products, aliases, supplierId);
      return withEngine(result, r.entry.shownName, '');
    }

    // ── 1) القارئ
    final readerPrompt = buildReaderPrompt(supplierName: supplierName, pastNames: pastNames(aliases, supplierId));
    final read = await AiRouter.run(
      chain: ordered(chain, cfg.readerId),
      keys: keys,
      onTry: (e) => onStatus?.call('يقرأ الفاتورة…'),
      onWait: wait,
      send: (e, k) async => _readAll(e, k, readerPrompt, await filesFor(e)),
    );
    final result = AiInvoiceService.parse(AiInvoiceService.decodeJson(read.text));
    for (final l in result.lines) {
      // القارئ لا يعرف موادنا: أي معرّف منه لا قيمة له
      l.productId = null;
      l.source = AiMatchSource.none;
      l.confidence = 0;
    }

    // ── 2) المرشحون محلياً
    final cands = [for (final l in result.lines) candidatesFor(l, products, aliases, supplierId)];

    // ── 3) المطابِق — لا داعي له إن لم يكن لأي سطر مرشح (كلها مواد جديدة)
    var note = '';
    var matcherName = '';
    if (result.lines.isNotEmpty && cands.any((c) => c.isNotEmpty)) {
      final mChain = cfg.matcherId.isNotEmpty ? ordered(chain, cfg.matcherId) : preferOther(chain, read.entry);
      final prompt = buildMatcherPrompt(
        lines: result.lines,
        candidates: cands,
        learning: learningMessages(aliases, supplierId, supplierName, products, cands),
        supplierName: supplierName,
      );
      try {
        final m = await AiRouter.run(
          chain: mChain,
          keys: keys,
          onTry: (e) => onStatus?.call('يطابق المواد مع موادك…'),
          onWait: wait,
          send: (e, k) async {
            final files = await filesFor(e);
            final text = await AiVisionClient.complete(
              provider: e.provider,
              model: e.model,
              apiKey: k.key,
              prompt: prompt,
              files: files.take(e.provider.maxImages).toList(),
            );
            _mustBeJson(text);
            return text;
          },
        );
        matcherName = m.entry.shownName;
        applyMatcher(result.lines, AiInvoiceService.decodeJson(m.text), cands);
      } on AiRouterException catch (e) {
        final why = e.attempts.isEmpty ? e.message : e.attempts.last.result;
        note = 'لم يردّ النموذج المطابِق ($why) — طابقتُ الأسطر محلياً، راجعها.';
      } catch (e) {
        note = 'تعذّرت المطابقة الذكية ($e) — طابقتُ الأسطر محلياً، راجعها.';
      }
    }

    // ── 4) ما تعلّمناه والاسم الحرفي أقوى من أي نموذج
    AiInvoiceService.applyMatching(result.lines, products, aliases, supplierId);
    final engine = matcherName.isEmpty || matcherName == read.entry.shownName
        ? read.entry.shownName
        : 'قرأها ${read.entry.shownName} • طابقها $matcherName';
    return withEngine(result, engine, note);
  }

  /// يقرأ كل الصور: دفعة واحدة، أو دفعات بحد المزوّد (Groq: 3 صور) ثم دمج JSON.
  static Future<String> _readAll(AiModelEntry e, AiKey k, String prompt, List<AiBlob> files) async {
    final max = e.provider.maxImages;
    if (files.length <= max) {
      final text = await AiVisionClient.complete(provider: e.provider, model: e.model, apiKey: k.key, prompt: prompt, files: files);
      _mustBeJson(text);
      return text;
    }
    final parts = <Map<String, dynamic>>[];
    for (var i = 0; i < files.length; i += max) {
      final chunk = files.sublist(i, min(i + max, files.length));
      final p = '$prompt\n\n## ملاحظة: هذه الصفحات ${i + 1}–${i + chunk.length} من ${files.length}. '
          'استخرج أسطر هذه الصفحات فقط، والمجاميع إن ظهرت فيها.';
      final text = await AiVisionClient.complete(provider: e.provider, model: e.model, apiKey: k.key, prompt: p, files: chunk);
      parts.add(_mustBeJson(text));
    }
    return jsonEncode(mergeChunks(parts));
  }

  static Map<String, dynamic> _mustBeJson(String text) {
    try {
      return AiInvoiceService.decodeJson(text);
    } catch (_) {
      throw AiBadOutput('الرد ليس JSON صالحاً');
    }
  }

  /// دمج قراءات دفعات الصفحات: الرأس من أول دفعة فيها رأس، الأسطر كلها، المجاميع من آخر دفعة.
  @visibleForTesting
  static Map<String, dynamic> mergeChunks(List<Map<String, dynamic>> parts) {
    final out = <String, dynamic>{'line_items': <Object?>[]};
    double n(Object? v) => v is num ? v.toDouble() : (double.tryParse('${v ?? ''}'.replaceAll(',', '')) ?? 0);
    for (final p in parts) {
      for (final k in const ['supplier_name', 'invoice_date', 'invoice_number', 'currency']) {
        final v = '${p[k] ?? ''}'.trim();
        if (v.isNotEmpty && '${out[k] ?? ''}'.trim().isEmpty) out[k] = p[k];
      }
      final items = p['line_items'] ?? p['items'];
      if (items is List) (out['line_items'] as List).addAll(items);
      final t = p['totals'];
      if (t is Map && n(t['grand_total']) > 0) out['totals'] = t;
      if (n(p['amount_paid']) > 0) out['amount_paid'] = p['amount_paid'];
      if ('${p['status'] ?? ''}'.trim().isNotEmpty) out['status'] = p['status'];
      // الدفع يُكتب غالباً في آخر صفحة: آخر دفعة فيها دفع مكتوب هي المعتمدة
      final pay = p['payment'];
      if (pay is Map && (n(pay['paid']) > 0 || n(pay['remaining']) > 0 || '${pay['evidence'] ?? ''}'.trim().isNotEmpty || out['payment'] == null)) {
        out['payment'] = pay;
      }
    }
    return out;
  }

  /// رسالة انتظار حد المزوّد بلا اسمه: «ينتظر قليلاً (12 ثانية)…».
  @visibleForTesting
  static String waitStatus(String raw) {
    final m = RegExp(r'(\d+)\s*ثانية').firstMatch(raw);
    return m == null ? 'ينتظر قليلاً…' : 'ينتظر قليلاً (${m.group(1)} ثانية)…';
  }

  /// [chain] مع جعل [firstId] أولاً إن وُجد.
  static List<AiModelEntry> ordered(List<AiModelEntry> chain, String firstId) {
    if (firstId.isEmpty) return chain;
    final i = chain.indexWhere((e) => e.id == firstId);
    if (i <= 0) return chain;
    return [chain[i], ...chain.where((e) => e.id != firstId)];
  }

  /// المطابِق التلقائي: نموذج غير القارئ أولاً (رأي ثانٍ)، والقارئ نفسه آخراً.
  static List<AiModelEntry> preferOther(List<AiModelEntry> chain, AiModelEntry reader) =>
      [...chain.where((e) => e.id != reader.id), ...chain.where((e) => e.id == reader.id)];

  static AiInvoiceResult withEngine(AiInvoiceResult r, String model, String note) => AiInvoiceResult(
        lines: r.lines,
        invoiceNumber: r.invoiceNumber,
        date: r.date,
        currency: r.currency,
        supplierName: r.supplierName,
        grandTotal: r.grandTotal,
        discount: r.discount,
        shipping: r.shipping,
        amountPaid: r.amountPaid,
        isCash: r.isCash,
        remaining: r.remaining,
        previousBalance: r.previousBalance,
        paymentEvidence: r.paymentEvidence,
        model: model,
        engineNote: note,
      );

  // ───────────────────────── المرشحون ─────────────────────────

  static final _numRe = RegExp(r'\d+(?:\.\d+)?');

  static Set<String> _tokens(String s) => AiAliasStore.normalize(s)
      .replaceAll('x', ' ')
      .split(' ')
      .where((t) => t.length > 1 || _numRe.hasMatch(t))
      .toSet();

  static Set<String> _nums(String s) => _numRe.allMatches(AiAliasStore.normalize(s)).map((m) => m.group(0)!).toSet();

  static Set<String> _grams(String s) {
    final t = AiAliasStore.normalize(s).replaceAll(' ', '');
    if (t.length < 3) return {t};
    return {for (var i = 0; i + 3 <= t.length; i++) t.substring(i, i + 3)};
  }

  /// تشابه الحروف (Dice على ثلاثيات) — يلتقط أخطاء الإملاء: «سيمس» ≈ «سيمنس».
  static double dice(String a, String b) {
    final x = _grams(a), y = _grams(b);
    if (x.isEmpty || y.isEmpty) return 0;
    return 2 * x.intersection(y).length / (x.length + y.length);
  }

  /// أقرب [k] مواد لسطر من الفاتورة.
  static List<AiCandidate> candidatesFor(AiInvoiceLine l, List<Product> products, List<AiAlias> aliases, int? supplierId,
      {int k = 8}) {
    final text = '${l.originalName} ${l.cleanName}';
    final a = _tokens(text);
    final aNums = _nums(text);
    final best = <int, AiCandidate>{};
    void offer(Product p, double s, String why) {
      final cur = best[p.id!];
      if (cur == null || s > cur.score) best[p.id!] = AiCandidate(p, s, why);
    }

    final byId = {for (final p in products) if (p.id != null) p.id!: p};
    // تعلّم سابق: الاسم نفسه، أو قريب جداً منه في الإملاء
    final learned = AiAliasStore.lookup(aliases, l.originalName, supplierId);
    if (learned != null && byId[learned] != null) offer(byId[learned]!, 2.0, 'تعلّم سابق');
    for (final al in aliases) {
      final p = byId[al.productId];
      if (p == null) continue;
      final d = max(dice(al.alias, l.originalName), dice(al.alias, l.cleanName));
      if (d >= 0.72) offer(p, 0.9 + d * 0.5, 'قريب من اسم تعلّمناه «${al.alias}»');
    }
    final nOrig = AiAliasStore.normalize(l.originalName), nClean = AiAliasStore.normalize(l.cleanName);
    for (final p in products) {
      if (p.id == null) continue;
      final pn = AiAliasStore.normalize(p.name);
      if (pn.isEmpty) continue;
      if (pn == nOrig || pn == nClean) {
        offer(p, 1.9, 'الاسم نفسه');
        continue;
      }
      final b = _tokens(p.name);
      var tokenScore = 0.0;
      if (a.isNotEmpty && b.isNotEmpty) {
        final inter = a.intersection(b).length;
        tokenScore = inter / b.length * 0.7 + inter / a.length * 0.3;
      }
      final d = max(dice(p.name, l.originalName), dice(p.name, l.cleanName));
      var s = max(tokenScore, d * 0.9);
      // أرقام المقاس: اختلافها يُضعف المرشح ولا يحذفه (المطابِق يرى الصورة ويقرر)
      final bNums = _nums(p.name);
      if (aNums.isNotEmpty && bNums.isNotEmpty && !bNums.every(aNums.contains)) s *= 0.35;
      if (s >= 0.18) offer(p, s, 'تشابه ${(s * 100).round()}%');
    }
    final list = best.values.toList()..sort((x, y) => y.score.compareTo(x.score));
    return list.take(k).toList();
  }

  // ───────────────────────── رسائل التعلّم ─────────────────────────

  /// أسماء هذا المورد السابقة (لتساعد القارئ على قراءة خطه واختصاراته).
  static List<String> pastNames(List<AiAlias> aliases, int? supplierId) => [
        for (final a in aliases)
          if (supplierId != null && a.supplierId == supplierId) a.alias,
      ].take(150).toList();

  /// «مرة ظهر هذا الاسم فغيّره المستخدم إلى هذه المادة» — ما يخص مرشحي هذه الفاتورة أولاً.
  @visibleForTesting
  static List<String> learningMessages(List<AiAlias> aliases, int? supplierId, String supplierName, List<Product> products,
      List<List<AiCandidate>> cands, {int limit = 250}) {
    final byId = {for (final p in products) if (p.id != null) p.id!: p};
    final inPlay = {for (final c in cands) for (final x in c) x.product.id};
    final sorted = aliases.where((a) => byId.containsKey(a.productId)).toList()
      ..sort((x, y) {
        int rank(AiAlias a) => (inPlay.contains(a.productId) ? 2 : 0) + (a.supplierId == supplierId && supplierId != null ? 1 : 0);
        final r = rank(y).compareTo(rank(x));
        return r != 0 ? r : y.hits.compareTo(x.hits);
      });
    final who = supplierName.trim().isEmpty ? 'هذا المورد' : '«${supplierName.trim()}»';
    return [
      for (final a in sorted.take(limit))
        a.supplierId == supplierId && supplierId != null
            ? 'ظهر «${a.alias}» في فاتورة $who فغيّره المستخدم إلى «${byId[a.productId]!.name}» (id ${a.productId})'
                '${a.hits > 1 ? ' — ${a.hits} مرات' : ''}. إذن «${a.alias}» عند $who = هذه المادة.'
            : 'عند مورد آخر: «${a.alias}» = «${byId[a.productId]!.name}» (id ${a.productId}).',
    ];
  }

  // ───────────────────────── التعليمات ─────────────────────────

  static String buildReaderPrompt({String supplierName = '', List<String> pastNames = const []}) {
    final who = supplierName.trim().isEmpty ? '' : ' (المورد: ${supplierName.trim()})';
    final names = pastNames.isEmpty
        ? ''
        : '''

## أسماء مرّت في فواتير هذا المورد سابقاً (لتقرأ خطه واختصاراته — لا تنسخها إن لم تكن في الفاتورة):
${jsonEncode(pastNames)}
''';
    return '''أنت قارئ دقيق لفواتير الشراء التجارية العراقية$who. مهمتك القراءة فقط: استخرج كل سطر كما هو في الفاتورة (صورة أو PDF، مطبوعة أو بخط اليد، كل الصفحات). لا تحاول مطابقة المواد — نموذج آخر سيطابقها.
$names
## لكل سطر مادة:
- original_name: الاسم كما في الفاتورة بالضبط (حرفاً بحرف، بلغته)
- name: الاسم منظّفاً (بلا طول اللفة أو التعبئة)
- qty, price, amount: الكمية، سعر الوحدة، المبلغ
- sale_unit: وحدة الشراء من عمود الوحدة (لفة، كرتون، باكيت، قطعة، كيس، شدة، درزن، متر، كغم، طن، لتر...). صحّح الإملاء: «كارتون»→«كرتون»، «باكت»→«باكيت»، «كيلو»→«كغم»
- units_count: كم وحدة صغرى في وحدة الشراء إن ظهر: «80M» أو «90 متر» في الاسم ⇒ 80/90 و sale_unit «لفة»؛ «كرتون 24» أو «×20» ⇒ 24/20؛ «درزن» = 12؛ وإلا 1
- unit_type: meter أو piece أو weight
- is_free: true للبونص/الهدية/«مجاناً» أو كمية إضافية بسعر 0. عمود «هدية» أو «بونص» فيه رقم ⇒ سطر ثانٍ للمادة نفسها بتلك الكمية و is_free: true
- expiry: تاريخ صلاحية السطر إن وُجد (انظر القواعد أدناه)، وإلا null

## قراءة الأرقام (مهم جداً):
- الأرقام العربية ٠١٢٣٤٥٦٧٨٩ ⇒ 0123456789
- بالدينار: النقطة أو الفارزة قبل 3 أرقام بالضبط فاصل آلاف: «1.500» = 1500، «12.750.000» = 12750000. بالدولار الكسور طبيعية
- «الأسعار بالألف» أو «×1000» في رأس العمود ⇒ اضرب السعر والمبلغ في 1000
- تحقّق من كل سطر: qty × price ≈ amount. إن لم يتطابق فأعد القراءة؛ وإن بقي فاعتمد amount و qty
- خصم على السطر ⇒ price و amount صافيان. خصم على الفاتورة ⇒ totals.discount
- «10+1» ⇒ سطر بكمية 10، وسطر للمادة نفسها بكمية 1 و is_free: true
- لا تُدرج أسطر المجموع والخصم والنقل والرصيد السابق والملاحظات (النقل ⇒ totals.shipping)

## أرجع JSON object فقط:
{
  "supplier_name": "",
  "invoice_date": "YYYY-MM-DD",
  "invoice_number": "",
  "currency": "IQD أو USD",
  "line_items": [
    {"original_name": "", "name": "", "qty": 0, "price": 0, "amount": 0, "sale_unit": "", "units_count": 1, "unit_type": "piece", "is_free": false, "expiry": null}
  ],
  "totals": {"subtotal": 0, "discount": 0, "shipping": 0, "grand_total": 0},
  ${AiInvoiceService.paymentJson}
}

${AiInvoiceService.paymentRules}

${AiInvoiceService.expiryRules}

- التاريخ 18/10/2026 ⇒ 2026-10-18''';
  }

  static String buildMatcherPrompt({
    required List<AiInvoiceLine> lines,
    required List<List<AiCandidate>> candidates,
    required List<String> learning,
    String supplierName = '',
  }) {
    final who = supplierName.trim().isEmpty ? '' : ' (المورد: ${supplierName.trim()})';
    final items = [
      for (var i = 0; i < lines.length; i++)
        {
          'i': i,
          'original_name': lines[i].originalName,
          'name': lines[i].cleanName,
          'qty': lines[i].qty,
          'price': lines[i].price,
          'amount': lines[i].amount,
          'sale_unit': lines[i].saleUnit,
          'units_count': lines[i].unitsCount,
          // [id, الاسم, الوحدة الأساسية, [[وحدة, كم وحدة أساسية فيها]], الكلفة]
          'candidates': [
            for (final c in candidates[i])
              [
                c.product.id,
                c.product.name,
                AiInvoiceService.baseUnitName(c.product),
                AiInvoiceService.cumulativeUnits(c.product),
                if ((c.product.costPrice ?? 0) > 0) c.product.costPrice,
              ]
          ],
        }
    ];
    final learn = learning.isEmpty ? '(لا شيء بعد)' : learning.map((m) => '- $m').join('\n');
    return '''أنت محاسب خبير بمواد المحلات العراقية$who. قرأ نموذج آخر هذه الفاتورة (أمامك صورتها أيضاً)، ومهمتك ربط كل سطر بمادة من موادنا.

## 🧠 رسائل التعلّم (تصحيحات المستخدم السابقة — الأولوية القصوى):
$learn
تعلّم منها أسلوب المورد في التسمية (اختصاراته، ترتيب المقاسات، كتابة الماركة) وطبّقه على كل الأسطر.

## الأسطر ومرشحوها (لكل سطر: candidates = [id, الاسم, الوحدة الأساسية, [[وحدة, كم وحدة أساسية فيها]], الكلفة]):
${jsonEncode(items)}

## القواعد:
1. اختر matched_product_id من candidates ذلك السطر فقط — أو null إن لم يطابق أحدها (مادة جديدة). لا تخترع id أبداً.
2. نفس العناصر = نفس المادة: الماركة + النوع + المقاس/الحجم/الوزن/اللون. اختلاف المقاس (2×1.5 مقابل 2×2.5، 500مل مقابل 1لتر) = مادة مختلفة.
3. ترتيب المقاس قد ينعكس (1.5*2 = 2×1.5). الإنجليزي ≈ العربي صوتياً (Berly ≈ بيرلي، Flex ≈ فلكس، Siemens/سيمس ≈ سيمنس).
4. الوحدة: إن كان للمادة المختارة وحدة بنفس المعنى فاكتب sale_unit باسمها عندنا حرفياً، و units_count = رقمها عندنا — إلا إن كتبت الفاتورة تعبئة مختلفة صراحة (اذكر ذلك في reason).
5. انظر إلى الصورة إن شككت في قراءة سطر. إن كانت الكمية أو السعر أو المبلغ مقروءة خطأً بوضوح فصحّحها في fix واذكر السبب.
6. confidence: 0.9–1 مؤكد، 0.7–0.89 جيد، 0.5–0.69 محتمل، أقل من 0.5 ⇒ matched_product_id = null.

## أرجع JSON object فقط:
{"lines": [{"i": 0, "matched_product_id": 12, "confidence": 0.95, "reason": "تطابق: Berly=بيرلي، 1.5*2=2×1.5", "sale_unit": "لفة", "units_count": 80, "fix": null}]}
- fix إن لزم: {"qty": 0, "price": 0, "amount": 0}
- سطر لكل i — لا تحذف سطراً ولا تضف سطراً.''';
  }

  // ───────────────────────── تطبيق المطابِق ─────────────────────────

  @visibleForTesting
  static void applyMatcher(List<AiInvoiceLine> lines, Map<String, dynamic> json, List<List<AiCandidate>> cands) {
    final items = json['lines'] ?? json['line_items'];
    if (items is! List) return;
    double num0(Object? v) => v is num ? v.toDouble() : (double.tryParse('${v ?? ''}'.replaceAll(',', '')) ?? 0);
    for (final raw in items) {
      if (raw is! Map) continue;
      final i = (raw['i'] as num?)?.toInt();
      if (i == null || i < 0 || i >= lines.length) continue;
      final l = lines[i];
      final allowed = {for (final c in cands[i]) c.product.id};
      final mid = int.tryParse('${raw['matched_product_id'] ?? ''}');
      final conf = num0(raw['confidence']).clamp(0, 1).toDouble();
      final reason = '${raw['reason'] ?? ''}'.trim();
      if (mid != null && allowed.contains(mid) && conf >= 0.5) {
        l.productId = mid;
        l.confidence = conf;
        l.source = AiMatchSource.ai;
        l.reason = reason.isEmpty ? 'طابقها النموذج' : reason;
      } else {
        l.productId = null;
        l.confidence = 0;
        l.source = AiMatchSource.none;
        l.reason = mid != null && !allowed.contains(mid) ? 'اقترح النموذج مادة من خارج المرشحين — تجاهلتها' : (reason.isEmpty ? 'لم أجد مادة مطابقة' : reason);
      }
      final su = '${raw['sale_unit'] ?? ''}'.trim();
      if (su.isNotEmpty) l.saleUnit = su;
      final uc = num0(raw['units_count']);
      if (uc > 0) l.unitsCount = uc;
      final fix = raw['fix'];
      if (fix is Map) {
        final q = num0(fix['qty']), p = num0(fix['price']), a = num0(fix['amount']);
        // نقبل التصحيح فقط إن كان متسقاً: الكمية × السعر ≈ المبلغ
        if (q > 0 && p >= 0 && a >= 0 && (q * p - a).abs() <= max(1.0, a * 0.02)) {
          final old = 'كمية ${l.qty} × ${l.price} = ${l.amount}';
          l.qty = q;
          l.price = p;
          l.amount = a;
          l.note = '${l.note.isEmpty ? '' : '${l.note}\n'}صحّح المطابِق القراءة (كانت $old)';
        }
      }
    }
  }
}
