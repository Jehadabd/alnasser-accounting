// lib/erp/sales/invoice_bridge.dart
//
// 🌉 تحويل عرض سعر أو طلب إلى فاتورة بيع حقيقية — دون أي تعديل على شاشة
// الفاتورة الأصلية: نكتب مسودة بنفس صيغة «الحفظ التلقائي» التي تستعيدها شاشة
// إنشاء القائمة عند فتحها، ثم نفتحها. الحفظ النهائي (المخزون، الدين، المزامنة،
// الترقيم) يتم بالمسار الأصلي تماماً، والمستخدم يراجع كل شيء قبل الحفظ.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../screens/create_invoice_screen.dart';
import '../erp_common.dart';

class DraftLine {
  DraftLine({
    required this.productName,
    required this.productUnit,
    required this.unitPrice,
    required this.baseCost,
    required this.quantity,
    required this.saleType,
    required this.factor,
    required this.price,
  });
  final String productName;

  /// وحدة المنتج الأساسية كما في products.unit (piece/meter/...).
  final String productUnit;
  final double unitPrice;

  /// كلفة الوحدة الأساسية.
  final double baseCost;
  final double quantity;

  /// اسم الوحدة المباعة (قطعة، متر، كرتون، لفة...).
  final String saleType;

  /// عدد الوحدات الأساسية في الوحدة المباعة.
  final double factor;
  final double price;
}

class InvoiceBridge {
  InvoiceBridge._();

  static const _key = 'temp_invoice_data';
  static const _storage = FlutterSecureStorage();

  static bool _isBase(DraftLine l) =>
      l.factor == 1 || l.saleType == 'قطعة' || l.saleType == 'متر';

  /// هل توجد فاتورة غير محفوظة في الشاشة؟
  static Future<bool> hasPendingDraft() async {
    try {
      final t = await _storage.read(key: _key);
      if (t == null || t.isEmpty) return false;
      final d = jsonDecode(t) as Map<String, dynamic>;
      final items = (d['invoiceItems'] as List<dynamic>? ?? const []);
      return items.any((i) => ((i as Map)['productName'] as String? ?? '').trim().isNotEmpty);
    } catch (_) {
      return false;
    }
  }

  /// يكتب المسودة ويفتح شاشة إنشاء القائمة. يعيد رقم الفاتورة التي حُفظت
  /// لهذا العميل بعد الفتح (أو null إن لم تُحفظ).
  static Future<int?> openAsInvoice(
    BuildContext context, {
    required String customerName,
    String? phone,
    String? address,
    required List<DraftLine> lines,
    double discount = 0,
    String paymentType = 'نقد',
  }) async {
    if (lines.isEmpty) throw ErpException('لا توجد مواد');
    if (await hasPendingDraft()) {
      if (!context.mounted) return null;
      final ok = await confirmDialog(context, 'فاتورة غير محفوظة',
          'في شاشة «إنشاء قائمة» فاتورة لم تُحفظ بعد. فتح هذا المستند سيستبدلها. متابعة؟');
      if (!ok) return null;
    }
    final now = DateTime.now();
    final data = {
      'customerName': customerName,
      'customerPhone': phone ?? '',
      'customerAddress': address ?? '',
      'installerName': '',
      'selectedDate': now.toIso8601String(),
      'paymentType': paymentType,
      'discount': discount.toDouble(),
      'paidAmount': '',
      'invoiceItems': [
        for (var i = 0; i < lines.length; i++)
          {
            'productName': lines[i].productName,
            'unit': lines[i].productUnit,
            'unitPrice': lines[i].unitPrice.toDouble(),
            'costPrice': (lines[i].baseCost * lines[i].quantity * lines[i].factor).toDouble(),
            'quantityIndividual': _isBase(lines[i]) ? lines[i].quantity.toDouble() : null,
            'quantityLargeUnit': _isBase(lines[i]) ? null : lines[i].quantity.toDouble(),
            'appliedPrice': lines[i].price.toDouble(),
            'itemTotal': (lines[i].price * lines[i].quantity).toDouble(),
            'saleType': lines[i].saleType,
            'unitsInLargeUnit': _isBase(lines[i]) ? null : lines[i].factor.toDouble(),
            'uniqueId': 'item_${now.microsecondsSinceEpoch}_$i',
          },
      ],
    };
    await _storage.write(key: _key, value: jsonEncode(data));
    if (!context.mounted) return null;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateInvoiceScreen()));
    // هل حُفظت فاتورة لهذا العميل بعد الفتح؟
    final db = await erpDb();
    final r = await db.rawQuery('''
      SELECT id FROM invoices WHERE customer_name = ? AND created_at >= ? AND COALESCE(is_deleted, 0) = 0
        AND status = 'محفوظة'
      ORDER BY id DESC LIMIT 1
    ''', [customerName, now.subtract(const Duration(seconds: 5)).toIso8601String()]);
    return r.isEmpty ? null : r.first['id'] as int;
  }
}
