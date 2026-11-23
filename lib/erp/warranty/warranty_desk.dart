// lib/erp/warranty/warranty_desk.dart
//
// 🛠️ «مكتب الضمان» — استلام قطعة من فاتورتها.
//
//   1. ابحث باسم العميل أو رقم الفاتورة أو الهاتف ⇒ فواتيره.
//   2. افتح فاتورة ⇒ موادها التي لها ضمان فقط، ولكل مادة: ساري حتى … / منتهٍ منذ …
//   3. لكل مادة:
//        • صيانة   — طلب ضمان للمتابعة (بلا مال ولا مخزون، كما كان).
//        • استبدال — قطعة جديدة تخرج من المخزن الرئيسي بـ«سند إخراج» على حساب
//                    «مصروف الضمان والاستبدال»، والمعطوبة تبقى طلب ضمان مفتوحاً
//                    (تُرسل للمورد من شاشة الطلب).
//        • استرجاع — يُحفظ «مرتجع مبيعات» في الخلفية عبر SalesReturnService نفسها
//                    (لا انتقال لشاشة المرتجع): الردّ نقداً من صندوق أو من دين العميل
//                    يُختار في نافذة الضمان، والسعر من سطر الفاتورة، والطباعة حسب الإعداد.
//                    بعده — كما في Odoo/SAP (إرجاع ثم شطب): القطعة المعيبة تُشطب فوراً
//                    بسند إخراج بكلفتها نفسها على «مصروف الضمان والاستبدال»، فلا تدخل
//                    الرصيد القابل للبيع إطلاقاً. إلا إن اخترت «سليمة تعود للبيع».
//   القطعة المعيبة (في الاستبدال والاسترجاع) تبقى ماديًا لدى المحل كطلب ضمان يُرسل
//   للمورد؛ إن عوّضك المورد بقطعة فهي فاتورة شراء، وإن عوّضك مالاً فسند قبض على الحساب نفسه.
//   الوحدة: أي وحدة من هرم المادة (كرتون/باكيت/قطعة) والكمية بها، والحد الأعلى
//   = المبيع في الفاتورة − ما أُرجع منها − ما استُبدل منها.
//   ضمان منتهٍ: تحذير ثم السماح، ويُسجَّل الطلب «خارج الضمان».
//
// 🛡️ المال والمخزون عبر المسارات الأصلية فقط (StockDocsService / SalesReturnService)؛
//    هذا الملف لا يكتب قيداً ولا معاملة عميل بنفسه.

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart' show DatabaseExecutor;

import '../../accounting/ledger.dart';
import '../../accounting/screens/acc_ui.dart' show fmtDate, fmtMoney, showError, showOk;
import '../../org/org_service.dart';
import '../erp_common.dart';
import '../erp_ui.dart';
import '../inventory/stock_docs_service.dart';
import '../debts/customer_money.dart' show CustomerMoney;
import '../pickers.dart' show CashBoxDropdown;
import '../sales/sales_return_screen.dart' show printSalesReturn;
import '../sales/sales_return_service.dart';
import '../../services/voucher_print.dart' show VoucherPrint;
import '../../wa_messages/wa_auto_docs.dart';
import '../stock_helpers.dart';
import 'item_warranty.dart';
import 'warranty_screens.dart' show WarrantyClaimEditor, printWarrantyReceipt;
import 'warranty_service.dart';

// ───────────────────────────── البيانات ─────────────────────────────

class DeskInvoice {
  DeskInvoice(this.id, this.number, this.date, this.customerId, this.customerName, this.total, this.warrantyLines);
  final int id;
  final String number;
  final DateTime? date;
  final int? customerId;
  final String customerName;
  final double total;
  final int warrantyLines;
}

class DeskLine {
  DeskLine({
    required this.productId,
    required this.name,
    required this.saleUnit,
    required this.soldQty,
    required this.soldBase,
    required this.spec,
    required this.end,
    required this.terms,
    required this.returnableBase,
    required this.replacedBase,
  });
  final int productId;
  final String name;
  final String saleUnit;
  final double soldQty;
  final double soldBase;
  final WarrantySpec spec;
  final DateTime end;
  final String? terms;

  /// المتبقي في الفاتورة بعد المرتجعات (لكل المادة في الفاتورة).
  final double returnableBase;

  /// ما استُبدل منها سابقاً من هذا المكتب.
  final double replacedBase;

  double get maxBase => (returnableBase - replacedBase).clamp(0, double.infinity).toDouble();

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// النهاية شاملة: آخر يوم يعمل فيه الضمان.
  bool get within => !_day(DateTime.now()).isAfter(_day(end));
  int get daysLeft => _day(end).difference(_day(DateTime.now())).inDays;
}

class WarrantyDesk {
  WarrantyDesk._();

  static const _accKey = 'warranty_expense';

  /// سعر الوحدة الأساسية في الفاتورة، والباقي ديناً عليها (لطريقة الردّ الافتراضية).
  static Future<({double perBase, double remaining})> refundInfo(DeskInvoice inv, DeskLine l, ProductLite p) async {
    final d = await erpDb();
    final it = await d.rawQuery('''
      SELECT ii.applied_price, ii.sale_type FROM invoice_items ii
      JOIN products pr ON (pr.sync_uuid = ii.product_sync_uuid OR (ii.product_sync_uuid IS NULL AND pr.name = ii.product_name))
      WHERE ii.invoice_id = ? AND pr.id = ? ORDER BY ii.id LIMIT 1''', [inv.id, l.productId]);
    var perBase = 0.0;
    if (it.isNotEmpty) {
      final u = p.unitNamed(it.first['sale_type'] as String?);
      final price = d0(it.first['applied_price']);
      perBase = u.factor > 0 ? price / u.factor : price;
    }
    final h = await d.query('invoices', columns: ['total_amount', 'amount_paid_on_invoice'], where: 'id = ?', whereArgs: [inv.id], limit: 1);
    final rem = h.isEmpty ? 0.0 : d0(h.first['total_amount']) - d0(h.first['amount_paid_on_invoice']);
    return (perBase: perBase, remaining: rem > 0 ? rem : 0.0);
  }

  /// أعمدة مضافة على طلبات الضمان: نوع العملية من المكتب ومرجعها والكمية بالأساسية.
  static Future<void> _ensure(DatabaseExecutor d) async {
    await WarrantyService.db();
    final cols = {for (final r in await d.rawQuery('PRAGMA table_info(warranty_claims)')) '${r['name']}'};
    for (final c in const [('desk_action', 'TEXT'), ('desk_ref', 'INTEGER'), ('desk_base_qty', 'REAL')]) {
      if (!cols.contains(c.$1)) await d.execute('ALTER TABLE warranty_claims ADD COLUMN ${c.$1} ${c.$2}');
    }
  }

  static String _like(String s) => '%${s.replaceAll('%', '').replaceAll('_', '').trim()}%';

  /// فواتير البيع: برقمها، أو اسم العميل، أو هاتفه. الأحدث أولاً.
  static Future<List<DeskInvoice>> search(String q) async {
    final t = q.trim();
    if (t.isEmpty) return const [];
    final d = await erpDb();
    await ItemWarrantyCols.ensure(d);
    final id = int.tryParse(t.replaceAll('#', ''));
    final rows = await d.rawQuery('''
      SELECT i.id, i.invoice_number, i.invoice_date, i.customer_id, i.customer_name, i.total_amount,
             (SELECT COUNT(*) FROM invoice_items ii WHERE ii.invoice_id = i.id
                AND ii.warranty_end IS NOT NULL AND TRIM(COALESCE(ii.warranty_spec, '')) NOT IN ('', '0')) AS wl
      FROM invoices i
      LEFT JOIN customers c ON c.id = i.customer_id
      WHERE COALESCE(i.is_deleted, 0) = 0 AND COALESCE(i.status, '') != 'معلقة'
        AND (i.invoice_number LIKE ? OR i.customer_name LIKE ? OR COALESCE(c.phone, '') LIKE ? OR i.id = ?)
      ORDER BY i.invoice_date DESC, i.id DESC
      LIMIT 60''', ['${t.replaceAll('%', '')}%', _like(t), _like(t), id ?? -1]);
    return [
      for (final r in rows)
        DeskInvoice(
          r['id'] as int,
          '${r['invoice_number'] ?? ''}'.trim().isEmpty ? '#${r['id']}' : '${r['invoice_number']}'.trim(),
          DateTime.tryParse('${r['invoice_date'] ?? ''}'),
          r['customer_id'] as int?,
          '${r['customer_name'] ?? ''}',
          d0(r['total_amount']),
          (r['wl'] as num?)?.toInt() ?? 0,
        ),
    ];
  }

  /// مواد الفاتورة التي لها ضمان مثبَّت على سطرها.
  static Future<List<DeskLine>> lines(int invoiceId) async {
    final d = await erpDb();
    await ItemWarrantyCols.ensure(d);
    await _ensure(d);
    final rows = await d.rawQuery('''
      SELECT ii.product_name, ii.sale_type, ii.quantity_large_unit AS ql, ii.quantity_individual AS qi,
             COALESCE(NULLIF(ii.units_in_large_unit, 0), 1) AS u,
             ii.warranty_spec, ii.warranty_end, ii.warranty_terms, p.id AS pid
      FROM invoice_items ii
      JOIN products p ON (p.sync_uuid = ii.product_sync_uuid OR (ii.product_sync_uuid IS NULL AND p.name = ii.product_name))
      WHERE ii.invoice_id = ? AND ii.warranty_end IS NOT NULL
      ORDER BY ii.id''', [invoiceId]);
    if (rows.isEmpty) return const [];
    final returnable = await _returnable(d, invoiceId);
    final replaced = <int, double>{
      for (final r in await d.rawQuery('''
        SELECT product_id AS pid, SUM(COALESCE(desk_base_qty, qty)) AS q FROM warranty_claims
        WHERE invoice_id = ? AND desk_action = 'replace' GROUP BY product_id''', [invoiceId]))
        if (r['pid'] != null) r['pid'] as int: d0(r['q']),
    };
    final out = <DeskLine>[];
    for (final r in rows) {
      final spec = WarrantySpec.parse(r['warranty_spec']);
      final end = DateTime.tryParse('${r['warranty_end'] ?? ''}');
      if (spec == null || spec.value <= 0 || end == null) continue;
      final large = d0(r['ql']) > 0;
      final qty = large ? d0(r['ql']) : d0(r['qi']);
      final pid = r['pid'] as int;
      final t = '${r['warranty_terms'] ?? ''}'.trim();
      out.add(DeskLine(
        productId: pid,
        name: '${r['product_name'] ?? ''}',
        saleUnit: '${r['sale_type'] ?? ''}',
        soldQty: qty,
        soldBase: large ? qty * d0(r['u']) : qty,
        spec: spec,
        end: end,
        terms: t.isEmpty ? null : t,
        returnableBase: returnable[pid] ?? 0,
        replacedBase: replaced[pid] ?? 0,
      ));
    }
    return out;
  }

  /// نفس حساب «مرتجع المبيعات» (المبيع − المُرجع المرحّل).
  static Future<Map<int, double>> _returnable(DatabaseExecutor d, int invoiceId) async {
    final sold = await d.rawQuery('''
      SELECT p.id AS pid,
             SUM(CASE WHEN COALESCE(ii.quantity_large_unit, 0) > 0
                      THEN ii.quantity_large_unit * COALESCE(NULLIF(ii.units_in_large_unit, 0), 1)
                      ELSE COALESCE(ii.quantity_individual, 0) END) AS q
      FROM invoice_items ii
      JOIN products p ON (p.sync_uuid = ii.product_sync_uuid OR (ii.product_sync_uuid IS NULL AND p.name = ii.product_name))
      WHERE ii.invoice_id = ? GROUP BY p.id''', [invoiceId]);
    final out = <int, double>{for (final r in sold) r['pid'] as int: d0(r['q'])};
    try {
      for (final r in await d.rawQuery('''
          SELECT i.product_id AS pid, SUM(i.base_qty) AS q
          FROM sales_return_items i JOIN sales_returns r ON r.id = i.return_id
          WHERE r.original_invoice_id = ? AND r.status = 'posted' GROUP BY i.product_id''', [invoiceId])) {
        final pid = r['pid'] as int;
        out[pid] = (out[pid] ?? 0) - d0(r['q']);
      }
    } catch (_) {} // لا جداول مرتجع بعد
    return out;
  }

  /// حساب «مصروف الضمان والاستبدال» تحت «فروقات وتسويات» (أو المصاريف) — يُنشأ أول مرة.
  static Future<int> expenseAccount() async {
    final d = await erpDb();
    final k = await d.query('accounts', columns: ['id'], where: 'system_key = ?', whereArgs: [_accKey], limit: 1);
    if (k.isNotEmpty) return k.first['id'] as int;
    return d.transaction((t) async {
      var parent = await t.query('accounts', where: "code = '53' AND is_group = 1", limit: 1);
      if (parent.isEmpty) parent = await t.query('accounts', where: "code = '5' AND is_group = 1", limit: 1);
      if (parent.isEmpty) return Ledger.systemAccountId(t, 'inventory_writeoff');
      final p = parent.first;
      final pc = '${p['code']}';
      final used = {for (final r in await t.query('accounts', columns: ['code'])) '${r['code']}'};
      var n = 4;
      while (used.contains('$pc${n.toString().padLeft(2, '0')}')) {
        n++;
      }
      return t.insert('accounts', {
        'code': '$pc${n.toString().padLeft(2, '0')}',
        'name': 'مصروف الضمان والاستبدال',
        'parent_id': p['id'],
        'type': 'expense',
        'is_group': 0,
        'is_control': 0,
        'system_key': _accKey,
        'currency': p['currency'] ?? 'IQD',
        'created_at': DateTime.now().toIso8601String(),
      });
    });
  }

  static WarrantyClaim _claim(DeskInvoice inv, DeskLine l, double baseQty, String problem,
          {String? serial, String? accessories, String? notes}) =>
      WarrantyClaim(
        customerId: inv.customerId,
        customerName: inv.customerName.trim().isEmpty ? 'زبون' : inv.customerName,
        productId: l.productId,
        productName: l.name,
        qty: baseQty,
        serialNo: (serial ?? '').trim().isEmpty ? null : serial!.trim(),
        invoiceId: inv.id,
        saleDate: inv.date,
        withinWarranty: l.within,
        claimDate: DateTime.now(),
        problem: problem.trim(),
        accessories: (accessories ?? '').trim().isEmpty ? null : accessories!.trim(),
        notes: (notes ?? '').trim().isEmpty ? null : notes!.trim(),
      );

  static Future<void> _mark(int claimId, String action, int? ref, double base) async {
    final d = await erpDb();
    await _ensure(d);
    await d.update('warranty_claims', {'desk_action': action, 'desk_ref': ref, 'desk_base_qty': base},
        where: 'id = ?', whereArgs: [claimId]);
  }

  /// صيانة: طلب متابعة فقط.
  static Future<int> repair(DeskInvoice inv, DeskLine l, double baseQty, String problem,
      {String? serial, String? accessories, String? notes}) async {
    final id = await WarrantyService.save(_claim(inv, l, baseQty, problem, serial: serial, accessories: accessories, notes: notes));
    await _mark(id, 'repair', null, baseQty);
    return id;
  }

  /// استبدال: سند إخراج من المخزن الرئيسي + طلب ضمان للقطعة المعطوبة.
  /// إن فشل حفظ الطلب يُلغى السند فوراً (لا يبقى إخراج بلا طلب).
  static Future<({int claimId, int docId})> replace(DeskInvoice inv, DeskLine l, UnitOption unit, double qty, String problem,
      {String? serial, String? notes}) async {
    final base = qty * unit.factor;
    if (base <= 0) throw ErpException('الكمية يجب أن تكون أكبر من صفر');
    if (base > l.maxBase + 1e-6) {
      throw ErpException('الحد الأعلى للاستبدال ${fmtQty(l.maxBase)} — المبيع في الفاتورة بعد المرتجع وما استُبدل سابقاً');
    }
    final d = await erpDb();
    final p = await ErpStock.byId(d, l.productId);
    if (p == null) throw ErpException('المادة غير موجودة');
    final main = await OrgService().defaultWarehouseId(d);
    final acc = await expenseAccount();
    final docId = await StockDocsService().create(
      docType: 'out',
      date: DateTime.now(),
      warehouseId: main,
      counterAccountId: acc,
      reason: 'استبدال ضمان — فاتورة ${inv.number} — ${inv.customerName}',
      notes: 'العطل: ${problem.trim()}${(notes ?? '').trim().isEmpty ? '' : ' — ${notes!.trim()}'}',
      lines: [StockDocLine(productId: l.productId, name: l.name, baseQty: -base, unitCost: p.cost, note: '${fmtQty(qty)} ${unit.name}')],
    );
    try {
      final claimId = await WarrantyService.save(_claim(inv, l, base, problem,
          serial: serial,
          notes: [
            'استُبدلت للعميل: ${fmtQty(qty)} ${unit.name}${unit.factor == 1 ? '' : ' (${fmtQty(base)} ${p.baseUnitName})'}',
            'سند إخراج #$docId من المخزن الرئيسي',
            if ((notes ?? '').trim().isNotEmpty) notes!.trim(),
          ].join(' — ')));
      await _mark(claimId, 'replace', docId, base);
      await WarrantyService.addNote(claimId, 'سُلّمت قطعة بديلة للعميل (سند إخراج #$docId) — المعطوبة لدى المحل');
      return (claimId: claimId, docId: docId);
    } catch (e) {
      await StockDocsService().voidDoc(docId, reason: 'تعذّر حفظ طلب الضمان: $e').catchError((_) {});
      rethrow;
    }
  }

  /// بعد حفظ «مرتجع المبيعات»: شطب القطعة المعيبة (ما لم تكن سليمة) ثم طلب ضمان
  /// بحلّ «استرجاع المبلغ». الشطب بكلفة المرتجع نفسها ومن مخزنه ⇒ قيمة المخزون لا تتغير
  /// والكلفة تنتقل إلى «مصروف الضمان والاستبدال». يعيد (الطلب، سند الشطب أو null، خطأ الشطب).
  static Future<({int claimId, int? scrapDoc, String? scrapError})> recordRefund(
      DeskInvoice inv, DeskLine l, int returnId, String problem,
      {String? notes, bool restock = false}) async {
    final d = await erpDb();
    final head = await d.query('sales_returns', columns: ['return_no', 'warehouse_id'], where: 'id = ?', whereArgs: [returnId], limit: 1);
    final items = await d.query('sales_return_items',
        columns: ['base_qty', 'unit_cost', 'product_name'], where: 'return_id = ? AND product_id = ?', whereArgs: [returnId, l.productId]);
    var base = 0.0, cost = 0.0;
    for (final i in items) {
      base += d0(i['base_qty']);
      cost += d0(i['base_qty']) * d0(i['unit_cost']);
    }
    final no = head.isEmpty ? '$returnId' : '${head.first['return_no'] ?? returnId}';
    int? scrap;
    String? scrapErr;
    if (!restock && base > 1e-9) {
      try {
        final wh = (head.isEmpty ? null : head.first['warehouse_id'] as int?) ?? await OrgService().defaultWarehouseId(d);
        scrap = await StockDocsService().create(
          docType: 'out',
          date: DateTime.now(),
          warehouseId: wh,
          counterAccountId: await expenseAccount(),
          reason: 'شطب قطعة معيبة مرتجعة بالضمان — مرتجع مبيعات رقم $no — فاتورة ${inv.number}',
          notes: 'العطل: ${problem.trim()}',
          lines: [StockDocLine(productId: l.productId, name: l.name, baseQty: -base, unitCost: cost / base)],
          // 🧾 القطعة دخلت المخزن للتو بالمرتجع نفسه (بين يديك فعلاً) ⇒ شطبها لا يُرفض بسبب رصيد
          //    دفتري سالب من بيع سابق بالسالب (كان: «المطلوب إخراجه 1 والمتوفر 0»). صافي الأثر صفر.
          allowNegative: true,
        );
      } catch (e) {
        scrapErr = '$e';
      }
    }
    final id = await WarrantyService.save(_claim(inv, l, base > 0 ? base : 1, problem,
        notes: [
          'استرجاع المبلغ — مرتجع مبيعات رقم $no',
          if (restock) 'القطعة سليمة وأُعيدت للبيع',
          if (scrap != null) 'شُطبت المعيبة بسند إخراج #$scrap',
          if (scrapErr != null) 'لم تُشطب المعيبة ($scrapErr) — اشطبها بسند إخراج',
          if ((notes ?? '').trim().isNotEmpty) notes!.trim(),
        ].join(' — ')));
    await _mark(id, 'refund', returnId, base);
    await WarrantyService.setStatus(id, WStatus.ready, resolution: WResolution.refunded, note: 'مرتجع مبيعات رقم $no');
    // المعيبة لدى المحل ⇒ يبقى الطلب مفتوحاً لإرسالها للمورد؛ السليمة ⇒ يُغلق
    if (restock) await WarrantyService.setStatus(id, WStatus.delivered);
    return (claimId: id, scrapDoc: scrap, scrapError: scrapErr);
  }
}

/// أعمدة ضمان السطر قد لا توجد في قاعدة قديمة — نضيفها (فارغة) ليعمل البحث.
class ItemWarrantyCols {
  ItemWarrantyCols._();
  static Future<void> ensure(DatabaseExecutor d) async {
    final cols = {for (final r in await d.rawQuery('PRAGMA table_info(invoice_items)')) '${r['name']}'};
    for (final c in const ['warranty_spec', 'warranty_end', 'warranty_terms']) {
      if (!cols.contains(c)) await d.execute('ALTER TABLE invoice_items ADD COLUMN $c TEXT');
    }
  }
}

// ───────────────────────────── الشاشة ─────────────────────────────

class WarrantyDeskScreen extends StatefulWidget {
  const WarrantyDeskScreen({super.key});
  @override
  State<WarrantyDeskScreen> createState() => _WarrantyDeskScreenState();
}

class _WarrantyDeskScreenState extends State<WarrantyDeskScreen> {
  final _q = TextEditingController();
  List<DeskInvoice> _results = const [];
  DeskInvoice? _inv;
  List<DeskLine>? _lines;
  bool _searching = false;
  int _seq = 0;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _search(String v) async {
    final my = ++_seq;
    setState(() => _searching = true);
    try {
      final r = await WarrantyDesk.search(v);
      if (!mounted || my != _seq) return;
      setState(() {
        _results = r;
        _searching = false;
        _inv = null;
        _lines = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _searching = false);
      showError(context, e);
    }
  }

  Future<void> _openInvoice(DeskInvoice inv) async {
    setState(() {
      _inv = inv;
      _lines = null;
    });
    try {
      final l = await WarrantyDesk.lines(inv.id);
      if (mounted && _inv?.id == inv.id) setState(() => _lines = l);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _act(DeskLine l, String mode) async {
    final inv = _inv!;
    final p = await ErpStock.byId(await erpDb(), l.productId);
    if (p == null || !mounted) return;
    if (!l.within) {
      final ok = await confirmDialog(
        context,
        'الضمان منتهٍ',
        '«${l.name}»: انتهى الضمان في ${fmtDate(l.end)} (منذ ${-l.daysLeft} يوماً).\n'
            'المتابعة تسجّل الطلب «خارج الضمان».',
        ok: 'متابعة خارج الضمان',
        color: ErpColors.orange,
      );
      if (!ok || !mounted) return;
    }
    ({double perBase, double remaining})? info;
    if (mode == 'refund') info = await WarrantyDesk.refundInfo(inv, l, p);
    if (!mounted) return;
    final r = await showDialog<_DeskInput>(
      context: context,
      builder: (_) => _DeskActionDialog(
        mode: mode,
        line: l,
        product: p,
        perBase: info?.perBase ?? 0,
        // فاتورة عليها دين ⇒ الافتراضي تنزيله؛ مدفوعة ⇒ نقداً (كما في شاشة المرتجع)
        defaultRefund: inv.customerId != null && (info?.remaining ?? 0) > 0 ? 'credit' : 'cash',
        hasCustomer: inv.customerId != null,
      ),
    );
    if (r == null || !mounted) return;
    try {
      switch (mode) {
        case 'repair':
          final repairId = await WarrantyDesk.repair(inv, l, r.qty * r.unit.factor, r.problem,
              serial: r.serial, accessories: r.accessories, notes: r.notes);
          if (mounted) showOk(context, 'سُجّل طلب الصيانة (#$repairId)');
          await _maybePrint('warranty_receipt', 'طباعة إيصال الاستلام للعميل؟', () async {
            final c = await WarrantyService.get(repairId);
            if (c != null && mounted) await printWarrantyReceipt(context, c);
          });
        case 'replace':
          final base = r.qty * r.unit.factor;
          final ok = await confirmDialog(
            context,
            'تأكيد الاستبدال',
            'سيخرج ${fmtQty(r.qty)} ${r.unit.name}${r.unit.factor == 1 ? '' : ' (${fmtQty(base)} ${p.baseUnitName})'} من «${l.name}» '
                'من المخزن الرئيسي بسند إخراج على حساب «مصروف الضمان والاستبدال» '
                '(كلفة تقريبية ${fmtMoney(p.cost * base)}).\nوتبقى القطعة المعطوبة طلب ضمان مفتوحاً.',
            ok: 'استبدال',
          );
          if (!ok || !mounted) return;
          final res = await WarrantyDesk.replace(inv, l, r.unit, r.qty, r.problem, serial: r.serial, notes: r.notes);
          if (mounted) showOk(context, 'تم الاستبدال — سند إخراج #${res.docId}، طلب ضمان #${res.claimId}');
          await _maybePrint('warranty_receipt', 'طباعة إيصال الاستبدال للعميل؟', () async {
            final c = await WarrantyService.get(res.claimId);
            if (c != null && mounted) await printWarrantyReceipt(context, c);
          });
        case 'refund':
          final price = roundMoney((info?.perBase ?? 0) * r.unit.factor);
          final amount = roundMoney(price * r.qty);
          // الردّ من حسابه يتجاوز دينه ⇒ يصير دائناً: بتأكيد صريح فقط
          if (r.refundMode == 'credit' && inv.customerId != null) {
            final bal = await CustomerMoney.balance(await erpDb(), inv.customerId!);
            final after = roundMoney(bal - amount);
            if (after < 0) {
              if (!mounted) return;
              final ok = await confirmDialog(
                context,
                'سيصبح للعميل رصيد دائن',
                'دين «${inv.customerName}» الآن ${fmtMoney(bal)}، والمرتجع من حسابه ${fmtMoney(amount)}.\n'
                    'بعد الحفظ يصبح له عندكم ${fmtMoney(-after)}. إن أعدتم له المبلغ نقداً فاختر «نقداً من الصندوق».',
                ok: 'حفظ ويصبح دائناً',
                color: ErpColors.red,
              );
              if (!ok || !mounted) return;
            }
          }
          final svc = SalesReturnService();
          final blocked = await svc.returnBlockReason(inv.id);
          if (blocked != null) throw ErpException(blocked);
          final wh = await OrgService().defaultWarehouseId(await erpDb());
          if (!mounted) return;
          final saved = await svc.create(
            context,
            customerId: inv.customerId,
            customerName: inv.customerName.trim().isEmpty ? 'زبون' : inv.customerName,
            originalInvoiceId: inv.id,
            refundMode: r.refundMode,
            cashBoxId: r.refundMode == 'cash' ? r.boxId : null,
            warehouseId: wh,
            date: DateTime.now(),
            lines: [ReturnLine(product: p, unit: r.unit, quantity: r.qty, price: price)],
            notes: 'ضمان — العطل: ${r.problem}${r.notes.isEmpty ? '' : ' — ${r.notes}'}',
          );
          if (inv.customerId != null) WaAutoDocs.salesReturnSaved(saved);
          final refundRes = await WarrantyDesk.recordRefund(inv, l, saved, r.problem, notes: r.notes, restock: r.restock);
          if (!mounted) return;
          if (refundRes.scrapError != null) {
            showError(context, 'حُفظ المرتجع وطلب الضمان #${refundRes.claimId}، لكن لم تُشطب القطعة المعيبة: ${refundRes.scrapError}\nاشطبها من المخزون ← سند إخراج.');
          } else {
            showOk(context, refundRes.scrapDoc == null
                ? 'سُجّل الاسترجاع (#${refundRes.claimId}) — ${fmtMoney(amount)} ${r.refundMode == 'cash' ? 'نقداً' : 'من دين العميل'} — القطعة أُعيدت للبيع'
                : 'سُجّل الاسترجاع (#${refundRes.claimId}) — ${fmtMoney(amount)} ${r.refundMode == 'cash' ? 'نقداً' : 'من دين العميل'} — شُطبت المعيبة');
          }
          await _maybePrint('sales_return', 'طباعة سند المرتجع للعميل؟', () => printSalesReturn(context, saved));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
    if (mounted) await _openInvoice(inv);
  }

  /// 🖨️ حسب «الإعدادات ← السندات ← طباعة السندات بعد الحفظ» (أو إعداد هذا النوع في مصمم
  /// السندات): اسألني ⇒ سؤال، اطبع دائماً ⇒ يطبع، لا تُظهر ⇒ لا شيء.
  Future<void> _maybePrint(String kind, String question, Future<void> Function() doPrint) async {
    final mode = await VoucherPrint.modeFor(kind);
    if (!mounted || mode == 'never') return;
    final go = mode == 'always' || await confirmDialog(context, 'طباعة', question, ok: 'طباعة');
    if (go && mounted) await doPrint();
  }

  @override
  Widget build(BuildContext context) {
    return ErpPage(
      title: 'استلام قطعة',
      subtitle: 'ابحث بالعميل أو رقم الفاتورة أو الهاتف — تظهر المواد التي لها ضمان',
      icon: Icons.manage_search_rounded,
      actions: [
        TextButton.icon(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WarrantyClaimEditor())),
          icon: const Icon(Icons.edit_note_rounded, color: Colors.white),
          label: const Text('بلا فاتورة', style: TextStyle(color: Colors.white)),
        ),
      ],
      headerExtra: SearchBox(controller: _q, autofocus: true, hint: 'اسم العميل، رقم الفاتورة، أو الهاتف', onChanged: _search),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: _inv == null ? _resultsView() : _invoiceView(_inv!),
      ),
    );
  }

  Widget _resultsView() {
    if (_searching && _results.isEmpty) return const Center(child: CircularProgressIndicator());
    if (_q.text.trim().isEmpty) {
      return const _Empty(icon: Icons.search_rounded, text: 'اكتب اسم العميل أو رقم الفاتورة للبدء');
    }
    if (_results.isEmpty) return const _Empty(icon: Icons.receipt_long_outlined, text: 'لا فواتير مطابقة');
    return ListView.separated(
      key: const ValueKey('results'),
      padding: const EdgeInsets.all(12),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final r = _results[i];
        final has = r.warrantyLines > 0;
        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _openInvoice(r),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: has ? ErpColors.navy.withValues(alpha: 0.25) : ErpColors.border),
              ),
              child: Row(children: [
                CircleAvatar(
                  backgroundColor: (has ? ErpColors.navy : ErpColors.muted).withValues(alpha: 0.1),
                  child: Icon(Icons.receipt_long_rounded, color: has ? ErpColors.navy : ErpColors.muted),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('فاتورة ${r.number} — ${r.customerName.isEmpty ? 'زبون' : r.customerName}',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text('${r.date == null ? '' : fmtDate(r.date!)}  •  ${fmtMoney(r.total)}',
                        style: const TextStyle(color: ErpColors.muted, fontSize: 12.5)),
                  ]),
                ),
                _Pill(has ? '${r.warrantyLines} بضمان' : 'بلا ضمان', has ? ErpColors.green : ErpColors.muted),
              ]),
            ),
          ),
        );
      },
    );
  }

  Widget _invoiceView(DeskInvoice inv) {
    final lines = _lines;
    return ListView(
      key: ValueKey('inv${inv.id}'),
      padding: const EdgeInsets.all(12),
      children: [
        Row(children: [
          IconButton(
            tooltip: 'رجوع للنتائج',
            onPressed: () => setState(() {
              _inv = null;
              _lines = null;
            }),
            icon: const Icon(Icons.arrow_forward_rounded),
          ),
          Expanded(
            child: Text('فاتورة ${inv.number} — ${inv.customerName.isEmpty ? 'زبون' : inv.customerName}',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          ),
          if (inv.date != null) Text(fmtDate(inv.date!), style: const TextStyle(color: ErpColors.muted)),
        ]),
        const SizedBox(height: 8),
        if (lines == null)
          const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
        else if (lines.isEmpty)
          const _Empty(icon: Icons.shield_outlined, text: 'لا مواد بضمان في هذه الفاتورة')
        else
          for (final l in lines) Padding(padding: const EdgeInsets.only(bottom: 10), child: _lineCard(l)),
      ],
    );
  }

  Widget _lineCard(DeskLine l) {
    final ok = l.within;
    final c = ok ? ErpColors.green : ErpColors.red;
    final status = ok
        ? 'ساري حتى ${fmtDate(l.end)} — متبقٍ ${l.daysLeft} يوماً'
        : 'منتهٍ منذ ${-l.daysLeft} يوماً (${fmtDate(l.end)})';
    final none = l.maxBase <= 1e-6;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.withValues(alpha: 0.35)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(ok ? Icons.verified_user_rounded : Icons.gpp_bad_rounded, color: c),
          const SizedBox(width: 10),
          Expanded(child: Text(l.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5))),
          _Pill(ok ? 'داخل الضمان' : 'خارج الضمان', c),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 14, runSpacing: 4, children: [
          _meta(Icons.shopping_bag_outlined, 'المبيع: ${fmtQty(l.soldQty)} ${l.saleUnit}'),
          _meta(Icons.event_available_rounded, status, color: c),
          _meta(Icons.shield_outlined, 'الضمان: ${l.spec.label}'),
          if (l.returnableBase + 1e-6 < l.soldBase) _meta(Icons.undo_rounded, 'أُرجع منها ${fmtQty(l.soldBase - l.returnableBase)}'),
          if (l.replacedBase > 0) _meta(Icons.swap_horiz_rounded, 'استُبدل منها ${fmtQty(l.replacedBase)}'),
        ]),
        if (l.terms != null) ...[
          const SizedBox(height: 6),
          Text('الشروط: ${l.terms}', style: const TextStyle(color: ErpColors.muted, fontSize: 12.5)),
        ],
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: [
          OutlinedButton.icon(
            onPressed: () => _act(l, 'repair'),
            icon: const Icon(Icons.build_rounded, size: 18),
            label: const Text('صيانة'),
          ),
          FilledButton.icon(
            onPressed: none ? null : () => _act(l, 'replace'),
            style: FilledButton.styleFrom(backgroundColor: ErpColors.cyan),
            icon: const Icon(Icons.swap_horiz_rounded, size: 18),
            label: const Text('استبدال'),
          ),
          FilledButton.icon(
            onPressed: none ? null : () => _act(l, 'refund'),
            style: FilledButton.styleFrom(backgroundColor: ErpColors.red),
            icon: const Icon(Icons.undo_rounded, size: 18),
            label: const Text('استرجاع'),
          ),
        ]),
        if (none)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
                l.returnableBase <= 1e-6
                    ? '✔ أُرجعت كلها بمرتجع مبيعات — الاسترجاع مسجَّل وحساب العميل والمخزون مصحَّحان. '
                        'الفاتورة تبقى كما بيعت والمرتجع مستند مستقل مربوط بها.'
                    : 'لا كمية متبقية للاستبدال أو الاسترجاع في هذه الفاتورة',
                style: TextStyle(
                    color: l.returnableBase <= 1e-6 ? ErpColors.green : ErpColors.muted, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
      ]),
    );
  }

  Widget _meta(IconData i, String t, {Color? color}) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(i, size: 15, color: color ?? ErpColors.muted),
        const SizedBox(width: 4),
        Text(t, style: TextStyle(fontSize: 12.5, color: color ?? ErpColors.text, fontWeight: color == null ? null : FontWeight.w700)),
      ]);
}

// ───────────────────────────── نافذة العملية ─────────────────────────────

class _DeskInput {
  _DeskInput(this.unit, this.qty, this.problem, this.serial, this.accessories, this.notes, this.restock,
      {this.refundMode = 'cash', this.boxId});
  final UnitOption unit;

  /// الاسترجاع: cash | credit، والصندوق للنقد.
  final String refundMode;
  final int? boxId;
  final double qty;
  final String problem, serial, accessories, notes;

  /// الاسترجاع: القطعة سليمة وتعود للبيع (لا شطب).
  final bool restock;
}

class _DeskActionDialog extends StatefulWidget {
  const _DeskActionDialog({
    required this.mode,
    required this.line,
    required this.product,
    this.perBase = 0,
    this.defaultRefund = 'cash',
    this.hasCustomer = false,
  });
  final String mode; // repair | replace | refund
  final DeskLine line;
  final ProductLite product;
  final double perBase; // سعر الوحدة الأساسية في الفاتورة
  final String defaultRefund;
  final bool hasCustomer;
  @override
  State<_DeskActionDialog> createState() => _DeskActionDialogState();
}

class _DeskActionDialogState extends State<_DeskActionDialog> {
  late UnitOption _unit = widget.product.unitNamed(widget.line.saleUnit);
  final _qty = TextEditingController(text: '1');
  final _problem = TextEditingController();
  final _serial = TextEditingController();
  final _acc = TextEditingController();
  final _notes = TextEditingController();
  bool _restock = false;
  late String _refund = widget.defaultRefund;
  int? _boxId;
  String? _err;

  @override
  void dispose() {
    for (final c in [_qty, _problem, _serial, _acc, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  double get _q => parseMoney(_qty.text) ?? 0;
  double get _maxBase => widget.mode == 'repair' ? widget.line.soldBase : widget.line.maxBase;
  double get _maxInUnit => _unit.factor > 0 ? _maxBase / _unit.factor : _maxBase;

  (String, IconData, Color) get _look => switch (widget.mode) {
        'replace' => ('استبدال القطعة', Icons.swap_horiz_rounded, ErpColors.cyan),
        'refund' => ('استرجاع المبلغ', Icons.undo_rounded, ErpColors.red),
        _ => ('استلام للصيانة', Icons.build_rounded, ErpColors.navy),
      };

  void _submit() {
    final q = _q;
    String? e;
    if (q <= 0) {
      e = 'اكتب الكمية';
    } else if (q * _unit.factor > _maxBase + 1e-6) {
      e = 'الحد الأعلى ${fmtQty(_maxInUnit)} ${_unit.name}';
    } else if (_problem.text.trim().isEmpty) {
      e = 'اكتب العطل كما وصفه العميل';
    } else if (widget.mode == 'refund' && _refund == 'cash' && _boxId == null) {
      e = 'اختر الصندوق الذي يُردّ منه المبلغ';
    }
    if (e != null) {
      setState(() => _err = e);
      return;
    }
    Navigator.pop(context,
        _DeskInput(_unit, q, _problem.text.trim(), _serial.text.trim(), _acc.text.trim(), _notes.text.trim(), _restock,
            refundMode: _refund, boxId: _boxId));
  }

  @override
  Widget build(BuildContext context) {
    final (title, icon, color) = _look;
    final l = widget.line;
    final p = widget.product;
    final units = p.units;
    final base = _q * _unit.factor;
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540, maxHeight: 720),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
            decoration: BoxDecoration(gradient: LinearGradient(colors: [color, Color.lerp(color, Colors.black, 0.25)!])),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                  Text(l.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.88), fontSize: 13)),
                ]),
              ),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: Colors.white)),
            ]),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (!l.within)
                  _banner(Icons.warning_amber_rounded, ErpColors.orange, 'الضمان منتهٍ — يُسجَّل الطلب خارج الضمان'),
                const Text('الوحدة', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final u in units)
                    ChoiceChip(
                      selected: u.name == _unit.name,
                      showCheckmark: false,
                      label: Text(u.factor == 1 ? u.name : '${u.name} (${fmtQty(u.factor)} ${p.baseUnitName})'),
                      selectedColor: color.withValues(alpha: 0.14),
                      side: BorderSide(color: u.name == _unit.name ? color : ErpColors.border),
                      onSelected: (_) => setState(() => _unit = u),
                    ),
                ]),
                const SizedBox(height: 14),
                Row(children: [
                  IconButton.filledTonal(
                    onPressed: _q <= 1 ? null : () => setState(() => _qty.text = fmtQty(_q - 1)),
                    icon: const Icon(Icons.remove_rounded),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _qty,
                      textAlign: TextAlign.center,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() => _err = null),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                      decoration: _dec('الكمية بـ«${_unit.name}»'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: (_q + 1) * _unit.factor > _maxBase + 1e-6 ? null : () => setState(() => _qty.text = fmtQty(_q + 1)),
                    icon: const Icon(Icons.add_rounded),
                  ),
                ]),
                const SizedBox(height: 6),
                Text(
                  [
                    'الحد: ${fmtQty(_maxInUnit)} ${_unit.name}',
                    if (_unit.factor != 1 && base > 0) '= ${fmtQty(base)} ${p.baseUnitName}',
                  ].join('  ·  '),
                  style: const TextStyle(color: ErpColors.muted, fontSize: 12.5),
                ),
                const SizedBox(height: 14),
                TextField(controller: _problem, maxLines: 2, decoration: _dec('العطل كما وصفه العميل *')),
                const SizedBox(height: 10),
                if (widget.mode != 'refund') ...[
                  TextField(controller: _serial, textDirection: TextDirection.ltr, decoration: _dec('الرقم التسلسلي (اختياري)')),
                  const SizedBox(height: 10),
                ],
                if (widget.mode == 'repair') ...[
                  TextField(controller: _acc, decoration: _dec('الملحقات المستلمة (شاحن، علبة…)')),
                  const SizedBox(height: 10),
                ],
                TextField(controller: _notes, maxLines: 2, decoration: _dec('ملاحظة')),
                if (widget.mode == 'refund') ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: ErpColors.red.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(14)),
                    child: Row(children: [
                      const Icon(Icons.payments_rounded, color: ErpColors.red),
                      const SizedBox(width: 10),
                      const Expanded(child: Text('المبلغ المردود', style: TextStyle(fontWeight: FontWeight.w700))),
                      Text(fmtMoney(roundMoney(roundMoney(widget.perBase * _unit.factor) * _q)),
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: ErpColors.red)),
                    ]),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: _refundChoice('cash', 'نقداً من الصندوق', Icons.point_of_sale_rounded, true)),
                    const SizedBox(width: 8),
                    Expanded(child: _refundChoice('credit', 'من دين العميل', Icons.account_balance_wallet_rounded, widget.hasCustomer)),
                  ]),
                  if (_refund == 'cash') ...[
                    const SizedBox(height: 10),
                    CashBoxDropdown(value: _boxId, width: double.infinity, onChanged: (b) => setState(() => _boxId = b?.id)),
                  ],
                ],
                if (widget.mode == 'refund')
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _restock,
                    onChanged: (v) => setState(() => _restock = v),
                    title: const Text('القطعة سليمة وتعود للبيع', style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(_restock
                        ? 'تعود إلى المخزون القابل للبيع بكلفتها'
                        : 'معيبة: تُشطب فوراً على «مصروف الضمان والاستبدال» ولا تدخل الرصيد'),
                  ),
                const SizedBox(height: 12),
                _banner(
                  Icons.info_outline_rounded,
                  ErpColors.blue,
                  switch (widget.mode) {
                    'replace' => 'تخرج القطعة البديلة من المخزن الرئيسي بسند إخراج على «مصروف الضمان والاستبدال»، '
                        'وتبقى المعطوبة طلب ضمان مفتوحاً يمكن إرساله للمورد.',
                    'refund' => 'يُحفظ «مرتجع مبيعات» على هذه الفاتورة مباشرة (يظهر في تقارير المرتجعات)، ويُطبع سنده حسب الإعداد. '
                        'وتُشطب القطعة المعيبة بكلفتها، فلا تُحسب في الرصيد القابل للبيع.',
                    _ => 'طلب متابعة فقط — لا يتغير مخزون ولا مال.',
                  },
                ),
                if (_err != null) ...[
                  const SizedBox(height: 10),
                  Text(_err!, style: const TextStyle(color: ErpColors.red, fontWeight: FontWeight.w700)),
                ],
              ]),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: ErpColors.border))),
            child: Row(children: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
              const Spacer(),
              FilledButton.icon(
                onPressed: _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: color,
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: Icon(icon),
                label: Text(widget.mode == 'refund' ? 'حفظ الاسترجاع' : title,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _refundChoice(String v, String label, IconData icon, bool enabled) {
    final on = _refund == v;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: enabled ? () => setState(() => _refund = v) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: on ? ErpColors.red.withValues(alpha: 0.08) : ErpColors.bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: on ? ErpColors.red : ErpColors.border, width: on ? 1.6 : 1),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 18, color: on ? ErpColors.red : ErpColors.muted),
            const SizedBox(width: 6),
            Flexible(
              child: Text(enabled ? label : '$label (لا عميل مسجّل)',
                  textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800, color: on ? ErpColors.red : ErpColors.text)),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _banner(IconData i, Color c, String t) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(14)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(i, color: c, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(t, style: const TextStyle(fontSize: 12.5, height: 1.5))),
        ]),
      );

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        isDense: true,
        filled: true,
        fillColor: ErpColors.bg,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: ErpColors.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: ErpColors.border)),
      );
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, this.color);
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12)),
      );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 56, color: ErpColors.muted.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: ErpColors.muted, fontSize: 15)),
        ]),
      );
}
