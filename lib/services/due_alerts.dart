// lib/services/due_alerts.dart
//
// 📅 تنبيه «الاستحقاقات» في نافذة التنبيهات (مع النواقص والصلاحية والركود).
//
//   • ما هو: استحقاقات العملاء (قسط، شيك قبض، كمبيالة) المفتوحة أو المسددة جزئياً
//     وما زال منها مبلغ — من «استحقاق / تقسيط» في بطاقة العميل.
//   • الإعدادات (إعدادات التنبيهات ← المطالبة بالديون — DueAlertSettings):
//       ① من يظهر:   المستحق اليوم فقط، أو اليوم وباقي هذا الشهر.
//       ② المتأخر:   يبقى يظهر يومياً حتى يُسدَّد، أو يظهر في يوم استحقاقه فقط.
//       ③ من وصلته رسالة واتساب (بعد تاريخ استحقاقه، من سجل الرسائل المرسلة فعلاً):
//          لا يظهر بعدها، أو في يوم استحقاقه فقط، أو يبقى يظهر يومياً بعلامة «وصلته رسالة».
//       ③ يحكم من وصلته رسالة، و② يحكم غيره.
//   • يحتاج صلاحية «التحصيل» (الاستحقاقات). قراءة فقط: لا يغيّر ديناً ولا استحقاقاً ولا يرسل شيئاً.
//
// «مواعيد المطالبة بالسداد» الشهرية بقيت كما هي: نافذة «مطالبات اليوم» المستقلة.

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' show DatabaseExecutor;

import '../erp/debts/due_items_service.dart' show dueKindLabels;
import '../models/app_user.dart';
import 'auth_service.dart';
import 'database_service.dart';

/// استحقاق في التنبيه.
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
    this.daysUntil = 0,
    this.waSentAt,
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

  /// 0 = اليوم أو لم يحلّ بعد، وأكثر = أيام التأخر.
  final int daysLate;

  /// أيام حتى الاستحقاق (لما يحلّ لاحقاً هذا الشهر)، 0 = حلّ.
  final int daysUntil;

  /// آخر رسالة واتساب وصلته بعد تاريخ الاستحقاق (null = لم تصله).
  final DateTime? waSentAt;
  final int? installmentNo;
  final int? installmentsTotal;
  final String? docNo;

  String get kindLabel => dueKindLabels[kind] ?? kind;
  bool get upcoming => daysUntil > 0;
}

/// إعدادات تنبيه الاستحقاقات.
class DueAlertSettings {
  const DueAlertSettings({
    this.enabled = true,
    this.scope = DueScope.month,
    this.overdue = DueOverdue.daily,
    this.wa = DueWa.hide,
  });

  final bool enabled;
  final DueScope scope;
  final DueOverdue overdue;
  final DueWa wa;

  static const _kEnabled = 'alerts_due_items_v1';
  static const _kScope = 'alerts_due_scope_v1';
  static const _kOverdue = 'alerts_due_overdue_v1';
  static const _kWa = 'alerts_due_wa_v1';

  static T _pick<T extends Enum>(List<T> values, String? name, T fallback) =>
      values.firstWhere((v) => v.name == name, orElse: () => fallback);

  static Future<DueAlertSettings> load() async {
    final p = await SharedPreferences.getInstance();
    return DueAlertSettings(
      enabled: p.getBool(_kEnabled) ?? true,
      scope: _pick(DueScope.values, p.getString(_kScope), DueScope.month),
      overdue: _pick(DueOverdue.values, p.getString(_kOverdue), DueOverdue.daily),
      wa: _pick(DueWa.values, p.getString(_kWa), DueWa.hide),
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kEnabled, enabled);
    await p.setString(_kScope, scope.name);
    await p.setString(_kOverdue, overdue.name);
    await p.setString(_kWa, wa.name);
  }

  DueAlertSettings copyWith({bool? enabled, DueScope? scope, DueOverdue? overdue, DueWa? wa}) => DueAlertSettings(
        enabled: enabled ?? this.enabled,
        scope: scope ?? this.scope,
        overdue: overdue ?? this.overdue,
        wa: wa ?? this.wa,
      );
}

/// ① من يظهر.
enum DueScope {
  today, // المستحق اليوم (والمتأخر حسب ②)
  month, // اليوم وباقي هذا الشهر
}

/// ② المتأخر الذي لم يُسدَّد (لمن لم تصله رسالة واتساب).
enum DueOverdue {
  daily, // يبقى يظهر يومياً حتى يُسدَّد
  dueDay, // يظهر في يوم استحقاقه فقط
}

/// ③ من وصلته رسالة واتساب بعد تاريخ استحقاقه.
enum DueWa {
  hide, // لا يظهر بعد وصول الرسالة (يُذكر عددهم)
  dueDay, // يظهر في يوم استحقاقه فقط
  daily, // يبقى يظهر يومياً بعلامة «وصلته رسالة»
}

class DueAlerts {
  DueAlerts._();

  /// الاستحقاقات التي تظهر الآن حسب الإعدادات، وعدد من أُخفي لأن رسالة واتساب وصلته.
  static Future<({List<DueAlert> items, int waHidden})> load({DateTime? now}) async {
    const none = (items: <DueAlert>[], waHidden: 0);
    try {
      final s = await DueAlertSettings.load();
      if (!s.enabled) return none;
      if (!AuthService().hasPermission(AppPermissions.collection)) return none;
      final db = await DatabaseService().database;
      return loadIn(db, now: now ?? DateTime.now(), settings: s);
    } catch (e) {
      debugPrint('⚠️ تنبيه الاستحقاقات: $e');
      return none;
    }
  }

  @visibleForTesting
  static Future<({List<DueAlert> items, int waHidden})> loadIn(DatabaseExecutor db,
      {required DateTime now, DueAlertSettings settings = const DueAlertSettings()}) async {
    final today = DateTime(now.year, now.month, now.day);
    final until = settings.scope == DueScope.month
        ? DateTime(now.year, now.month + 1, 1) // حتى نهاية الشهر
        : today.add(const Duration(days: 1)); // حتى نهاية اليوم
    final rows = await db.rawQuery('''
      SELECT d.id, d.due_no, d.kind, d.party_id, COALESCE(c.name, d.party_name) AS name, c.phone,
             d.amount, d.paid_amount, d.currency, d.due_date, d.installment_no, d.installments_total, d.doc_no
      FROM due_items d LEFT JOIN customers c ON c.id = d.party_id
      WHERE d.party_type = 'customer'
        AND d.status IN ('open', 'partial')
        AND d.kind IN ('cheque_in', 'receivable_note', 'installment')
        AND d.due_date < ?
        AND (d.amount - d.paid_amount) > 0.0001
        AND COALESCE(c.is_deleted, 0) = 0
      ORDER BY d.due_date ASC, d.id ASC''', [until.toIso8601String()]);
    final lastWa = await _lastWaSent(db);
    final items = <DueAlert>[];
    var hidden = 0;
    for (final r in rows) {
      final customerId = (r['party_id'] as num).toInt();
      final due = DateTime.tryParse('${r['due_date']}') ?? now;
      final dueDay = DateTime(due.year, due.month, due.day);
      final late = daysLate(due, now);
      final until0 = dueDay.isAfter(today) ? dueDay.difference(today).inDays : 0;
      final sent = lastWa[customerId];
      final waSince = sent != null && !sent.isBefore(dueDay) ? sent : null; // وصلته بعد حلول الاستحقاق
      final verdict = decide(settings, daysLate: late, upcoming: until0 > 0, waSent: waSince != null);
      if (verdict == DueVerdict.hideWa) {
        hidden++;
        continue;
      }
      if (verdict == DueVerdict.hide) continue;
      final doc = '${r['doc_no'] ?? ''}'.trim();
      items.add(DueAlert(
        id: (r['id'] as num).toInt(),
        dueNo: (r['due_no'] as num?)?.toInt() ?? 0,
        kind: '${r['kind']}',
        customerId: customerId,
        customerName: '${r['name'] ?? ''}'.trim(),
        phone: '${r['phone'] ?? ''}'.trim(),
        remaining: ((r['amount'] as num?)?.toDouble() ?? 0) - ((r['paid_amount'] as num?)?.toDouble() ?? 0),
        currency: '${r['currency'] ?? 'IQD'}',
        dueDate: due,
        daysLate: late,
        daysUntil: until0,
        waSentAt: waSince,
        installmentNo: (r['installment_no'] as num?)?.toInt(),
        installmentsTotal: (r['installments_total'] as num?)?.toInt(),
        docNo: doc.isEmpty ? null : doc,
      ));
    }
    return (items: items, waHidden: hidden);
  }

  /// قرار الإعدادات لاستحقاق واحد (دالة صافية).
  ///   • لم يحلّ بعد (باقي الشهر): يظهر.
  ///   • وصلته رسالة واتساب بعد حلوله: ③ — لا يظهر / يوم استحقاقه فقط / يومياً.
  ///   • غيره: يوم استحقاقه يظهر، والمتأخر حسب ②.
  static DueVerdict decide(DueAlertSettings s, {required int daysLate, required bool upcoming, required bool waSent}) {
    if (upcoming) return DueVerdict.show;
    if (waSent) {
      return switch (s.wa) {
        DueWa.hide => DueVerdict.hideWa,
        DueWa.dueDay => daysLate == 0 ? DueVerdict.show : DueVerdict.hideWa,
        DueWa.daily => DueVerdict.show,
      };
    }
    if (daysLate == 0) return DueVerdict.show;
    return s.overdue == DueOverdue.daily ? DueVerdict.show : DueVerdict.hide;
  }

  /// آخر رسالة واتساب أُرسلت بنجاح لكل عميل (أي قاعدة أو إرسال يدوي). فارغ إن لا سجل.
  static Future<Map<int, DateTime>> _lastWaSent(DatabaseExecutor db) async {
    try {
      final r = await db.rawQuery("SELECT customer_id AS c, MAX(at) AS t FROM wa_message_log "
          "WHERE status = 'sent' AND customer_id IS NOT NULL GROUP BY customer_id");
      return {
        for (final x in r)
          if (DateTime.tryParse('${x['t']}') != null) (x['c'] as num).toInt(): DateTime.parse('${x['t']}'),
      };
    } catch (_) {
      return const {}; // لم يُرسل شيء بعد (الجدول غير موجود)
    }
  }

  /// أيام التأخر بالتاريخ وحده (0 = اليوم أو لم يحلّ).
  static int daysLate(DateTime due, DateTime now) {
    final a = DateTime(due.year, due.month, due.day), b = DateTime(now.year, now.month, now.day);
    return max(0, b.difference(a).inDays);
  }
}

enum DueVerdict { show, hide, hideWa }
