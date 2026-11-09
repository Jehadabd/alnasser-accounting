// lib/marketing/marketing_publisher.dart
//
// ⏰ النشر الآلي للمنشورات المجدولة — كل دقيقة ما دام البرنامج مفتوحاً (الجهاز الرئيسي):
//   • حدودنا أشد من حدود Meta: منشور كل 15 دقيقة على الأقل، و10 في اليوم كحد أقصى.
//   • كل منشور يُحجز قبل نشره (لا يُنشر مرتين)، ونتيجته تُحفظ (رقمه في Meta أو سبب الفشل).
//   • فشل الرمز أو الصلاحية ⇒ يتوقف النشر حتى يُصلَح (لا محاولات متكررة على Meta).

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'marketing_store.dart';
import 'meta_graph_client.dart';

class MarketingPublisher {
  MarketingPublisher._();

  static const minGap = Duration(minutes: 15);
  static const maxPerDay = 10;

  static Timer? _timer;
  static bool _busy = false;

  static void start() {
    _timer ??= Timer.periodic(const Duration(minutes: 1), (_) => unawaited(tick()));
    unawaited(tick());
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// ينشر منشوراً واحداً مستحقاً (إن سمحت الحدود). يعيد رسالة لما حدث أو null.
  static Future<String?> tick({MarketingStore? store}) async {
    if (_busy) return null;
    _busy = true;
    final s = store ?? MarketingStore();
    try {
      final cfg = await s.settings();
      if (cfg['auto'] != '1') return null;
      final pageId = cfg['page_id'];
      final token = await s.token();
      if (pageId == null || pageId.isEmpty || token == null) return null;
      final due = await s.due(DateTime.now());
      if (due.isEmpty) return null;
      if (await s.publishedToday() >= maxPerDay) return 'بلغ حد النشر اليومي ($maxPerDay)';
      final last = await s.lastPublished();
      if (last != null && DateTime.now().difference(last) < minGap) return null;
      final p = due.first;
      if (p.id == null || !await s.claim(p.id!)) return null;
      return await publish(s, MetaGraphClient(token), p, pageId: pageId, igId: cfg['ig_id']);
    } catch (e) {
      debugPrint('📣 النشر: $e');
      return '$e';
    } finally {
      _busy = false;
    }
  }

  /// ينشر [p] الآن (بعد حجزه) ويحفظ النتيجة.
  static Future<String> publish(MarketingStore s, MetaGraphClient c, MkPost p, {required String pageId, String? igId}) async {
    final problem = p.problem;
    if (problem != null) {
      await s.markResult(p.id!, error: problem);
      return problem;
    }
    String? fb, ig;
    final errors = <String>[];
    if (p.facebook) {
      try {
        final img = (p.imagePath ?? '').isEmpty ? null : File(p.imagePath!);
        fb = img != null && await img.exists() ? await c.postPhoto(pageId, img, p.text) : await c.postText(pageId, p.text);
      } on MetaException catch (e) {
        errors.add('فيسبوك: ${e.message}');
      }
    }
    if (p.instagram) {
      if (igId == null || igId.isEmpty) {
        errors.add('إنستغرام: لا حساب إنستغرام أعمال مرتبط بالصفحة');
      } else {
        try {
          ig = await c.postInstagram(igId, p.imageUrl!, p.text);
        } on MetaException catch (e) {
          errors.add('إنستغرام: ${e.message}');
        }
      }
    }
    // نُشر على قناة واحدة على الأقل = منشور (والخطأ يبقى ظاهراً للأخرى)
    final ok = fb != null || ig != null;
    await s.markResult(p.id!, fbId: fb, igId: ig, error: ok ? null : errors.join(' • '));
    if (ok && errors.isNotEmpty) {
      await s.savePost(MkPost(
        id: null,
        text: p.text,
        imagePath: p.imagePath,
        imageUrl: p.imageUrl,
        at: p.at,
        facebook: fb == null && p.facebook,
        instagram: ig == null && p.instagram,
        status: MkStatus.failed,
        error: errors.join(' • '),
        campaignId: p.campaignId,
      ));
    }
    return ok ? 'نُشر' : errors.join(' • ');
  }
}
