// lib/services/ai_models/ai_router.dart
//
// 🔀 تجربة النماذج بالترتيب، والمفاتيح لكل نموذج — دورة واحدة فقط.
//
// حسب سبب الفشل:
//   • نفدت الحصة (429/402)      ⇒ المفتاح التالي للنموذج نفسه. المفتاح يُستراح: دقيقة
//                                 (حد الدقيقة) أو 6 ساعات (حصة اليوم) — لا يُجرَّب خلالها.
//                                 حد الدقيقة ولا بديل (آخر مفتاح لآخر نموذج) ⇒ انتظار ما يطلبه
//                                 المزوّد (حتى 45 ثانية) ثم إعادة مرة واحدة (Groq: 8 آلاف توكن/دقيقة).
//   • المفتاح مرفوض (401/403)   ⇒ المفتاح التالي، ويُستراح المفتاح حتى إعادة التشغيل.
//   • خادم مشغول/مهلة/اتصال     ⇒ إعادة بالمفتاح نفسه مرة واحدة بعد ثانيتين، ثم التالي.
//   • الطلب مرفوض/لا يقرأ الصور/
//     غير موجود/أكبر من حده      ⇒ النموذج التالي (لا فائدة من مفتاح آخر).
//   • رد فارغ أو ليس JSON        ⇒ النموذج التالي.
// الحد: 8 محاولات أو 3 دقائق، ثم رسالة فيها ما جُرّب وسبب فشل كل محاولة.


import 'package:flutter/foundation.dart';

import 'ai_models_config.dart';
import 'ai_vision_client.dart';

class AiAttempt {
  AiAttempt(this.model, this.key, this.result);
  final String model;
  final String key;
  final String result;
  @override
  String toString() => '• $model ($key): $result';
}

class AiRunResult {
  AiRunResult(this.text, this.entry, this.attempts);
  final String text;
  final AiModelEntry entry;
  final List<AiAttempt> attempts;
}

class AiRouterException implements Exception {
  AiRouterException(this.message, this.attempts);
  final String message;
  final List<AiAttempt> attempts;
  @override
  String toString() => attempts.isEmpty ? message : '$message\n${attempts.join('\n')}';
}

/// رد النموذج غير صالح (ليس JSON مثلاً) — ننتقل إلى النموذج التالي.
class AiBadOutput implements Exception {
  AiBadOutput(this.message);
  final String message;
  @override
  String toString() => message;
}

class AiRouter {
  AiRouter._();

  /// مفاتيح مُستراحة: معرّف المفتاح ← حتى متى.
  static final Map<String, DateTime> _rest = {};

  @visibleForTesting
  static Duration retryDelay = const Duration(seconds: 2);

  /// أطول انتظار لحد الدقيقة قبل الإعادة.
  @visibleForTesting
  static Duration maxQuotaWait = const Duration(seconds: 45);

  @visibleForTesting
  static DateTime Function() now = DateTime.now;

  static bool resting(AiKey k) {
    final until = _rest[k.id];
    return until != null && now().isBefore(until);
  }

  static void _restKey(AiKey k, Duration d) => _rest[k.id] = now().add(d);

  @visibleForTesting
  static void resetForTest() => _rest.clear();

  /// يجرّب [chain] بالترتيب حتى ينجح [send]. [send] يرمي AiCallException أو AiBadOutput.
  static Future<AiRunResult> run({
    required List<AiModelEntry> chain,
    required Map<AiProvider, List<AiKey>> keys,
    required Future<String> Function(AiModelEntry entry, AiKey key) send,
    int maxAttempts = 8,
    Duration budget = const Duration(minutes: 3),
    void Function(AiModelEntry entry)? onTry,
    void Function(String status)? onWait,
  }) async {
    final attempts = <AiAttempt>[];
    final started = now();
    bool outOfBudget() => attempts.length >= maxAttempts || now().difference(started) > budget;

    if (chain.isEmpty) {
      throw AiRouterException('لا يوجد نموذج مفعّل له مفتاح — أضف مفتاحاً من الإعدادات ← النظام والأدوات ← نماذج الذكاء الاصطناعي', attempts);
    }
    for (final entry in chain) {
      if (outOfBudget()) break;
      final all = keys[entry.provider] ?? const <AiKey>[];
      final usable = all.where((k) => !resting(k)).toList();
      if (usable.isEmpty) {
        attempts.add(AiAttempt(entry.shownName, '—', all.isEmpty ? 'لا مفتاح لـ ${entry.provider.label}' : 'كل المفاتيح في استراحة (نفدت حصتها)'));
        continue;
      }
      onTry?.call(entry);
      var nextModel = false;
      for (final key in usable) {
        if (nextModel || outOfBudget()) break;
        final lastOption = identical(entry, chain.last) && identical(key, usable.last);
        var retried = false;
        var waitedQuota = false;
        while (true) {
          if (outOfBudget()) break;
          var again = false;
          var wait = retryDelay;
          try {
            final text = await send(entry, key);
            attempts.add(AiAttempt(entry.shownName, key.masked, 'نجح'));
            return AiRunResult(text, entry, attempts);
          } on AiBadOutput catch (e) {
            attempts.add(AiAttempt(entry.shownName, key.masked, e.message));
            nextModel = true;
          } on AiCallException catch (e) {
            attempts.add(AiAttempt(entry.shownName, key.masked, e.message));
            final w = e.retryAfter ?? const Duration(seconds: 20);
            switch (e.kind) {
              case AiErrorKind.quota:
                if (!e.daily && lastOption && !waitedQuota && w <= maxQuotaWait) {
                  // لا بديل: ننتظر حد الدقيقة ونعيد مرة واحدة بدل أن نفشل
                  waitedQuota = true;
                  again = true;
                  wait = w + const Duration(milliseconds: 800);
                  onWait?.call('انتظار حد الدقيقة في ${entry.provider.label} (${(wait.inMilliseconds / 1000).ceil()} ثانية)…');
                } else {
                  _restKey(key, e.daily ? const Duration(hours: 6) : const Duration(seconds: 70));
                }
              case AiErrorKind.auth:
                _restKey(key, const Duration(days: 1));
              case AiErrorKind.server:
              case AiErrorKind.timeout:
              case AiErrorKind.network:
                if (!retried) {
                  retried = true;
                  again = true; // المفتاح نفسه مرة واحدة
                }
              case AiErrorKind.badRequest:
              case AiErrorKind.notVision:
              case AiErrorKind.notFound:
              case AiErrorKind.tooLarge:
              case AiErrorKind.empty:
                nextModel = true;
            }
          } catch (e) {
            // خطأ غير متوقع في معالجة الرد: النموذج التالي
            attempts.add(AiAttempt(entry.shownName, key.masked, 'خطأ في معالجة الرد: $e'));
            nextModel = true;
          }
          if (!again) break;
          await Future<void>.delayed(wait);
        }
      }
    }
    throw AiRouterException(
        outOfBudget() ? 'توقفت المحاولات (الحد ${attempts.length} محاولة أو 3 دقائق):' : 'فشلت كل النماذج:', attempts);
  }
}
