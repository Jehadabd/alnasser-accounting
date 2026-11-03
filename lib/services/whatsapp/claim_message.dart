// lib/services/whatsapp/claim_message.dart
//
// 📨 رسالة المطالبة بالسداد عبر واتساب — نص رسمي جاهز، قراءة فقط.
//   • [ClaimMessage.build] نص المطالبة (دالة نقية قابلة للاختبار).
//   • [WhatsAppLink.normalizePhone] الرقم بصيغة دولية (العراق 964 افتراضياً).
//   • [WhatsAppLink.open] يفتح واتساب بالنص (تطبيق الحاسبة ثم المتصفح)، وينسخ
//     النص للحافظة احتياطاً. واتساب من الرابط يقبل نصاً فقط — لا مرفقات.

import 'dart:io' show Platform, Process;

import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:intl/intl.dart' hide TextDirection;
import 'package:url_launcher/url_launcher.dart';

class ClaimMessage {
  ClaimMessage._();

  static String _money(double v) => NumberFormat('#,##0.##', 'en_US').format(v);
  static String _date(DateTime d) => DateFormat('yyyy/MM/dd').format(d);

  /// [amount] المبلغ المطلوب في هذا الموعد (null = كامل الرصيد)، [balance] الرصيد الحالي.
  static String build({
    required String customerName,
    required String company,
    required double balance,
    double? amount,
    DateTime? lastPaid,
    String? invoiceNumber,
    DateTime? today,
  }) {
    final day = today ?? DateTime.now();
    final c = company.trim();
    final claim = amount ?? balance;
    final b = StringBuffer()
      ..writeln('السيد/السيدة ${customerName.trim()} المحترم/المحترمة،')
      ..writeln('تحية طيبة وبعد،')
      ..writeln()
      ..write('نودّ إعلامكم بأن المبلغ المستحق في ذمتكم')
      ..write(c.isEmpty ? '' : ' لدى $c')
      ..writeln(' بتاريخ ${_date(day)} هو ${_money(claim)} دينار عراقي.');
    if (amount != null && (balance - amount).abs() > 0.004) {
      b.writeln('علماً بأن الرصيد الكلي لحسابكم ${_money(balance)} دينار عراقي.');
    }
    if ((invoiceNumber ?? '').trim().isNotEmpty) b.writeln('يتعلق المبلغ بالفاتورة رقم ${invoiceNumber!.trim()}.');
    if (lastPaid != null) b.writeln('آخر سداد مسجّل في حسابكم بتاريخ ${_date(lastPaid)}.');
    b
      ..writeln()
      ..writeln('نرجو التكرم بتسديد المبلغ في أقرب وقت ممكن، أو مراجعتنا لأي استفسار يخص الحساب.')
      ..writeln()
      ..write('مع فائق التقدير والاحترام');
    if (c.isNotEmpty) b.write('\n$c');
    return b.toString();
  }
}

class WhatsAppLink {
  WhatsAppLink._();

  /// أرقام فقط بصيغة دولية: 07701234567 ← 9647701234567.
  static String? normalizePhone(String? phone) {
    if (phone == null) return null;
    var p = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (p.startsWith('+')) p = p.substring(1);
    if (p.startsWith('00')) p = p.substring(2);
    if (p.startsWith('0')) p = '964${p.substring(1)}';
    if (!p.startsWith('964') && p.length <= 10) p = '964$p';
    return p.length < 8 ? null : p;
  }

  /// يفتح واتساب برسالة [text] إلى [phone]. يعيد false إن تعذّر فتحه (النص في الحافظة).
  static Future<bool> open(String phone, String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } catch (_) {}
    final enc = Uri.encodeComponent(text);
    if (Platform.isWindows) {
      try {
        await Process.start('cmd', ['/c', 'start', '""', 'whatsapp://send?phone=$phone&text=$enc']);
        return true;
      } catch (_) {}
    }
    for (final u in [
      if (Platform.isAndroid) Uri.parse('whatsapp://send?phone=$phone&text=$enc'),
      Uri.parse('https://wa.me/$phone?text=$enc'),
      Uri.parse('https://api.whatsapp.com/send?phone=$phone&text=$enc'),
    ]) {
      try {
        if (await launchUrl(u, mode: LaunchMode.externalApplication)) return true;
      } catch (_) {}
    }
    return false;
  }
}
