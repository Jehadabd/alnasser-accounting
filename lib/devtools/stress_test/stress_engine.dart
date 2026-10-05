// lib/devtools/stress_test/stress_engine.dart
//
// 🧪 اختبار التحمّل الحقيقي: يكتب في قاعدة البيانات الحقيقية عبر المسارات نفسها
// التي تستعملها الشاشات — لا محاكاة:
//   • العملاء وتعديل أسمائهم وهواتفهم: AppProvider.addCustomer / updateCustomer
//   • المعاملات اليدوية: AppProvider.addTransaction، وتعديلها كما في شاشة العميل
//     (DatabaseService.updateTransaction / convertTransactionType)
//   • الفواتير وتعديلاتها ونقلها بين العملاء: InvoiceController.saveInvoice
//     (ما تستدعيه شاشة «إنشاء فاتورة» عند الحفظ)
//   • المواد: DatabaseService.insertProduct (كشاشة «إدخال بضاعة»)
//
// وبجانبها «حقيقة متوقعة» مستقلة (stress_model.dart) تُحدَّث بعد نجاح كل عملية،
// ثم يُقارن كل رقم في القاعدة بها: رصيد كل عميل، مجموع معاملاته، كل معاملة، كل
// فاتورة (عميلها وإجماليها ومسددها ونوعها وموادها ودَينها المسجّل)، رصيد كل مادة،
// وعدم ظهور عملاء مكررين.
//
// المزامنة: المرحلة الكبيرة تعمل والمزامنة متوقفة (حدود فايربيس المجانية)، ثم
// تُفعَّل فيُرفع كل شيء، ويُقارن الحاسوبان ببصمة تُنشر في فايربيس.

// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../controllers/invoice_controller.dart';
import '../../models/customer.dart';
import '../../models/invoice.dart';
import '../../models/invoice_input_data.dart';
import '../../models/invoice_item.dart';
import '../../models/product.dart';
import '../../models/transaction.dart';
import '../../providers/app_provider.dart';
import '../../services/auth_service.dart';
import '../../services/database/business/invoice_debt_reconciler.dart';
import '../../services/database_service.dart';
import '../../services/demo_mode.dart';
import '../../services/firebase_sync/firebase_sync_config.dart';
import '../../services/firebase_sync/firebase_sync_helper.dart';
import '../../services/firebase_sync/invoice_sync_service.dart';
import '../../widgets/line_discount_dialog.dart' show lineNetPrice;
import 'stress_model.dart';

const String kStressCustomerPrefix = 'عميل اختبار';
const String kStressProductPrefix = 'مادة اختبار';

double _r2(double v) => (v * 100).roundToDouble() / 100;
double _step(double v, double step) => (v / step).roundToDouble() * step;

/// سطر فاتورة بصيغة بسيطة (يُبنى منها InvoiceItem كما تبنيه الشاشة)
class _L {
  _L(this.product, this.large, this.qty, this.gross, {this.discType, this.discValue = 0});
  final TProduct product;
  bool large;
  double qty;
  double gross;
  String? discType;
  double discValue;

  double get applied => discType == null ? gross : lineNetPrice(gross, discType, discValue);
  double get total => _r2(qty * applied);
  double get baseQty => large ? qty * product.factor : qty;
}

class StressReport {
  StressReport(this.title);
  final String title;
  int checks = 0;
  final List<String> problems = [];
  final List<String> notes = [];
  final Map<String, Object?> summary = {};
  bool get ok => problems.isEmpty;

  void check(bool cond, String problem) {
    checks++;
    if (!cond) problems.add(problem);
  }

  String toText() {
    final b = StringBuffer()
      ..writeln('═══ $title ═══')
      ..writeln('الوقت: ${DateTime.now()}')
      ..writeln('عدد الفحوص: $checks')
      ..writeln('النتيجة: ${ok ? '✅ مطابق 100%' : '❌ ${problems.length} خلل'}')
      ..writeln();
    summary.forEach((k, v) => b.writeln('• $k: $v'));
    if (notes.isNotEmpty) {
      b.writeln();
      for (final n in notes) {
        b.writeln('ℹ️ $n');
      }
    }
    if (problems.isNotEmpty) {
      b.writeln();
      b.writeln('— الخلل (أول 300) —');
      for (final pr in problems.take(300)) {
        b.writeln('❌ $pr');
      }
    }
    return b.toString();
  }
}

class StressEngine extends ChangeNotifier {
  StressEngine(this.app);
  final AppProvider app;

  final _db = DatabaseService();
  final _uuid = const Uuid();

  StressConfig? cfg;
  StressTruth truth = StressTruth();
  int nextCustomer = 0;
  bool bulkDone = false;
  bool running = false;
  bool _stop = false;
  String status = 'جاهز';
  final List<String> log = [];
  DateTime? startedAt;
  int _uid = 0;

  // عدّادات
  final Map<String, int> ops = {};
  int saves = 0;

  Directory? _dir;
  File? _journal;

  // ─────────────────────────── الملفات ───────────────────────────

  Future<Directory> _stressDir() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationSupportDirectory();
    final d = Directory(p.join(base.path, 'stress_test'));
    if (!await d.exists()) await d.create(recursive: true);
    return _dir = d;
  }

  /// مجلد التقارير على سطح المكتب ليسهل فتحها
  Future<Directory> reportsDir() async {
    final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    final d = home != null
        ? Directory(p.join(home, 'Desktop', 'alnaser_stress_reports'))
        : Directory(p.join((await _stressDir()).path, 'reports'));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<void> load() async {
    final d = await _stressDir();
    final st = File(p.join(d.path, 'state.json'));
    _journal = File(p.join(d.path, 'journal.jsonl'));
    if (await st.exists()) {
      try {
        final m = jsonDecode(await st.readAsString()) as Map<String, Object?>;
        cfg = StressConfig.fromJson(m['config'] as Map<String, Object?>);
        nextCustomer = (m['next'] as num?)?.toInt() ?? 0;
        bulkDone = m['bulkDone'] == true;
        ((m['ops'] as Map?) ?? const {}).forEach((k, v) => ops['$k'] = (v as num).toInt());
        saves = (m['saves'] as num?)?.toInt() ?? 0;
      } catch (e) {
        _say('⚠️ تعذّرت قراءة حالة الاختبار السابق: $e');
      }
    }
    if (cfg != null && await _journal!.exists()) {
      truth = StressTruth.replay(await _journal!.readAsLines());
      _say('استُعيدت حالة الاختبار ${cfg!.tag}: ${truth.customers.length} عميل، '
          '${truth.invoices.length} فاتورة، ${truth.events} حدث');
    }
    notifyListeners();
  }

  Future<void> _saveState() async {
    final d = await _stressDir();
    final st = File(p.join(d.path, 'state.json'));
    final tmp = File('${st.path}.tmp');
    await tmp.writeAsString(jsonEncode({
      'config': cfg?.toJson(),
      'next': nextCustomer,
      'bulkDone': bulkDone,
      'ops': ops,
      'saves': saves,
      'at': DateTime.now().toIso8601String(),
    }));
    await tmp.rename(st.path);
  }

  void _emit(Map<String, Object?> e) {
    truth.apply(e);
    _journal!.writeAsStringSync('${jsonEncode(e)}\n', mode: FileMode.append, flush: true);
  }

  void _say(String s) {
    final line = '${DateTime.now().toIso8601String().substring(11, 19)}  $s';
    log.insert(0, line);
    if (log.length > 400) log.removeLast();
    print('🧪 $s');
    notifyListeners();
  }

  void _count(String k) => ops[k] = (ops[k] ?? 0) + 1;

  /// يبدأ تشغيلة جديدة (يمسح سجل التشغيلة السابقة من ملفات الاختبار فقط — لا يمس القاعدة)
  Future<void> newRun(StressConfig c) async {
    final d = await _stressDir();
    for (final n in ['journal.jsonl', 'state.json']) {
      final f = File(p.join(d.path, n));
      if (await f.exists()) {
        await f.rename(p.join(d.path, '${DateTime.now().millisecondsSinceEpoch}_$n.old'));
      }
    }
    cfg = c;
    truth = StressTruth();
    nextCustomer = 0;
    bulkDone = false;
    ops.clear();
    saves = 0;
    _journal = File(p.join(d.path, 'journal.jsonl'));
    await _saveState();
    _say('تشغيلة جديدة ${c.tag}: ${c.customers} عميل × ${c.invoicesPerCustomer} فاتورة × '
        '${c.editsPerInvoice} تعديل، ${c.txPerCustomer} معاملة يدوية لكل عميل');
  }

  void requestStop() {
    _stop = true;
    status = 'يتوقف بعد العملية الحالية…';
    notifyListeners();
  }

  // ─────────────────────────── شروط الأمان ───────────────────────────

  /// أسباب منع البدء (فارغة = مسموح)
  Future<List<String>> blockers({required bool needSyncOff}) async {
    final out = <String>[];
    if (DemoMode.isOn) out.add('البرنامج في الوضع التجريبي — الاختبار يعمل على قاعدة البيانات الحقيقية فقط');
    if (!AuthService().isAdmin) out.add('يلزم الدخول بحساب المدير');
    final syncOn = await FirebaseSyncConfig.isEnabled();
    if (needSyncOff && syncOn) {
      out.add('المزامنة مفعّلة — أوقفها من إعدادات المزامنة قبل المرحلة الكبيرة (حدود فايربيس اليومية)');
    }
    if (!needSyncOff && !syncOn) out.add('المزامنة متوقفة — فعّلها أولاً');
    return out;
  }

  // ─────────────────────────── المرحلة الكبيرة ───────────────────────────

  Future<void> runBulk() async {
    final c = cfg;
    if (c == null || running) return;
    final b = await blockers(needSyncOff: true);
    if (b.isNotEmpty) {
      for (final x in b) {
        _say('⛔ $x');
      }
      return;
    }
    running = true;
    _stop = false;
    startedAt = DateTime.now();
    final startSaves = saves;
    status = 'يعمل';
    notifyListeners();
    try {
      if (truth.products.length < c.products) await _createProducts();
      for (var i = nextCustomer; i < c.customers; i++) {
        if (_stop) break;
        final had = truth.customers[i];
        if (had != null && !had.done) {
          _say('العميل ${i + 1} توقف أثناءه في تشغيلة سابقة — يُكمل من التالي');
        } else {
          await _processCustomer(i);
        }
        nextCustomer = i + 1;
        await _saveState();
        final el = DateTime.now().difference(startedAt!).inSeconds;
        final done = saves - startSaves;
        final left = c.totalInvoiceSaves - saves;
        final eta = done > 0 ? Duration(seconds: (el / done * left).round()) : null;
        status = 'العميل ${i + 1}/${c.customers} — حفظ فواتير $saves/${c.totalInvoiceSaves}'
            '${eta != null ? ' — المتبقي تقريباً ${eta.inHours}س ${eta.inMinutes % 60}د' : ''}';
        notifyListeners();
      }
      if (nextCustomer >= c.customers) {
        bulkDone = true;
        await _saveState();
        _say('✅ انتهت المرحلة الكبيرة — اضغط «التحقق من الحسابات»');
        status = 'انتهت المرحلة الكبيرة';
      } else {
        status = 'متوقف عند العميل ${nextCustomer + 1}';
        _say('⏸️ توقف — اضغط «متابعة» للإكمال');
      }
    } catch (e, st) {
      _say('❌ توقف بخطأ: $e');
      print(st);
      status = 'توقف بخطأ';
    } finally {
      running = false;
      notifyListeners();
    }
  }

  Future<void> _createProducts() async {
    final c = cfg!;
    final rnd = Random(c.seed);
    const factors = [6, 10, 12, 20, 24, 40, 50];
    for (var k = truth.products.length; k < c.products; k++) {
      final name = '$kStressProductPrefix ${c.tag}-${(k + 1).toString().padLeft(3, '0')}';
      final factor = factors[rnd.nextInt(factors.length)];
      final price = _step(1000 + rnd.nextDouble() * 49000, 250);
      final cost = _step(price * (0.6 + rnd.nextDouble() * 0.25), 250);
      const opening = 5000000.0;
      final now = DateTime.now();
      final id = await _db.insertProduct(Product(
        name: name,
        unit: 'piece',
        unitPrice: price,
        costPrice: cost,
        price1: price,
        price2: _step(price * 0.95, 250),
        price3: _step(price * 1.05, 250),
        price4: _step(price * 0.9, 250),
        price5: _step(price * 0.85, 250),
        price6: price,
        unitHierarchy: jsonEncode([
          {'unit_name': 'كرتون', 'quantity': factor}
        ]),
        unitCosts: jsonEncode({'piece': cost, 'كرتون': cost * factor}),
        stockQuantity: opening,
        createdAt: now,
        lastModifiedAt: now,
      ));
      final row = await (await _db.database).query('products', columns: ['sync_uuid'], where: 'id = ?', whereArgs: [id]);
      _emit({
        'e': 'prod',
        'id': id,
        'uuid': (row.isEmpty ? null : row.first['sync_uuid']) ?? '',
        'name': name,
        'factor': factor,
        'price': price,
        'cost': cost,
        'open': opening,
      });
      _count('مواد');
    }
    _say('أُنشئت ${truth.products.length} مادة اختبار (رصيد افتتاحي 5,000,000 قطعة لكل منها)');
  }

  String _custName(int i) => '$kStressCustomerPrefix ${cfg!.tag}-${(i + 1).toString().padLeft(4, '0')}';

  String _phone(Random rnd, String prefix) {
    final b = StringBuffer(prefix);
    for (var k = 0; k < 7; k++) {
      b.write(rnd.nextInt(10));
    }
    return b.toString();
  }

  Future<TCustomer> _createCustomer(int idx, String name, String phone) async {
    final now = DateTime.now();
    await app.addCustomer(Customer(name: name, phone: phone, createdAt: now, lastModifiedAt: now));
    final rows = await (await _db.database).query('customers',
        columns: ['id', 'sync_uuid'],
        where: 'name = ? AND COALESCE(is_deleted, 0) = 0',
        whereArgs: [name],
        orderBy: 'id DESC',
        limit: 1);
    if (rows.isEmpty) throw Exception('لم يُعثر على العميل بعد إنشائه: $name');
    _emit({
      'e': 'cust',
      'i': idx,
      'id': rows.first['id'],
      'uuid': rows.first['sync_uuid'] ?? '',
      'name': name,
      'phone': phone,
    });
    _count('عملاء');
    return truth.customers[idx]!;
  }

  Future<void> _processCustomer(int i) async {
    final c = cfg!;
    final rnd = Random(c.seed * 100003 + i * 7919);
    final cust = await _createCustomer(i, _custName(i), _phone(rnd, '0770'));

    // ── المعاملات اليدوية ──
    final txIds = <int>[];
    for (var k = 0; k < c.txPerCustomer; k++) {
      final id = await _addManual(cust, rnd, live: false);
      if (id != null) txIds.add(id);
    }
    for (final id in txIds) {
      final n = c.txEditsMin + rnd.nextInt(c.txEditsMax - c.txEditsMin + 1);
      for (var k = 0; k < n; k++) {
        await _editManual(cust, id, rnd, k);
      }
    }

    // ── الفواتير وتعديلاتها، وبينها تعديل اسم العميل وهاتفه ──
    final renameAt = rnd.nextInt(c.invoicesPerCustomer * max(1, c.editsPerInvoice));
    final phoneAt = rnd.nextInt(c.invoicesPerCustomer * max(1, c.editsPerInvoice));
    var step = 0;
    for (var v = 0; v < c.invoicesPerCustomer; v++) {
      if (_stop) break;
      final invId = await _createInvoice(cust, rnd, live: false);
      if (invId == null) continue;
      final kinds = List<String>.of(_editKinds)..shuffle(rnd);
      for (var e = 0; e < c.editsPerInvoice; e++) {
        if (step == renameAt) await _renameCustomer(cust, rnd);
        if (step == phoneAt) await _changePhone(cust, rnd);
        step++;
        final k1 = kinds[e % kinds.length];
        final more = rnd.nextDouble() < 0.35 ? [_editKinds[rnd.nextInt(_editKinds.length)]] : const <String>[];
        await _editInvoice(invId, [k1, ...more], rnd, pool: truth.customers.keys.toList(), live: false);
      }
    }
    if (!_stop) _emit({'e': 'done', 'i': i});
  }

  // ─────────────────────────── المعاملات اليدوية ───────────────────────────

  Future<int?> _addManual(TCustomer cust, Random rnd, {required bool live, Map<String, double>? deltas}) async {
    final bal = await _localBalance(cust.id);
    final payment = bal > 5000 && rnd.nextDouble() < 0.4;
    double amt;
    if (payment) {
      amt = -_step(max(1000, bal * (0.1 + rnd.nextDouble() * 0.5)), 250);
      if (-amt > bal) amt = -_step(bal, 250);
      if (amt == 0) amt = _step(5000 + rnd.nextDouble() * 195000, 250);
    } else {
      amt = _step(5000 + rnd.nextDouble() * 195000, 250);
    }
    final uuid = _uuid.v4();
    final now = DateTime.now();
    try {
      await app.addTransaction(DebtTransaction(
        customerId: cust.id,
        amountChanged: amt,
        transactionType: amt > 0 ? 'manual_debt' : 'manual_payment',
        transactionNote: '${live ? 'جولة حيّة' : 'اختبار'} ${cfg?.tag ?? ''}',
        transactionDate: now,
        createdAt: now,
        transactionUuid: uuid,
      ));
    } catch (e) {
      _refuse('إضافة معاملة', e);
      return null;
    }
    final r = await (await _db.database)
        .query('transactions', columns: ['id'], where: 'transaction_uuid = ?', whereArgs: [uuid], limit: 1);
    if (r.isEmpty) throw Exception('المعاملة لم تُحفظ: $uuid');
    final id = r.first['id'] as int;
    _emit(live
        ? {'e': 'ltx', 'i': cust.idx, 'id': id, 'amt': amt}
        : {'e': 'tx', 'i': cust.idx, 'id': id, 'amt': amt});
    _count(live ? 'معاملات حيّة' : 'معاملات يدوية');
    return id;
  }

  Future<void> _editManual(TCustomer cust, int id, Random rnd, int k, {bool live = false}) async {
    final tx = await _db.getTransactionById(id);
    if (tx == null) return;
    final cur = live ? (truth.liveManual[id] ?? tx.amountChanged) : (cust.manual[id] ?? tx.amountChanged);
    final kind = live ? 'amount' : const ['amount', 'note', 'date', 'convert', 'amount'][(k + rnd.nextInt(5)) % 5];
    double intended = cur;
    try {
      switch (kind) {
        case 'amount':
          final mag = _step(5000 + rnd.nextDouble() * 150000, 250);
          intended = cur >= 0 ? mag : -min(mag, max(250.0, (await _localBalance(cust.id)) + cur.abs()));
          intended = _step(intended, 250);
          if (intended == 0) intended = cur;
          await _db.updateTransaction(tx.copyWith(amountChanged: intended));
          break;
        case 'note':
          await _db.updateTransaction(tx.copyWith(transactionNote: 'تعديل ملاحظة ${rnd.nextInt(1000)}'));
          break;
        case 'date':
          await _db.updateTransaction(tx.copyWith(transactionDate: tx.transactionDate.subtract(Duration(days: 1 + rnd.nextInt(20)))));
          break;
        case 'convert':
          await _db.convertTransactionType(id);
          intended = -cur;
          break;
      }
    } catch (e) {
      _refuse('تعديل معاملة ($kind)', e);
      return;
    }
    _emit(live ? {'e': 'ltx', 'i': cust.idx, 'id': id, 'amt': intended} : {'e': 'tx', 'i': cust.idx, 'id': id, 'amt': intended});
    _count(live ? 'تعديلات معاملات حيّة' : 'تعديلات معاملات');
  }

  Future<double> _localBalance(int customerId) async {
    final r = await (await _db.database).rawQuery(
        'SELECT COALESCE(SUM(amount_changed), 0) AS b FROM transactions WHERE customer_id = ? AND COALESCE(is_deleted, 0) = 0',
        [customerId]);
    return ((r.first['b'] as num?) ?? 0).toDouble();
  }

  // ─────────────────────────── العملاء ───────────────────────────

  Future<void> _renameCustomer(TCustomer cust, Random rnd, {String suffix = 'معدّل'}) async {
    final c = await _db.getCustomerById(cust.id);
    if (c == null) return;
    final base = cust.name.replaceAll(RegExp(r' \(.*\)$'), '');
    final n = '$base ($suffix ${1 + rnd.nextInt(99)})';
    await app.updateCustomer(c.copyWith(name: n, lastModifiedAt: DateTime.now()));
    _emit({'e': 'custEdit', 'i': cust.idx, 'name': n, 'phone': cust.phone});
    _count('تغيير اسم عميل');
  }

  Future<void> _changePhone(TCustomer cust, Random rnd) async {
    final c = await _db.getCustomerById(cust.id);
    if (c == null) return;
    final ph = _phone(rnd, '0780');
    await app.updateCustomer(c.copyWith(phone: ph, lastModifiedAt: DateTime.now()));
    _emit({'e': 'custEdit', 'i': cust.idx, 'name': cust.name, 'phone': ph});
    _count('تغيير هاتف عميل');
  }

  // ─────────────────────────── الفواتير ───────────────────────────

  static const _editKinds = [
    'qty', 'price', 'add', 'remove', 'unit', 'lineDisc', 'gift', 'invDisc', 'loading', 'payType', 'paid', 'date', 'transfer',
  ];

  TProduct _randProduct(Random rnd) {
    final list = truth.products.values.toList();
    return list[rnd.nextInt(list.length)];
  }

  _L _randLine(Random rnd) {
    final pr = _randProduct(rnd);
    final large = rnd.nextDouble() < 0.4;
    final qty = (1 + rnd.nextInt(large ? 5 : 30)).toDouble();
    final gross = large ? pr.price * pr.factor : _step(pr.price * (0.95 + rnd.nextDouble() * 0.15), 250);
    final l = _L(pr, large, qty, gross);
    final r = rnd.nextDouble();
    if (r < 0.12) {
      l.discType = 'percent';
      l.discValue = const [5.0, 10.0, 15.0][rnd.nextInt(3)];
    } else if (r < 0.2) {
      l.discType = 'amount';
      l.discValue = _step(gross * 0.1, 250);
    }
    return l;
  }

  InvoiceItem _item(_L l) {
    final applied = l.applied;
    return InvoiceItem(
      invoiceId: 0,
      productId: l.product.id,
      productName: l.product.name,
      unit: 'piece',
      unitPrice: l.product.price,
      costPrice: l.product.cost * l.baseQty,
      quantityIndividual: l.large ? null : l.qty,
      quantityLargeUnit: l.large ? l.qty : null,
      appliedPrice: applied,
      itemTotal: l.total,
      saleType: l.large ? 'كرتون' : 'قطعة',
      unitsInLargeUnit: l.large ? l.product.factor.toDouble() : null,
      productSyncUuid: l.product.uuid,
      priceBeforeDiscount: l.discType != null ? l.gross : null,
      discountType: l.discType,
      discountValue: (l.discType == null || l.discType == 'gift') ? null : l.discValue,
      uniqueId: 'st_${DateTime.now().microsecondsSinceEpoch}_${_uid++}',
    );
  }

  _L? _fromItem(InvoiceItem it) {
    TProduct? pr = it.productId != null ? truth.products[it.productId] : null;
    pr ??= truth.products.values.where((x) => x.name == it.productName).firstOrNull;
    if (pr == null) return null;
    final large = (it.quantityLargeUnit ?? 0) > 0;
    final qty = large ? it.quantityLargeUnit! : (it.quantityIndividual ?? 0);
    final gross = it.discountType != null ? (it.priceBeforeDiscount ?? it.appliedPrice) : it.appliedPrice;
    return _L(pr, large, qty, gross, discType: it.discountType, discValue: it.discountValue ?? 0);
  }

  Map<String, double> _qtyMap(List<_L> lines) {
    final m = <String, double>{};
    for (final l in lines) {
      m['${l.product.id}'] = (m['${l.product.id}'] ?? 0) + l.baseQty;
    }
    return m;
  }

  double _itemsTotal(List<_L> lines) => lines.fold<double>(0, (a, l) => a + l.total);

  /// ما تفعله الشاشة بعد الحفظ والمزامنة مفعّلة: رفع الحزمة ثم العميل (لا انتظار)
  Future<void> _afterSaveLikeUi(Invoice saved) async {
    if (!await FirebaseSyncConfig.isEnabled()) return;
    final uuid = saved.invoiceUuid;
    final cid = saved.customerId;
    unawaited(() async {
      try {
        if (uuid != null && uuid.isNotEmpty) await InvoiceSyncService().syncInvoiceBundleNow(uuid);
        if (cid != null) {
          final cu = await _db.getCustomerById(cid);
          if (cu != null && (cu.syncUuid ?? '').isNotEmpty) await FirebaseSyncHelper().syncCustomer(cu.toMap());
        }
      } catch (_) {}
    }());
  }

  Future<int?> _createInvoice(TCustomer cust, Random rnd, {required bool live, bool forceDebt = false}) async {
    final lines = List.generate(1 + rnd.nextInt(5), (_) => _randLine(rnd));
    final itemsTotal = _itemsTotal(lines);
    final discount = rnd.nextDouble() < 0.2 ? _step(itemsTotal * 0.04, 250) : 0.0;
    final loading = rnd.nextDouble() < 0.2 ? _step(1000 + rnd.nextDouble() * 9000, 500) : 0.0;
    final total = _r2(itemsTotal + loading - discount);
    final debt = forceDebt || rnd.nextDouble() < 0.6;
    final paid = debt ? (rnd.nextBool() ? 0.0 : _step(total * rnd.nextDouble() * 0.6, 1000)) : total;
    final date = DateTime.now().subtract(Duration(days: rnd.nextInt(60)));
    final input = InvoiceInputData(
      customerName: cust.name,
      customerPhone: rnd.nextDouble() < 0.3 ? cust.phone : '',
      customerAddress: '',
      paidAmount: paid,
      loadingFee: loading,
      discount: discount,
      paymentType: debt ? 'دين' : 'نقد',
      selectedDate: date,
      invoiceItems: lines.map(_item).toList(),
    );
    final res = await InvoiceController().saveInvoice(input);
    saves++;
    if (!res.success || res.invoice?.id == null) {
      _refuse('إنشاء فاتورة', res.errorMessage ?? 'فشل');
      return null;
    }
    final inv = res.invoice!;
    _emit({
      'e': 'inv',
      'id': inv.id,
      'uuid': inv.invoiceUuid ?? '',
      'c': cust.idx,
      'total': total,
      'paid': paid,
      'type': debt ? 'دين' : 'نقد',
      'q': _qtyMap(lines),
      if (live) 'live': true,
    });
    _count(live ? 'فواتير حيّة' : 'فواتير');
    await _afterSaveLikeUi(inv);
    return inv.id;
  }

  Future<void> _editInvoice(int invId, List<String> kinds, Random rnd,
      {required List<int> pool, required bool live}) async {
    final inv = await _db.getInvoiceById(invId);
    final t = truth.invoices[invId];
    if (inv == null || t == null) return;
    final items = await _db.getInvoiceItems(invId);
    final lines = <_L>[];
    for (final it in items) {
      final l = _fromItem(it);
      if (l != null) lines.add(l);
    }
    if (lines.isEmpty) return;

    var discount = inv.discount;
    var loading = inv.loadingFee;
    var type = inv.paymentType;
    var paid = inv.amountPaidOnInvoice;
    var date = inv.invoiceDate;
    var customerIdx = t.customerIdx;
    var name = inv.customerName;
    final done = <String>[];

    for (final kind in kinds) {
      switch (kind) {
        case 'qty':
          final l = lines[rnd.nextInt(lines.length)];
          l.qty = (1 + rnd.nextInt(l.large ? 6 : 40)).toDouble();
          break;
        case 'price':
          final l = lines[rnd.nextInt(lines.length)];
          if (l.discType == 'gift') break;
          l.gross = _step(max(250, l.gross * (0.85 + rnd.nextDouble() * 0.35)), 250);
          break;
        case 'add':
          lines.add(_randLine(rnd));
          break;
        case 'remove':
          if (lines.length > 1) lines.removeAt(rnd.nextInt(lines.length));
          break;
        case 'unit':
          final l = lines[rnd.nextInt(lines.length)];
          l.large = !l.large;
          l.qty = (1 + rnd.nextInt(l.large ? 4 : 20)).toDouble();
          l.gross = l.large ? l.product.price * l.product.factor : l.product.price;
          l.discType = null;
          l.discValue = 0;
          break;
        case 'lineDisc':
          final l = lines[rnd.nextInt(lines.length)];
          if (rnd.nextBool()) {
            l.discType = 'percent';
            l.discValue = const [5.0, 7.5, 10.0, 20.0][rnd.nextInt(4)];
          } else {
            l.discType = 'amount';
            l.discValue = _step(l.gross * 0.12, 250);
          }
          break;
        case 'gift':
          // هدية لسطر، أو إلغاء هدية قائمة؛ ويبقى في الفاتورة سطر مدفوع واحد على الأقل
          final gifts = lines.where((x) => x.discType == 'gift').toList();
          if (gifts.isNotEmpty && rnd.nextBool()) {
            gifts.first.discType = null;
          } else {
            final paidLines = lines.where((x) => x.discType != 'gift').toList();
            if (paidLines.length > 1) paidLines[rnd.nextInt(paidLines.length)].discType = 'gift';
          }
          break;
        case 'invDisc':
          discount = rnd.nextDouble() < 0.3 ? 0 : _step(_itemsTotal(lines) * (0.01 + rnd.nextDouble() * 0.05), 250);
          break;
        case 'loading':
          loading = rnd.nextDouble() < 0.3 ? 0 : _step(500 + rnd.nextDouble() * 9500, 500);
          break;
        case 'payType':
          type = type == 'دين' ? 'نقد' : 'دين';
          if (type == 'دين') paid = rnd.nextBool() ? 0 : -1; // -1 = جزء من الإجمالي يُحسب بعد قليل
          break;
        case 'paid':
          if (type == 'دين') paid = -1;
          break;
        case 'date':
          date = date.subtract(Duration(days: 1 + rnd.nextInt(15)));
          break;
        case 'transfer':
          final others = pool.where((x) => x != customerIdx).toList();
          if (others.isEmpty) break;
          customerIdx = others[rnd.nextInt(others.length)];
          name = truth.customers[customerIdx]!.name; // يختاره المستخدم من قائمة العملاء بالاسم
          break;
      }
      done.add(kind);
    }

    // سطر مدفوع واحد على الأقل
    if (lines.every((l) => l.discType == 'gift')) lines.first.discType = null;
    final itemsTotal = _itemsTotal(lines);
    if (discount >= itemsTotal) discount = _step(itemsTotal * 0.05, 250);
    final total = _r2(itemsTotal + loading - discount);
    if (type == 'نقد') {
      paid = total;
    } else if (paid < 0) {
      paid = _step(total * rnd.nextDouble() * 0.8, 1000);
    }
    if (type == 'دين' && paid > total) paid = _step(total * 0.5, 1000);

    final input = InvoiceInputData(
      invoiceToManage: inv,
      customerName: name,
      // كالشاشة: حقل الهاتف يبقى كما حُفظ في الفاتورة (حتى عند نقلها لعميل آخر)
      customerPhone: inv.customerPhone ?? '',
      customerAddress: inv.customerAddress ?? '',
      installerName: inv.installerName,
      paidAmount: paid,
      loadingFee: loading,
      discount: discount,
      paymentType: type,
      selectedDate: date,
      invoiceItems: lines.map(_item).toList(),
    );
    final res = await InvoiceController().saveInvoice(input);
    saves++;
    if (!res.success) {
      _refuse('تعديل فاتورة (${done.join('+')})', res.errorMessage ?? 'فشل');
      return;
    }
    _emit({
      'e': 'inv',
      'id': invId,
      'uuid': t.uuid,
      'c': customerIdx,
      'total': total,
      'paid': paid,
      'type': type,
      'q': _qtyMap(lines),
      if (t.live) 'live': true,
    });
    for (final k in done) {
      _count('تعديل فاتورة: $k');
    }
    if (customerIdx != t.customerIdx) _count('نقل فاتورة لعميل آخر');
    if (res.invoice != null) await _afterSaveLikeUi(res.invoice!);
  }

  void _refuse(String what, Object reason) {
    var why = reason.toString().replaceAll('Exception: ', '').split('\n').first;
    if (why.length > 70) why = '${why.substring(0, 70)}…';
    _emit({'e': 'refuse', 'why': '$what: $why'});
    _count('رفض');
  }

  // ─────────────────────────── التحقق المحلي ───────────────────────────

  Future<StressReport> verify({String title = 'التحقق من الحسابات (مقارنة القاعدة بالمتوقع)'}) async {
    final rep = StressReport(title);
    final c = cfg;
    if (c == null) {
      rep.problems.add('لا توجد تشغيلة');
      return rep;
    }
    status = 'يتحقق…';
    notifyListeners();
    final db = await _db.database;

    // 1) العملاء
    var sumExpected = 0.0;
    for (final cu in truth.customers.values) {
      final rows = await db.query('customers', where: 'id = ?', whereArgs: [cu.id], limit: 1);
      if (rows.isEmpty) {
        rep.check(false, 'العميل ${cu.name}: غير موجود في القاعدة');
        continue;
      }
      final r = rows.first;
      final stored = ((r['current_total_debt'] as num?) ?? 0).toDouble();
      final sum = await _localBalance(cu.id);
      final exp = truth.expectedBalance(cu.idx);
      sumExpected += exp;
      rep.check((r['is_deleted'] as int? ?? 0) == 0, 'العميل ${cu.name}: محذوف');
      rep.check(r['name'] == cu.name, 'العميل ${cu.idx + 1}: الاسم «${r['name']}» والمتوقع «${cu.name}»');
      rep.check((r['phone'] as String? ?? '') == cu.phone, 'العميل ${cu.name}: الهاتف ${r['phone']} والمتوقع ${cu.phone}');
      rep.check((sum - exp).abs() < 0.01, 'العميل ${cu.name}: مجموع معاملاته ${_f(sum)} والمتوقع ${_f(exp)} (فرق ${_f(sum - exp)})');
      rep.check((stored - sum).abs() < 0.01, 'العميل ${cu.name}: الرصيد المخزّن ${_f(stored)} ≠ مجموع معاملاته ${_f(sum)}');
      // كل معاملة يدوية
      for (final e in cu.manual.entries) {
        final tr = await db.query('transactions',
            columns: ['amount_changed', 'is_deleted', 'customer_id'], where: 'id = ?', whereArgs: [e.key], limit: 1);
        if (tr.isEmpty) {
          rep.check(false, 'معاملة ${e.key} للعميل ${cu.name}: غير موجودة');
          continue;
        }
        final a = ((tr.first['amount_changed'] as num?) ?? 0).toDouble();
        rep.check((a - e.value).abs() < 0.01, 'معاملة ${e.key} (${cu.name}): ${_f(a)} والمتوقع ${_f(e.value)}');
        rep.check((tr.first['is_deleted'] as int? ?? 0) == 0, 'معاملة ${e.key} (${cu.name}): محذوفة');
        rep.check(tr.first['customer_id'] == cu.id, 'معاملة ${e.key}: انتقلت لعميل آخر');
      }
    }
    for (final e in truth.liveManual.entries) {
      final tr = await db.query('transactions', columns: ['amount_changed'], where: 'id = ?', whereArgs: [e.key], limit: 1);
      final a = tr.isEmpty ? double.nan : ((tr.first['amount_changed'] as num?) ?? 0).toDouble();
      rep.check((a - e.value).abs() < 0.01, 'معاملة حيّة ${e.key}: ${_f(a)} والمتوقع ${_f(e.value)}');
    }

    // 2) لا عملاء مكررون أو وهميون (عميل يُنشأ خطأً عند حفظ فاتورة)
    final testCustomers = await db.rawQuery(
        "SELECT id, name FROM customers WHERE name LIKE ? AND COALESCE(is_deleted, 0) = 0",
        ['$kStressCustomerPrefix ${c.tag}-%']);
    final known = truth.customers.values.map((x) => x.id).toSet();
    final extra = testCustomers.where((r) => !known.contains(r['id'])).toList();
    rep.check(extra.isEmpty,
        'عملاء أُنشئوا دون قصد (${extra.length}): ${extra.take(10).map((r) => r['name']).join('، ')}');

    // 3) الفواتير
    for (final t in truth.invoices.values) {
      final rows = await db.query('invoices', where: 'id = ?', whereArgs: [t.id], limit: 1);
      if (rows.isEmpty) {
        rep.check(false, 'فاتورة ${t.id}: غير موجودة');
        continue;
      }
      final r = rows.first;
      final cu = truth.customers[t.customerIdx];
      final total = ((r['total_amount'] as num?) ?? 0).toDouble();
      final paid = ((r['amount_paid_on_invoice'] as num?) ?? 0).toDouble();
      rep.check((r['is_deleted'] as int? ?? 0) == 0, 'فاتورة ${t.id}: محذوفة');
      rep.check(r['customer_id'] == cu?.id,
          'فاتورة ${t.id}: عميلها ${r['customer_id']} (${r['customer_name']}) والمتوقع ${cu?.id} (${cu?.name})');
      rep.check((total - t.total).abs() < 0.01, 'فاتورة ${t.id}: الإجمالي ${_f(total)} والمتوقع ${_f(t.total)}');
      rep.check((paid - t.paid).abs() < 0.01, 'فاتورة ${t.id}: المسدد ${_f(paid)} والمتوقع ${_f(t.paid)}');
      rep.check(r['payment_type'] == t.type, 'فاتورة ${t.id}: النوع ${r['payment_type']} والمتوقع ${t.type}');
      // المواد
      final items = await db.rawQuery('''
        SELECT product_id,
               SUM(CASE WHEN COALESCE(quantity_large_unit, 0) > 0
                        THEN quantity_large_unit * COALESCE(NULLIF(units_in_large_unit, 0), 1)
                        ELSE COALESCE(quantity_individual, 0) END) AS q,
               SUM(item_total) AS s
        FROM invoice_items WHERE invoice_id = ? GROUP BY product_id''', [t.id]);
      final got = {for (final it in items) (it['product_id'] as int?) ?? -1: ((it['q'] as num?) ?? 0).toDouble()};
      final sumItems = items.fold<double>(0, (a, it) => a + ((it['s'] as num?) ?? 0).toDouble());
      final loading = ((r['loading_fee'] as num?) ?? 0).toDouble();
      final disc = ((r['discount'] as num?) ?? 0).toDouble();
      rep.check((sumItems + loading - disc - total).abs() < 0.01,
          'فاتورة ${t.id}: مجموع موادها ${_f(sumItems)} + أجور ${_f(loading)} − خصم ${_f(disc)} ≠ إجماليها ${_f(total)}');
      final keys = {...got.keys, ...t.qty.keys};
      for (final k in keys) {
        rep.check(((got[k] ?? 0) - (t.qty[k] ?? 0)).abs() < 0.0001,
            'فاتورة ${t.id}: كمية المادة $k ${got[k] ?? 0} والمتوقع ${t.qty[k] ?? 0}');
      }
      // الدين المسجّل: كله على عميلها الحالي، وصفر على أي عميل سابق
      if (cu != null) {
        final rec = await InvoiceDebtReconciler.recordedContribution(db, t.id, cu.id);
        rep.check((rec - t.debt).abs() < 0.01,
            'فاتورة ${t.id}: دينها المسجّل على ${cu.name} ${_f(rec)} والمتوقع ${_f(t.debt)}');
        final others = await db.rawQuery(
            'SELECT DISTINCT customer_id FROM transactions WHERE invoice_id = ? AND customer_id != ? AND COALESCE(is_deleted, 0) = 0',
            [t.id, cu.id]);
        for (final o in others) {
          final oid = o['customer_id'] as int?;
          if (oid == null) continue;
          final orec = await InvoiceDebtReconciler.recordedContribution(db, t.id, oid);
          rep.check(orec.abs() < 0.01, 'فاتورة ${t.id}: بقي منها ${_f(orec)} على العميل السابق $oid');
        }
      }
    }

    // 4) المواد
    for (final pr in truth.products.values) {
      final rows = await db.query('products', columns: ['stock_quantity'], where: 'id = ?', whereArgs: [pr.id], limit: 1);
      final stock = rows.isEmpty ? double.nan : ((rows.first['stock_quantity'] as num?) ?? 0).toDouble();
      final exp = truth.expectedStock(pr.id);
      rep.check((stock - exp).abs() < 0.0001, 'المادة ${pr.name}: رصيدها ${_f(stock)} والمتوقع ${_f(exp)}');
    }

    final totalDebt = await db.rawQuery(
        "SELECT COALESCE(SUM(current_total_debt), 0) AS s FROM customers WHERE name LIKE ? AND COALESCE(is_deleted, 0) = 0",
        ['$kStressCustomerPrefix ${c.tag}-%']);
    rep.summary.addAll({
      'التشغيلة': c.tag,
      'العملاء': truth.customers.length,
      'الفواتير': truth.invoices.length,
      'المعاملات اليدوية': truth.customers.values.fold<int>(0, (a, x) => a + x.manual.length),
      'المواد': truth.products.length,
      'مرات حفظ الفواتير': saves,
      'مجموع الديون المتوقع': _f(sumExpected),
      'مجموع ديون عملاء الاختبار في القاعدة': _f(((totalDebt.first['s'] as num?) ?? 0).toDouble()),
    });
    if (ops.isNotEmpty) {
      rep.notes.add('العمليات: ${ops.entries.map((e) => '${e.key}=${e.value}').join('، ')}');
    }
    if (truth.refusals.isNotEmpty) {
      rep.notes.add('عمليات رفضها البرنامج (لم تُحتسب في المتوقع — كما يحدث للمستخدم):');
      final sorted = truth.refusals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      for (final e in sorted.take(25)) {
        rep.notes.add('   ${e.value} × ${e.key}');
      }
    }
    await _writeReport(rep);
    status = rep.ok ? 'التحقق: مطابق 100%' : 'التحقق: ${rep.problems.length} خلل';
    _say(status);
    notifyListeners();
    return rep;
  }

  Future<File> _writeReport(StressReport rep) async {
    final d = await reportsDir();
    final ts = DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);
    final f = File(p.join(d.path, 'report_${cfg?.tag ?? 'x'}_$ts.txt'));
    await f.writeAsString(rep.toText());
    _say('حُفظ التقرير: ${f.path}');
    return f;
  }

  String _f(double v) => v.isNaN ? '—' : v.toStringAsFixed(2).replaceAll(RegExp(r'\.00$'), '');

  // ─────────────────────────── المزامنة: المعلّق ───────────────────────────

  Future<Map<String, int>> pendingCounts() async {
    final db = await _db.database;
    Future<int> q(String sql) async {
      try {
        final r = await db.rawQuery(sql);
        return ((r.first.values.first as num?) ?? 0).toInt();
      } catch (_) {
        return -1;
      }
    }

    return {
      'عملاء': await q('''SELECT COUNT(*) FROM customers WHERE sync_uuid IS NOT NULL AND sync_uuid != ''
          AND COALESCE(is_created_by_me, 1) = 1 AND (synced_at IS NULL OR last_modified_at > synced_at)'''),
      'معاملات': await q('''SELECT COUNT(*) FROM transactions WHERE COALESCE(transaction_uuid, '') != ''
          AND COALESCE(is_uploaded, 0) = 0 AND COALESCE(is_created_by_me, 1) = 1
          AND (invoice_sync_uuid IS NULL OR invoice_sync_uuid = '' OR is_deleted = 1)'''),
      'فواتير': await q("SELECT COUNT(*) FROM invoices WHERE COALESCE(is_synced, 0) = 0 AND invoice_uuid IS NOT NULL"),
    };
  }

  // ─────────────────────────── البصمة والمقارنة بين الحاسوبين ───────────────────────────

  /// بصمة كل عميل اختبار (بمعرّف المزامنة) وكل مادة اختبار — من القاعدة مباشرة
  Future<Map<String, Object?>> localFingerprint() async {
    final db = await _db.database;
    final custRows = await db.rawQuery('''
      SELECT c.sync_uuid AS u, c.name AS n, c.current_total_debt AS b,
        (SELECT COALESCE(SUM(t.amount_changed), 0) FROM transactions t WHERE t.customer_id = c.id AND COALESCE(t.is_deleted, 0) = 0) AS ts,
        (SELECT COUNT(*) FROM transactions t WHERE t.customer_id = c.id AND COALESCE(t.is_deleted, 0) = 0 AND ABS(t.amount_changed) > 0.001) AS tc,
        (SELECT COUNT(*) FROM invoices i WHERE i.customer_id = c.id AND COALESCE(i.is_deleted, 0) = 0) AS ic,
        (SELECT COALESCE(SUM(i.total_amount), 0) FROM invoices i WHERE i.customer_id = c.id AND COALESCE(i.is_deleted, 0) = 0) AS it,
        (SELECT COALESCE(SUM(CASE WHEN i.payment_type = 'دين' THEN i.total_amount - i.amount_paid_on_invoice ELSE 0 END), 0)
           FROM invoices i WHERE i.customer_id = c.id AND COALESCE(i.is_deleted, 0) = 0) AS id
      FROM customers c
      WHERE c.name LIKE ? AND COALESCE(c.is_deleted, 0) = 0 AND COALESCE(c.sync_uuid, '') != ''
    ''', ['$kStressCustomerPrefix %']);
    final customers = <String, String>{};
    final names = <String, String>{};
    for (final r in custRows) {
      final u = r['u'] as String;
      customers[u] = [
        _f(((r['b'] as num?) ?? 0).toDouble()),
        _f(((r['ts'] as num?) ?? 0).toDouble()),
        '${r['tc']}',
        '${r['ic']}',
        _f(((r['it'] as num?) ?? 0).toDouble()),
        _f(((r['id'] as num?) ?? 0).toDouble()),
      ].join('|');
      names[u] = '${r['n']}';
    }
    final prodRows = await db.rawQuery(
        "SELECT sync_uuid AS u, stock_quantity AS s FROM products WHERE name LIKE ? AND COALESCE(sync_uuid, '') != ''",
        ['$kStressProductPrefix %']);
    final products = {for (final r in prodRows) r['u'] as String: _f(((r['s'] as num?) ?? 0).toDouble())};
    return {'customers': customers, 'names': names, 'products': products};
  }

  Map<String, double> _expectedBulkByUuid() => {
        for (final cu in truth.customers.values)
          if (cu.uuid.isNotEmpty) cu.uuid: truth.expectedBalance(cu.idx) - (truth.liveDeltas()[cu.idx] ?? 0),
      };

  Map<String, double> _expectedBulkStockByUuid() {
    final live = truth.liveStockDeltas();
    return {
      for (final pr in truth.products.values)
        if (pr.uuid.isNotEmpty) pr.uuid: truth.expectedStock(pr.id) - (live[pr.id] ?? 0),
    };
  }

  /// ينشر بصمة هذا الحاسوب (وتوقعات المرحلة الكبيرة إن كانت عنده) في فايربيس
  Future<void> publish() async {
    final dev = await FirebaseSyncConfig.getDeviceId();
    final fp = await localFingerprint();
    final hasTruth = truth.customers.isNotEmpty && bulkDone;
    final live = truth.liveDeltas();
    final liveStock = truth.liveStockDeltas();
    String? uuidOfIdx(int idx) => truth.customers[idx]?.uuid;
    await FirebaseFirestore.instance.collection('snapshots').doc('stress_$dev').set({
      'kind': 'stress_test',
      'deviceId': dev,
      'tag': cfg?.tag,
      'at': DateTime.now().toIso8601String(),
      'fingerprint': fp['customers'],
      'products': fp['products'],
      if (hasTruth) 'bulkExpected': _expectedBulkByUuid(),
      if (hasTruth) 'bulkStock': _expectedBulkStockByUuid(),
      'liveDelta': {
        for (final e in live.entries)
          if (uuidOfIdx(e.key) != null) uuidOfIdx(e.key)!: e.value,
      },
      'liveStockDelta': {
        for (final e in liveStock.entries)
          if ((truth.products[e.key]?.uuid ?? '').isNotEmpty) truth.products[e.key]!.uuid: e.value,
      },
    });
    _say('نُشرت بصمة هذا الحاسوب في فايربيس (${(fp['customers'] as Map).length} عميل)');
  }

  /// يقارن هذا الحاسوب بالبصمات المنشورة من الحواسيب الأخرى وبالمتوقع المجمّع
  Future<StressReport> compareDevices() async {
    final rep = StressReport('مقارنة الحاسوبين عبر فايربيس');
    final dev = await FirebaseSyncConfig.getDeviceId();
    final snap = await FirebaseFirestore.instance.collection('snapshots').get();
    final docs = snap.docs.where((d) => d.id.startsWith('stress_') && d.data()['kind'] == 'stress_test').toList();
    final mine = await localFingerprint();
    final myCust = Map<String, String>.from(mine['customers'] as Map);
    final myProd = Map<String, String>.from(mine['products'] as Map);
    final names = Map<String, String>.from(mine['names'] as Map);
    final peers = docs.where((d) => d.id != 'stress_$dev').toList();
    rep.summary['عملاء الاختبار هنا'] = myCust.length;
    rep.summary['حواسيب أخرى نشرت بصمتها'] = peers.length;
    if (peers.isEmpty) rep.notes.add('لا يوجد حاسوب آخر نشر بصمته بعد — انشرها من الحاسوب الآخر ثم أعد المقارنة');

    // 1) تطابق حرفي مع كل حاسوب آخر
    for (final d in peers) {
      final data = d.data();
      final theirs = Map<String, Object?>.from((data['fingerprint'] as Map?) ?? const {});
      final theirProd = Map<String, Object?>.from((data['products'] as Map?) ?? const {});
      rep.notes.add('الحاسوب ${data['deviceId']} نشر بصمته ${data['at']}');
      for (final u in {...myCust.keys, ...theirs.keys}) {
        final a = myCust[u];
        final b = theirs[u] as String?;
        rep.check(a == b,
            'العميل ${names[u] ?? u}: هنا [${a ?? 'غير موجود'}] وعند الآخر [${b ?? 'غير موجود'}] (رصيد|مجموع المعاملات|عددها|الفواتير|إجماليها|دينها)');
      }
      for (final u in {...myProd.keys, ...theirProd.keys}) {
        rep.check(myProd[u] == theirProd[u], 'المادة $u: رصيدها هنا ${myProd[u]} وعند الآخر ${theirProd[u]}');
      }
    }

    // 2) المتوقع المجمّع: توقعات المرحلة الكبيرة + فروق الجولة الحيّة من كل الحواسيب
    final all = docs.map((d) => d.data()).toList();
    final bulkDoc = all.where((m) => m['bulkExpected'] != null).toList();
    if (bulkDoc.isNotEmpty) {
      final bulk = Map<String, Object?>.from(bulkDoc.first['bulkExpected'] as Map);
      final bulkStock = Map<String, Object?>.from((bulkDoc.first['bulkStock'] as Map?) ?? const {});
      final delta = <String, double>{};
      final stockDelta = <String, double>{};
      // فروقي أنا من الذاكرة (أحدث من المنشور)، وفروق الآخرين من وثائقهم
      for (final m in all.where((m) => m['deviceId'] != dev)) {
        ((m['liveDelta'] as Map?) ?? const {}).forEach((k, v) => delta['$k'] = (delta['$k'] ?? 0) + (v as num).toDouble());
        ((m['liveStockDelta'] as Map?) ?? const {})
            .forEach((k, v) => stockDelta['$k'] = (stockDelta['$k'] ?? 0) + (v as num).toDouble());
      }
      truth.liveDeltas().forEach((idx, v) {
        final u = truth.customers[idx]?.uuid;
        if (u != null) delta[u] = (delta[u] ?? 0) + v;
      });
      truth.liveStockDeltas().forEach((pid, v) {
        final u = truth.products[pid]?.uuid;
        if (u != null) stockDelta[u] = (stockDelta[u] ?? 0) + v;
      });
      final db = await _db.database;
      for (final u in bulk.keys) {
        final exp = (bulk[u] as num).toDouble() + (delta[u] ?? 0);
        final r = await db.rawQuery('''
          SELECT COALESCE(SUM(t.amount_changed), 0) AS s, MAX(c.current_total_debt) AS b FROM customers c
          LEFT JOIN transactions t ON t.customer_id = c.id AND COALESCE(t.is_deleted, 0) = 0
          WHERE c.sync_uuid = ? AND COALESCE(c.is_deleted, 0) = 0''', [u]);
        final sum = ((r.first['s'] as num?) ?? double.nan).toDouble();
        final stored = ((r.first['b'] as num?) ?? double.nan).toDouble();
        rep.check((sum - exp).abs() < 0.01, 'العميل ${names[u] ?? u}: مجموع معاملاته هنا ${_f(sum)} والمتوقع ${_f(exp)}');
        rep.check((stored - exp).abs() < 0.01, 'العميل ${names[u] ?? u}: رصيده المخزّن هنا ${_f(stored)} والمتوقع ${_f(exp)}');
      }
      for (final u in bulkStock.keys) {
        final exp = (bulkStock[u] as num).toDouble() + (stockDelta[u] ?? 0);
        final got = double.tryParse(myProd[u] ?? '') ?? double.nan;
        rep.check((got - exp).abs() < 0.0001, 'المادة $u: رصيدها هنا ${myProd[u]} والمتوقع ${_f(exp)}');
      }
      rep.summary['عملاء قورنوا بالمتوقع'] = bulk.length;
    } else {
      rep.notes.add('لم ينشر الحاسوب الأول توقعات المرحلة الكبيرة بعد (زر «نشر البصمة» بعد التحقق)');
    }
    final pend = await pendingCounts();
    rep.summary['معلّق للرفع هنا'] = pend.entries.map((e) => '${e.key} ${e.value}').join('، ');
    if (pend.values.any((v) => v > 0)) {
      rep.notes.add('ما زالت هنا بيانات لم تُرفع — انتظر حتى تصير صفراً ثم أعد المقارنة');
    }
    await _writeReport(rep);
    _say(rep.ok ? '✅ الحاسوبان متطابقان' : '❌ ${rep.problems.length} اختلاف بين الحاسوبين');
    notifyListeners();
    return rep;
  }

  // ─────────────────────────── الجولة الحيّة (المزامنة مفعّلة) ───────────────────────────

  Future<void> runLive({required bool primary, int customers = 50}) async {
    if (running) return;
    final b = await blockers(needSyncOff: false);
    if (b.isNotEmpty) {
      for (final x in b) {
        _say('⛔ $x');
      }
      return;
    }
    running = true;
    _stop = false;
    status = 'الجولة الحيّة تعمل';
    notifyListeners();
    try {
      cfg ??= StressConfig(
        customers: 0,
        invoicesPerCustomer: 0,
        editsPerInvoice: 0,
        txPerCustomer: 0,
        txEditsMin: 0,
        txEditsMax: 0,
        products: 0,
        seed: DateTime.now().millisecondsSinceEpoch % 100000,
        tag: 'LIVE',
      );
      if (_journal == null) await load();
      _journal ??= File(p.join((await _stressDir()).path, 'journal.jsonl'));
      await _saveState();
      final db = await _db.database;
      // عملاء الجولة: أول N عميل اختبار بالاسم (الحاسوبان يختاران المجموعة نفسها)
      final rows = await db.rawQuery(
          "SELECT id, sync_uuid, name, phone FROM customers WHERE name LIKE ? AND COALESCE(is_deleted, 0) = 0 "
          "AND COALESCE(sync_uuid, '') != '' ORDER BY sync_uuid LIMIT ?",
          ['$kStressCustomerPrefix %', customers]);
      if (rows.length < 2) throw Exception('لا يوجد عملاء اختبار بعد على هذا الحاسوب');
      // المواد: من الحقيقة، وإلا من القاعدة (الحاسوب الثاني)
      if (truth.products.isEmpty) {
        final prods = await db.rawQuery(
            "SELECT id, sync_uuid, name, price1, cost_price, unit_hierarchy FROM products WHERE name LIKE ?",
            ['$kStressProductPrefix %']);
        for (final pr in prods) {
          var factor = 1;
          try {
            final h = jsonDecode('${pr['unit_hierarchy']}') as List;
            factor = ((h.first as Map)['quantity'] as num).toInt();
          } catch (_) {}
          _emit({
            'e': 'prod',
            'id': pr['id'],
            'uuid': pr['sync_uuid'] ?? '',
            'name': pr['name'],
            'factor': factor,
            'price': pr['price1'] ?? 1000,
            'cost': pr['cost_price'] ?? 0,
            'open': 0, // رصيد هذا الحاسوب لا يُتحقق منه بالحقيقة المحلية هنا (البصمة تقارنه)
          });
        }
      }
      if (truth.products.isEmpty) throw Exception('لا توجد مواد اختبار على هذا الحاسوب');
      final pool = <int>[];
      for (var k = 0; k < rows.length; k++) {
        final u = rows[k]['sync_uuid'] as String;
        var cu = truth.byUuid(u);
        if (cu == null) {
          final idx = 900000 + k;
          _emit({
            'e': 'cust',
            'i': idx,
            'id': rows[k]['id'],
            'uuid': u,
            'name': rows[k]['name'],
            'phone': rows[k]['phone'] ?? '',
          });
          _emit({'e': 'done', 'i': idx});
          cu = truth.customers[idx]!;
        }
        pool.add(cu.idx);
      }
      final rnd = Random(DateTime.now().microsecondsSinceEpoch);
      var n = 0;
      for (final idx in pool) {
        if (_stop) break;
        final cu = truth.customers[idx]!;
        n++;
        status = 'الجولة الحيّة: العميل $n/${pool.length}';
        notifyListeners();
        // معاملتان يدويتان وتعديل إحداهما
        final t1 = await _addManual(cu, rnd, live: true);
        await _addManual(cu, rnd, live: true);
        if (t1 != null) await _editManual(cu, t1, rnd, 0, live: true);
        // فاتورة دين وأربعة تعديلات منها نقل لعميل آخر من المجموعة
        final inv = await _createInvoice(cu, rnd, live: true, forceDebt: true);
        if (inv != null) {
          for (final k in const ['qty', 'price', 'paid', 'transfer']) {
            await _editInvoice(inv, [k], rnd, pool: pool, live: true);
          }
        }
        // تعديل الاسم والهاتف — من الحاسوب الأول فقط (صاحب بطاقة العميل)
        if (primary && n <= 10 && cu.idx < 900000) {
          await _renameCustomer(cu, rnd, suffix: 'حي');
          await _changePhone(cu, rnd);
        }
      }
      _say('✅ انتهت الجولة الحيّة — انتظر حتى يصير «المعلّق للرفع» صفراً على الحاسوبين، ثم «نشر البصمة» و«المقارنة»');
      status = 'انتهت الجولة الحيّة';
    } catch (e, st) {
      _say('❌ الجولة الحيّة توقفت: $e');
      print(st);
      status = 'توقف بخطأ';
    } finally {
      running = false;
      notifyListeners();
    }
  }
}
