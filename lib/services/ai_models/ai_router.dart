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
//   • خادم مشغول/اتصال           ⇒ إعادة بالمفتاح نفسه مرة واحدة بعد ثانيتين، ثم التالي.
//   • انتهت المهلة               ⇒ النموذج التالي مباشرة (إعادة الطلب نفسه = دقيقة ونصف أخرى).
//   • ما يتكرر عند كل فتح (مفتاح بلا رصيد 402، مفتاح مرفوض، نموذج أُوقف 404) يُحفظ في
//     الجهاز فلا يُجرَّب بعد إعادة التشغيل حتى تنقضي مدته — كان كل فتح يبدأ بخطأ «لا رصيد».
//   • الطلب مرفوض/لا يقرأ الصور/
//     غير موجود/أكبر من حده      ⇒ النموذج التالي (لا فائدة من مفتاح آخر).
//   • رد فارغ أو ليس JSON        ⇒ النموذج التالي.
// الحد: 8 محاولات أو 3 دقائق، ثم رسالة فيها ما جُرّب وسبب فشل كل محاولة.


import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  /// مفاتيح مُستراحة: معرّف المفتاح ← حتى متى. ونماذج متوقفة: «model:معرّف النموذج».
  static final Map<String, DateTime> _rest = {};

  static const _prefsKey = 'ai_router_rest_v1';
  static bool _loaded = false;
  static bool _persist = true;

  /// الاستراحات الطويلة (ساعة فأكثر) تُحفظ في الجهاز.
  static Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    if (!_persist) return;
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      final m = jsonDecode(raw);
      if (m is! Map) return;
      final t = now();
      m.forEach((k, v) {
        final until = DateTime.tryParse('$v');
        if (until != null && until.isAfter(t)) _rest['$k'] = until;
      });
    } catch (_) {}
  }

  static Future<void> _save() async {
    if (!_persist) return;
    try {
      final t = now();
      final keep = {
        for (final e in _rest.entries)
          if (e.value.isAfter(t) && e.value.difference(t) >= const Duration(hours: 1)) e.key: e.value.toIso8601String(),
      };
      await (await SharedPreferences.getInstance()).setString(_prefsKey, jsonEncode(keep));
    } catch (_) {}
  }

  static String _modelKey(AiModelEntry e) => 'model:${e.id}';
  static bool _modelResting(AiModelEntry e) {
    final until = _rest[_modelKey(e)];
    return until != null && now().isBefore(until);
  }

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
  static void resetForTest() {
    _rest.clear();
    _loaded = true;
    _persist = false;
  }

  /// للإعدادات: «أعد تجربة كل المفاتيح والنماذج» (بعد شحن رصيد أو تغيير مفتاح).
  static Future<void> clearRests() async {
    _rest.clear();
    await _save();
  }

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
    await _load();
    final attempts = <AiAttempt>[];
    final started = now();
    var changed = false;
    void restKey(AiKey k, Duration d) {
      _restKey(k, d);
      if (d >= const Duration(hours: 1)) changed = true;
    }
    bool outOfBudget() => attempts.length >= maxAttempts || now().difference(started) > budget;

    if (chain.isEmpty) {
      throw AiRouterException('لا يوجد نموذج مفعّل له مفتاح — أضف مفتاحاً من الإعدادات ← النظام والأدوات ← نماذج الذكاء الاصطناعي', attempts);
    }
    for (final entry in chain) {
      if (outOfBudget()) break;
      if (_modelResting(entry)) {
        attempts.add(AiAttempt(entry.shownName, '—', 'النموذج متوقف مؤقتاً (فشل سابق)'));
        continue;
      }
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
            if (changed) await _save();
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
                  restKey(key, e.daily ? const Duration(hours: 6) : const Duration(seconds: 70));
                }
              case AiErrorKind.auth:
                restKey(key, const Duration(days: 1));
              case AiErrorKind.server:
              case AiErrorKind.network:
                if (!retried) {
                  retried = true;
                  again = true; // المفتاح نفسه مرة واحدة
                }
              case AiErrorKind.timeout:
                nextModel = true; // لا نعيد طلباً استغرق المهلة كاملة
              case AiErrorKind.notVision:
              case AiErrorKind.notFound:
                // نموذج أُوقف أو لا يقرأ الصور: لا يُجرَّب ثلاثة أيام (يُفحص من الإعدادات متى شئت)
                _rest[_modelKey(entry)] = now().add(const Duration(days: 3));
                changed = true;
                nextModel = true;
              case AiErrorKind.badRequest:
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
    if (changed) await _save();
    throw AiRouterException(
        outOfBudget() ? 'توقفت المحاولات (الحد ${attempts.length} محاولة أو 3 دقائق):' : 'فشلت كل النماذج:', attempts);
  }
}
