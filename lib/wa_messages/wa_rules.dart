// lib/wa_messages/wa_rules.dart
//
// 📏 قواعد رسائل واتساب التلقائية: «لمن، ومتى، وبأي رسالة».
//
//   • لمن:   كل المدينين، أو عملاء أختارهم، أو الكل عدا عملاء، أو المستحقون اليوم في
//            «مواعيد المطالبة بالسداد».
//   • الشرط: لم يسدّد منذ N يوم/شهر على دينه القائم (0 = بلا شرط)، ودين لا يقل عن حد.
//   • متى:   أي يوم أو أيام محددة من الشهر، ومن ساعة معيّنة.
//   • التكرار: مرة واحدة حتى يسدّد (تعود بعد أي تسديد جديد)، أو مرة كل شهر، أو كل N يوم.
//   • الإرسال: تلقائي بلا تدخل، أو ينتظر موافقتك بقائمة.
//   • الرسالة: نص القاعدة (أو النص الافتراضي)، عنوان المحل، وكشف حساب ملخّص (نص أو PDF).
//
// تُحفظ في إعدادات هذا الجهاز (لا تُزامَن). الدوال الصافية هنا (بلا قاعدة بيانات) مختبَرة.

import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../owner/wa_auto/wa_auto_reminder.dart';

enum WaAudience { all, selected, except, dueReminders }

enum WaRepeat { once, monthly, everyDays }

enum WaAttach { none, text, pdf }

/// خيارات الرسالة (للقواعد وللإرسال اليدوي).
class WaMessageOptions {
  const WaMessageOptions({this.template = '', this.address = true, this.attach = WaAttach.none});

  /// فارغ = النص الافتراضي من «الرسالة وعنوان المحل».
  final String template;
  final bool address;
  final WaAttach attach;

  WaMessageOptions copyWith({String? template, bool? address, WaAttach? attach}) => WaMessageOptions(
        template: template ?? this.template,
        address: address ?? this.address,
        attach: attach ?? this.attach,
      );

  Map<String, dynamic> toJson() => {'template': template, 'address': address, 'attach': attach.name};

  factory WaMessageOptions.fromJson(Map<String, dynamic>? j) => WaMessageOptions(
        template: '${j?['template'] ?? ''}',
        address: j?['address'] != false,
        attach: WaAttach.values.firstWhere((a) => a.name == j?['attach'], orElse: () => WaAttach.none),
      );
}

class WaRule {
  WaRule({
    required this.id,
    required this.name,
    this.enabled = true,
    this.audience = WaAudience.all,
    Set<int>? ids,
    this.lateValue = 3,
    this.lateUnit = 'month',
    this.minDebt = 1,
    List<int>? days,
    this.hour = 10,
    this.repeat = WaRepeat.once,
    this.repeatDays = 30,
    this.auto = true,
    this.options = const WaMessageOptions(),
  })  : ids = ids ?? <int>{},
        days = days ?? <int>[];

  final String id;
  String name;
  bool enabled;
  WaAudience audience;

  /// للمختارين أو المستثنين.
  Set<int> ids;

  /// شرط التأخر: 0 = بلا شرط. الوحدة 'day' أو 'month'.
  int lateValue;
  String lateUnit;
  double minDebt;

  /// أيام الشهر (1..31، و0 = آخر يوم). فارغة = كل يوم.
  List<int> days;

  /// من هذه الساعة فما بعد (0..23)، أو -1 = أي ساعة.
  int hour;
  WaRepeat repeat;
  int repeatDays;

  /// true = يرسل وحده بلا أي تدخل. false = يعرض القائمة وينتظر موافقتك.
  bool auto;
  WaMessageOptions options;

  static String newId() => '${DateTime.now().microsecondsSinceEpoch}${Random().nextInt(999)}';

  WaRule copy() => WaRule.fromJson(toJson());

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'enabled': enabled,
        'audience': audience.name,
        'ids': (ids.toList()..sort()),
        'lateValue': lateValue,
        'lateUnit': lateUnit,
        'minDebt': minDebt,
        'days': days,
        'hour': hour,
        'repeat': repeat.name,
        'repeatDays': repeatDays,
        'auto': auto,
        'options': options.toJson(),
      };

  factory WaRule.fromJson(Map<String, dynamic> j) => WaRule(
        id: '${j['id']}',
        name: '${j['name'] ?? 'قاعدة'}',
        enabled: j['enabled'] != false,
        audience: WaAudience.values.firstWhere((a) => a.name == j['audience'], orElse: () => WaAudience.all),
        ids: {for (final x in (j['ids'] as List? ?? const [])) if (x is num) x.toInt()},
        lateValue: ((j['lateValue'] as num?) ?? 0).toInt().clamp(0, 3650),
        lateUnit: j['lateUnit'] == 'day' ? 'day' : 'month',
        minDebt: ((j['minDebt'] as num?) ?? 1).toDouble(),
        days: [for (final x in (j['days'] as List? ?? const [])) if (x is num && x >= 0 && x <= 31) x.toInt()],
        hour: ((j['hour'] as num?) ?? -1).toInt().clamp(-1, 23),
        repeat: WaRepeat.values.firstWhere((r) => r.name == j['repeat'], orElse: () => WaRepeat.once),
        repeatDays: ((j['repeatDays'] as num?) ?? 30).toInt().clamp(1, 365),
        auto: j['auto'] != false,
        options: WaMessageOptions.fromJson((j['options'] as Map?)?.cast<String, dynamic>()),
      );

  // ───────────── نصوص للعرض ─────────────

  String get lateText {
    if (lateValue <= 0) return 'كل من عليه دين';
    final unit = lateUnit == 'day'
        ? (lateValue == 1 ? 'يوم' : (lateValue == 2 ? 'يومين' : (lateValue <= 10 ? 'أيام' : 'يوماً')))
        : (lateValue == 1 ? 'شهر' : (lateValue == 2 ? 'شهرين' : (lateValue <= 10 ? 'أشهر' : 'شهراً')));
    return 'لم يسدّد منذ ${lateValue <= 2 ? '' : '$lateValue '}$unit';
  }

  String get daysText {
    if (days.isEmpty) return 'كل يوم';
    final d = [...days]..sort();
    return 'يوم ${d.map((x) => x == 0 ? 'آخر الشهر' : '$x').join(' و')}';
  }

  String get hourText => hour < 0 ? 'أي ساعة' : 'من الساعة ${hour.toString().padLeft(2, '0')}:00';

  String get repeatText => switch (repeat) {
        WaRepeat.once => 'مرة واحدة حتى يسدّد',
        WaRepeat.monthly => 'مرة كل شهر',
        WaRepeat.everyDays => 'كل $repeatDays يوماً حتى يسدّد',
      };

  String get audienceText => switch (audience) {
        WaAudience.all => 'كل المدينين',
        WaAudience.selected => '${ids.length} عميل مختار',
        WaAudience.except => 'الكل عدا ${ids.length}',
        WaAudience.dueReminders => 'المستحقون في مواعيد المطالبة',
      };

  String get summary => '$audienceText • $lateText • $daysText • $hourText • $repeatText • ${auto ? 'تلقائي' : 'بموافقتي'}';
}

/// حقائق عميل وقت التقييم.
class WaFacts {
  const WaFacts({required this.id, required this.name, required this.phone, required this.debt, this.since});
  final int id;
  final String name;
  final String phone;
  final double debt;

  /// منذ متى بلا تسديد على الدين القائم (null = لا دين قائم).
  final DateTime? since;
}

/// دوال صافية لتقييم القواعد.
class WaRuleEval {
  WaRuleEval._();

  static int _lastDay(DateTime d) => DateTime(d.year, d.month + 1, 0).day;

  /// اليوم من أيام القاعدة؟ يوم أكبر من أيام الشهر (31 في شباط) = آخر يوم فيه.
  static bool dayMatches(WaRule r, DateTime now) {
    if (r.days.isEmpty) return true;
    final last = _lastDay(now);
    for (final d in r.days) {
      if (d == 0 || d >= last) {
        if (now.day == last) return true;
      } else if (d == now.day) {
        return true;
      }
    }
    return false;
  }

  static bool isDueNow(WaRule r, DateTime now) => r.enabled && dayMatches(r, now) && (r.hour < 0 || now.hour >= r.hour);

  static bool lateEnough(WaRule r, DateTime? since, DateTime now) {
    if (r.lateValue <= 0) return true;
    if (since == null) return false;
    if (r.lateUnit == 'day') return now.difference(since).inDays >= r.lateValue;
    return WaAutoReminder.monthsBetween(since, now) >= r.lateValue;
  }

  /// هل يسمح التكرار بإرسال جديد؟ [lastSent] آخر إرسال ناجح بهذه القاعدة لهذا العميل.
  static bool repeatAllows(WaRule r, DateTime? lastSent, DateTime? since, DateTime now) {
    if (lastSent == null) return true;
    switch (r.repeat) {
      case WaRepeat.once:
        // دورة جديدة: سدّد (أو صار دينه صفراً ثم استدان) بعد آخر رسالة
        return since != null && since.isAfter(lastSent);
      case WaRepeat.monthly:
        return lastSent.year != now.year || lastSent.month != now.month;
      case WaRepeat.everyDays:
        return now.difference(lastSent).inDays >= r.repeatDays;
    }
  }

  /// من تصله رسالة هذه القاعدة الآن.
  static List<WaFacts> select(
    WaRule r,
    Iterable<WaFacts> people, {
    required Map<int, DateTime> lastSent,
    Set<int> dueToday = const {},
    required DateTime now,
  }) {
    final floor = max(r.minDebt, 0.01);
    return [
      for (final p in people)
        if (p.debt >= floor &&
            switch (r.audience) {
              WaAudience.all => true,
              WaAudience.selected => r.ids.contains(p.id),
              WaAudience.except => !r.ids.contains(p.id),
              WaAudience.dueReminders => dueToday.contains(p.id),
            } &&
            lateEnough(r, p.since, now) &&
            repeatAllows(r, lastSent[p.id], p.since, now))
          p,
    ];
  }
}

/// حفظ القواعد في إعدادات هذا الجهاز.
class WaRules {
  WaRules._();

  static const _k = 'wa_rules_v1';
  static const _kMigrated = 'wa_rules_migrated_v1';

  /// معرّف القاعدة المنقولة من «التذكير الشهري» القديم.
  static const legacyId = 'legacy_monthly';

  static Future<List<WaRule>> load() async {
    final p = await SharedPreferences.getInstance();
    if (!(p.getBool(_kMigrated) ?? false)) await _migrate(p);
    try {
      final raw = p.getString(_k);
      if (raw == null || raw.isEmpty) return [];
      return [
        for (final x in (jsonDecode(raw) as List))
          if (x is Map) WaRule.fromJson(x.cast<String, dynamic>()),
      ];
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveAll(List<WaRule> rules) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_k, jsonEncode([for (final r in rules) r.toJson()]));
  }

  static Future<void> upsert(WaRule r) async {
    final all = await load();
    final i = all.indexWhere((x) => x.id == r.id);
    if (i < 0) {
      all.add(r);
    } else {
      all[i] = r;
    }
    await saveAll(all);
  }

  static Future<void> remove(String id) async => saveAll((await load())..removeWhere((r) => r.id == id));

  /// «التذكير الشهري» القديم ⇒ قاعدة بالقيم نفسها (مرة واحدة). مطفأة إن كان مطفأً.
  static Future<void> _migrate(SharedPreferences p) async {
    try {
      final s = await WaAutoReminder.load();
      final had = p.containsKey('wa_auto_day') || p.containsKey('wa_auto_selected') || p.containsKey('wa_auto_auto');
      if (had && (p.getString(_k) ?? '').isEmpty) {
        final r = WaRule(
          id: legacyId,
          name: 'التذكير الشهري',
          enabled: s.enabled && s.autoStart,
          audience: s.onlySelected ? WaAudience.selected : WaAudience.all,
          ids: s.selected,
          lateValue: s.overdueMonths,
          lateUnit: 'month',
          minDebt: s.onlySelected ? 1 : s.minDebt,
          days: [s.day],
          hour: s.hour,
          repeat: WaRepeat.monthly,
          auto: false, // كان يسأل بعدّ تنازلي — نبقيه بموافقتك حتى تغيّره
          options: const WaMessageOptions(address: false),
        );
        await p.setString(_k, jsonEncode([r.toJson()]));
      }
    } catch (_) {}
    await p.setBool(_kMigrated, true);
  }
}
