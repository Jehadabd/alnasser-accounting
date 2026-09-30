// lib/services/demo_seeder.dart
//
// 🧪 مولّد بيانات الوضع التجريبي: سنة كاملة لمحل كهربائيات وصحيات في الموصل.
// يعمل فقط على القاعدة التجريبية (DemoMode.isOn)، ويستعمل دوال البرنامج نفسها
// (حفظ القائمة، فاتورة الشراء، الوصل، دفعة المورد، سند المصروف) حتى تكون
// الأرصدة والمخزون والقيود متطابقة كأن البيانات أُدخلت يدوياً.

import 'dart:math';

import '../accounting/vouchers_service.dart';
import '../controllers/invoice_controller.dart';
import '../erp/debts/customer_money.dart';
import '../erp/debts/receipts_service.dart';
import '../models/customer.dart';
import '../models/invoice_input_data.dart';
import '../models/invoice_item.dart';
import '../models/product.dart';
import '../models/purchase_invoice.dart';
import '../models/purchase_invoice_item.dart';
import '../models/supplier.dart';
import '../models/transaction.dart';
import '../providers/app_provider.dart';
import 'database_service.dart';
import 'demo_mode.dart';
import 'purchase_service.dart';

class DemoSeeder {
  DemoSeeder._();

  /// القاعدة التجريبية فارغة؟ (لا عملاء ولا مواد)
  static Future<bool> needsSeed() async {
    if (!DemoMode.isOn) return false;
    final db = await DatabaseService().database;
    final c = await db.rawQuery('SELECT (SELECT COUNT(*) FROM customers) + (SELECT COUNT(*) FROM products) AS n');
    return ((c.first['n'] as num?) ?? 0) == 0;
  }

  static const _areas = [
    'الجدعة', 'الزهور', 'المثنى', 'الحدباء', 'النبي يونس', 'الموصل الجديدة', 'حي العربي', 'الفيصلية',
    'القاهرة', 'البكر', 'الكرامة', 'وادي حجر', 'باب الطوب', 'الرفاعي',
  ];
  static const _first = [
    'أحمد', 'محمد', 'علي', 'عمر', 'خالد', 'يوسف', 'إبراهيم', 'حسين', 'مصطفى', 'سعد', 'زياد', 'فراس',
    'مهند', 'رائد', 'أنس', 'بلال', 'حمزة', 'ياسر', 'وليد', 'نزار', 'قصي', 'عادل', 'صالح', 'ماهر',
  ];
  static const _last = [
    'الجبوري', 'الطائي', 'العبيدي', 'الحمداني', 'السبعاوي', 'النعيمي', 'الشمري', 'اللهيبي',
    'الدليمي', 'البدراني', 'الصفار', 'الحيالي', 'العزاوي', 'الراوي', 'الموصلي', 'الجوادي',
  ];
  static const _suppliers = [
    'شركة النور للكهربائيات', 'مكتب الفرات للصحيات', 'شركة بغداد للأسلاك', 'مجموعة أربيل التجارية',
    'شركة دهوك للأنابيب', 'مكتب الرافدين للإنارة', 'شركة الموصل للعدد اليدوية', 'مخازن الحدباء',
    'شركة زاخو للاستيراد', 'مكتب الشمال للدهانات',
  ];

  // [القسم، الاسم، الكلفة بالدينار، حجم الكرتون (0 = بلا كرتون)]
  static const _catalog = <List<Object>>[
    ['أسلاك وكابلات', 'سلك 2.5 ملم لفة 100 م', 42000, 0],
    ['أسلاك وكابلات', 'سلك 4 ملم لفة 100 م', 68000, 0],
    ['أسلاك وكابلات', 'سلك 1.5 ملم لفة 100 م', 29000, 0],
    ['أسلاك وكابلات', 'كيبل 3×2.5 متر', 1750, 0],
    ['أسلاك وكابلات', 'كيبل 4×6 متر', 5200, 0],
    ['أسلاك وكابلات', 'سلك سماعة متر', 250, 0],
    ['مفاتيح وسويجات', 'سويج مفرد أبيض', 1250, 50],
    ['مفاتيح وسويجات', 'سويج مزدوج أبيض', 1750, 50],
    ['مفاتيح وسويجات', 'بلك 13 أمبير', 1500, 50],
    ['مفاتيح وسويجات', 'بلك تلفون', 1250, 50],
    ['مفاتيح وسويجات', 'سويج جرس', 1000, 50],
    ['مفاتيح وسويجات', 'بلك مزدوج 13 أمبير', 2500, 40],
    ['قواطع ولوحات', 'قاطع 16 أمبير', 3500, 24],
    ['قواطع ولوحات', 'قاطع 32 أمبير', 4500, 24],
    ['قواطع ولوحات', 'قاطع 63 أمبير ثلاثي', 18000, 12],
    ['قواطع ولوحات', 'لوحة توزيع 12 خط', 22000, 0],
    ['قواطع ولوحات', 'لوحة توزيع 24 خط', 38000, 0],
    ['قواطع ولوحات', 'قاطع تسريب أرضي', 16000, 12],
    ['إنارة', 'لمبة LED 12 واط', 1250, 100],
    ['إنارة', 'لمبة LED 20 واط', 2000, 100],
    ['إنارة', 'سبوت لايت سقفي', 2750, 50],
    ['إنارة', 'بروجكتر 50 واط', 11000, 20],
    ['إنارة', 'بروجكتر 100 واط', 19000, 10],
    ['إنارة', 'شريط LED متر', 1500, 0],
    ['إنارة', 'نيون 120 سم', 5500, 25],
    ['إنارة', 'ثريا صالة', 65000, 0],
    ['صحيات', 'حنفية مغسلة', 12000, 0],
    ['صحيات', 'خلاط دوش', 27000, 0],
    ['صحيات', 'سيفون أرضي', 3000, 40],
    ['صحيات', 'شطافة كاملة', 8000, 30],
    ['صحيات', 'مغسلة سيراميك', 45000, 0],
    ['صحيات', 'كرسي إفرنجي', 120000, 0],
    ['صحيات', 'سخان ماء 50 لتر', 135000, 0],
    ['صحيات', 'صمام نصف انج', 2500, 50],
    ['صحيات', 'صمام انج', 4500, 40],
    ['أنابيب ووصلات', 'أنبوب PPR نصف انج 4 م', 4000, 0],
    ['أنابيب ووصلات', 'أنبوب PPR انج 4 م', 7500, 0],
    ['أنابيب ووصلات', 'أنبوب PVC 4 انج', 9000, 0],
    ['أنابيب ووصلات', 'كوع PPR نصف انج', 250, 200],
    ['أنابيب ووصلات', 'تي PPR نصف انج', 300, 200],
    ['أنابيب ووصلات', 'رابط PPR انج', 400, 150],
    ['أنابيب ووصلات', 'خرطوم مرن 40 سم', 1500, 100],
    ['عدد يدوية', 'مفك عادي', 1500, 24],
    ['عدد يدوية', 'مفك فاحص', 1000, 24],
    ['عدد يدوية', 'كماشة 8 انج', 6000, 12],
    ['عدد يدوية', 'قطاعة أسلاك', 5500, 12],
    ['عدد يدوية', 'شريط لاصق عازل', 500, 100],
    ['عدد يدوية', 'دريل كهربائي', 45000, 0],
    ['عدد يدوية', 'فيتة 5 متر', 3000, 24],
    ['براغي ومثبتات', 'رول بلاك 8 ملم كيس', 1500, 50],
    ['براغي ومثبتات', 'براغي خشب كيس', 2000, 50],
    ['براغي ومثبتات', 'كلبسات أسلاك كيس', 1500, 50],
    ['براغي ومثبتات', 'سليكون شفاف', 2500, 24],
    ['مراوح ومبردات', 'مروحة سقفية', 42000, 0],
    ['مراوح ومبردات', 'مروحة جدارية', 28000, 0],
    ['مراوح ومبردات', 'ساحبة هواء حمام', 14000, 10],
    ['مراوح ومبردات', 'مضخة مبردة', 8000, 20],
    ['مراوح ومبردات', 'ماطور مبردة', 32000, 0],
    ['دهانات', 'صبغ أبيض 4 لتر', 18000, 4],
    ['دهانات', 'صبغ زيتي 1 لتر', 9000, 12],
    ['دهانات', 'فرشاة صبغ 3 انج', 1500, 24],
    ['دهانات', 'رولة صبغ', 3500, 12],
    ['أقفال وإكسسوارات', 'قفل باب داخلي', 9000, 12],
    ['أقفال وإكسسوارات', 'قفل باب خارجي', 22000, 6],
    ['أقفال وإكسسوارات', 'مقبض باب', 6000, 12],
    ['أقفال وإكسسوارات', 'جرس لاسلكي', 11000, 10],
  ];

  static double _round250(double v) => (v / 250).round() * 250.0;

  /// يولّد سنة بيانات. [onProgress] يستقبل (نسبة 0..1، رسالة).
  static Future<void> run(void Function(double progress, String message) onProgress) async {
    if (!DemoMode.isOn) throw StateError('المولّد يعمل على القاعدة التجريبية فقط');
    final rnd = Random(2025);
    final dbs = DatabaseService();
    final db = await dbs.database;
    final provider = AppProvider();
    final purchases = PurchaseService();
    final today = DateTime.now();
    final start = DateTime(today.year - 1, today.month, today.day);

    // ── الأقسام والمواد ──
    onProgress(0.01, 'إنشاء الأقسام والمواد...');
    final catIds = <String, int>{};
    for (final row in _catalog) {
      final cat = row[0] as String;
      catIds[cat] ??= await db.insert('categories', {'name': cat});
    }
    final products = <Map<String, Object>>[];
    for (var i = 0; i < _catalog.length; i++) {
      final row = _catalog[i];
      final cost = (row[2] as int).toDouble();
      final carton = row[3] as int;
      final retail = _round250(cost * (1.25 + rnd.nextDouble() * 0.15));
      final wholesale = _round250(cost * (1.12 + rnd.nextDouble() * 0.06));
      final isMeter = (row[1] as String).contains('متر') && !(row[1] as String).contains('لفة');
      final unit = isMeter ? 'meter' : 'piece';
      final stock = isMeter ? 400.0 + rnd.nextInt(600) : (carton > 0 ? carton * (3 + rnd.nextInt(6)) : 10 + rnd.nextInt(30)).toDouble();
      final id = await dbs.insertProduct(Product(
        name: row[1] as String,
        unit: unit,
        unitPrice: retail,
        costPrice: cost,
        price1: retail,
        price2: wholesale,
        price3: _round250(retail * 1.05),
        categoryId: catIds[row[0]],
        stockQuantity: stock,
        alertQuantity: carton > 0 ? carton.toDouble() : 3,
        unitHierarchy: carton > 0 ? '[{"unit_name":"كرتون","quantity":$carton}]' : null,
        barcode: '62${(100000 + i * 137).toString().padLeft(8, '0')}',
        createdAt: start,
        lastModifiedAt: start,
      ));
      products.add({'id': id, 'name': row[1] as String, 'cost': cost, 'retail': retail, 'wholesale': wholesale,
        'carton': carton, 'unit': unit});
    }

    // ── العملاء ──
    onProgress(0.04, 'إنشاء العملاء...');
    final customers = <Map<String, Object>>[];
    final usedNames = <String>{};
    while (customers.length < 70) {
      final name = '${_first[rnd.nextInt(_first.length)]} ${_last[rnd.nextInt(_last.length)]}';
      if (!usedNames.add(name)) continue;
      final phone = '07${[7, 8, 5][rnd.nextInt(3)]}${(10000000 + rnd.nextInt(89999999))}';
      await provider.addCustomer(Customer(
        name: name,
        phone: phone,
        address: 'الموصل - ${_areas[rnd.nextInt(_areas.length)]}',
        createdAt: start,
        lastModifiedAt: start,
      ));
      final r = await db.query('customers', columns: ['id'], where: 'name = ?', whereArgs: [name], limit: 1);
      customers.add({'id': r.first['id'] as int, 'name': name, 'phone': phone, 'wholesale': rnd.nextDouble() < 0.3});
    }

    // ── الموردون ──
    final suppliers = <int>[];
    for (final s in _suppliers) {
      suppliers.add(await purchases.addSupplier(Supplier(
        name: s,
        phone: '075${10000000 + rnd.nextInt(89999999)}',
        address: rnd.nextBool() ? 'بغداد' : 'أربيل',
        createdAt: start,
        updatedAt: start,
      )));
    }

    // ── الصندوق وحسابات المصاريف ──
    final vouchers = VouchersService();
    final boxes = await vouchers.cashBoxes();
    final boxId = boxes.isEmpty ? null : boxes.firstWhere((b) => b.isDefault, orElse: () => boxes.first).id;
    Future<int?> acc(String code) async {
      final r = await db.query('accounts', columns: ['id'], where: 'code = ?', whereArgs: [code], limit: 1);
      return r.isEmpty ? null : r.first['id'] as int;
    }
    final rent = await acc('5201'), salaries = await acc('5202'), power = await acc('5203'), net = await acc('5206');

    final controller = InvoiceController(db: dbs);
    final receipts = ReceiptsService();
    final totalDays = today.difference(start).inDays;
    var invoices = 0;

    for (var d = 0; d <= totalDays; d++) {
      final day = start.add(Duration(days: d));
      if (day.weekday == DateTime.friday) continue;
      if (d % 5 == 0) onProgress(0.06 + 0.92 * d / totalDays, 'يوم ${day.year}/${day.month}/${day.day} — $invoices قائمة');

      // 🛒 المشتريات: كل 9 أيام تقريباً فاتورة شراء للمواد التي قلّت
      if (d % 9 == 0) {
        final low = await db.rawQuery(
            'SELECT id, name, stock_quantity, cost_price, unit FROM products WHERE stock_quantity < 40 ORDER BY RANDOM() LIMIT 10');
        final pick = low.isNotEmpty ? low : await db.rawQuery(
            'SELECT id, name, stock_quantity, cost_price, unit FROM products ORDER BY RANDOM() LIMIT 6');
        final items = <PurchaseInvoiceItem>[];
        for (final p in pick) {
          final qty = (p['unit'] == 'meter' ? 300 : 20 + rnd.nextInt(80)).toDouble();
          final price = ((p['cost_price'] as num?) ?? 1000).toDouble();
          items.add(PurchaseInvoiceItem(
            productId: p['id'] as int,
            productName: p['name'] as String,
            unitName: p['unit'] == 'meter' ? 'متر' : 'قطعة',
            quantity: qty,
            unitPrice: price,
            totalPrice: qty * price,
          ));
        }
        final total = items.fold<double>(0, (s, i) => s + i.totalPrice);
        try {
          await purchases.savePurchaseInvoice(
            PurchaseInvoice(
              invoiceNumber: 'P-${day.year}${day.month.toString().padLeft(2, '0')}${day.day.toString().padLeft(2, '0')}',
              supplierId: suppliers[rnd.nextInt(suppliers.length)],
              totalAmount: total,
              paidAmount: 0,
              status: 'confirmed',
              date: day,
            ),
            items,
            confirm: true,
            cashBoxId: boxId,
          );
        } catch (e) {
          print('🧪 تخطّي فاتورة شراء: $e');
        }
      }

      // 💸 دفعات للموردين كل أسبوعين
      if (d % 14 == 7 && boxId != null) {
        final owed = await db.rawQuery('''
          SELECT supplier_id AS id, SUM(amount_changed) AS bal FROM supplier_transactions
          WHERE COALESCE(is_deleted, 0) = 0 AND currency = 'IQD' GROUP BY supplier_id HAVING bal > 100000''');
        for (final s in owed.take(3)) {
          final bal = ((s['bal'] as num?) ?? 0).toDouble();
          try {
            await receipts.supplierPayment(
              supplierId: s['id'] as int,
              amount: _round250(bal * (0.4 + rnd.nextDouble() * 0.4)),
              currency: 'IQD',
              method: 'cash',
              date: day,
              cashBoxId: boxId,
            );
          } catch (e) {
            print('🧪 تخطّي دفعة مورد: $e');
          }
        }
      }

      // 🧾 المبيعات: 3 إلى 7 قوائم يومياً
      final sales = 3 + rnd.nextInt(5);
      for (var k = 0; k < sales; k++) {
        final c = customers[rnd.nextInt(customers.length)];
        final wholesale = c['wholesale'] as bool;
        final lines = <InvoiceItem>[];
        final used = <int>{};
        for (var n = 1 + rnd.nextInt(4); n > 0; n--) {
          final p = products[rnd.nextInt(products.length)];
          if (!used.add(p['id'] as int)) continue;
          final carton = p['carton'] as int;
          final byCarton = wholesale && carton > 0 && rnd.nextDouble() < 0.5;
          final double qty = p['unit'] == 'meter' ? (10 + rnd.nextInt(60)).toDouble() : (1 + rnd.nextInt(byCarton ? 2 : 6)).toDouble();
          final unitPrice = (wholesale ? p['wholesale'] : p['retail']) as double;
          final price = byCarton ? unitPrice * carton : unitPrice;
          final baseQty = byCarton ? qty * carton : qty;
          lines.add(InvoiceItem(
            invoiceId: 0,
            productId: p['id'] as int,
            productName: p['name'] as String,
            unit: p['unit'] as String,
            unitPrice: unitPrice,
            costPrice: (p['cost'] as double) * baseQty,
            quantityIndividual: byCarton ? null : qty,
            quantityLargeUnit: byCarton ? qty : null,
            unitsInLargeUnit: byCarton ? carton.toDouble() : null,
            appliedPrice: price,
            itemTotal: qty * price,
            saleType: byCarton ? 'كرتون' : (p['unit'] == 'meter' ? 'متر' : 'قطعة'),
          ));
        }
        if (lines.isEmpty) continue;
        final total = lines.fold<double>(0, (s, i) => s + i.itemTotal);
        final discount = total > 50000 && rnd.nextDouble() < 0.3 ? (total % 1000) : 0.0;
        final isCash = rnd.nextDouble() < 0.55;
        final net = total - discount;
        final paid = isCash ? net : (rnd.nextDouble() < 0.3 ? _round250(net * (0.2 + rnd.nextDouble() * 0.4)) : 0.0);
        final at = DateTime(day.year, day.month, day.day, 9 + rnd.nextInt(10), rnd.nextInt(60));
        try {
          final res = await controller.saveInvoice(InvoiceInputData(
            customerName: c['name'] as String,
            customerPhone: c['phone'] as String,
            customerAddress: '',
            paidAmount: paid,
            loadingFee: 0,
            discount: discount,
            paymentType: isCash ? 'نقد' : 'دين',
            selectedDate: at,
            invoiceItems: lines,
          ));
          if (res.success) invoices++;
        } catch (e) {
          print('🧪 تخطّي قائمة: $e');
        }
      }

      // 💵 تسديدات العملاء: كل يومين 1-3 عملاء مدينين
      if (d % 2 == 0) {
        final debtors = await db.rawQuery(
            'SELECT id, current_total_debt AS debt FROM customers WHERE current_total_debt > 20000 ORDER BY RANDOM() LIMIT ${1 + rnd.nextInt(3)}');
        for (final r in debtors) {
          final debt = ((r['debt'] as num?) ?? 0).toDouble();
          final amount = _round250(debt * (0.3 + rnd.nextDouble() * 0.6));
          if (amount <= 0) continue;
          try {
            await CustomerMoney.post(null,
                provider: provider,
                customerId: r['id'] as int,
                amount: -amount,
                kind: CustomerTxKind.cash,
                note: 'تسديد',
                date: day,
                cashBoxId: boxId);
          } catch (e) {
            print('🧪 تخطّي تسديد: $e');
          }
        }
      }

      // 📝 ديون يدوية قديمة أحياناً (مثل دفتر الديون الورقي)
      if (d % 23 == 0) {
        final c = customers[rnd.nextInt(customers.length)];
        try {
          await provider.addTransaction(DebtTransaction(
            customerId: c['id'] as int,
            amountChanged: _round250(15000 + rnd.nextDouble() * 85000),
            transactionType: 'manual_debt',
            transactionNote: 'دين سابق من الدفتر',
            transactionDate: day,
            createdAt: day,
          ));
        } catch (_) {}
      }

      // 🏠 المصاريف الشهرية
      if (boxId != null) {
        Future<void> expense(int? account, double amount, String text) async {
          if (account == null) return;
          try {
            await vouchers.create(
                type: VoucherType.expense, amount: amount, date: day, cashBoxId: boxId, accountId: account, description: text);
          } catch (e) {
            print('🧪 تخطّي مصروف: $e');
          }
        }
        if (day.day == 1) await expense(rent, 750000, 'إيجار المحل لشهر ${day.month}');
        if (day.day == 5) await expense(power, _round250(150000 + rnd.nextDouble() * 120000), 'أمبيرات المولدة والكهرباء');
        if (day.day == 10) await expense(net, 35000, 'اشتراك الإنترنت');
        if (day.day == 28) await expense(salaries, 1200000, 'رواتب عاملين اثنين');
      }
    }
    onProgress(1.0, 'اكتمل: $invoices قائمة بيع خلال سنة');
  }
}
