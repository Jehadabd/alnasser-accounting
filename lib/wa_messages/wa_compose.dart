// lib/wa_messages/wa_compose.dart
//
// ✍️ تأليف رسالة المطالبة: نص (القاعدة أو الافتراضي) + عنوان المحل + كشف حساب ملخّص
// «منذ آخر مرة كان رصيده صفراً» — نصاً داخل الرسالة أو ملف PDF.
// الكشف من محرك الكشوفات نفسه (StatementEngine — قراءة فقط) فيطابق ما يُطبع من البرنامج.

import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../owner/wa_auto/wa_auto_reminder.dart';
import '../screens/statements/statement_engine.dart';
import '../screens/statements/statement_pdf.dart';
import '../services/settings_manager.dart';
import 'wa_rules.dart';

class WaComposed {
  WaComposed(this.text, {this.pdf, this.pdfName, this.attachLabel = ''});
  final String text;
  final Uint8List? pdf;
  final String? pdfName;

  /// للسجل: '' أو 'كشف نصي' أو 'كشف PDF'.
  final String attachLabel;
}

class WaCompose {
  WaCompose._();

  static const _kAddress = 'wa_shop_address';

  /// أقصى طول للرسالة (حد الخادم 4000).
  static const maxLength = 3800;

  static final _n = NumberFormat('#,##0', 'en');

  /// عنوان المحل للرسائل: المحفوظ هنا، وإلا عنوان الفاتورة.
  static Future<String> address() async {
    final p = await SharedPreferences.getInstance();
    final saved = p.getString(_kAddress);
    if (saved != null) return saved.trim();
    try {
      return (await SettingsManager.getAppSettings()).invoiceDesign.companyAddress.trim();
    } catch (_) {
      return '';
    }
  }

  static Future<void> setAddress(String v) async =>
      (await SharedPreferences.getInstance()).setString(_kAddress, v.trim());

  /// يملأ القالب ويضيف العنوان (إن لم يُكتب {العنوان} في النص). دالة صافية.
  static String renderText(String template, WaTarget t, String shop, {String address = ''}) {
    final hasPlaceholder = template.contains('{العنوان}');
    var text = WaAutoReminder.render(template.replaceAll('{العنوان}', address), t, shop);
    if (!hasPlaceholder && address.trim().isNotEmpty) text = '$text\n📍 العنوان: ${address.trim()}';
    return text;
  }

  /// الكشف نصاً: آخر الحركات حتى يتسع [budget] حرفاً. دالة صافية.
  static String statementText(StatementResult s, {int budget = 1800}) {
    final head = '📄 كشف حساب مختصر — ${s.periodText}';
    final tail = 'الرصيد الحالي: ${_n.format(s.closing.round())} دينار';
    final lines = <String>[];
    var used = head.length + tail.length + 40;
    for (var i = s.rows.length - 1; i >= 0; i--) {
      final r = s.rows[i];
      final sign = r.amount < 0 ? '-' : '+';
      final line = '${stmtDate(r.date)} • ${r.title} • $sign${_n.format(r.amount.abs().round())}';
      if (used + line.length + 1 > budget) break;
      lines.insert(0, line);
      used += line.length + 1;
    }
    final hidden = s.rows.length - lines.length;
    return [
      head,
      if (s.opening.abs() >= 0.5) 'رصيد سابق: ${_n.format(s.opening.round())}',
      if (hidden > 0) '… و$hidden حركة أقدم',
      ...lines,
      tail,
    ].join('\n');
  }

  /// الرسالة كاملة لعميل. [viaServer] = false ⇒ PDF يتحول نصاً (WhatsApp Desktop لا يرسل ملفات).
  static Future<WaComposed> compose({
    required WaTarget t,
    required WaMessageOptions o,
    required String defaultTemplate,
    required bool viaServer,
  }) async {
    final shop = await WaAutoReminder.shopName();
    final addr = o.address ? await address() : '';
    final tpl = o.template.trim().isEmpty ? defaultTemplate : o.template;
    var text = renderText(tpl, t, shop, address: addr);
    var attach = o.attach;
    if (attach == WaAttach.pdf && !viaServer) attach = WaAttach.text;
    if (attach == WaAttach.none) return WaComposed(text);

    final s = await StatementEngine.account(
      customerId: t.id,
      customerName: t.name,
      period: const StmtPeriod.sinceZero(),
      detail: StmtDetail.summary,
    );
    if (attach == WaAttach.text) {
      final room = maxLength - text.length - 2;
      if (room > 200) text = '$text\n\n${statementText(s, budget: room)}';
      return WaComposed(text, attachLabel: o.attach == WaAttach.pdf ? 'كشف نصي (بدل PDF)' : 'كشف نصي');
    }
    final pdf = await buildAccountStatementPdf(s);
    final safe = t.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return WaComposed(text, pdf: pdf, pdfName: 'كشف حساب - $safe.pdf', attachLabel: 'كشف PDF');
  }
}
