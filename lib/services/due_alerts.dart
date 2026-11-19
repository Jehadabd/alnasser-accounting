// lib/services/due_alerts.dart
//
// 📅 تنبيه «الاستحقاقات» في نافذة التنبيهات (مع النواقص والصلاحية والركود).
//
//   • من يظهر: استحقاقات العملاء (قسط، شيك قبض، كمبيالة) المفتوحة أو المسددة جزئياً،
//     التي حلّ تاريخها اليوم أو مضى، وما زال منها مبلغ — من «استحقاق / تقسيط» في بطاقة العميل.
//   • من لا يظهر: العميل الذي تصله رسالة واتساب التلقائية (قاعدة مفعّلة «تلقائي» تشمله،
//     ودينه فوق حدها، ورقمه صالح) — يُطالَب أصلاً. يُذكر عددهم فقط.
//   • التشغيل: إعدادات التنبيهات ← «الاستحقاقات» (مفعّل افتراضياً)، بالتكرار نفسه.
//   • يحتاج صلاحية «التحصيل» (الاستحقاقات). قراءة فقط: لا يغيّر ديناً ولا استحقاقاً.
//
// «مواعيد المطالبة بالسداد» الشهرية بقيت كما هي: نافذة «مطالبات اليوم» المستقلة.

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' show DatabaseExecutor;

import '../erp/debts/due_items_service.dart' show dueKindLabels;
import '../erp/erp_common.dart' show isoDayAfter;
import '../models/app_user.dart';
import '../owner/wa_auto/wa_auto_reminder.dart';
import '../wa_messages/wa_rules.dart';
import 'auth_service.dart';
import 'database_service.dart';

/// استحقاق حلّ موعده.
class DueAlert {
  const DueAlert({
    required this.id,
    required this.dueNo,
    required this.kind,
    required this.customerId,
    required this.customerName,
    required this.phone,
    required this.remaining,
    required this.currency,
    required this.dueDate,
    required this.daysLate,
    this.installmentNo,
    this.installmentsTotal,
    this.docNo,
  });

  final int id;
  final int dueNo;
  final String kind;
  final int customerId;
  final String customerName;
  final String phone;

  /// المتبقي بعملة الاستحقاق.
  final double remaining;
  final String currency;
  final DateTime dueDate;

  /// 0 = اليوم، وأكثر = أيام التأخر.
  final int daysLate;
  final int? installmentNo;
  final int? installmentsTotal;
  final String? docNo;

  String get kindLabel => dueKindLabels[kind] ?? kind;
}

class DueAlerts {
  DueAlerts._();

  static const _kEnabled = 'alerts_due_items_v1';

  static Future<bool> enabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kEnabled) ?? true;
  }

  static Future<void> setEnabled(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kEnabled, v);
  }

  /// الاستحقاقات التي حلّت (بلا من تصلهم رسالة واتساب التلقائية) وعدد المستثنين.
  static Future<({List<DueAlert> items, int waCovered})> load({DateTime? now}) async {
    const none = (items: <DueAlert>[], waCovered: 0);
    try {
      if (!await enabled()) return none;
      if (!AuthService().hasPermission(AppPermissions.collection)) return none;
      final wa = await WaAutoReminder.load();
      // الرسائل التلقائية لا تُرسَل أصلاً ما لم يُفعَّل الإرسال الآلي ويُقبل خطره
      final rules = wa.enabled && wa.riskAccepted ? await WaRules.load() : const <WaRule>[];
      final db = await DatabaseService().database;
      return loadIn(db, now: now ?? DateTime.now(), rules: rules);
    } catch (e) {
      debugPrint('⚠️ تنبيه الاستحقاقات: $e');
      return none;
    }
  }

  @visibleForTesting
  static Future<({List<DueAlert> items, int waCovered})> loadIn(DatabaseExecutor db,
      {required DateTime now, List<WaRule> rules = const []}) async {
    final rows = await db.rawQuery('''
      SELECT d.id, d.due_no, d.kind, d.party_id, COALESCE(c.name, d.party_name) AS name, c.phone,
             COALESCE(c.current_total_debt, 0) AS debt, d.amount, d.paid_amount, d.currency,
             d.due_date, d.installment_no, d.installments_total, d.doc_no
      FROM due_items d LEFT JOIN customers c ON c.id = d.party_id
      WHERE d.party_type = 'customer'
        AND d.status IN ('open', 'partial')
        AND d.kind IN ('cheque_in', 'receivable_note', 'installment')
        AND d.due_date < ?
        AND (d.amount - d.paid_amount) > 0.0001
        AND COALESCE(c.is_deleted, 0) = 0
      ORDER BY d.due_date ASC, d.id ASC''', [isoDayAfter(now)]);
    final items = <DueAlert>[];
    var covered = 0;
    for (final r in rows) {
      final customerId = (r['party_id'] as num).toInt();
      final phone = '${r['phone'] ?? ''}'.trim();
      if (coveredByWa(rules, customerId: customerId, debt: (r['debt'] as num?)?.toDouble() ?? 0, phone: phone)) {
        covered++;
        continue;
      }
      final due = DateTime.tryParse('${r['due_date']}') ?? now;
      final doc = '${r['doc_no'] ?? ''}'.trim();
      items.add(DueAlert(
        id: (r['id'] as num).toInt(),
        dueNo: (r['due_no'] as num?)?.toInt() ?? 0,
        kind: '${r['kind']}',
        customerId: customerId,
        customerName: '${r['name'] ?? ''}'.trim(),
        phone: phone,
        remaining: ((r['amount'] as num?)?.toDouble() ?? 0) - ((r['paid_amount'] as num?)?.toDouble() ?? 0),
        currency: '${r['currency'] ?? 'IQD'}',
        dueDate: due,
        daysLate: daysLate(due, now),
        installmentNo: (r['installment_no'] as num?)?.toInt(),
        installmentsTotal: (r['installments_total'] as num?)?.toInt(),
        docNo: doc.isEmpty ? null : doc,
      ));
    }
    return (items: items, waCovered: covered);
  }

  /// أيام التأخر بالتاريخ وحده (0 = اليوم).
  static int daysLate(DateTime due, DateTime now) {
    final a = DateTime(due.year, due.month, due.day), b = DateTime(now.year, now.month, now.day);
    return max(0, b.difference(a).inDays);
  }

  /// هل تصل هذا العميلَ رسالةُ واتساب تلقائية؟ (قاعدة مفعّلة «تلقائي» تشمله ودينه فوق حدها ورقمه صالح)
  /// قواعد «المستحقون اليوم في مواعيد المطالبة» لا تُحسب: لا تخص الاستحقاقات.
  static bool coveredByWa(List<WaRule> rules, {required int customerId, required double debt, required String? phone}) {
    if (WaAutoReminder.normalizePhone(phone) == null) return false;
    for (final r in rules) {
      if (!r.enabled || !r.auto) continue;
      if (debt < max(r.minDebt, 0.01)) continue;
      final inAudience = switch (r.audience) {
        WaAudience.all => true,
        WaAudience.selected => r.ids.contains(customerId),
        WaAudience.except => !r.ids.contains(customerId),
        WaAudience.dueReminders => false,
      };
      if (inAudience) return true;
    }
    return false;
  }
}
