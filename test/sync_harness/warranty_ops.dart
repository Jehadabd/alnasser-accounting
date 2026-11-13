// test/sync_harness/warranty_ops.dart
//
// 🛡️ ضمان المادة على سطر الفاتورة — سيناريو كامل على جهاز واحد بكود التطبيق الحقيقي:
//   • حساب النهاية (شاملة، ونهاية الشهر، والكبيسة، والأيام) وترميز المدة واسمها.
//   • مدة الضمان تُحفظ على المادة عبر نموذج Product كما تحفظها بطاقة المادة.
//   • الفاتورة الجديدة (InvoiceController) تُثبِّت الضمان على سطرها.
//   • تغيير مدة ضمان المادة ثم تعديل الفاتورة كما تفعل الشاشة: السطر القديم يبقى
//     بضمانه، والسطر المضاف يأخذ المدة الجديدة؛ وكذلك سطور بلا معرّف (بالمادة).
//   • مادة «بلا ضمان» ⇒ لا ضمان على السطر.
//   • المعلّقة تُثبَّت حين تُحفظ لا قبلها، والكاشير (createPosInvoice) يُثبِّت.
//   • «من تاريخ الشراء»: من آخر فاتورة شراء مؤكدة قبل البيع، ومن البيع إن لم توجد.
//   • أعمدة الطباعة: تُضاف للتصاميم المحفوظة قبلها، ونصوص خلاياها.
// يعيد {'fails','notes', 'invA', 'expA', 'spec'} — invA فاتورة بسطرين يُتحقق منها على الجهاز الآخر.
// ignore_for_file: avoid_print

import 'package:alnaser/controllers/invoice_controller.dart';
import 'package:alnaser/erp/warranty/item_warranty.dart';
import 'package:alnaser/erp/warranty/warranty_service.dart';
import 'package:alnaser/models/invoice.dart';
import 'package:alnaser/models/invoice_design_settings.dart';
import 'package:alnaser/models/invoice_input_data.dart';
import 'package:alnaser/models/invoice_item.dart';
import 'package:alnaser/models/product.dart';
import 'package:alnaser/models/purchase_invoice.dart';
import 'package:alnaser/models/purchase_invoice_item.dart';
import 'package:alnaser/models/supplier.dart';
import 'package:alnaser/services/database_service.dart';
import 'package:alnaser/services/held_invoices.dart';
import 'package:alnaser/services/purchase_service.dart';
import 'package:sqflite/sqflite.dart';

import 'scenario_ops.dart' show scenOp;

Future<Map<String, Object?>> warrantyScenario(Database db, String prod) async {
  final fails = <String>[];
  final notes = <String>[];
  void eq(String label, Object? actual, Object? expected) {
    if (actual != expected) fails.add('$label: المتوقع «$expected» والفعلي «$actual»');
  }

  String iso(DateTime d) => ItemWarranty.iso(d);
  final now = DateTime.now();
  final t0 = DateTime(now.year, now.month, now.day);
  const y1 = WarrantySpec(1, WarrantyUnit.year);
  const m6 = WarrantySpec(6, WarrantyUnit.month);
  const d10 = WarrantySpec(10, WarrantyUnit.day);

  // ── 1) الحساب والترميز (بلا قاعدة) ──
  eq('سنة من 2026/11/13', iso(y1.endFrom(DateTime(2026, 11, 13))), '2027-11-12');
  eq('شهر من 2026/03/15', iso(const WarrantySpec(1, WarrantyUnit.month).endFrom(DateTime(2026, 3, 15))), '2026-04-14');
  eq('شهر من 2026/01/31 (لا 31 في شباط)', iso(const WarrantySpec(1, WarrantyUnit.month).endFrom(DateTime(2026, 1, 31))),
      '2026-02-28');
  eq('شهر من 2028/01/31 (كبيسة)', iso(const WarrantySpec(1, WarrantyUnit.month).endFrom(DateTime(2028, 1, 31))),
      '2028-02-29');
  eq('سنة من 2024/02/29', iso(y1.endFrom(DateTime(2024, 2, 29))), '2025-02-28');
  eq('18 شهراً من 2026/11/13', iso(const WarrantySpec(18, WarrantyUnit.month).endFrom(DateTime(2026, 11, 13))),
      '2028-05-12');
  eq('10 أيام من 2026/11/13', iso(d10.endFrom(DateTime(2026, 11, 13))), '2026-11-22');
  eq('يوم واحد = يوم البيع نفسه', iso(const WarrantySpec(1, WarrantyUnit.day).endFrom(DateTime(2026, 11, 13))),
      '2026-11-13');
  eq('ترميز «6m:p»', WarrantySpec.parse('6m:p')?.encode(), '6m:p');
  eq('أساس «6m:p»', WarrantySpec.parse('6m:p')?.basis, WarrantyBasis.purchase);
  eq('اسم 1y', WarrantySpec.parse('1y')?.label, 'سنة');
  eq('اسم 2y', WarrantySpec.parse('2y')?.label, 'سنتان');
  eq('اسم 3m', WarrantySpec.parse('3m')?.label, '3 أشهر');
  eq('اسم 18m', WarrantySpec.parse('18m')?.label, '18 شهراً');
  eq('نص غير مفهوم', WarrantySpec.parse('سنة'), null);
  eq('«0» = بلا ضمان صراحةً', WarrantySpec.parse('0')?.isNone, true);
  // خلل قديم في وحدة الصيانة: 31 كانون الثاني + شهر كان 3 آذار
  eq('نهاية ضمان طلب الصيانة (31/1 + شهر)', iso(WarrantyService.endOf(DateTime(2026, 1, 31), 1)!), '2026-02-28');

  // ── 2) أعمدة الطباعة ──
  final old = InvoiceDesignSettings.fromJson({
    'columns': [
      for (final c in InvoiceColumnConfig.defaultColumns().where((c) => !InvoiceColumnConfig.isWarranty(c.id)))
        c.toJson()
    ],
  });
  final ends = old.columns.where((c) => c.id == 'warrantyEnd').toList();
  eq('تصميم محفوظ قبل الضمان: عمود «الضمان حتى» أُضيف', ends.length, 1);
  if (ends.isNotEmpty) {
    eq('«الضمان حتى» ظاهر', ends.first.visible, true);
    eq('«الضمان حتى» في آخر الجدول', old.visibleColumns.last.id, 'warrantyEnd');
  }
  eq('خلية «الضمان حتى»', ItemWarranty.cellText('warrantyEnd', spec: '1y', start: '2026-11-13', end: '2027-11-12'),
      '2027/11/12');
  eq('خلية «مدة الضمان»', ItemWarranty.cellText('warrantyPeriod', spec: '1y', start: '2026-11-13', end: '2027-11-12'),
      'سنة');
  eq('خلية سطر بلا ضمان', ItemWarranty.cellText('warrantyEnd'), '');
  eq('عمود غير الضمان', ItemWarranty.cellText('amount'), null);

  // ── أدوات ──
  final pr = await db.query('products', columns: ['id', 'name'], where: 'sync_uuid = ?', whereArgs: [prod], limit: 1);
  if (pr.isEmpty) return {'fails': ['لا مادة بالمعرّف $prod'], 'notes': notes};
  final pid = pr.first['id'] as int;
  final pname = pr.first['name'] as String;

  Future<void> setSpec(String s) async {
    final cur = (await DatabaseService().getProductById(pid))!;
    // كما تحفظها بطاقة المادة: Product.fromMap({...الحالي, ...المتغيّر})
    await DatabaseService().updateProduct(Product.fromMap(
        {...cur.toMap(), 'warranty_spec': s, 'last_modified_at': DateTime.now().toIso8601String()}));
    eq('مدة ضمان المادة بعد حفظها', (await DatabaseService().getProductById(pid))!.warrantySpec, s);
  }

  Future<int> invId(String uuid) async =>
      (await db.query('invoices', columns: ['id'], where: 'invoice_uuid = ?', whereArgs: [uuid], limit: 1)).first['id']
          as int;

  Future<List<Map<String, Object?>>> lines(int id) => db.query('invoice_items',
      columns: ['warranty_spec', 'warranty_start', 'warranty_end'], where: 'invoice_id = ?', whereArgs: [id], orderBy: 'id');

  void lineIs(String label, Map<String, Object?> l, WarrantySpec? s, DateTime start) {
    eq('$label: المدة', l['warranty_spec'], s?.encode());
    eq('$label: البداية', l['warranty_start'], s == null ? null : iso(start));
    eq('$label: النهاية', l['warranty_end'], s == null ? null : iso(s.endFrom(start)));
  }

  Future<String> save(String name, double qty, {String? inv}) async {
    final res = (await scenOp('invSave', {
      'inv': inv,
      'name': name,
      'items': [
        {'prodId': pid, 'qty': qty, 'price': 1000}
      ],
      'discount': 0,
      'fee': 0,
      'paid': qty * 1000,
      'ptype': 'نقد',
    })) as Map;
    if (res['ok'] != true) throw StateError('حفظ الفاتورة رُفض: ${res['stage']} ${res['err']}');
    return res['uuid'] as String;
  }

  InvoiceItem newLine(double qty) => InvoiceItem(
        invoiceId: 0,
        productId: pid,
        productName: pname,
        unit: 'piece',
        unitPrice: 1000,
        costPrice: 0.5,
        quantityIndividual: qty,
        appliedPrice: 1000,
        itemTotal: qty * 1000,
        saleType: 'قطعة',
      );

  // ── 3) فاتورة جديدة من شاشة الفاتورة: ضمان سنة ──
  await setSpec('1y');
  final invA = await save('زبون الضمان', 1);
  final idA = await invId(invA);
  var ls = await lines(idA);
  eq('الفاتورة الجديدة: عدد السطور', ls.length, 1);
  if (ls.length == 1) lineIs('الفاتورة الجديدة', ls[0], y1, t0);

  // ── 4) المدة صارت 6 أشهر؛ التعديل كما تفعله الشاشة (السطور المحمّلة + سطر جديد) ──
  await setSpec('6m');
  final head = Invoice.fromMap((await db.query('invoices', where: 'id = ?', whereArgs: [idA], limit: 1)).first);
  final loaded = await DatabaseService().getInvoiceItems(idA);
  final items = [...loaded, newLine(2)];
  final total = items.fold<double>(0, (s, i) => s + i.itemTotal);
  final res = await InvoiceController(db: DatabaseService()).saveInvoice(InvoiceInputData(
    invoiceToManage: head,
    customerName: head.customerName,
    customerPhone: '',
    customerAddress: '',
    paidAmount: total,
    loadingFee: 0,
    discount: 0,
    paymentType: 'نقد',
    selectedDate: head.invoiceDate,
    invoiceItems: items,
  ));
  if (!res.success) fails.add('تعديل الفاتورة رُفض: ${res.errorMessage}');
  ls = await lines(idA);
  eq('بعد التعديل: عدد السطور', ls.length, 2);
  if (ls.length == 2) {
    lineIs('السطر القديم بعد تغيير مدة المادة', ls[0], y1, t0);
    lineIs('السطر المضاف', ls[1], m6, t0);
  }

  // سطور بلا معرّفها القديم (تُبنى من جديد): تُطابق بالمادة فيبقى الضمان القديم
  final invB = await save('زبون بلا معرّفات', 1);
  await setSpec('10d');
  await save('زبون بلا معرّفات', 3, inv: invB);
  ls = await lines(await invId(invB));
  if (ls.length == 1) lineIs('سطر أُعيد بناؤه بلا معرّفه', ls[0], m6, t0);

  // ── 5) مادة «بلا ضمان» ──
  await setSpec('0');
  ls = await lines(await invId(await save('زبون بلا ضمان', 1)));
  if (ls.length == 1) lineIs('مادة بلا ضمان', ls[0], null, t0);

  // ── 6) المعلّقة: لا ضمان قبل حفظها، وتُثبَّت حين تُحفظ ──
  await setSpec('10d');
  final held = await HeldInvoices.hold(
    existing: null,
    items: [newLine(1)],
    customerName: 'زبون المعلّقة',
    invoiceDate: now,
    paymentType: 'نقد',
    discount: 0,
    loadingFee: 0,
    paid: 1000,
  );
  ls = await lines(held.id!);
  if (ls.length == 1) eq('المعلّقة قبل حفظها بلا ضمان', ls[0]['warranty_end'], null);
  await save('زبون المعلّقة', 1, inv: held.invoiceUuid);
  ls = await lines(held.id!);
  if (ls.length == 1) lineIs('المعلّقة بعد حفظها', ls[0], d10, t0);

  // ── 7) الكاشير ──
  await setSpec('1y');
  Future<int> pos() => DatabaseService().createPosInvoice(
        items: [
          {
            'product_id': pid,
            'product_name': pname,
            'quantity': 1.0,
            'price': 1000.0,
            'unit': 'قطعة',
            'cost_price': 0.5,
            'sale_type': 'قطعة',
            'units_in_large_unit': 1.0,
          }
        ],
        totalAmount: 1000,
        paymentType: 'نقد',
        discount: 0,
        paidAmount: 1000,
      );
  ls = await lines(await pos());
  if (ls.length == 1) lineIs('فاتورة الكاشير', ls[0], y1, t0);

  // ── 8) من تاريخ الشراء ──
  await setSpec('1y:p');
  const y1p = WarrantySpec(1, WarrantyUnit.year, basis: WarrantyBasis.purchase);
  final ps = PurchaseService();
  final sid =
      await ps.addSupplier(Supplier(name: 'مورد الضمان ${now.microsecondsSinceEpoch}', createdAt: now, updatedAt: now));
  final bought = t0.subtract(const Duration(days: 10));
  await ps.savePurchaseInvoice(
    PurchaseInvoice(invoiceNumber: 'W-1', supplierId: sid, totalAmount: 5000, status: 'confirmed', date: bought),
    [PurchaseInvoiceItem(productId: pid, unitName: 'قطعة', quantity: 5, unitPrice: 1000, totalPrice: 5000)],
  );
  ls = await lines(await pos());
  if (ls.length == 1) lineIs('من تاريخ الشراء (قبل 10 أيام)', ls[0], y1p, DateTime(bought.year, bought.month, bought.day));
  // بيع قبل أي شراء ⇒ من تاريخ البيع
  final early = t0.subtract(const Duration(days: 40));
  final probe = <String, dynamic>{'product_id': pid, 'product_name': pname, 'unique_id': 'probe'};
  await ItemWarranty.stampLines(db, [probe], early);
  lineIs('من تاريخ الشراء ولا شراء قبل البيع', probe, y1p, early);

  notes.add('سنة من اليوم حتى ${ItemWarranty.show(iso(y1.endFrom(t0)))}؛ التعديل بعد تغيير المدة أبقى السطر القديم '
      'على سنة والمضاف 6 أشهر؛ المعلّقة 10 أيام عند حفظها؛ الكاشير سنة؛ من الشراء قبل 10 أيام');
  return {
    'fails': fails,
    'notes': notes,
    'invA': invA,
    'expA': [
      {'spec': y1.encode(), 'end': iso(y1.endFrom(t0))},
      {'spec': m6.encode(), 'end': iso(m6.endFrom(t0))},
    ],
    'spec': '1y:p',
  };
}
