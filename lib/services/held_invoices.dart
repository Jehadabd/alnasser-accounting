// lib/services/held_invoices.dart
//
// ⏸️ الفواتير المعلّقة (Hold / Park) — مأخوذة من debt_book مع إصلاح ثلاثة أخطاء:
//   1) هناك كان زر التعليق يحوّل فاتورة «محفوظة» إلى «معلقة» وهي تملك قيد دين
//      وحركة مخزون، فيختل الدفتر. هنا: يُعلَّق الجديد أو المعلّق فقط.
//   2) هناك كان العميل يُربط بأول نتيجة بحث تقريبي (كتابة «علي» تربط
//      «علي حسين»). هنا: مطابقة الاسم المطبَّع الدقيقة فقط، وإلا بلا عميل.
//   3) هناك كانت البنود تُحذف ثم تُضاف واحداً واحداً بلا معاملة؛ انقطاع
//      في المنتصف يترك فاتورة ناقصة. هنا: استبدال البنود في معاملة واحدة.
//
// الفاتورة المعلّقة لا تؤثر على المخزون ولا الديون ولا التقارير (كلها تستثني
// الحالة «معلقة»)، وتُستدعى بفتحها في «إنشاء فاتورة» ثم «حفظ».

import '../models/invoice.dart';
import '../models/invoice_item.dart';
import 'database_service.dart';

class HeldInvoices {
  HeldInvoices._();

  static const status = 'معلقة';
  static const _where = "status = 'معلقة' AND COALESCE(is_deleted, 0) = 0";

  static Future<int> count() async {
    final db = await DatabaseService().database;
    final r = await db.rawQuery('SELECT COUNT(*) AS c FROM invoices WHERE $_where');
    return (r.first['c'] as num?)?.toInt() ?? 0;
  }

  /// الأحدث تعديلاً أولاً، مع عدد البنود
  static Future<List<(Invoice, int)>> list() async {
    final db = await DatabaseService().database;
    final rows = await db.rawQuery('''
      SELECT i.*, (SELECT COUNT(*) FROM invoice_items ii WHERE ii.invoice_id = i.id) AS _items
      FROM invoices i WHERE i.$_where
      ORDER BY i.last_modified_at DESC, i.id DESC
    ''');
    return [for (final m in rows) (Invoice.fromMap(m), (m['_items'] as num?)?.toInt() ?? 0)];
  }

  /// يعلّق الفاتورة الحالية ويعيدها (بمعرّفها). يرمي [StateError] لفاتورة محفوظة.
  static Future<Invoice> hold({
    required Invoice? existing,
    required List<InvoiceItem> items,
    required String customerName,
    String? customerPhone,
    String? customerAddress,
    String? installerName,
    required DateTime invoiceDate,
    required String paymentType,
    required double discount,
    required double loadingFee,
    required double paid,
    double pointsRate = 0,
    int? createdByUserId,
    String? createdByUsername,
  }) async {
    if (existing != null && existing.status != status) {
      throw StateError('فاتورة محفوظة لا تُعلَّق: احفظ تعديلها أو ألغِه');
    }
    final lines = items.where((i) => i.productName.trim().isNotEmpty).toList();
    if (lines.isEmpty) throw StateError('لا توجد بنود لتعليقها');

    final dbs = DatabaseService();
    final name = customerName.trim();
    final customer = name.isEmpty ? null : await dbs.findCustomerByNormalizedName(name);
    final itemsTotal = lines.fold<double>(0, (s, i) => s + i.itemTotal);
    final now = DateTime.now();

    var inv = Invoice(
      id: existing?.id,
      customerName: name,
      customerPhone: customerPhone?.trim(),
      customerAddress: customerAddress?.trim(),
      installerName: (installerName ?? '').trim().isEmpty ? null : installerName!.trim(),
      invoiceDate: invoiceDate,
      paymentType: paymentType,
      totalAmount: itemsTotal + loadingFee - discount,
      discount: discount,
      amountPaidOnInvoice: paid,
      loadingFee: loadingFee,
      createdAt: existing?.createdAt ?? now,
      lastModifiedAt: now,
      customerId: customer?.id,
      status: status,
      pointsRate: pointsRate,
      createdByUserId: existing?.createdByUserId ?? createdByUserId,
      createdByUsername: existing?.createdByUsername ?? createdByUsername,
      notes: existing?.notes,
      invoiceUuid: existing?.invoiceUuid,
      creatorDeviceId: existing?.creatorDeviceId,
      version: existing?.version ?? 1,
      monthlySequenceNumber: existing?.monthlySequenceNumber,
      invoiceNumber: existing?.invoiceNumber,
      invoiceYear: existing?.invoiceYear,
      invoiceMonth: existing?.invoiceMonth,
    );

    final isNew = existing?.id == null;
    final int id;
    if (isNew) {
      id = await dbs.insertInvoice(inv); // يختم حقول المزامنة
    } else {
      id = existing!.id!;
      await dbs.updateInvoice(inv);
    }

    // البنود: حذف القديم وإدراج الجديد في معاملة واحدة
    final db = await dbs.database;
    try {
      await db.transaction((txn) async {
        await txn.delete('invoice_items', where: 'invoice_id = ?', whereArgs: [id]);
        for (final it in lines) {
          final m = it.copyWith(invoiceId: id).toMap()..remove('id');
          await txn.insert('invoice_items', m);
        }
      });
    } catch (e) {
      // فاتورة جديدة بلا بنود لا معنى لها: نحذفها حتى لا تبقى فارغة في القائمة
      if (isNew) {
        try {
          await dbs.deleteInvoice(id);
        } catch (_) {}
      }
      rethrow;
    }
    return (await dbs.getInvoiceById(id)) ?? inv;
  }

  /// حذف فاتورة معلّقة (حذف منطقي يتزامن). يرفض غير المعلّقة.
  static Future<void> discard(Invoice inv) async {
    if (inv.id == null || inv.status != status) return;
    await DatabaseService().deleteInvoice(inv.id!);
  }
}
