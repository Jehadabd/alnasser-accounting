// lib/wa_messages/wa_scheduler.dart
//
// 🕒 مُشغّل القواعد التلقائية: كل دقيقة ما دام البرنامج مفتوحاً (يقيّم القواعد كل 5 دقائق):
//   • قاعدة «تلقائي» حلّ موعدها ⇒ تُرسل لمن تنطبق عليهم بلا أي نافذة — مثل التنبيهات.
//   • قاعدة «بموافقتي» ⇒ نافذة بالقائمة مرة واحدة في اليوم، ولا يُرسل شيء حتى تضغط «أرسل».
// على الجهاز الرئيسي فقط (لا يرسل جهازان الرسالة نفسها)، ولمدير البرنامج.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:shared_preferences/shared_preferences.dart';

import '../owner/wa_auto/wa_auto_reminder.dart';
import '../owner/wa_auto/wa_local_server.dart';
import '../owner/wa_auto/wa_server_client.dart';
import '../services/database_service.dart';
import '../services/debt_reminders.dart';
import 'wa_message_log.dart';
import 'wa_outbox.dart';
import 'wa_rules.dart';
import 'wa_access.dart';

class WaRulesEngine {
  WaRulesEngine._();

  /// كل المدينين برقم واتساب صالح، مع «منذ متى بلا تسديد» (قراءة فقط).
  static Future<List<WaFacts>> facts() async {
    final db = await DatabaseService().database;
    final rows = await db.rawQuery(
      "SELECT id, name, phone, current_total_debt AS d FROM customers "
      "WHERE COALESCE(is_deleted, 0) = 0 AND current_total_debt > 0 AND TRIM(COALESCE(phone, '')) != ''",
    );
    final since = await WaAutoReminder.lateSinceAll();
    return [
      for (final r in rows)
        if (WaAutoReminder.normalizePhone('${r['phone']}') != null)
          WaFacts(
            id: r['id'] as int,
            name: '${r['name'] ?? ''}'.trim(),
            phone: WaAutoReminder.normalizePhone('${r['phone']}')!,
            debt: (r['d'] as num?)?.toDouble() ?? 0,
            since: since[r['id'] as int],
          ),
    ];
  }

  static Future<Set<int>> _dueReminderIds() async {
    try {
      return {for (final d in await DebtReminders.dueToday()) d.member.customerId};
    } catch (_) {
      return {};
    }
  }

  /// من تصله رسالة القاعدة الآن (بغض النظر عن يومها وساعتها) — للمعاينة وللتشغيل.
  static Future<List<WaFacts>> targets(WaRule r, {List<WaFacts>? all, Set<int>? due, DateTime? now}) async {
    return WaRuleEval.select(
      r,
      all ?? await facts(),
      lastSent: await WaMessageLog.lastSent(r.id),
      dueToday: r.audience == WaAudience.dueReminders ? (due ?? await _dueReminderIds()) : const {},
      now: now ?? DateTime.now(),
    );
  }

  static List<WaJob> jobs(WaRule r, Iterable<WaFacts> list) => [
        for (final p in list)
          WaJob(
            customerId: p.id,
            name: p.name,
            phone: p.phone,
            source: 'rule',
            ruleId: r.id,
            ruleName: r.name,
            options: r.options,
          ),
      ];

  // ───────────── التقييم الدوري ─────────────

  static DateTime? _lastEval;
  static bool _busy = false;

  static String _today() => DateFormat('yyyy-MM-dd', 'en').format(DateTime.now());

  static Future<bool> _askedToday(String ruleId) async =>
      (await SharedPreferences.getInstance()).getString('wa_rule_asked_$ruleId') == _today();

  static Future<void> _markAsked(String ruleId) async =>
      (await SharedPreferences.getInstance()).setString('wa_rule_asked_$ruleId', _today());

  /// [force] = الآن بلا انتظار الدقائق الخمس.
  static Future<void> tick(BuildContext context, {bool force = false}) async {
    if (_busy || !WaAccess.rules || WaOutbox.running) return;
    final now = DateTime.now();
    if (!force && _lastEval != null && now.difference(_lastEval!) < const Duration(minutes: 5)) return;
    _busy = true;
    _lastEval = now;
    try {
      final s = await WaAutoReminder.load();
      if (!s.enabled || !s.riskAccepted) return;
      final due = [for (final r in await WaRules.load()) if (WaRuleEval.isDueNow(r, now)) r];
      if (due.isEmpty) return;
      final all = await facts();
      final dueIds = due.any((r) => r.audience == WaAudience.dueReminders) ? await _dueReminderIds() : <int>{};
      final queued = <int>{}; // عميل واحد لا يأخذ رسالتين من قاعدتين في الجولة نفسها
      for (final r in due) {
        final list = [
          for (final p in await targets(r, all: all, due: dueIds, now: now))
            if (!queued.contains(p.id)) p
        ];
        if (list.isEmpty) continue;
        if (r.auto) {
          WaOutbox.enqueue(jobs(r, list));
          queued.addAll(list.map((p) => p.id));
          continue;
        }
        if (await _askedToday(r.id) || !context.mounted) continue;
        await _markAsked(r.id);
        if (!context.mounted) continue;
        final chosen = await showDialog<List<WaFacts>>(
          context: context,
          barrierDismissible: false,
          builder: (_) => WaApproveDialog(rule: r, people: list),
        );
        if (chosen != null && chosen.isNotEmpty) {
          WaOutbox.enqueue(jobs(r, chosen));
          queued.addAll(chosen.map((p) => p.id));
        }
      }
    } catch (e) {
      debugPrint('💬 قواعد واتساب: $e');
    } finally {
      _busy = false;
    }
  }
}

/// 🕒 يبدأ مع الشاشة الرئيسية: يشغّل الخادم (إن فُعّل «مع فتح البرنامج») ثم يقيّم القواعد كل دقيقة.
class WaAutoScheduler {
  WaAutoScheduler._();
  static Timer? _timer;
  static BuildContext? _context;

  static void start(BuildContext context, {required bool primarySeat}) {
    if (!primarySeat) return;
    _context = context;
    if (_timer == null && WaAccess.rules) {
      unawaited(() async {
        try {
          if (!await WaLocalServer.startAtLaunch()) return;
          if ((await WaAutoReminder.load()).viaServer) await WaServerClient.ensureReady();
        } catch (_) {}
      }());
      unawaited(WaMessageLog.prune().catchError((_) {}));
    }
    unawaited(_tick(force: true));
    _timer ??= Timer.periodic(const Duration(minutes: 1), (_) => _tick());
  }

  static Future<void> _tick({bool force = false}) async {
    final c = _context;
    if (c == null || !c.mounted) return;
    await WaRulesEngine.tick(c, force: force);
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
  }
}

/// نافذة «بموافقتي»: القائمة بمربعات اختيار، ولا يُرسل شيء حتى «أرسل».
class WaApproveDialog extends StatefulWidget {
  const WaApproveDialog({super.key, required this.rule, required this.people});
  final WaRule rule;
  final List<WaFacts> people;
  @override
  State<WaApproveDialog> createState() => _WaApproveDialogState();
}

class _WaApproveDialogState extends State<WaApproveDialog> {
  late final Set<int> _sel = {for (final p in widget.people) p.id};
  static final _n = NumberFormat('#,##0', 'en');

  @override
  Widget build(BuildContext context) {
    final r = widget.rule;
    return AlertDialog(
      icon: const Icon(Icons.chat_rounded, color: Color(0xFF047857), size: 34),
      title: Text('رسائل واتساب: ${r.name}'),
      content: SizedBox(
        width: 540,
        height: 420,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${r.lateText} • ${r.repeatText}', style: const TextStyle(color: Color(0xFF64748B))),
          const SizedBox(height: 6),
          Row(children: [
            Text('المحدد: ${_sel.length} من ${widget.people.length}', style: const TextStyle(fontWeight: FontWeight.w800)),
            const Spacer(),
            TextButton(
              onPressed: () => setState(() {
                if (_sel.length == widget.people.length) {
                  _sel.clear();
                } else {
                  _sel.addAll(widget.people.map((p) => p.id));
                }
              }),
              child: Text(_sel.length == widget.people.length ? 'إلغاء الكل' : 'تحديد الكل'),
            ),
          ]),
          Expanded(
            child: ListView(children: [
              for (final p in widget.people)
                CheckboxListTile(
                  dense: true,
                  value: _sel.contains(p.id),
                  onChanged: (v) => setState(() => v == true ? _sel.add(p.id) : _sel.remove(p.id)),
                  title: Text(p.name),
                  subtitle: Text('${_n.format(p.debt.round())} دينار'
                      '${p.since == null ? '' : ' • بلا تسديد منذ ${DateFormat('yyyy/MM/dd', 'en').format(p.since!)}'}'),
                ),
            ]),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, const <WaFacts>[]), child: const Text('ليس اليوم')),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF047857)),
          onPressed: _sel.isEmpty
              ? null
              : () => Navigator.pop(context, [for (final p in widget.people) if (_sel.contains(p.id)) p]),
          icon: const Icon(Icons.send_rounded),
          label: Text('أرسل (${_sel.length})'),
        ),
      ],
    );
  }
}
