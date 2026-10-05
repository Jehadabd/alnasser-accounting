// lib/devtools/stress_test/stress_model.dart
//
// 🧪 «الحقيقة المتوقعة» لاختبار التحمّل: سجل مستقل عن قاعدة البيانات لكل ما
// قصد الاختبار فعله (العملاء، المعاملات، الفواتير، المواد). في النهاية تُقارن
// قاعدة البيانات بهذا السجل رقماً برقم.
//
// السجل يُكتب حدثاً بحدث في ملف (journal.jsonl) بعد نجاح كل عملية، فإن أُغلق
// البرنامج أثناء الاختبار يُعاد بناؤه من الملف ويكمل من حيث توقف.

import 'dart:convert';

class StressConfig {
  StressConfig({
    required this.customers,
    required this.invoicesPerCustomer,
    required this.editsPerInvoice,
    required this.txPerCustomer,
    required this.txEditsMin,
    required this.txEditsMax,
    required this.products,
    required this.seed,
    required this.tag,
  });

  final int customers;
  final int invoicesPerCustomer;
  final int editsPerInvoice;
  final int txPerCustomer;
  final int txEditsMin;
  final int txEditsMax;
  final int products;
  final int seed;

  /// رمز قصير يميّز بيانات هذه التشغيلة (يظهر في أسماء العملاء والمواد)
  final String tag;

  Map<String, Object?> toJson() => {
        'customers': customers,
        'invoicesPerCustomer': invoicesPerCustomer,
        'editsPerInvoice': editsPerInvoice,
        'txPerCustomer': txPerCustomer,
        'txEditsMin': txEditsMin,
        'txEditsMax': txEditsMax,
        'products': products,
        'seed': seed,
        'tag': tag,
      };

  factory StressConfig.fromJson(Map<String, Object?> m) => StressConfig(
        customers: (m['customers'] as num).toInt(),
        invoicesPerCustomer: (m['invoicesPerCustomer'] as num).toInt(),
        editsPerInvoice: (m['editsPerInvoice'] as num).toInt(),
        txPerCustomer: (m['txPerCustomer'] as num).toInt(),
        txEditsMin: (m['txEditsMin'] as num).toInt(),
        txEditsMax: (m['txEditsMax'] as num).toInt(),
        products: (m['products'] as num).toInt(),
        seed: (m['seed'] as num).toInt(),
        tag: m['tag'] as String,
      );

  int get totalInvoiceSaves => customers * invoicesPerCustomer * (1 + editsPerInvoice);
}

class TProduct {
  TProduct(this.id, this.uuid, this.name, this.factor, this.price, this.cost, this.opening);
  final int id;
  final String uuid;
  final String name;

  /// كم قطعة في الكرتون
  final int factor;
  final double price;
  final double cost;
  final double opening;
}

class TCustomer {
  TCustomer(this.idx, this.id, this.uuid, this.name, this.phone);
  final int idx;
  final int id;
  final String uuid;
  String name;
  String phone;

  /// معرّف المعاملة اليدوية ← مبلغها المقصود (موجب دين، سالب تسديد)
  final Map<int, double> manual = {};
  bool done = false;
}

class TInvoice {
  TInvoice(this.id, this.uuid, this.customerIdx, this.total, this.paid, this.type, this.qty, {this.live = false});
  final int id;
  final String uuid;
  int customerIdx;
  double total;
  double paid;
  String type;

  /// معرّف المادة ← الكمية بالوحدة الأساسية
  Map<int, double> qty;
  final bool live;

  double get debt => type == 'دين' ? total - paid : 0;
}

/// الحقيقة المتوقعة كلها + إعادة بنائها من سجل الأحداث.
class StressTruth {
  final Map<int, TProduct> products = {};
  final Map<int, TCustomer> customers = {}; // idx ← عميل
  final Map<int, TInvoice> invoices = {}; // id ← فاتورة
  final Map<int, double> liveManual = {}; // معاملات الجولة الحيّة: id ← مبلغ (للفروق)
  final Map<int, int> liveManualCustomer = {}; // id ← idx العميل
  final Map<String, int> refusals = {}; // سبب رفض البرنامج ← العدد
  int events = 0;

  TCustomer? byId(int id) {
    for (final c in customers.values) {
      if (c.id == id) return c;
    }
    return null;
  }

  TCustomer? byUuid(String uuid) {
    for (final c in customers.values) {
      if (c.uuid == uuid) return c;
    }
    return null;
  }

  double manualSum(int idx) =>
      (customers[idx]?.manual.values.fold<double>(0.0, (a, b) => a + b) ?? 0) +
      liveManual.entries.where((e) => liveManualCustomer[e.key] == idx).fold<double>(0.0, (a, e) => a + e.value);

  double expectedBalance(int idx) =>
      manualSum(idx) +
      invoices.values.where((i) => i.customerIdx == idx).fold<double>(0.0, (a, i) => a + i.debt);

  double expectedStock(int productId) {
    final p = products[productId];
    if (p == null) return 0;
    var sold = 0.0;
    for (final i in invoices.values) {
      sold += i.qty[productId] ?? 0;
    }
    return p.opening - sold;
  }

  /// الفرق الذي أحدثته الجولة الحيّة على رصيد كل عميل (يُنشر لتجمعه الأجهزة)
  Map<int, double> liveDeltas() {
    final out = <int, double>{};
    liveManual.forEach((id, amt) {
      final c = liveManualCustomer[id];
      if (c != null) out[c] = (out[c] ?? 0) + amt;
    });
    for (final i in invoices.values.where((i) => i.live)) {
      out[i.customerIdx] = (out[i.customerIdx] ?? 0) + i.debt;
    }
    return out;
  }

  Map<int, double> liveStockDeltas() {
    final out = <int, double>{};
    for (final i in invoices.values.where((i) => i.live)) {
      i.qty.forEach((pid, q) => out[pid] = (out[pid] ?? 0) - q);
    }
    return out;
  }

  /// يطبّق حدثاً واحداً (من السجل أو لحظة وقوعه)
  void apply(Map<String, Object?> e) {
    events++;
    switch (e['e']) {
      case 'prod':
        final p = TProduct(
          (e['id'] as num).toInt(),
          e['uuid'] as String,
          e['name'] as String,
          (e['factor'] as num).toInt(),
          (e['price'] as num).toDouble(),
          (e['cost'] as num).toDouble(),
          (e['open'] as num).toDouble(),
        );
        products[p.id] = p;
        break;
      case 'cust':
        final i = (e['i'] as num).toInt();
        customers[i] = TCustomer(i, (e['id'] as num).toInt(), e['uuid'] as String, e['name'] as String,
            (e['phone'] as String?) ?? '');
        break;
      case 'custEdit':
        final c = customers[(e['i'] as num).toInt()];
        if (c != null) {
          c.name = e['name'] as String;
          c.phone = (e['phone'] as String?) ?? '';
        }
        break;
      case 'tx':
        final c = customers[(e['i'] as num).toInt()];
        c?.manual[(e['id'] as num).toInt()] = (e['amt'] as num).toDouble();
        break;
      case 'ltx':
        final id = (e['id'] as num).toInt();
        liveManual[id] = (e['amt'] as num).toDouble();
        liveManualCustomer[id] = (e['i'] as num).toInt();
        break;
      case 'inv':
        final id = (e['id'] as num).toInt();
        final q = <int, double>{};
        ((e['q'] as Map?) ?? const {}).forEach((k, v) => q[int.parse('$k')] = (v as num).toDouble());
        final existing = invoices[id];
        if (existing == null) {
          invoices[id] = TInvoice(id, e['uuid'] as String, (e['c'] as num).toInt(), (e['total'] as num).toDouble(),
              (e['paid'] as num).toDouble(), e['type'] as String, q,
              live: e['live'] == true);
        } else {
          existing
            ..customerIdx = (e['c'] as num).toInt()
            ..total = (e['total'] as num).toDouble()
            ..paid = (e['paid'] as num).toDouble()
            ..type = e['type'] as String
            ..qty = q;
        }
        break;
      case 'done':
        customers[(e['i'] as num).toInt()]?.done = true;
        break;
      case 'refuse':
        final k = e['why'] as String;
        refusals[k] = (refusals[k] ?? 0) + 1;
        break;
    }
  }

  static StressTruth replay(Iterable<String> lines) {
    final t = StressTruth();
    for (final l in lines) {
      if (l.trim().isEmpty) continue;
      try {
        t.apply(jsonDecode(l) as Map<String, Object?>);
      } catch (_) {
        // سطر مبتور في آخر الملف (انقطاع أثناء الكتابة) — يُتجاهل
      }
    }
    return t;
  }
}
