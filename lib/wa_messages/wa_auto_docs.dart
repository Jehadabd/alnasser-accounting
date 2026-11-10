// lib/wa_messages/wa_auto_docs.dart
//
// 🤖 «عملاء الإرسال التلقائي»: عملاء يختارهم المدير، ولكل واحد ما يصله تلقائياً عبر الخادم
// لحظة الحفظ — بلا أي ضغطة:
//   • الفاتورة عند حفظها أول مرة.            • الفاتورة من جديد بعد تعديلها.
//   • وصل القبض (التسديد) عند حفظه.         • سند تعديل الفاتورة (إضافة/مرتجع: قبض/صرف/مدين/دائن).
//   • مستند مرتجع المبيعات عند حفظه.
// القواعد:
//   • الرقم يُؤكَّد مرة واحدة عند إضافة العميل هنا (يُحفظ في «الأرقام المؤكَّدة»)؛ لا رقم
//     مؤكَّد ⇒ لا إرسال (لا يُخمَّن رقم ويُرسل له بلا سؤال).
//   • نفس ملف الطباعة حرفياً، ونفس حماية الدين (CustomerBalanceGuard) والحد اليومي.
//   • وصل قبض فيه أكثر من عميل لا يُرسل (فيه أرصدة غيره).
//   • لا يتكرر: الفاتورة الواحدة تُرسل عند أول حفظ مرة واحدة (سجل الرسائل).
//   • يعمل في الخلفية بالترتيب، والنتيجة في الإشعار أعلى الشاشة و«سجل الرسائل».
// لا يغيّر أي فاتورة أو دين أو معاملة.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../erp/debts/receipt_pdf.dart';
import '../main.dart' show globalNavigatorKey;
import '../erp/debts/receipts_service.dart';
import '../erp/sales/sales_return_screen.dart' show salesReturnPdf;
import '../models/invoice.dart';
import '../services/customer_balance_guard.dart';
import '../services/database_service.dart';
import '../services/printed_vouchers.dart';
import '../services/saved_invoice_print_pdf.dart';
import '../services/voucher_print.dart';
import 'wa_doc_sender.dart';
import 'wa_message_log.dart';
import 'wa_phone_book.dart';
import 'wa_send_notice.dart';

/// ما يُرسل تلقائياً.
enum WaAutoDocKind {
  invoiceCash('فاتورة النقد عند حفظها', 'الفواتير'),
  invoiceDebt('فاتورة الدين عند حفظها', 'الفواتير'),
  invoiceEdited('الفاتورة من جديد بعد تعديلها', 'الفواتير'),
  receipt('وصل القبض (التسديد)', 'السندات'),
  editVoucher('سند تعديل الفاتورة: قبض/صرف نقدي، إشعار مدين/دائن', 'السندات'),
  salesReturn('مستند مرتجع المبيعات', 'السندات');

  const WaAutoDocKind(this.label, this.group);
  final String label;

  /// القسم في نافذة الإعداد.
  final String group;

  /// اسم قصير للشارات.
  String get short => switch (this) {
        invoiceCash => 'فاتورة نقد',
        invoiceDebt => 'فاتورة دين',
        invoiceEdited => 'الفاتورة المعدّلة',
        receipt => 'وصل القبض',
        editVoucher => 'سند التعديل',
        salesReturn => 'المرتجع',
      };
}

class WaAutoDocSub {
  WaAutoDocSub(this.customerId, this.name, this.kinds);
  final int customerId;
  final String name;
  final Set<WaAutoDocKind> kinds;
}

class WaAutoDocs {
  WaAutoDocs._();

  static const _table = 'wa_auto_docs';
  static int _readyGen = -1;

  static Future<Database> _db() async {
    final db = await DatabaseService().database;
    if (_readyGen != DatabaseService.openGeneration) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $_table (
          customer_id INTEGER PRIMARY KEY,
          name TEXT,
          kinds TEXT NOT NULL,
          updated_at TEXT
        )''');
      _readyGen = DatabaseService.openGeneration;
    }
    return db;
  }

  static Set<WaAutoDocKind> _parse(Object? raw) {
    try {
      final l = jsonDecode('${raw ?? '[]'}') as List;
      return {
        for (final k in WaAutoDocKind.values) if (l.contains(k.name)) k,
        // الإعداد الأول (قبل فصل النقد والدين): «الفاتورة» = الاثنان
        if (l.contains('invoice')) ...{WaAutoDocKind.invoiceCash, WaAutoDocKind.invoiceDebt},
      };
    } catch (_) {
      return {};
    }
  }

  // ───────────── الإعدادات ─────────────

  static Future<List<WaAutoDocSub>> all() async {
    final db = await _db();
    return [
      for (final r in await db.query(_table, orderBy: 'name'))
        WaAutoDocSub(r['customer_id'] as int, '${r['name'] ?? ''}', _parse(r['kinds'])),
    ];
  }

  static Future<Set<WaAutoDocKind>> kindsFor(int? customerId) async {
    if (customerId == null || customerId <= 0) return const {};
    try {
      final db = await _db();
      final r = await db.query(_table, columns: ['kinds'], where: 'customer_id = ?', whereArgs: [customerId], limit: 1);
      return r.isEmpty ? const {} : _parse(r.first['kinds']);
    } catch (_) {
      return const {};
    }
  }

  /// يحفظ اشتراك العميل ويؤكد رقمه (فارغ الأنواع = حذف الاشتراك).
  static Future<void> save(int customerId, String name, String phone, Set<WaAutoDocKind> kinds) async {
    final db = await _db();
    if (kinds.isEmpty) {
      await db.delete(_table, where: 'customer_id = ?', whereArgs: [customerId]);
      return;
    }
    final key = WaPhoneBook.keyOf(customerId, name)!;
    await WaPhoneBook.confirm(key, name, phone);
    await db.insert(
      _table,
      {
        'customer_id': customerId,
        'name': name,
        'kinds': jsonEncode([for (final k in kinds) k.name]),
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> remove(int customerId) async {
    final db = await _db();
    await db.delete(_table, where: 'customer_id = ?', whereArgs: [customerId]);
  }

  // ───────────── الأحداث (تُستدعى بعد الحفظ — لا تنتظرها الشاشة) ─────────────

  /// فاتورة حُفظت. [firstSave] = لم تكن محفوظة قبل هذا الحفظ.
  static void invoiceSaved(Invoice inv, {required bool firstSave}) {
    final id = inv.id;
    final cid = inv.customerId;
    if (id == null || cid == null || inv.status != 'محفوظة') return;
    _enqueue(() async {
      final kinds = await kindsFor(cid);
      final kind = !firstSave
          ? WaAutoDocKind.invoiceEdited
          : (inv.paymentType == 'دين' ? WaAutoDocKind.invoiceDebt : WaAutoDocKind.invoiceCash);
      if (!kinds.contains(kind)) return;
      // الفاتورة تُرسل عند أول حفظ مرة واحدة فقط
      final rule = firstSave ? 'auto_invoice_$id' : 'auto_invoice_edit_${id}_${DateTime.now().millisecondsSinceEpoch}';
      if (firstSave && (await WaMessageLog.lastSent(rule)).isNotEmpty) return;
      final fresh = await DatabaseService().getInvoiceById(id) ?? inv;
      final phone = await _gate(cid, fresh.customerName.trim(), rule, 'الفاتورة ${fresh.formattedInvoiceNumber}');
      if (phone == null) return;
      final bytes = await SavedInvoicePrintPdf.build(fresh);
      final safe = fresh.customerName.trim().replaceAll(RegExp(r'[^\w؀-ۿ]+'), '_');
      await _send(
        WaDoc(
          showsDebt: true,
          bytes: bytes,
          fileName: 'فاتورة_${fresh.formattedInvoiceNumber}_$safe.pdf',
          caption: '${firstSave ? 'فاتورة' : 'فاتورة (معدّلة)'} رقم ${fresh.formattedInvoiceNumber} — ${fresh.customerName.trim()}',
          customerId: cid,
          customerName: fresh.customerName.trim(),
        ),
        phone,
        rule,
      );
    });
  }

  /// وصل قبض حُفظ.
  static void receiptSaved(int receiptId) {
    _enqueue(() async {
      final lines = await ReceiptsService().receiptLines(receiptId);
      final cid = WaDocSender.singleCustomer(lines);
      if (cid == null) return; // وصل جماعي: فيه أرصدة عملاء آخرين
      if (!(await kindsFor(cid)).contains(WaAutoDocKind.receipt)) return;
      final rule = 'auto_receipt_$receiptId';
      if ((await WaMessageLog.lastSent(rule)).isNotEmpty) return;
      final db = await DatabaseService().database;
      final h = await db.rawQuery('''
        SELECT r.*, b.name AS box_name FROM customer_receipts r LEFT JOIN cash_boxes b ON b.id = r.cash_box_id
        WHERE r.id = ?''', [receiptId]);
      if (h.isEmpty) return;
      final r = h.first;
      final name = '${lines.first['customer_name'] ?? ''}'.trim();
      final phone = await _gate(cid, name, rule, 'وصل القبض ${r['receipt_no']}');
      if (phone == null) return;
      final stamp = await PrintedVouchers.forCustomerReceipt(receiptId); // نسخة مسجّلة مثل الطباعة
      final bytes = await ReceiptPdf.build(
        title: 'وصل قبض',
        number: (r['receipt_no'] as num).toInt(),
        date: DateTime.tryParse('${r['receipt_date']}') ?? DateTime.now(),
        boxName: '${r['box_name'] ?? ''}',
        currency: (r['currency'] as String?) ?? 'IQD',
        fxRate: (r['fx_rate'] as num?)?.toDouble() ?? 1,
        lines: lines,
        docNo: r['doc_no'] as String?,
        notes: r['notes'] as String?,
        commission: (r['commission'] as num?)?.toDouble() ?? 0,
        recordedBy: r['created_by'] as String?,
        stamp: stamp,
      );
      await _send(
        WaDoc(
          showsDebt: true,
          bytes: bytes,
          fileName: 'وصل_قبض_${r['receipt_no']}.pdf',
          caption: 'وصل قبض رقم ${r['receipt_no']} — $name',
          customerId: cid,
          customerName: name,
        ),
        phone,
        rule,
      );
    });
  }

  /// سند تعديل فاتورة (إضافة/مرتجع) سُجّل.
  static void editVoucherSaved(int eventId, {int? legacyCashVoucherId}) {
    _enqueue(() async {
      final rule = 'auto_edit_voucher_$eventId';
      if ((await WaMessageLog.lastSent(rule)).isNotEmpty) return;
      // العميل أولاً (بلا تسجيل نسخة لمن لا يشترك)
      final db = await DatabaseService().database;
      final ev = await db.rawQuery(
          'SELECT i.customer_id AS c FROM invoice_edit_events e JOIN invoices i ON i.id = e.invoice_id WHERE e.id = ?',
          [eventId]);
      final cid = ev.isEmpty ? null : (ev.first['c'] as num?)?.toInt();
      if (cid == null || !(await kindsFor(cid)).contains(WaAutoDocKind.editVoucher)) return;
      final cn = await db.query('customers', columns: ['name'], where: 'id = ?', whereArgs: [cid], limit: 1);
      final phone = await _gate(cid, cn.isEmpty ? '' : '${cn.first['name']}'.trim(), rule, 'سند تعديل الفاتورة');
      if (phone == null) return;
      final built = await VoucherPrint.editEventPdf(eventId, legacyCashVoucherId: legacyCashVoucherId);
      if (built == null) return;
      final title = VoucherKinds.title(built.kind);
      final no = built.data.field('voucherNo');
      await _send(
        WaDoc(
          showsDebt: true,
          bytes: built.bytes,
          fileName: '${title}_$no.pdf'.replaceAll(' ', '_'),
          caption: '$title رقم $no — الفاتورة ${built.data.field('invoiceNo')}',
          customerId: built.customerId ?? cid,
          customerName: built.data.field('customer'),
        ),
        phone,
        rule,
      );
    });
  }

  /// مرتجع مبيعات حُفظ.
  static void salesReturnSaved(int returnId) {
    _enqueue(() async {
      final rule = 'auto_sales_return_$returnId';
      if ((await WaMessageLog.lastSent(rule)).isNotEmpty) return;
      final db = await DatabaseService().database;
      final h = await db.query('sales_returns',
          columns: ['customer_id', 'customer_name', 'return_no'], where: 'id = ?', whereArgs: [returnId], limit: 1);
      if (h.isEmpty) return;
      final cid = (h.first['customer_id'] as num?)?.toInt();
      if (cid == null || !(await kindsFor(cid)).contains(WaAutoDocKind.salesReturn)) return;
      final name = '${h.first['customer_name'] ?? ''}'.trim();
      final phone = await _gate(cid, name, rule, 'مرتجع المبيعات ${h.first['return_no']}');
      if (phone == null) return;
      final built = await salesReturnPdf(returnId);
      await _send(
        WaDoc(
          showsDebt: false,
          bytes: built.bytes,
          fileName: 'مرتجع_مبيعات_${h.first['return_no']}.pdf',
          caption: 'مرتجع مبيعات رقم ${h.first['return_no']} — $name',
          customerId: cid,
          customerName: name,
        ),
        phone,
        rule,
      );
    });
  }

  // ───────────── الإرسال ─────────────

  static Future<void> _chain = Future.value();

  /// بالترتيب، واحداً بعد واحد، في الخلفية — خطأ واحد لا يوقف ما بعده.
  static void _enqueue(Future<void> Function() job) {
    _chain = _chain.then((_) async {
      try {
        await job();
      } catch (e) {
        debugPrint('⚠️ الإرسال التلقائي: $e');
        WaSendNotice.finish(null, WaNoticeState.failed, 'تعذّر الإرسال التلقائي', '$e');
      }
    });
  }

  static Future<void> _fail(int? cid, String name, String rule, String label, String why) async {
    WaSendNotice.finish(null, WaNoticeState.failed, 'لم يُرسل $label تلقائياً${name.isEmpty ? '' : ' إلى $name'}', why);
    await WaMessageLog.add(
      customerId: cid,
      name: name,
      phone: '',
      source: 'auto_doc',
      ruleId: rule,
      ruleName: label,
      status: 'failed',
      error: why,
      amount: 0,
      attach: 'PDF',
    );
  }

  /// قبل بناء الملف (وقبل تسجيل أي نسخة مطبوعة): الإرسال مسموح؟ الرقم مؤكَّد؟ الدين مطابق؟
  /// يعيد الرقم، أو null بعد تسجيل السبب.
  static Future<String?> _gate(int cid, String name, String rule, String label) async {
    final block = await WaDocSender.blockReason();
    if (block != null) {
      await _fail(cid, name, rule, label, block);
      return null;
    }
    final key = WaPhoneBook.keyOf(cid, name);
    var phone = await WaPhoneBook.phoneOf(key);
    // رقم العميل في سجل الديون تغيّر منذ التأكيد ⇒ يُسأل مرة واحدة الآن، ثم تلقائي كما كان
    final changed = phone == null ? null : await WaPhoneBook.changedRegistryPhone(key);
    if (changed != null && changed != phone) {
      final ctx = globalNavigatorKey.currentContext;
      final ok = ctx == null || !ctx.mounted
          ? null
          : await WaDocSender.askPhone(
              ctx,
              WaDoc(
                bytes: Uint8List(0),
                fileName: label,
                caption: 'إرسال تلقائي عند الحفظ — رقمه في سجل الديون تغيّر',
                customerId: cid,
                customerName: name,
              ),
              changed,
              changed: true,
            );
      if (ok == null) {
        await _fail(cid, name, rule, label, 'رقم العميل في سجل الديون تغيّر ولم يُؤكَّد — لم يُرسل');
        return null;
      }
      await WaPhoneBook.confirm(key!, name, ok); // تأكيد صريح الآن
      phone = ok;
    } else if (changed != null) {
      await WaPhoneBook.confirm(key!, name, phone!); // نفس الرقم: يُحدَّث رقم السجل فقط
    }
    if (phone == null) {
      await _fail(cid, name, rule, label, 'لا رقم مؤكَّد لهذا العميل — أكّده من «الإرسال التلقائي للعملاء»');
      return null;
    }
    final chk = await CustomerBalanceGuard.check(cid);
    if (chk != null && !chk.ok) {
      await _fail(cid, name, rule, label, chk.message);
      return null;
    }
    return phone;
  }

  static Future<void> _send(WaDoc doc, String phone, String rule) =>
      WaDocSender.transmit(doc, phone, source: 'auto_doc', ruleId: rule);
}
