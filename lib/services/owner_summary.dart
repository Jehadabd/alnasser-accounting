// lib/services/owner_summary.dart
//
// 📊 ملخص المالك اليومي على تيليجرام — قراءة فقط.
//
//   • الأرقام من المحركات نفسها التي تبني التقارير: SalesFacts (المبيعات والمرتجعات
//     والربح)، CashFlow (المقبوض وحركة الديون والدرج)، أرصدة الصناديق من القيود،
//     سجل الحركات وأحداث تعديل الفواتير (العمليات الحساسة)، المخزون، ومواعيد المطالبة.
//   • لا يكتب في قاعدة البيانات شيئاً. ما يحفظه: تاريخ آخر إرسال ناجح والإعداد،
//     في إعدادات هذا الجهاز (SharedPreferences).
//   • يُرسل مرة في اليوم بعد الساعة المختارة، من جهاز واحد: الشاشة الأولى، وليس
//     طرفية شبكة، وليس الوضع التجريبي. الإعداد لكل جهاز — يُفعَّل على حاسبة واحدة.
//   • إن لم يكن البرنامج مفتوحاً وقتها: عند التشغيل التالي يُرسل ملخص الأمس (مرة).
//   • قسم يتعذّر حسابه يُكتب «تعذّر حسابه» ولا يوقف بقية الملخص.

import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:intl/intl.dart' hide TextDirection;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../accounting/vouchers_service.dart';
import '../lan/lan_settings.dart' show AppNetworkMode;
import 'database_service.dart';
import 'debt_reminders.dart';
import 'demo_mode.dart';
import 'invoice_edit_events.dart';
import 'invoice_settings_service.dart';
import 'reports/cash_flow.dart';
import 'reports/sales_facts.dart';
import 'seat_service.dart';
import 'settings_manager.dart';
import 'telegram_backup_service.dart';

/// سطر عملية حساسة (من فعل ماذا).
class OwnerSensitiveOp {
  const OwnerSensitiveOp(this.user, this.action, this.details);
  final String user;
  final String action;
  final String details;
}

/// بيانات الملخص (null في أي حقل = تعذّر حسابه).
class OwnerSummaryData {
  OwnerSummaryData(this.day);
  final DateTime day;
  String shopName = '';

  // المبيعات
  int? invoiceCount;
  double? sales, cashSales, creditSales, returns, profit;

  // النقد والديون
  double? netCollected, debtPayments, debtIncrease, debtDecrease, drawerNet;

  // الصناديق (الاسم ← الرصيد في الحسابات)
  Map<String, double>? boxes;

  // العمليات الحساسة
  int? sensitiveCount;
  List<OwnerSensitiveOp> sensitive = const [];

  // المخزون
  int? outOfStock, belowMin;
  List<String> outOfStockNames = const [];

  // مطالبات الغد
  int? claimsTomorrow;
  double? claimsTomorrowTotal;
}

class OwnerSummary {
  OwnerSummary._();

  static const _kEnabled = 'owner_summary_enabled';
  static const _kHour = 'owner_summary_hour';
  static const _kMinute = 'owner_summary_minute';
  static const _kLastSent = 'owner_summary_last_sent'; // yyyy-MM-dd لليوم الذي أُرسل ملخصه

  /// حد رسالة تيليجرام 4096 حرفاً — نترك هامشاً.
  static const int maxLength = 3800;

  static String dayKey(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  // ───────────────────────── الإعداد ─────────────────────────

  static Future<bool> enabled() async => (await SharedPreferences.getInstance()).getBool(_kEnabled) ?? false;

  static Future<void> setEnabled(bool v) async => (await SharedPreferences.getInstance()).setBool(_kEnabled, v);

  /// وقت الإرسال (الافتراضي 21:00).
  static Future<({int hour, int minute})> time() async {
    final p = await SharedPreferences.getInstance();
    return (hour: (p.getInt(_kHour) ?? 21).clamp(0, 23).toInt(), minute: (p.getInt(_kMinute) ?? 0).clamp(0, 59).toInt());
  }

  static Future<void> setTime(int hour, int minute) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kHour, hour.clamp(0, 23).toInt());
    await p.setInt(_kMinute, minute.clamp(0, 59).toInt());
  }

  static Future<String?> lastSent() async => (await SharedPreferences.getInstance()).getString(_kLastSent);

  /// هل هذا الجهاز هو المرسِل؟ (لا طرفية، الشاشة الأولى، لا وضع تجريبي)
  static bool get deviceCanSend => !AppNetworkMode.isClient && SeatService.isPrimary && !DemoMode.isOn;

  // ───────────────────────── الجدولة ─────────────────────────

  static Timer? _timer;
  static bool _sending = false;
  static DateTime? _lastFailure;

  /// يُستدعى مرة بعد فتح البرنامج. آمن للتكرار.
  static void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _tick());
    Future.delayed(const Duration(seconds: 20), _tick);
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
  }

  static Future<void> _tick() async {
    if (_sending || !deviceCanSend) return;
    try {
      if (!await enabled()) return;
      // بعد فشل: محاولة كل 15 دقيقة لا كل دقيقة
      final lf = _lastFailure;
      if (lf != null && DateTime.now().difference(lf).inMinutes < 15) return;
      final now = DateTime.now();
      final last = await lastSent();
      final today = dayKey(now);
      final t = await time();
      final at = DateTime(now.year, now.month, now.day, t.hour, t.minute);
      final yesterday = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1));
      DateTime? day;
      if (now.isBefore(at)) {
        // قبل موعد اليوم: ملخص الأمس إن لم يُرسل (البرنامج كان مغلقاً وقتها)
        if (last == null || last.compareTo(dayKey(yesterday)) < 0) day = yesterday;
      } else if (last != today) {
        day = DateTime(now.year, now.month, now.day);
      }
      if (day == null) return;
      // فحص ربط تيليجرام فقط حين يحين الإرسال، لا كل دقيقة (ما قبله حساب بلا أثر)
      if (!await TelegramBackupService().isConfigured) return;
      // أول تفعيل: لا نرسل الأمس بأثر رجعي
      if (last == null && day == yesterday) {
        await _markSent(yesterday);
        return;
      }
      await sendFor(day);
    } catch (e) {
      debugPrint('⚠️ ملخص المالك: $e');
    }
  }

  static Future<void> _markSent(DateTime day) async =>
      (await SharedPreferences.getInstance()).setString(_kLastSent, dayKey(day));

  /// يبني ملخص [day] ويرسله. يعيد نص الخطأ أو null عند النجاح.
  static Future<String?> sendFor(DateTime day, {bool markSent = true}) async {
    if (_sending) return 'إرسال آخر جارٍ';
    _sending = true;
    try {
      final data = await build(day);
      final r = await TelegramBackupService().sendMessageWithDetails(format(data));
      if (!r.success) {
        _lastFailure = DateTime.now();
        return r.toString();
      }
      _lastFailure = null;
      if (markSent) {
        final last = await lastSent();
        // لا نرجع بتاريخ آخر إرسال إلى الوراء (إرسال يدوي لملخص قديم)
        if (last == null || dayKey(day).compareTo(last) > 0) await _markSent(day);
      }
      return null;
    } catch (e) {
      _lastFailure = DateTime.now();
      return '$e';
    } finally {
      _sending = false;
    }
  }

  // ───────────────────────── البناء (قراءة فقط) ─────────────────────────

  static Future<OwnerSummaryData> build(DateTime day) async {
    final d = OwnerSummaryData(DateTime(day.year, day.month, day.day));
    final db = await DatabaseService().database;
    try {
      // اسم المحل كما يُطبع في رأس الفاتورة (إعدادات تصميم الفاتورة)، ثم الترويسة المحفوظة.
      // (كانت تُقرأ الترويسة وحدها، وقيمتها الافتراضية اسم محل آخر مكتوب في الكود)
      final printed = (await SettingsManager.getAppSettings()).invoiceDesign.companyName.trim();
      d.shopName = printed.isNotEmpty ? printed : (await InvoiceSettingsService.getInvoiceHeader()).trim();
    } catch (_) {}

    SalesFacts? facts;
    try {
      // نسبة ربح المواد المؤقتة نفسها التي تستعملها التقارير
      final settings = await SettingsManager.getAppSettings();
      facts = await SalesFacts.load(db,
          from: d.day, to: d.day, adHocProfitPercentage: settings.defaultAdHocProfitPercentage);
      final t = facts.totals();
      d
        ..invoiceCount = t.invoiceCount
        ..sales = t.sales
        ..cashSales = t.cashSales
        ..creditSales = t.creditSales
        ..returns = t.totalReturns
        ..profit = t.profit;
    } catch (e) {
      debugPrint('⚠️ ملخص المالك (المبيعات): $e');
    }
    if (facts != null) {
      try {
        final c = await CashFlow.load(db, facts, from: d.day, to: d.day);
        d
          ..netCollected = c.netCollected
          ..debtPayments = c.debtPayments
          ..debtIncrease = c.debtIncrease
          ..debtDecrease = c.debtDecrease
          ..drawerNet = c.drawerNet;
      } catch (e) {
        debugPrint('⚠️ ملخص المالك (النقد): $e');
      }
    }
    try {
      d.boxes = await _boxes(db);
    } catch (_) {}
    try {
      await _sensitive(db, d);
    } catch (_) {}
    try {
      await _stock(db, d);
    } catch (_) {}
    try {
      final tomorrow = d.day.add(const Duration(days: 1, hours: 12));
      final due = (await DebtReminders.dueTodayDetailed(includeSnoozed: true, now: tomorrow)).due;
      d
        ..claimsTomorrow = due.length
        ..claimsTomorrowTotal = due.fold<double>(0, (s, x) => s + (x.member.amount ?? x.balance));
    } catch (_) {}
    return d;
  }

  static Future<Map<String, double>> _boxes(DatabaseExecutor db) async {
    final svc = VouchersService();
    final boxes = await svc.cashBoxes();
    final bal = await svc.cashBoxBalances();
    return {for (final b in boxes) b.name: bal[b.id] ?? 0};
  }

  /// عمليات تستحق انتباه المالك: حذف، إلغاء، تعديل، تجاوز سقف، موافقة مدير،
  /// وتعديل فواتير بعد حفظها.
  static Future<void> _sensitive(DatabaseExecutor db, OwnerSummaryData d) async {
    final from = d.day.toIso8601String();
    final to = d.day.add(const Duration(days: 1)).toIso8601String();
    final ops = <OwnerSensitiveOp>[];
    var count = 0;
    try {
      const actions = ['حذف', 'إلغاء', 'تعديل', 'تجاوز سقف الدين', 'موافقة المدير', 'استبعاد'];
      final ph = List.filled(actions.length, '?').join(',');
      final n = await db.rawQuery(
          'SELECT COUNT(*) AS n FROM activity_logs WHERE at >= ? AND at < ? AND action IN ($ph)', [from, to, ...actions]);
      count += ((n.first['n'] as num?) ?? 0).toInt();
      final rows = await db.rawQuery(
          'SELECT user_name, action, screen, details FROM activity_logs '
          'WHERE at >= ? AND at < ? AND action IN ($ph) ORDER BY at DESC LIMIT 8',
          [from, to, ...actions]);
      for (final r in rows) {
        ops.add(OwnerSensitiveOp('${r['user_name'] ?? ''}', '${r['action'] ?? ''}',
            '${r['screen'] ?? ''}${(r['details'] ?? '').toString().isEmpty ? '' : ' — ${r['details']}'}'));
      }
    } on DatabaseException {
      // لا سجل حركات بعد
    }
    if (await InvoiceEditEvents.exists(db)) {
      final n = await db.rawQuery(
          'SELECT COUNT(*) AS n FROM ${InvoiceEditEvents.table} WHERE created_at >= ? AND created_at < ?', [from, to]);
      final edits = ((n.first['n'] as num?) ?? 0).toInt();
      count += edits;
      if (edits > 0) {
        final rows = await db.rawQuery(
            'SELECT invoice_id, created_by, total_before, total_after FROM ${InvoiceEditEvents.table} '
            'WHERE created_at >= ? AND created_at < ? ORDER BY created_at DESC LIMIT 5',
            [from, to]);
        for (final r in rows) {
          ops.add(OwnerSensitiveOp(
              '${r['created_by'] ?? ''}',
              'تعديل فاتورة بعد حفظها',
              '#${r['invoice_id']}: ${money(r['total_before'])} ← ${money(r['total_after'])}'));
        }
      }
    }
    d
      ..sensitiveCount = count
      ..sensitive = ops;
  }

  /// نفدت = رصيدها صفر أو أقل وبيعت خلال 30 يوماً (لا الراكدة القديمة).
  /// تحت الحد = لها حد أدنى ورصيدها موجب ودونه.
  static Future<void> _stock(DatabaseExecutor db, OwnerSummaryData d) async {
    final since = dayKey(d.day.subtract(const Duration(days: 30))); // YYYY-MM-DD
    final out = await db.rawQuery('''
      SELECT p.name FROM products p
      WHERE COALESCE(p.is_deleted, 0) = 0 AND COALESCE(p.stock_quantity, 0) <= 0
        AND EXISTS (SELECT 1 FROM invoice_items ii JOIN invoices i ON i.id = ii.invoice_id
                    WHERE ii.product_id = p.id AND substr(i.invoice_date, 1, 10) >= ? AND COALESCE(i.is_deleted, 0) = 0)
      ORDER BY p.name''', [since]);
    d
      ..outOfStock = out.length
      ..outOfStockNames = [for (final r in out.take(6)) '${r['name'] ?? ''}'];
    try {
      final below = await db.rawQuery('''
        SELECT COUNT(*) AS n FROM products p JOIN product_details dd ON dd.product_id = p.id
        WHERE COALESCE(p.is_deleted, 0) = 0 AND COALESCE(dd.min_qty, 0) > 0
          AND COALESCE(p.stock_quantity, 0) > 0 AND p.stock_quantity <= dd.min_qty''');
      d.belowMin = ((below.first['n'] as num?) ?? 0).toInt();
    } on DatabaseException {
      d.belowMin = null;
    }
  }

  // ───────────────────────── التنسيق ─────────────────────────

  static String money(Object? v) {
    final n = v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    // الدينار العراقي بلا كسور: يُقرَّب للعرض (القيود نفسها لا تتغيّر)
    return NumberFormat('#,##0', 'en_US').format(n.roundToDouble());
  }

  /// تيليجرام يقرأ الرسالة HTML: < > & تُهرَّب.
  @visibleForTesting
  static String esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

  static String format(OwnerSummaryData d) {
    String m(double? v) => v == null ? 'تعذّر حسابه' : money(v);
    final b = StringBuffer();
    final title = 'ملخص يوم ${DateFormat('yyyy/MM/dd').format(d.day)}${d.shopName.isEmpty ? '' : ' — ${d.shopName}'}';
    b.writeln('📊 <b>${esc(title)}</b>');
    b.writeln();
    b.writeln('🧾 <b>المبيعات:</b> ${m(d.sales)}${d.invoiceCount == null ? '' : ' (${d.invoiceCount} فاتورة)'}');
    if (d.sales != null) b.writeln('   نقداً ${m(d.cashSales)} • آجلاً ${m(d.creditSales)}');
    if ((d.returns ?? 0).abs() > 0.004) b.writeln('↩️ المرتجعات: ${m(d.returns)}');
    b.writeln('📈 الربح التقديري: ${m(d.profit)}');
    b.writeln();
    b.writeln('💵 <b>المقبوض الصافي:</b> ${m(d.netCollected)}');
    if ((d.debtPayments ?? 0).abs() > 0.004) b.writeln('   منه تسديد ديون: ${m(d.debtPayments)}');
    if (d.debtIncrease != null) {
      b.writeln('📒 الديون: زادت ${m(d.debtIncrease)} • نقصت ${m((d.debtDecrease ?? 0).abs())}');
    }
    b.writeln('🗄️ صافي حركة الدرج: ${m(d.drawerNet)}');
    final boxes = d.boxes;
    if (boxes != null && boxes.isNotEmpty) {
      b.writeln('🏦 الصناديق (في الحسابات):');
      for (final e in boxes.entries.take(8)) {
        b.writeln('   • ${esc(e.key)}: ${money(e.value)}');
      }
    }
    b.writeln();
    if (d.sensitiveCount == null) {
      b.writeln('⚠️ العمليات الحساسة: تعذّر حسابها');
    } else if (d.sensitiveCount == 0) {
      b.writeln('✅ لا عمليات حساسة اليوم');
    } else {
      b.writeln('⚠️ <b>عمليات حساسة اليوم: ${d.sensitiveCount}</b>');
      for (final o in d.sensitive.take(8)) {
        final who = o.user.trim().isEmpty ? '' : '${o.user} — ';
        var line = '$who${o.action}: ${o.details}';
        if (line.length > 140) line = '${line.substring(0, 137)}...';
        b.writeln('   • ${esc(line)}');
      }
    }
    if (d.outOfStock != null && d.outOfStock! > 0) {
      b.writeln('📦 نفدت (بيعت خلال 30 يوماً): ${d.outOfStock}');
      b.writeln('   ${esc(d.outOfStockNames.join('، '))}${d.outOfStock! > d.outOfStockNames.length ? '…' : ''}');
    }
    if (d.belowMin != null && d.belowMin! > 0) b.writeln('⬇️ تحت الحد الأدنى: ${d.belowMin} مادة');
    if (d.claimsTomorrow != null && d.claimsTomorrow! > 0) {
      b.writeln('📅 مطالبات الغد: ${d.claimsTomorrow} عميل — ${m(d.claimsTomorrowTotal)}');
    }
    b.writeln();
    b.write('— أُرسل تلقائياً من برنامج الناصر للمحاسبة');
    var s = b.toString();
    if (s.length > maxLength) {
      // القطع عند نهاية سطر: لا يُقطع وسم HTML في منتصفه
      final cut = s.lastIndexOf('\n', maxLength - 2);
      s = '${s.substring(0, cut > 0 ? cut : maxLength - 2)}\n…';
    }
    return s;
  }
}
