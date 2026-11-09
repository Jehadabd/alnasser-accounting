// lib/wa_messages/wa_outbox.dart
//
// 📤 صندوق الصادر: كل رسائل واتساب (القواعد التلقائية، الإرسال اليدوي، مواعيد المطالبة،
// حساب العميل) تمر من هنا واحدة بعد الأخرى:
//   • بالطريقة المضبوطة (الخادم أو WhatsApp Desktop)، بفاصل عشوائي وحد يومي مشترك.
//   • المبلغ يُقرأ من سجل الديون لحظة الإرسال: من صار دينه صفراً لا تصله مطالبة.
//   • كل نتيجة في سجل الرسائل. فشلان متتاليان (لا بسبب رقم ليس على واتساب) ⇒ يتوقف.
//   • لا يغيّر أي دين أو معاملة.

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../erp/activity/activity_log.dart';
import '../owner/wa_auto/wa_auto_reminder.dart';
import '../owner/wa_auto/wa_server_client.dart';
import '../owner/wa_auto/wa_usage_mark.dart';
import '../services/database_service.dart';
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
  });
  final int customerId;
  final String name, phone;

  /// 'rule' | 'manual' | 'reminder' | 'card'
  final String source;
  final String? ruleId, ruleName;
  final WaMessageOptions options;

  String get key => '$customerId|${ruleId ?? source}';
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
          note = 'بلغ الحد اليومي (${s.maxPerDay}) — ما بقي يُرسل غداً (القواعد تعيده وحدها)';
          _queue.clear();
          break;
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
        if (r.isEmpty || r.first['del'] != 0 || debt < 0.5) {
          skipped++;
          await WaMessageLog.add(
              customerId: job.customerId,
              name: job.name,
              phone: job.phone,
              source: job.source,
              ruleId: job.ruleId,
              ruleName: job.ruleName,
              status: 'skipped',
              error: 'لا دين عليه الآن',
              amount: debt);
          first = true; // لا انتظار بلا إرسال
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
