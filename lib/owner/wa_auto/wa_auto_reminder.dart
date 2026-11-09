// lib/owner/wa_auto/wa_auto_reminder.dart
//
// 👑💬 تذكير الديون الشهري عبر WhatsApp Desktop (ميزة حساب المالك فقط، ومدير البرنامج).
//
// ⚠️ إرسال آلي من رقم واتساب عادي ليس طريقاً رسمياً من واتساب: قد يُقيَّد الرقم. لذلك:
//   • مطفأ افتراضياً، ولا يُفعَّل إلا بعد موافقة صريحة على الخطر.
//   • فاصل عشوائي بين الرسائل، وحد يومي، وصيغة تحية تتنوع بين الزبائن.
//   • لكل زبون رسالة واحدة في الشهر (سجل محفوظ يمنع التكرار حتى لو انقطع الإرسال).
//   • المبلغ يُقرأ من سجل الديون لحظة الإرسال (من سدّد أثناء التشغيل لا يُذكَّر).
//   • لا يغيّر أي دين أو معاملة: قراءة فقط.

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../../erp/activity/activity_log.dart';
import '../../services/auth_service.dart';
import '../../services/database_service.dart';
import '../../services/license_service.dart';
import '../../services/settings_manager.dart';
import '../owner_access.dart';
import 'wa_desktop.dart';
import 'wa_server_client.dart';
import 'wa_usage_mark.dart';

/// زبون مستحق للتذكير.
class WaTarget {
  WaTarget({required this.id, required this.name, required this.phone, required this.debt, this.lateMonths});
  final int id;
  final String name;
  final String phone; // دولي بلا + (9647…)
  final double debt;

  /// أشهر كاملة مضت بلا تسديد على الدين القائم (null = لا دين قائم).
  final int? lateMonths;
}

class WaAutoSettings {
  WaAutoSettings({
    required this.enabled,
    required this.riskAccepted,
    required this.minDebt,
    required this.day,
    required this.template,
    required this.minDelay,
    required this.maxDelay,
    required this.maxPerDay,
    required this.autoStart,
    required this.loadWait,
    required this.onlySelected,
    required this.selected,
    required this.hour,
    required this.refocus,
    this.overdueMonths = 0,
    this.via = 'desktop',
  });

  final bool enabled;
  final bool riskAccepted;
  final double minDebt;

  /// يوم الإرسال في الشهر: 0 = آخر يوم، أو 1..28.
  final int day;
  final String template;
  final int minDelay; // ثوانٍ
  final int maxDelay;
  final int maxPerDay;

  /// عند فتح البرنامج في يوم الإرسال: نافذة عدّ تنازلي تبدأ الإرسال (يمكن إلغاؤها).
  final bool autoStart;

  /// مهلة تحميل المحادثة قبل ضغط «إرسال» (ثوانٍ).
  final int loadWait;

  /// true = يُرسل فقط للعملاء الذين اخترتهم (الافتراضي). false = كل مدين فوق الحد الأدنى.
  final bool onlySelected;

  /// أرقام العملاء المختارين.
  final Set<int> selected;

  /// ساعة البدء في يوم الإرسال (0..23)؛ -1 = عند فتح البرنامج في أي ساعة.
  final int hour;

  /// إرجاع البرنامج إلى المقدمة بعد كل رسالة.
  final bool refocus;

  /// شرط التأخر: 0 = كل من عليه دين؛ N = فقط من مضى عليه N شهراً فأكثر بلا تسديد.
  final int overdueMonths;

  /// طريقة الإرسال: 'desktop' = WhatsApp Desktop على هذه الحاسبة، 'server' = خادم المالك.
  final String via;
  bool get viaServer => via == 'server';

  static const defaultTemplate = 'السيد {الاسم}،\n'
      'نذكّركم بأن المبلغ المترتب بذمتكم {المبلغ} دينار.\n'
      'يرجى التسديد في أقرب وقت، مع الشكر.\n'
      '{المحل}';

  WaAutoSettings copyWith({
    bool? enabled,
    bool? riskAccepted,
    double? minDebt,
    int? day,
    String? template,
    int? minDelay,
    int? maxDelay,
    int? maxPerDay,
    bool? autoStart,
    int? loadWait,
    bool? onlySelected,
    Set<int>? selected,
    int? hour,
    bool? refocus,
    int? overdueMonths,
    String? via,
  }) =>
      WaAutoSettings(
        enabled: enabled ?? this.enabled,
        riskAccepted: riskAccepted ?? this.riskAccepted,
        minDebt: minDebt ?? this.minDebt,
        day: day ?? this.day,
        template: template ?? this.template,
        minDelay: minDelay ?? this.minDelay,
        maxDelay: maxDelay ?? this.maxDelay,
        maxPerDay: maxPerDay ?? this.maxPerDay,
        autoStart: autoStart ?? this.autoStart,
        loadWait: loadWait ?? this.loadWait,
        onlySelected: onlySelected ?? this.onlySelected,
        selected: selected ?? this.selected,
        hour: hour ?? this.hour,
        refocus: refocus ?? this.refocus,
        overdueMonths: overdueMonths ?? this.overdueMonths,
        via: via ?? this.via,
      );
}

/// حالة الإرسال الجاري (للشاشة).
class WaRunState {
  const WaRunState({
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
}

class WaAutoReminder {
  WaAutoReminder._();

  static const _k = 'wa_auto_';
  static const _logKey = 'wa_auto_log_v1';

  /// 👑 مدير البرنامج على ترخيص المالك أو ترخيص فيه مزامنة (الاشتراك). WhatsApp Desktop
  /// يحتاج ويندوز؛ الخادم يعمل من أي جهاز.
  static bool get allowed {
    if (!AuthService().isAdmin) return false;
    if (OwnerAccess.enabled) return true;
    try {
      return LicenseService().getStoredLicense()?.isSyncAllowed ?? false;
    } catch (_) {
      return false;
    }
  }

  /// الإرسال بالطريقة المضبوطة. null = أُرسلت.
  static Future<({String? error, bool notOnWhatsApp})> _deliver(WaAutoSettings s, String phone, String text) async {
    if (s.viaServer) return WaServerClient.send(phone, text);
    if (!WaDesktop.supported) return (error: 'WhatsApp Desktop يعمل على ويندوز فقط — اختر «الخادم»', notOnWhatsApp: false);
    final err = await WaDesktop.send(phone, text, loadWait: Duration(seconds: s.loadWait));
    if (s.refocus) await _refocus(); // 🔙 البرنامج إلى المقدمة فوراً بعد الضغط
    return (error: err, notOnWhatsApp: false);
  }

  // ───────────── الإعدادات ─────────────

  static Future<WaAutoSettings> load() async {
    final p = await SharedPreferences.getInstance();
    return WaAutoSettings(
      enabled: p.getBool('${_k}enabled') ?? false,
      riskAccepted: p.getBool('${_k}risk') ?? false,
      minDebt: p.getDouble('${_k}min_debt') ?? 1000,
      day: p.getInt('${_k}day') ?? 0,
      template: p.getString('${_k}template') ?? WaAutoSettings.defaultTemplate,
      minDelay: p.getInt('${_k}min_delay') ?? 30,
      maxDelay: p.getInt('${_k}max_delay') ?? 90,
      maxPerDay: p.getInt('${_k}max_day') ?? 100,
      autoStart: p.getBool('${_k}auto') ?? false,
      loadWait: p.getInt('${_k}load_wait') ?? 4,
      onlySelected: p.getBool('${_k}only_selected') ?? true,
      selected: {
        for (final x in p.getStringList('${_k}selected') ?? const <String>[])
          if (int.tryParse(x) != null) int.parse(x),
      },
      hour: p.getInt('${_k}hour') ?? 22,
      refocus: p.getBool('${_k}refocus') ?? true,
      overdueMonths: p.getInt('${_k}overdue') ?? 0,
      via: p.getString('${_k}via') == 'server' ? 'server' : 'desktop',
    );
  }

  static Future<void> save(WaAutoSettings s) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('${_k}enabled', s.enabled);
    await p.setBool('${_k}risk', s.riskAccepted);
    await p.setDouble('${_k}min_debt', s.minDebt);
    await p.setInt('${_k}day', s.day.clamp(0, 28));
    await p.setString('${_k}template', s.template);
    await p.setInt('${_k}min_delay', max(10, s.minDelay));
    await p.setInt('${_k}max_delay', max(max(10, s.minDelay), s.maxDelay));
    await p.setInt('${_k}max_day', s.maxPerDay.clamp(1, 1000));
    await p.setBool('${_k}auto', s.autoStart);
    await p.setInt('${_k}load_wait', s.loadWait.clamp(2, 20));
    await p.setBool('${_k}only_selected', s.onlySelected);
    await p.setStringList('${_k}selected', [for (final id in s.selected) '$id']);
    await p.setInt('${_k}hour', s.hour.clamp(-1, 23));
    await p.setBool('${_k}refocus', s.refocus);
    await p.setInt('${_k}overdue', s.overdueMonths.clamp(0, 24));
    await p.setString('${_k}via', s.via);
  }

  // ───────────── التأخر عن التسديد ─────────────

  /// أشهر كاملة بين [from] و[now] (لا تقل عن صفر).
  static int monthsBetween(DateTime from, DateTime now) {
    var m = (now.year - from.year) * 12 + now.month - from.month;
    if (now.day < from.day) m--;
    return max(0, m);
  }

  /// من حركات مرتبة (عميل، تاريخ، مبلغ، نوع) بالعميل ثم التاريخ: لكل عميل رصيده
  /// موجب في النهاية ⇒ أشهر منذ «آخر تسديد على الدين القائم»:
  ///   • آخر تسديد (manual_payment بمبلغ سالب — وصل، خصم، مرتجع على الحساب)، أو
  ///   • بداية الدين القائم (أول دين بعد آخر مرة صار فيها الرصيد صفراً) إن كانت أحدث.
  /// فمن سدّد كل دينه قبل سنة ثم استدان أمس متأخر صفر شهر، لا سنة.
  static Map<int, int> lateFrom(Iterable<(int, DateTime?, double, String?)> rows, DateTime now) {
    final out = <int, int>{};
    int? cur;
    var bal = 0.0;
    DateTime? since;
    void flush() {
      if (cur != null && bal > 0.009 && since != null) out[cur!] = monthsBetween(since!, now);
    }

    for (final (c, d, a, type) in rows) {
      if (c != cur) {
        flush();
        cur = c;
        bal = 0;
        since = null;
      }
      final clearBefore = bal <= 0.009;
      bal += a;
      if (d == null) continue;
      if (clearBefore && bal > 0.009) since = d; // دين جديد بعد رصيد صفر
      if (a < 0 && type == 'manual_payment') since = d; // تسديد
    }
    flush();
    return out;
  }

  /// أشهر التأخر لكل عميل عليه دين (قراءة فقط).
  static Future<Map<int, int>> lateMonthsAll() async {
    final db = await DatabaseService().database;
    final rows = await db.rawQuery('''
      SELECT t.customer_id AS c, t.transaction_date AS d, t.amount_changed AS a, t.transaction_type AS ty
      FROM transactions t JOIN customers cu ON cu.id = t.customer_id
      WHERE COALESCE(t.is_deleted, 0) = 0 AND COALESCE(cu.is_deleted, 0) = 0 AND cu.current_total_debt > 0
      ORDER BY t.customer_id, t.transaction_date, t.id''');
    return lateFrom([
      for (final r in rows)
        (
          r['c'] as int,
          DateTime.tryParse('${r['d'] ?? ''}'),
          (r['a'] as num?)?.toDouble() ?? 0,
          r['ty'] as String?,
        )
    ], DateTime.now());
  }

  // ───────────── السجل (لكل شهر: من أُرسل له) ─────────────

  static String monthKey(DateTime d) => DateFormat('yyyy-MM', 'en').format(d);

  static Future<Map<String, dynamic>> _log() async {
    final p = await SharedPreferences.getInstance();
    try {
      final raw = p.getString(_logKey);
      if (raw == null) return {};
      return (jsonDecode(raw) as Map).cast<String, dynamic>();
    } catch (_) {
      return {};
    }
  }

  static Future<void> _record(int customerId, String status, double amount, {String? error}) async {
    final p = await SharedPreferences.getInstance();
    final log = await _log();
    final m = monthKey(DateTime.now());
    final month = ((log[m] as Map?) ?? {}).cast<String, dynamic>();
    month['$customerId'] = {
      's': status,
      't': DateTime.now().toIso8601String(),
      'a': amount.round(),
      if (error != null) 'e': error,
    };
    log[m] = month;
    // نُبقي آخر 12 شهراً فقط
    final keys = log.keys.toList()..sort();
    while (keys.length > 12) {
      log.remove(keys.removeAt(0));
    }
    await p.setString(_logKey, jsonEncode(log));
  }

  /// سجل هذا الشهر: رقم العميل ← (الحالة، الوقت، المبلغ، الخطأ)
  static Future<Map<String, Map<String, dynamic>>> monthLog([DateTime? at]) async {
    final m = ((await _log())[monthKey(at ?? DateTime.now())] as Map?) ?? {};
    return {for (final e in m.entries) '${e.key}': (e.value as Map).cast<String, dynamic>()};
  }

  static Future<int> sentToday() async {
    final today = DateFormat('yyyy-MM-dd', 'en').format(DateTime.now());
    final m = await monthLog();
    return m.values.where((v) => v['s'] == 'sent' && '${v['t']}'.startsWith(today)).length;
  }

  // ───────────── من يُذكَّر ─────────────

  /// رقم عراقي/دولي بلا + ، أو null إن لم يكن رقماً صالحاً.
  static String? normalizePhone(String? raw) {
    var c = (raw ?? '').replaceAll(RegExp(r'[^0-9+]'), '');
    if (c.startsWith('+')) c = c.substring(1);
    if (c.startsWith('00')) c = c.substring(2);
    if (c.startsWith('0')) c = '964${c.substring(1)}';
    if (!c.startsWith('964') && c.length == 10 && c.startsWith('7')) c = '964$c';
    if (c.length < 11 || c.length > 15) return null;
    return c;
  }

  /// كل المدينين بالحد الأدنى فأكثر: مع رقم صالح (targets) وبلا رقم (noPhone).
  static Future<({List<WaTarget> targets, int noPhone, int badPhone})> debtors(double minDebt) async {
    final db = await DatabaseService().database;
    final rows = await db.rawQuery(
      'SELECT id, name, phone, current_total_debt AS d FROM customers '
      'WHERE COALESCE(is_deleted, 0) = 0 AND current_total_debt >= ? '
      'ORDER BY current_total_debt DESC',
      [minDebt],
    );
    final late = await lateMonthsAll();
    final out = <WaTarget>[];
    var noPhone = 0, bad = 0;
    for (final r in rows) {
      final raw = '${r['phone'] ?? ''}'.trim();
      if (raw.isEmpty) {
        noPhone++;
        continue;
      }
      final phone = normalizePhone(raw);
      if (phone == null) {
        bad++;
        continue;
      }
      out.add(WaTarget(
        id: r['id'] as int,
        name: '${r['name'] ?? ''}'.trim(),
        phone: phone,
        debt: (r['d'] as num?)?.toDouble() ?? 0,
        lateMonths: late[r['id'] as int],
      ));
    }
    return (targets: out, noPhone: noPhone, badPhone: bad);
  }

  /// العملاء الذين لهم رقم صالح (أياً كان دينهم) — لاختيار من تصله الرسالة.
  static Future<List<WaTarget>> withPhones() async {
    final db = await DatabaseService().database;
    final rows = await db.rawQuery(
      "SELECT id, name, phone, current_total_debt AS d FROM customers "
      "WHERE COALESCE(is_deleted, 0) = 0 AND TRIM(COALESCE(phone, '')) != '' "
      'ORDER BY current_total_debt DESC, name',
    );
    final late = await lateMonthsAll();
    return [
      for (final r in rows)
        if (normalizePhone('${r['phone']}') != null)
          WaTarget(
            id: r['id'] as int,
            name: '${r['name'] ?? ''}'.trim(),
            phone: normalizePhone('${r['phone']}')!,
            debt: (r['d'] as num?)?.toDouble() ?? 0,
            lateMonths: late[r['id'] as int],
          ),
    ];
  }

  /// من سيُرسل لهم (قبل استبعاد من أُرسل لهم هذا الشهر):
  /// المختارون الذين عليهم دين، أو كل مدين فوق الحد الأدنى.
  /// ثم شرط التأخر (overdueMonths) إن كان مضبوطاً.
  static Future<List<WaTarget>> targets(WaAutoSettings s) async {
    final base = !s.onlySelected
        ? (await debtors(s.minDebt)).targets
        : [for (final t in await withPhones()) if (s.selected.contains(t.id) && t.debt > 0) t];
    if (s.overdueMonths <= 0) return base;
    return [for (final t in base) if ((t.lateMonths ?? -1) >= s.overdueMonths) t];
  }

  /// من لم يُرسل له بنجاح هذا الشهر.
  static Future<List<WaTarget>> pending(WaAutoSettings s) async {
    final all = await targets(s);
    final log = await monthLog();
    return [for (final t in all) if (log['${t.id}']?['s'] != 'sent') t];
  }

  /// الحد الأدنى الذي يُفحص لحظة الإرسال (المختارون: أي دين أكبر من صفر).
  static double _floor(WaAutoSettings s) => s.onlySelected ? 0.0001 : s.minDebt;

  // ───────────── نص الرسالة ─────────────

  static const _greetings = ['', 'مرحباً، ', 'تحية طيبة، ', 'السلام عليكم، '];

  static Future<String> shopName() async {
    try {
      final s = await SettingsManager.getAppSettings();
      return s.invoiceDesign.companyName.trim();
    } catch (_) {
      return '';
    }
  }

  /// التاريخ بأرقام إنجليزية بلا بيانات لغة (DateFormat يحتاج تهيئة اللغة أولاً)
  static String _today() {
    final d = DateTime.now();
    String two(int n) => n < 10 ? '0$n' : '$n';
    return '${d.year}/${two(d.month)}/${two(d.day)}';
  }

  /// يملأ القالب؛ التحية تتنوع بين الزبائن (ثابتة للزبون نفسه).
  static String render(String template, WaTarget t, String shop) {
    final amount = NumberFormat('#,##0', 'en').format(t.debt.round());
    var text = template
        .replaceAll('{الاسم}', t.name)
        .replaceAll('{المبلغ}', amount)
        .replaceAll('{المحل}', shop)
        .replaceAll('{التاريخ}', _today());
    text = text.trim(); // بلا سطر فارغ في النهاية إن لم يُكتب اسم المحل
    return '${_greetings[t.id % _greetings.length]}$text';
  }

  // ───────────── الاستحقاق (للتشغيل التلقائي) ─────────────

  static bool isDueDay(WaAutoSettings s, DateTime now) {
    if (s.day == 0) return now.day == DateTime(now.year, now.month + 1, 0).day;
    return now.day >= s.day;
  }

  /// يوم الإرسال وحلّت ساعته.
  static bool isDueNow(WaAutoSettings s, DateTime now) => isDueDay(s, now) && (s.hour < 0 || now.hour >= s.hour);

  /// 🧪 رسالة تجربة إلى أي رقم (بلا عميل، ولا تُسجَّل). null = ضُغط «إرسال».
  static Future<String?> sendTest(String rawPhone) async {
    if (!allowed) return 'غير متاح';
    final phone = normalizePhone(rawPhone);
    if (phone == null) return 'رقم غير صالح';
    final s = await load();
    final t = WaTarget(id: 0, name: 'تجربة', phone: phone, debt: 125000);
    if (s.viaServer) {
      try {
        final st = await WaServerClient.ensureReady();
        if (!st.linked) return 'الخادم غير مربوط برقم واتساب';
      } on WaServerException catch (e) {
        return e.message;
      }
    }
    await WaUsageMark.record(s.via);
    final r = await _deliver(s, phone, render(s.template, t, await shopName()));
    if (r.error == null) await WaUsageMark.record(s.via, sends: 1);
    if (s.viaServer) unawaited(WaServerClient.pullState().catchError((_) {}));
    return r.error;
  }

  /// يعيد نافذة البرنامج إلى المقدمة (بعد إرسال كل رسالة).
  static Future<void> _refocus() async {
    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (_) {}
  }

  static Future<bool> snoozedToday() async {
    final p = await SharedPreferences.getInstance();
    return p.getString('${_k}snooze') == DateFormat('yyyy-MM-dd', 'en').format(DateTime.now());
  }

  static Future<void> snoozeToday() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('${_k}snooze', DateFormat('yyyy-MM-dd', 'en').format(DateTime.now()));
  }

  // ───────────── الإرسال ─────────────

  static final ValueNotifier<WaRunState> state = ValueNotifier(const WaRunState());
  static bool _stop = false;

  static bool get running => state.value.running;
  static void stop() => _stop = true;

  /// يرسل لمن لم يُذكَّر هذا الشهر. [limit] للتجربة (مثلاً 5).
  /// [overdue] و[allDebtors]: إرسال يدوي لمجموعة غير ما في الإعدادات (المتأخرون N شهراً،
  /// أو كل المدينين فوق الحد بدل المختارين) — دون تغيير الإعدادات المحفوظة.
  static Future<void> run({int? limit, int? overdue, bool? allDebtors}) async {
    if (running || !allowed) return;
    final saved = await load();
    if (!saved.enabled || !saved.riskAccepted) return;
    final s = saved.copyWith(overdueMonths: overdue, onlySelected: allDebtors == null ? null : !allDebtors);
    _stop = false;
    final already = await sentToday();
    final room = max(0, s.maxPerDay - already);
    var list = await pending(s);
    if (limit != null) list = list.take(limit).toList();
    list = list.take(room).toList();
    if (list.isEmpty) {
      state.value = WaRunState(
          note: room == 0
              ? 'بلغت الحد اليومي (${s.maxPerDay}) — يكمل غداً'
              : (s.onlySelected && s.selected.isEmpty
                  ? 'لم تختر أي عميل بعد'
                  : (s.overdueMonths > 0
                      ? 'لا أحد متأخر ${s.overdueMonths} شهراً فأكثر ولم يُذكَّر هذا الشهر'
                      : 'لا أحد ينتظر التذكير هذا الشهر')));
      return;
    }
    if (s.viaServer) {
      state.value = const WaRunState(running: true, note: 'يوقظ الخادم…');
      try {
        final st = await WaServerClient.ensureReady();
        if (!st.linked) {
          state.value = const WaRunState(note: 'الخادم غير مربوط برقم واتساب — اربطه من «إعدادات الخادم»');
          return;
        }
      } on WaServerException catch (e) {
        state.value = WaRunState(note: 'الخادم: ${e.message}');
        return;
      }
    }
    await WaUsageMark.record(s.via); // 🔖 علامة دائمة: الخدمة شُغّلت
    final shop = await shopName();
    final rnd = Random();
    var sent = 0, failed = 0, skipped = 0, failsInRow = 0;
    String? note;
    state.value = WaRunState(running: true, total: list.length);
    final db = await DatabaseService().database;
    for (var i = 0; i < list.length; i++) {
      if (_stop) {
        note = 'أُوقف يدوياً';
        break;
      }
      var t = list[i];
      // المبلغ من سجل الديون الآن (قد يكون سدّد أثناء التشغيل)
      final r = await db.rawQuery(
          'SELECT current_total_debt AS d, COALESCE(is_deleted, 0) AS del FROM customers WHERE id = ?', [t.id]);
      final now = r.isEmpty ? 0.0 : ((r.first['d'] as num?)?.toDouble() ?? 0);
      if (r.isEmpty || r.first['del'] != 0 || now < _floor(s)) {
        skipped++;
        state.value = WaRunState(running: true, total: list.length, sent: sent, failed: failed, skipped: skipped);
        continue;
      }
      t = WaTarget(id: t.id, name: t.name, phone: t.phone, debt: now);
      state.value = WaRunState(
          running: true, total: list.length, sent: sent, failed: failed, skipped: skipped, current: t.name);
      final res = await _deliver(s, t.phone, render(s.template, t, shop));
      final err = res.error;
      if (err == null) {
        sent++;
        failsInRow = 0;
        await _record(t.id, 'sent', t.debt);
      } else {
        failed++;
        // رقم ليس على واتساب مشكلة الزبون لا الإرسال: لا يوقف التشغيل
        if (!res.notOnWhatsApp) failsInRow++;
        await _record(t.id, 'failed', t.debt, error: err);
        if (failsInRow >= 2) {
          note = 'توقف بعد فشلين متتاليين: $err';
          break;
        }
      }
      if (i == list.length - 1) break;
      // ⏳ فاصل عشوائي (يُفحص الإيقاف كل ثانية)
      final wait = s.minDelay + rnd.nextInt(max(1, s.maxDelay - s.minDelay + 1));
      final next = DateTime.now().add(Duration(seconds: wait));
      state.value = WaRunState(
          running: true, total: list.length, sent: sent, failed: failed, skipped: skipped, nextAt: next);
      while (DateTime.now().isBefore(next) && !_stop) {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
    if (s.viaServer) {
      try {
        await WaServerClient.pullState(); // نسخة الجلسة الأحدث عند البرنامج
      } catch (_) {}
    }
    if (sent > 0) await WaUsageMark.record(s.via, sends: sent);
    state.value = WaRunState(total: list.length, sent: sent, failed: failed, skipped: skipped, note: note ?? 'انتهى');
    await ActivityLog.log('إرسال', 'تذكير الديون عبر واتساب',
        'أُرسل $sent، فشل $failed، تُخطّي $skipped (سدّدوا أو نزل دينهم تحت الحد)${note == null ? '' : ' — $note'}');
  }
}
