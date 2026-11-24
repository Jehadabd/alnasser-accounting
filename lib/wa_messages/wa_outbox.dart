// lib/wa_messages/wa_outbox.dart
//
// 📤 صندوق الصادر: كل رسائل واتساب (القواعد التلقائية، الإرسال اليدوي، مواعيد المطالبة،
// حساب العميل) تمر من هنا واحدة بعد الأخرى:
//   • بالطريقة المضبوطة (الخادم أو WhatsApp Desktop)، بفاصل عشوائي وحد يومي مشترك.
//   • المبلغ يُقرأ من سجل الديون لحظة الإرسال: من صار دينه صفراً لا تصله مطالبة.
//   • كل نتيجة في سجل الرسائل. فشلان متتاليان (لا بسبب رقم ليس على واتساب) ⇒ يتوقف.
//   • لا يغيّر أي دين أو معاملة.
//   • 📊 حد اليوم: ما يزيد يُرحَّل (WaCarryOver) ويُرسل أول اليوم التالي. حد الساعة: ينتظر حتى تفرغ.

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../erp/activity/activity_log.dart';
import '../owner/wa_auto/wa_auto_reminder.dart';
import '../owner/wa_auto/wa_server_client.dart';
import '../owner/wa_auto/wa_usage_mark.dart';
import '../services/customer_balance_guard.dart'; // 🛡️ الرصيد = مجموع المعاملات
import '../services/database_service.dart';
import '../services/sync_perks.dart';
import 'wa_capacity.dart';
import 'wa_compose.dart';
import 'wa_message_log.dart';
import 'wa_rules.dart';

/// رسالة تنتظر الإرسال.
class WaJob {
  WaJob({
    required this.customerId,
    required this.name,
    required this.phone,
    required this.source,
    required this.options,
    this.ruleId,
    this.ruleName,
    this.requireDebt = true,
  });
  final int customerId;
  final String name, phone;

  /// 'rule' | 'manual' | 'reminder' | 'card'
  final String source;
  final String? ruleId, ruleName;
  final WaMessageOptions options;

  /// true (المطالبات) = لا تُرسل لمن لا دين عليه لحظة الإرسال. false = رسائل عامة (الولاء).
  final bool requireDebt;

  String get key => '$customerId|${ruleId ?? source}';

  Map<String, dynamic> toJson() => {
        'c': customerId,
        'n': name,
        'p': phone,
        's': source,
        'r': ruleId,
        'rn': ruleName,
        'o': options.toJson(),
        'd': requireDebt,
      };

  static WaJob? fromJson(Map<String, dynamic> j) {
    final c = j['c'];
    if (c is! int || '${j['p'] ?? ''}'.isEmpty) return null;
    return WaJob(
      customerId: c,
      name: '${j['n'] ?? ''}',
      phone: '${j['p']}',
      source: '${j['s'] ?? 'rule'}',
      ruleId: j['r'] as String?,
      ruleName: j['rn'] as String?,
      options: WaMessageOptions.fromJson((j['o'] as Map?)?.cast<String, dynamic>()),
      requireDebt: j['d'] != false,
    );
  }
}

/// 📦 رسائل تجاوزت حد اليوم: تُحفظ وتُرسل أول اليوم التالي قبل غيرها.
/// تُفحص كأي رسالة لحظة الإرسال (الدين الآن، تطابق الكشف)؛ وما مضى عليه 7 أيام يُهمل.
class WaCarryOver {
  WaCarryOver._();
  static const _k = 'wa_carry_over_v1';

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static Future<List<Map<String, dynamic>>> _read(SharedPreferences p) async {
    try {
      final raw = p.getString(_k);
      if (raw == null || raw.isEmpty) return [];
      return [for (final x in jsonDecode(raw) as List) if (x is Map) x.cast<String, dynamic>()];
    } catch (_) {
      return [];
    }
  }

  /// كم رسالة مرحَّلة الآن.
  static Future<int> count() async => (await _read(await SharedPreferences.getInstance())).length;

  static Future<void> add(List<WaJob> jobs) async {
    if (jobs.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    final list = await _read(p);
    final keys = {for (final x in list) '${x['c']}|${x['r'] ?? x['s']}'};
    final today = _day(DateTime.now());
    for (final j in jobs) {
      if (keys.add(j.key)) list.add({...j.toJson(), 'day': today});
    }
    await p.setString(_k, jsonEncode(list));
  }

  /// ما رُحِّل من يوم سابق (يُزال من المخزن). ما رُحِّل اليوم يبقى لغدٍ.
  static Future<List<WaJob>> takeDue() async {
    final p = await SharedPreferences.getInstance();
    final list = await _read(p);
    if (list.isEmpty) return const [];
    final now = DateTime.now();
    final today = _day(now);
    final oldest = _day(now.subtract(const Duration(days: 7)));
    final due = <WaJob>[], keep = <Map<String, dynamic>>[];
    for (final x in list) {
      final d = '${x['day'] ?? ''}';
      if (d == today) {
        keep.add(x);
      } else if (d.compareTo(oldest) >= 0) {
        final j = WaJob.fromJson(x);
        if (j != null) due.add(j);
      }
    }
    await p.setString(_k, jsonEncode(keep));
    return due;
  }
}

class WaOutboxState {
  const WaOutboxState({
    this.running = false,
    this.total = 0,
    this.sent = 0,
    this.failed = 0,
    this.skipped = 0,
    this.current,
    this.nextAt,
    this.note,
  });
  final bool running;
  final int total, sent, failed, skipped;
  final String? current;
  final DateTime? nextAt;
  final String? note;
  int get done => sent + failed + skipped;
}

class WaOutbox {
  WaOutbox._();

  static final ValueNotifier<WaOutboxState> state = ValueNotifier(const WaOutboxState());
  static final _queue = <WaJob>[];
  static bool _stop = false;
  static bool _pumping = false;

  static bool get running => _pumping;
  static int get queued => _queue.length;

  /// يضيف رسائل (بلا تكرار لنفس العميل بنفس القاعدة) ويبدأ إن لم يكن يعمل. يعيد عدد المضاف.
  static int enqueue(List<WaJob> jobs) {
    if (!SyncPerks.enabled) return 0; // ⭐ ميزة اشتراك المزامنة
    final keys = {for (final j in _queue) j.key};
    var added = 0;
    for (final j in jobs) {
      if (keys.add(j.key)) {
        _queue.add(j);
        added++;
      }
    }
    if (added > 0 && !_pumping) unawaited(_pump());
    return added;
  }

  /// يوقف الإرسال ويفرغ ما ينتظر (ما أُرسل يبقى في السجل).
  static void stop() {
    _stop = true;
    _queue.clear();
  }

  static String _hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static Future<void> _pump() async {
    _pumping = true;
    _stop = false;
    var sent = 0, failed = 0, skipped = 0, failsInRow = 0, total = _queue.length;
    String? note;
    void emit({String? current, DateTime? nextAt, bool running = true}) => state.value = WaOutboxState(
          running: running,
          total: total,
          sent: sent,
          failed: failed,
          skipped: skipped,
          current: current,
          nextAt: nextAt,
          note: note,
        );
    try {
      final s = await WaAutoReminder.load();
      if (!s.enabled || !s.riskAccepted) {
        note = 'الإرسال الآلي مطفأ — فعّله من «طريقة الإرسال والأمان»';
        _queue.clear();
        return;
      }
      if (s.viaServer) {
        emit(current: 'يجهّز الخادم…');
        try {
          final st = await WaServerClient.ensureReady();
          if (!st.linked) {
            note = 'الخادم غير مربوط برقم واتساب — اربطه من «خادم واتساب»';
            _queue.clear();
            return;
          }
        } on WaServerException catch (e) {
          note = 'الخادم: ${e.message}';
          _queue.clear();
          return;
        }
      }
      await WaUsageMark.record(s.via); // 🔖 علامة دائمة: الخدمة شُغّلت
      final db = await DatabaseService().database;
      final rnd = Random();
      var first = true;
      while (_queue.isNotEmpty && !_stop) {
        if (await WaMessageLog.sentToday() >= s.maxPerDay) {
          // 📦 لا يضيع شيء: ما بقي يُرحَّل ويُرسل أول اليوم التالي (ولو لم يكن يوم القاعدة)
          final rest = List<WaJob>.of(_queue);
          await WaCarryOver.add(rest);
          note = 'بلغ حد اليوم (${s.maxPerDay}) — ${rest.length} رسالة تُرسل غداً أولاً';
          _queue.clear();
          break;
        }
        // 🕐 حد الساعة: ينتظر حتى تخرج أقدم رسالة من نافذة الساعة
        final gate = WaCapacity.hourGate(
            await WaMessageLog.sentSince(DateTime.now().subtract(const Duration(hours: 1))), s.maxPerHour, DateTime.now());
        if (gate != null) {
          note = 'بلغ حد الساعة (${s.maxPerHour}) — يكمل الساعة ${_hm(gate)}';
          emit(nextAt: gate);
          while (DateTime.now().isBefore(gate) && !_stop) {
            await Future<void>.delayed(const Duration(seconds: 1));
          }
          if (_stop) break;
          note = null;
          first = true; // انتظر ما يكفي — لا فاصل إضافي
          continue;
        }
        // ⏳ فاصل عشوائي قبل كل رسالة عدا الأولى (يُفحص الإيقاف كل ثانية)
        if (!first) {
          final wait = s.minDelay + rnd.nextInt(max(1, s.maxDelay - s.minDelay + 1));
          final next = DateTime.now().add(Duration(seconds: wait));
          emit(nextAt: next);
          while (DateTime.now().isBefore(next) && !_stop) {
            await Future<void>.delayed(const Duration(seconds: 1));
          }
          if (_stop) break;
        }
        first = false;
        final job = _queue.removeAt(0);
        total = max(total, sent + failed + skipped + _queue.length + 1);

        // المبلغ من سجل الديون الآن
        final r = await db.rawQuery(
            'SELECT current_total_debt AS d, COALESCE(is_deleted, 0) AS del FROM customers WHERE id = ?',
            [job.customerId]);
        final debt = r.isEmpty ? 0.0 : ((r.first['d'] as num?)?.toDouble() ?? 0);
        if (r.isEmpty || r.first['del'] != 0 || (job.requireDebt && debt < 0.5)) {
          skipped++;
          await WaMessageLog.add(
              customerId: job.customerId,
              name: job.name,
              phone: job.phone,
              source: job.source,
              ruleId: job.ruleId,
              ruleName: job.ruleName,
              status: 'skipped',
              error: r.isEmpty || r.first['del'] != 0 ? 'العميل محذوف' : 'لا دين عليه الآن',
              amount: debt);
          first = true; // لا انتظار بلا إرسال
          emit();
          continue;
        }
        // 🛡️ المبلغ المطالَب به والكشف المرفق يجب أن يتطابقا بالفلس — وإلا لا تُرسل المطالبة
        final chk = await CustomerBalanceGuard.check(job.customerId, db: db);
        if (chk != null && !chk.ok) {
          skipped++;
          await WaMessageLog.add(
              customerId: job.customerId,
              name: job.name,
              phone: job.phone,
              source: job.source,
              ruleId: job.ruleId,
              ruleName: job.ruleName,
              status: 'skipped',
              error: chk.message,
              amount: debt);
          first = true;
          emit();
          continue;
        }
        emit(current: job.name);
        String? err;
        String? extra;
        var notOnWa = false;
        var attachLabel = '';
        try {
          final c = await WaCompose.compose(
            t: WaTarget(id: job.customerId, name: job.name, phone: job.phone, debt: debt),
            o: job.options,
            defaultTemplate: s.template,
            viaServer: s.viaServer,
          );
          attachLabel = c.attachLabel;
          final res = await WaAutoReminder.deliver(s, job.phone, c.text, pdf: c.pdf, pdfName: c.pdfName);
          err = res.error;
          notOnWa = res.notOnWhatsApp;
          extra = res.note;
        } catch (e) {
          err = 'تعذّر تجهيز الرسالة: $e';
        }
        // 🕐 الخادم رفض لأن ساعته امتلأت (حدّه أقل من حد البرنامج): ليست فشلاً — تعود الرسالة وتنتظر
        if (err != null && err == WaServerClient.errorText('hour_limit')) {
          _queue.insert(0, job);
          final until = DateTime.now().add(const Duration(minutes: 5));
          note = 'الخادم بلغ حد الساعة — محاولة جديدة ${_hm(until)}';
          emit(nextAt: until);
          while (DateTime.now().isBefore(until) && !_stop) {
            await Future<void>.delayed(const Duration(seconds: 1));
          }
          if (_stop) break;
          note = null;
          first = true;
          continue;
        }
        if (err == null) {
          sent++;
          failsInRow = 0;
        } else {
          failed++;
          if (!notOnWa) failsInRow++;
        }
        await WaMessageLog.add(
            customerId: job.customerId,
            name: job.name,
            phone: job.phone,
            source: job.source,
            ruleId: job.ruleId,
            ruleName: job.ruleName,
            status: err == null ? 'sent' : 'failed',
            error: err ?? extra,
            amount: debt,
            attach: attachLabel);
        if (failsInRow >= 2) {
          note = 'توقف بعد فشلين متتاليين: $err';
          _queue.clear();
          break;
        }
        emit();
      }
      if (_stop) note ??= 'أُوقف يدوياً';
      if (s.viaServer) {
        try {
          await WaServerClient.pullState(); // نسخة الجلسة الأحدث عند البرنامج
        } catch (_) {}
      }
      if (sent > 0) await WaUsageMark.record(s.via, sends: sent);
      if (sent + failed > 0) {
        await ActivityLog.log('إرسال', 'رسائل واتساب',
            'أُرسل $sent، فشل $failed، تُخطّي $skipped${note == null ? '' : ' — $note'}');
      }
    } catch (e) {
      note = 'خطأ: $e';
      _queue.clear();
    } finally {
      _pumping = false;
      state.value = WaOutboxState(
          total: total, sent: sent, failed: failed, skipped: skipped, note: note ?? 'انتهى الإرسال');
      // أُضيف شيء أثناء الإنهاء؟
      if (_queue.isNotEmpty && !_stop) unawaited(_pump());
    }
  }
}
