// lib/wa_messages/wa_doc_sender.dart
//
// 📨 إرسال مستند PDF (فاتورة، كشف حساب، وصل، سند) مباشرة إلى واتساب صاحبه عبر الخادم —
// بجانب زر «مشاركة» الذي يبقى كما هو.
//   • الرقم: رقم الفاتورة نفسها إن وُجد، وإلا رقم العميل في سجل الديون (بالمعرّف، ثم
//     بالاسم إن طابق عميلاً واحداً فقط). لا رقم ⇒ يُطلب كتابته.
//   • أول مرة لكل عميل يُسأل المستخدم (الاسم، الرقم، المستند)، وبعد أول إرسال ناجح يُحفظ الرقم في
//     «الأرقام المؤكَّدة» فيُرسل له بعدها مباشرة. رقم مختلف عن المحفوظ ⇒ يُسأل من جديد.
//   • الخادم فقط: WhatsApp Desktop لا يرسل ملفات.
//   • الحد اليومي مشترك مع باقي رسائل واتساب، وكل إرسال في «سجل الرسائل».

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../owner/wa_auto/wa_auto_reminder.dart';
import '../owner/wa_auto/wa_server_client.dart';
import '../owner/wa_auto/wa_usage_mark.dart';
import '../services/database_service.dart';
import 'wa_message_log.dart';
import 'wa_phone_book.dart';

/// مستند جاهز للإرسال.
class WaDoc {
  WaDoc({required this.bytes, required this.fileName, required this.caption, this.customerId, this.customerName = '', this.phone});
  final Uint8List bytes;
  final String fileName, caption, customerName;
  final int? customerId;
  final String? phone;
}

class WaDocSender {
  WaDocSender._();

  /// رقم واتساب صالح: رقم المستند، ثم العميل بالمعرّف، ثم بالاسم (تطابق وحيد). null = لا رقم.
  static Future<String?> resolvePhone({String? phone, int? customerId, String? customerName}) async {
    final direct = WaAutoReminder.normalizePhone(phone);
    if (direct != null) return direct;
    try {
      final db = await DatabaseService().database;
      if (customerId != null) {
        final r = await db.query('customers', columns: ['phone'], where: 'id = ?', whereArgs: [customerId], limit: 1);
        final p = r.isEmpty ? null : WaAutoReminder.normalizePhone(r.first['phone'] as String?);
        if (p != null) return p;
      }
      final name = (customerName ?? '').trim();
      if (name.isNotEmpty) {
        final r = await db.query('customers',
            columns: ['phone'], where: 'TRIM(name) = ? AND COALESCE(is_deleted, 0) = 0', whereArgs: [name], limit: 2);
        if (r.length == 1) return WaAutoReminder.normalizePhone(r.first['phone'] as String?);
      }
    } catch (_) {}
    return null;
  }

  /// بلا مانع ⇒ null. وإلا السبب.
  static Future<String?> blockReason() async {
    final s = await WaAutoReminder.load();
    if (!s.enabled || !s.riskAccepted) {
      return 'إرسال واتساب الآلي مطفأ — يفعّله المدير من الإعدادات ← رسائل واتساب للزبائن ← طريقة الإرسال والأمان';
    }
    if (!s.viaServer) return 'إرسال الملفات يحتاج «الخادم» (WhatsApp Desktop لا يرسل ملفات) — استعمل «مشاركة»';
    if (await WaMessageLog.sentToday() >= s.maxPerDay) return 'بلغ حد رسائل اليوم (${s.maxPerDay})';
    return null;
  }

  /// فحص مسبق قبل بناء مستند يُسجَّل نسخةً مطبوعة (وصل/سند): يعرض السبب ويعيد false.
  static Future<bool> precheck(BuildContext context) async {
    final block = await blockReason();
    if (block == null) return true;
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(block), backgroundColor: Colors.red.shade700));
    }
    return false;
  }

  /// معرّف العميل إن كانت أسطر الوصل كلها لعميل واحد، وإلا null (وصل جماعي ⇒ يُكتب الرقم).
  static int? singleCustomer(Iterable<Map<String, Object?>> lines) {
    final ids = {for (final l in lines) (l['customer_id'] as num?)?.toInt()};
    return ids.length == 1 ? ids.first : null;
  }

  /// يبني المستند ([build]) ثم يسأل ويرسل. يعرض النتيجة في شريط أسفل الشاشة.
  static Future<void> send(BuildContext context, Future<WaDoc?> Function() build, {String source = 'doc'}) async {
    void toast(String m, {bool error = false}) => ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(m), backgroundColor: error ? Colors.red.shade700 : null));

    final block = await blockReason();
    if (block != null) {
      if (context.mounted) toast(block, error: true);
      return;
    }
    final WaDoc? doc;
    try {
      doc = await build();
    } catch (e) {
      if (context.mounted) toast('تعذّر تجهيز المستند: $e', error: true);
      return;
    }
    if (doc == null || !context.mounted) return;
    // 📒 الرقم المؤكَّد سابقاً لصاحب المستند
    final key = WaPhoneBook.keyOf(doc.customerId, doc.customerName);
    final saved = await WaPhoneBook.phoneOf(key);
    final docPhone = WaAutoReminder.normalizePhone(doc.phone);
    String? found;
    if (docPhone != null) {
      found = docPhone; // رقم المستند أولاً
    } else if (saved != null && doc.customerId != null) {
      found = saved; // عميل مسجّل أكّدت رقمه من قبل
    } else {
      found = await resolvePhone(customerId: doc.customerId, customerName: doc.customerName);
    }
    if (!context.mounted) return;
    final String phone;
    if (saved != null && found == saved) {
      phone = saved; // ✓ مؤكَّد من قبل: بلا سؤال
    } else {
      final ok = await showDialog<String>(
          context: context, builder: (_) => _ConfirmDialog(doc: doc!, phone: found ?? saved, changed: saved != null && found != null));
      if (ok == null || !context.mounted) return;
      phone = ok;
    }

    toast('يرسل إلى ${doc.customerName.isEmpty ? phone : doc.customerName}…');
    String? err;
    String? note;
    try {
      final st = await WaServerClient.ensureReady();
      if (!st.linked) {
        err = 'الخادم غير مربوط برقم واتساب — اربطه من «خادم واتساب»';
      } else {
        final r = await WaServerClient.send(phone, doc.caption, pdf: doc.bytes, pdfName: doc.fileName);
        err = r.error;
        note = r.note;
      }
    } on WaServerException catch (e) {
      err = e.message;
    } catch (e) {
      err = '$e';
    }
    await WaMessageLog.add(
      customerId: doc.customerId,
      name: doc.customerName,
      phone: phone,
      source: source,
      ruleName: doc.fileName,
      status: err == null ? 'sent' : 'failed',
      error: err ?? note,
      amount: 0,
      attach: 'PDF',
    );
    if (err == null) {
      await WaUsageMark.record('server', sends: 1);
      // 📒 بعد أول إرسال ناجح: هذا هو رقمه، والمرات القادمة بلا سؤال
      if (key != null && phone != saved) {
        try {
          await WaPhoneBook.confirm(key, doc.customerName, phone);
        } catch (_) {}
      }
    }
    if (!context.mounted) return;
    toast(err == null ? (note ?? 'أُرسل ✓ إلى ${doc.customerName.isEmpty ? phone : doc.customerName}') : 'لم يُرسل: $err',
        error: err != null || note != null);
  }
}

/// تأكيد قبل الإرسال، مع إمكانية كتابة الرقم أو تصحيحه. يعيد الرقم الدولي أو null.
class _ConfirmDialog extends StatefulWidget {
  const _ConfirmDialog({required this.doc, required this.phone, this.changed = false});
  final WaDoc doc;
  final String? phone;
  final bool changed; // له رقم مؤكَّد مختلف
  @override
  State<_ConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends State<_ConfirmDialog> {
  late final _c = TextEditingController(text: widget.phone ?? '');
  String? _err;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _go() {
    final p = WaAutoReminder.normalizePhone(_c.text);
    if (p == null) {
      setState(() => _err = 'رقم غير صالح — مثل 07701234567');
      return;
    }
    Navigator.pop(context, p);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        icon: const Icon(Icons.send_to_mobile_rounded, color: Color(0xFF047857), size: 34),
        title: Text('إرسال عبر واتساب${widget.doc.customerName.isEmpty ? '' : ' إلى ${widget.doc.customerName}'}'),
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('📄 ${widget.doc.fileName}'),
            const SizedBox(height: 6),
            Text(widget.doc.caption, style: const TextStyle(color: Color(0xFF64748B))),
            const SizedBox(height: 12),
            Text(
              widget.changed
                  ? '⚠️ رقم المستند يختلف عن رقمه المؤكَّد سابقاً — تأكد منه. بعد الإرسال يصبح هو المؤكَّد.'
                  : 'أول مرة لهذا العميل: تأكد من الرقم. بعد الإرسال يُحفظ، والمرات القادمة تُرسل مباشرة.',
              style: TextStyle(fontSize: 12, color: widget.changed ? const Color(0xFFB45309) : const Color(0xFF047857)),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _c,
              autofocus: widget.phone == null,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: widget.phone == null ? 'لا رقم مسجّل — اكتب رقم واتساب' : 'رقم واتساب',
                errorText: _err,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (_) => _go(),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF047857)),
            onPressed: _go,
            icon: const Icon(Icons.send_rounded),
            label: const Text('إرسال'),
          ),
        ],
      );
}

/// زر «إرسال عبر واتساب» يوضع بجانب زر المشاركة.
class WaSendDocButton extends StatelessWidget {
  const WaSendDocButton({super.key, required this.make, this.enabled = true, this.color, this.source = 'doc'});
  final Future<WaDoc?> Function() make;
  final bool enabled;
  final Color? color;
  final String source;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'إرسال لصاحبه عبر واتساب (الخادم)',
        visualDensity: VisualDensity.compact,
        icon: Icon(Icons.send_to_mobile_rounded, color: color ?? const Color(0xFF047857)),
        onPressed: enabled ? () => WaDocSender.send(context, make, source: source) : null,
      );
}
