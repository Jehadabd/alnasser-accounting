// test/sync_harness/harness.dart
// المتحكّم: يشغّل الأجهزة الوهمية والسحابة الوهمية، ويحفظ «الحقيقة»، ويفحص
// كل جهاز مقابلها. «الحقيقة» هنا نفس نموذج tools/sync_sim/world.py:
//   • رصيد العميل = مجموع معاملاته غير المحذوفة.
//   • حذف عميل على جهاز يحذف المعاملات التي كان ذلك الجهاز يعرفها لحظة الحذف.
//   • العميل ظاهر ⇔ لم يُحذف، أو بقيت له معاملة غير محذوفة.

// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:sqflite_common_ffi/sqflite_ffi.dart' show sqfliteFfiInit;
import 'package:sqflite_common_ffi/src/isolate.dart' show SqfliteIsolate, createIsolate;

import 'cloud.dart';
import 'device.dart';
import 'protocol.dart';

class DeviceHandle {
  final String name;
  final String dir;
  late Isolate isolate;
  SendPort? _cmd;
  final ReceivePort replies = ReceivePort();
  final Completer<void> _ready = Completer<void>();
  bool online;
  int _next = 1;
  final Map<int, Completer<Object?>> _pending = {};

  DeviceHandle(this.name, this.dir, this.online) {
    replies.listen((m) {
      if (m is SendPort) {
        _cmd = m;
        if (!_ready.isCompleted) _ready.complete();
      } else if (m is DeviceReply) {
        final c = _pending.remove(m.id);
        if (c == null) return;
        if (m.error != null) {
          c.completeError(DeviceError(name, m.error!));
        } else {
          c.complete(m.value);
        }
      }
    });
  }

  Future<void> get ready => _ready.future;

  Future<Object?> call(String op, [Map<String, Object?> args = const {}, Duration? timeout]) {
    final id = _next++;
    final c = Completer<Object?>();
    _pending[id] = c;
    _cmd!.send(DeviceCommand(id, op, args));
    return c.future.timeout(timeout ?? const Duration(minutes: 3));
  }
}

class DeviceError implements Exception {
  final String device;
  final String message;
  DeviceError(this.device, this.message);
  @override
  String toString() => '[$device] $message';
}

class TruthCustomer {
  final String name;
  final String creator;
  bool tomb = false;
  TruthCustomer(this.name, this.creator);
}

class TruthTx {
  final String cust;
  final String owner;
  double amount;
  String type;
  bool deleted = false;
  TruthTx(this.cust, this.owner, this.amount, this.type);
}

/// 📦 المخزن المشترك: الكمية = الرصيد الافتتاحي + الحركات − بنود الفواتير
/// المحفوظة (المعلّقة لا تخصم؛ إبطال دين الفاتورة بحذف العميل لا يعيد البضاعة).
class TruthProduct {
  final String name;
  final String creator;
  final int? carton;
  double opening;
  double movements = 0;
  TruthProduct(this.name, this.creator, this.opening, this.carton);
}

class TruthInvoice {
  String cust;
  final String creator;
  double total;
  double paid;
  String ptype; // دين | نقد
  String status; // محفوظة | معلقة
  /// عملاء أُبطل دين الفاتورة لهم بحذفهم. الإبطال نهائي لذلك العميل فقط:
  /// نقل الفاتورة لعميل آخر يعيد دينها عليه (صف دين جديد بمعرّف آخر).
  Set<String> voidedFor = {};
  bool get voided => voidedFor.contains(cust);
  Map<String, double> items = {}; // منتج ← كمية بالوحدة الأساسية
  List<Map<String, Object?>> specs = []; // البنود كما أُرسلت (لإعادة تعديلها: إرجاع)
  TruthInvoice(this.cust, this.creator, this.total, this.paid, this.ptype, this.status);

  double get contribution {
    if (voided || ptype != 'دين' || status != 'محفوظة') return 0.0;
    final r = total - paid;
    return r > 0 ? r : 0.0;
  }
}

class Truth {
  final Map<String, TruthCustomer> customers = {};
  final Map<String, TruthTx> txs = {};
  final Map<String, TruthInvoice> invoices = {};
  final Map<String, TruthProduct> products = {};

  /// نسخ المنتج الواحد (الاسم نفسه أُنشئ على جهازين قبل تزامنهما): كل نسخة ←
  /// الباقية منها. يضبطه Harness من مستندات السحابة بقاعدة التطبيق.
  Map<String, String> survivorOf = {};
  String survivor(String p) => survivorOf[p] ?? p;

  /// كمية المنتج = الرصيد الافتتاحي للنسخة الباقية + حركات كل النسخ − مبيعها.
  double stock(String p) {
    final s = survivor(p);
    final group = products.keys.where((u) => survivor(u) == s).toList();
    return products[s]!.opening +
        group.fold(0.0, (a, u) => a + products[u]!.movements) -
        invoices.values.where((i) => i.status == 'محفوظة').fold(
            0.0, (a, i) => a + group.fold(0.0, (b, u) => b + (i.items[u] ?? 0.0)));
  }

  double balance(String cust) =>
      txs.values.where((t) => t.cust == cust && !t.deleted).fold(0.0, (s, t) => s + t.amount) +
      invoices.values.where((i) => i.cust == cust).fold(0.0, (s, i) => s + i.contribution);

  bool hasActive(String cust) =>
      txs.values.any((t) => t.cust == cust && !t.deleted) ||
      invoices.values.any((i) => i.cust == cust && i.contribution > 0);

  bool visible(String cust) => !customers[cust]!.tomb || hasActive(cust);
}

class Harness {
  final FakeCloud cloud = FakeCloud();
  final Directory root;
  final Map<String, DeviceHandle> devices = {};
  final Truth truth = Truth();
  final Random rnd;
  final List<String> opErrors = [];
  int _marker = 0;
  static SqfliteIsolate? _sqlite; // خادم SQLite واحد لكل الاختبارات

  Harness({int seed = 0})
      : root = Directory.systemTemp.createTempSync('sync_harness_'),
        rnd = Random(seed);

  Map<String, Object> basePrefs() => {
        'firebase_sync_enabled': true,
        if (harsh) 'firebase_sync_auto_delete_days': 0, // التنظيف يحذف كل ما قرأه الجميع
      };

  /// الوضع القاسي: تنظيف ذكي للسحابة، نسخ احتياطي واستعادة، «بياناتي صحيحة»،
  /// فواتير معلّقة، وانضمام أجهزة جديدة متأخراً.
  bool harsh = false;
  final Map<String, String> _backups = {};
  int restores = 0, cleanups = 0, joins = 0, armored = 0, twinProducts = 0;
  int duplicateNamesRefused = 0;

  Future<DeviceHandle> spawn(String name,
      {String? dir,
      Map<String, Object>? prefs,
      Map<String, String>? secure,
      bool online = true}) async {
    dir ??= '${root.path}${Platform.pathSeparator}$name';
    final h = DeviceHandle(name, dir, online);
    cloud.setOnline(name, online);
    _sqlite ??= await createIsolate(sqfliteFfiInit);
    h.isolate = await Isolate.spawn(
      deviceMain,
      DeviceBoot(
        name: name,
        dir: dir!,
        cloud: cloud.sendPort,
        controller: h.replies.sendPort,
        sqlite: _sqlite!.sendPort,
        prefs: prefs ?? basePrefs(),
        secure: secure ?? {'firebase_sync_device_id': 'dev_$name'},
        online: online,
      ),
      debugName: name,
    );
    await h.ready;
    devices[name] = h;
    return h;
  }

  Future<void> start(int n, {bool init = true}) async {
    for (var i = 1; i <= n; i++) {
      await spawn('D$i');
    }
    if (init) await Future.wait([for (final d in devices.values) initDevice(d.name)]);
  }

  Future<void> initDevice(String name) async {
    final ok = await devices[name]!.call('init', const {}, const Duration(minutes: 5));
    if (ok != true) {
      final logs = await devices[name]!.call('logs', {'n': 60});
      throw StateError('init failed on $name:\n${(logs as List).join('\n')}');
    }
  }

  DeviceHandle d(String name) => devices[name]!;

  // ─────────────────────────── أفعال المستخدم ───────────────────────────

  Future<String?> addCustomer(String dev, String name, {String? phone}) async {
    final uuid = await d(dev).call('addCustomer', {'name': name, 'phone': phone}) as String?;
    if (uuid != null) truth.customers[uuid] = TruthCustomer(name, dev);
    return uuid;
  }

  Future<String?> addTx(String dev, String cust, double amount) async {
    final marker = 'H${++_marker}';
    final tu = await d(dev).call('addTx', {'cust': cust, 'amount': amount, 'marker': marker})
        as String?;
    if (tu != null) {
      truth.txs[tu] = TruthTx(cust, dev, amount, amount >= 0 ? 'manual_debt' : 'manual_payment');
    }
    progress('J addTx $dev tx=$tu cust=$cust amount=$amount online=${d(dev).online}');
    return tu;
  }

  Future<String?> addProduct(String dev, String name, double stock, {int? carton}) async {
    final u = await d(dev).call('addProduct', {'name': name, 'stock': stock, 'carton': carton})
        as String?;
    if (u != null) truth.products[u] = TruthProduct(name, dev, stock, carton);
    progress('J addProduct $dev prod=$u stock=$stock carton=$carton online=${d(dev).online}');
    return u;
  }

  Future<void> adjustStock(String dev, String prod, double delta) async {
    await d(dev).call('adjustStock', {'prod': prod, 'delta': delta});
    truth.products[prod]?.movements += delta;
    progress('J adjustStock $dev prod=$prod delta=$delta online=${d(dev).online}');
  }

  Future<void> purchase(String dev, String prod, double qty) async {
    await d(dev).call('purchase', {'prod': prod, 'qty': qty});
    truth.products[prod]?.movements += qty;
    progress('J purchase $dev prod=$prod qty=$qty online=${d(dev).online}');
  }

  /// أصناف موجودة على الجهاز (ومعروفة في الحقيقة)، لبنود فاتورة عشوائية.
  Future<List<Map<String, Object?>>> randomItems(String dev) async {
    final list = (await d(dev).call('products') as List)
        .cast<Map>()
        .map((m) => m.cast<String, Object?>())
        .where((m) => truth.products.containsKey(m['uuid']))
        .toList();
    if (list.isEmpty) return const [];
    final n = rnd.nextInt(3); // 0..2 أصناف
    final out = <Map<String, Object?>>[];
    for (var k = 0; k < n; k++) {
      final p = list[rnd.nextInt(list.length)];
      if (out.any((x) => x['prod'] == p['uuid'])) continue;
      out.add({
        'prod': p['uuid'],
        'qty': [1, 2, 3][rnd.nextInt(3)].toDouble(),
        'large': p['carton'] != null && rnd.nextDouble() < 0.3,
      });
    }
    return out;
  }

  /// 🔁 إرجاع بتعديل الفاتورة نفسها (لا تسوية): إنقاص كمية بند صنف بواحد
  /// (أو حذفه إن صار صفراً) وإنقاص المجموع بقيمته. فاتورة النقد يُنقص
  /// مسددها معها (أُعيد المبلغ للزبون).
  Future<bool> returnItems(String dev) async {
    final own = (await d(dev).call('ownInvoices') as List).cast<List>();
    final cands = own.where((x) {
      final t = truth.invoices[x[0]];
      return t != null && t.status == 'محفوظة' && t.specs.isNotEmpty;
    }).toList();
    if (cands.isEmpty) return false;
    final x = cands[rnd.nextInt(cands.length)];
    final u = x[0] as String;
    final t = truth.invoices[u]!;
    final specs = [for (final s in t.specs) Map<String, Object?>.from(s)];
    final k = rnd.nextInt(specs.length);
    final s = specs[k];
    final p = truth.products[s['prod']];
    final unitValue = (s['large'] == true && p?.carton != null) ? p!.carton!.toDouble() : 1.0;
    final qty = s['qty'] as double;
    if (qty <= 1) {
      specs.removeAt(k);
    } else {
      s['qty'] = qty - 1;
    }
    final newTotal = t.total - unitValue;
    if (newTotal <= 0) return false;
    final paid = t.ptype == 'نقد' ? newTotal : (t.paid > newTotal ? newTotal : t.paid);
    progress('J returnItems $dev inv=$u prod=${s['prod']} value=$unitValue');
    await saveInvoice(dev, x[1] as String, newTotal, paid, t.ptype, inv: u, items: specs);
    return true;
  }

  Map<String, double> _baseItems(List<Map<String, Object?>> items) {
    final out = <String, double>{};
    for (final it in items) {
      final p = truth.products[it['prod']];
      if (p == null) continue;
      final qty = it['qty'] as double;
      final base = (it['large'] == true && p.carton != null) ? qty * p.carton! : qty;
      out[it['prod'] as String] = (out[it['prod']] ?? 0) + base;
    }
    return out;
  }

  /// تعديلات رفضها التطبيق لأن السجل من نسخة احتياطية مستعادة والجهاز لم
  /// يلحق بالبقية بعد (DatabaseService.isRestoredRecordLocked).
  int lockedEdits = 0;

  bool _locked(Object? r, String what) {
    if (r is Map && r['locked'] == true) {
      lockedEdits++;
      progress('J locked $what');
      return true;
    }
    return false;
  }

  Future<void> editTx(String dev, String tx, double amount) async {
    final r = await d(dev).call('editTx', {'tx': tx, 'amount': amount});
    if (_locked(r, 'editTx $dev tx=$tx')) return;
    truth.txs[tx]?.amount = amount;
    progress('J editTx $dev tx=$tx amount=$amount online=${d(dev).online}');
  }

  Future<void> convertTx(String dev, String tx) async {
    final raw = await d(dev).call('convertTx', {'tx': tx});
    if (_locked(raw, 'convertTx $dev tx=$tx')) return;
    final r = (raw as Map).cast<String, Object?>();
    final t = truth.txs[tx];
    if (t != null) {
      t.amount = (r['amount'] as double?) ?? -t.amount;
      t.type = (r['type'] as String?) ??
          (t.type == 'manual_debt' ? 'manual_payment' : 'manual_debt');
    }
    progress('J convertTx $dev tx=$tx amount=${t?.amount} online=${d(dev).online}');
  }

  Future<void> deleteCustomer(String dev, String cust) async {
    final r = (await d(dev).call('deleteCustomer', {'cust': cust}) as Map).cast<String, Object?>();
    if (_locked(r, 'deleteCustomer $dev cust=$cust')) return;
    truth.customers[cust]?.tomb = true;
    for (final tu in (r['txs'] as List).cast<String>()) {
      truth.txs[tu]?.deleted = true;
    }
    for (final iu in (r['invs'] as List).cast<String>()) {
      final ti = truth.invoices[iu];
      if (ti != null) ti.voidedFor.add(cust);
    }
    progress('J deleteCustomer $dev cust=$cust txs=${(r['txs'] as List).length} '
        'invs=${(r['invs'] as List).length} online=${d(dev).online}');
  }

  /// حفظ فاتورة جديدة ([inv] = null) أو تعديل فاتورة قائمة، عبر مسار الشاشة.
  Future<String?> saveInvoice(String dev, String cust, double total, double paid, String ptype,
      {String? inv, List<Map<String, Object?>> items = const []}) async {
    final r = (await d(dev).call('saveInvoice', {
      'cust': cust,
      'total': total,
      'paid': paid,
      'ptype': ptype,
      'inv': inv,
      'items': items,
    }) as Map)
        .cast<String, Object?>();
    if (r['ok'] != true) {
      rejectedInvoices++;
      progress('J saveInvoice $dev inv=$inv cust=$cust REJECTED online=${d(dev).online}');
      return null; // رفضه التطبيق (تحقق مالي) — لا تغيير في الحقيقة
    }
    final uuid = r['uuid'] as String;
    final savedCust = (r['cust'] as String?) ?? cust;
    final savedPaid = (r['paid'] as num?)?.toDouble() ?? paid;
    progress('J saveInvoice $dev inv=$uuid cust=$savedCust total=$total paid=$savedPaid '
        '$ptype edit=${inv != null} online=${d(dev).online}');
    final prev = truth.invoices[uuid];
    final ti = TruthInvoice(savedCust, dev, total, savedPaid, ptype, 'محفوظة');
    if (prev != null) ti.voidedFor = {...prev.voidedFor}; // إبطال حذف العميل نهائي (له)
    ti.items = _baseItems(items);
    ti.specs = [for (final s in items) Map<String, Object?>.from(s)];
    truth.invoices[uuid] = ti;
    return uuid;
  }

  int rejectedInvoices = 0;

  Future<void> setOnline(String dev, bool online) async {
    final h = d(dev);
    if (h.online == online) return;
    h.online = online;
    if (online) {
      cloud.setOnline(dev, true);
      await h.call('setOnline', {'online': true});
    } else {
      await h.call('setOnline', {'online': false});
      cloud.setOnline(dev, false);
    }
  }

  final Map<String, int> _restarts = {};
  final List<Isolate> _frozen = [];

  /// إعادة تشغيل «التطبيق» على جهاز كقتل مفاجئ للعملية: الخيط ينتهي فوراً بلا
  /// إغلاق للقاعدة، ثم تُنسخ ملفات القاعدة كما هي على القرص (كانقطاع الكهرباء)
  /// ويُشغَّل الجهاز من النسخة بنفس الإعدادات، ثم يُهيّأ من جديد.
  Future<void> restart(String dev) async {
    final h = d(dev);
    progress('restart $dev: kill');
    final k = (_restarts[dev] ?? 0) + 1;
    _restarts[dev] = k;
    final newDir = '${root.path}${Platform.pathSeparator}${dev}_r$k';
    Directory(newDir).createSync(recursive: true);
    final saved = (await h.call('shutdown', {
      'copyTo': '$newDir${Platform.pathSeparator}debt_book.db',
    }) as Map)
        .cast<String, Object?>();
    // «قتل» العملية: الخيط يُجمَّد فلا يعمل بعدها أبداً (ولا يُغلق شيئاً)
    h.isolate.pause();
    _frozen.add(h.isolate);
    h.replies.close();
    cloud.dropDevice(dev);
    devices.remove(dev);
    await spawn(dev,
        dir: newDir,
        prefs: (saved['prefs'] as Map).cast<String, Object>(),
        secure: (saved['secure'] as Map).cast<String, String>(),
        online: h.online);
    progress('restart $dev: init');
    await initDevice(dev);
    progress('restart $dev: done');
  }

  Future<void> backup(String dev) async {
    final dir = Directory('${root.path}${Platform.pathSeparator}backups')..createSync(recursive: true);
    final path = '${dir.path}${Platform.pathSeparator}${dev}_${DateTime.now().microsecondsSinceEpoch}.db';
    await d(dev).call('backup', {'path': path});
    _backups[dev] = path;
    progress('J backup $dev online=${d(dev).online}');
  }

  /// استعادة نسخة احتياطية قديمة (كاستعادة Dropbox: الملف يُستبدل والتطبيق مغلق).
  /// مسموحة فقط إن لم يبقَ على الجهاز عمل غير مرفوع — وإلا يضيع فعلاً.
  Future<bool> restoreBackup(String dev) async {
    final path = _backups.remove(dev);
    if (path == null) return false;
    if ((await d(dev).call('pendingOwnWork') as int) > 0) return false;
    final h = d(dev);
    progress('J restore $dev online=${h.online}');
    final k = (_restarts[dev] ?? 0) + 1;
    _restarts[dev] = k;
    final newDir = '${root.path}${Platform.pathSeparator}${dev}_r$k';
    Directory(newDir).createSync(recursive: true);
    final saved = (await h.call('shutdown') as Map).cast<String, Object?>();
    h.isolate.pause();
    _frozen.add(h.isolate);
    h.replies.close();
    cloud.dropDevice(dev);
    devices.remove(dev);
    File(path).copySync('$newDir${Platform.pathSeparator}debt_book.db');
    final prefs = (saved['prefs'] as Map).cast<String, Object>()
      ..['sync_db_restored_pending'] = true
      ..['sync_db_restored_rows_marked'] = false;
    await spawn(dev,
        dir: newDir,
        prefs: prefs,
        secure: (saved['secure'] as Map).cast<String, String>(),
        online: h.online);
    await initDevice(dev);
    restores++;
    return true;
  }

  Future<void> joinNewDevice() async {
    final name = 'D${devices.length + joins + 1}';
    if (devices.containsKey(name)) return;
    progress('J join $name');
    await spawn(name);
    await initDevice(name);
    joins++;
  }

  Future<String?> suspendInvoice(String dev, String cust, double total,
      {List<Map<String, Object?>> items = const []}) async {
    final r = (await d(dev).call('suspendInvoice', {
      'cust': cust,
      'total': total,
      'items': items,
      'paid': 0.0,
      'ptype': 'دين',
    }) as Map)
        .cast<String, Object?>();
    final uuid = r['uuid'] as String?;
    final c = r['cust'] as String?;
    if (uuid == null || c == null) return null;
    truth.invoices[uuid] = TruthInvoice(c, dev, total, 0.0, 'دين', 'معلقة')
      ..items = _baseItems(items);
    return uuid;
  }

  Future<void> restartAll() async {
    for (final n in devices.keys.toList()) {
      await restart(n);
    }
  }

  // ─────────────────────────── الاستقرار والفحص ───────────────────────────

  Future<void> waitCloudQuiet({Duration quiet = const Duration(milliseconds: 1500)}) async {
    final deadline = DateTime.now().add(const Duration(minutes: 3));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (DateTime.now().difference(cloud.lastWriteAt) >= quiet) return;
    }
  }

  /// كل الأجهزة متصلة، ثم دورات مزامنة حتى تهدأ السحابة وتتطابق الأجهزة مع الحقيقة.
  Future<List<String>> settle({int rounds = 4}) async {
    for (final n in devices.keys.toList()) {
      await setOnline(n, true);
    }
    List<String> errs = const [];
    for (var r = 0; r < rounds; r++) {
      await waitCloudQuiet();
      await Future.wait([
        for (final h in devices.values)
          h.call('kick').catchError((Object e) {
            opErrors.add('kick ${h.name}: $e');
            return null;
          })
      ]);
      await waitCloudQuiet();
      await _waitBootstraps();
      errs = await check();
      if (errs.isEmpty) return errs;
    }
    return errs;
  }

  /// جهاز جديد/مستعيد ينتظر إعادة بثّ الأجهزة (استطلاع كل 10 ثوانٍ ثم سحب
  /// كامل): فحصه قبل انتهاء ذلك يُظهر نقصاً مؤقتاً لا خللاً.
  Future<void> _waitBootstraps() async {
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    while (DateTime.now().isBefore(deadline)) {
      var busy = false;
      for (final h in devices.values) {
        final st = (await h.call('state') as Map).cast<String, Object?>();
        if (st['bootstrapping'] == true) busy = true;
      }
      if (!busy) return;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }

  /// الباقية من كل مجموعة نسخ، بقاعدة التطبيق (ProductSyncService._copyWins)
  /// على مستندات السحابة: وقت التعديل الأحدث، والمعروف يغلب المجهول، ثم
  /// المعرّف الأكبر.
  Map<String, String> productSurvivors() {
    final docs = cloud.collection('products');
    final byName = <String, List<String>>{};
    truth.products.forEach((u, p) => byName.putIfAbsent(p.name, () => []).add(u));
    bool wins(String a, String b) {
      final ta = DateTime.tryParse(docs[a]?['last_modified_at']?.toString() ?? '');
      final tb = DateTime.tryParse(docs[b]?['last_modified_at']?.toString() ?? '');
      if (ta != null && tb != null) {
        if (ta.isAfter(tb)) return true;
        if (tb.isAfter(ta)) return false;
      } else if (ta != null || tb != null) {
        return ta != null;
      }
      return a.compareTo(b) > 0;
    }

    final out = <String, String>{};
    for (final g in byName.values) {
      if (g.length < 2) continue;
      var best = g.first;
      for (final u in g.skip(1)) {
        if (wins(u, best)) best = u;
      }
      for (final u in g) {
        out[u] = best;
      }
    }
    return out;
  }

  Future<List<String>> check() async {
    final errs = <String>[];
    truth.survivorOf = productSurvivors();
    for (final h in devices.values) {
      final st = (await h.call('state') as Map).cast<String, Object?>();
      final rows = <String, Map<String, Object?>>{};
      for (final c in (st['customers'] as List).cast<Map>()) {
        final u = c['uuid'] as String?;
        if (u == null) continue;
        if (rows.containsKey(u)) errs.add('${h.name}: العميل ${c['name']} مكرر (صفّان بنفس المعرّف)');
        rows[u] = c.cast<String, Object?>();
      }
      for (final e in truth.customers.entries) {
        final cu = e.key;
        final row = rows[cu];
        final vis = truth.visible(cu);
        final shown = row != null && ((row['del'] as int?) ?? 0) == 0;
        if (vis != shown) {
          errs.add('${h.name}: العميل ${e.value.name} ${shown ? "ظاهر" : "مخفي/غائب"} '
              'والصحيح ${vis ? "ظاهر برصيد ${truth.balance(cu)}" : "مخفي"}');
          continue;
        }
        if (!vis) continue;
        final debt = row!['debt'] as double;
        final sum = row['sum'] as double;
        final want = truth.balance(cu);
        if ((debt - want).abs() > 0.01 || (sum - want).abs() > 0.01) {
          errs.add('${h.name}: رصيد ${e.value.name} = $debt (مجموع معاملاته $sum) والصحيح $want');
        }
      }
      for (final e in rows.entries) {
        if (truth.customers.containsKey(e.key)) continue;
        if (((e.value['del'] as int?) ?? 0) == 0) {
          errs.add('${h.name}: عميل غير موجود في الحقيقة ظاهر: ${e.value['name']}');
        }
      }
      final pend = st['pending'] as int? ?? 0;
      if (pend > 0) {
        final rowsP = (st['txs'] as List).cast<Map>().where((t) =>
            (t['up'] == 0 || t['up'] == null) && (t['mine'] != 0 || t['del'] == 1));
        final det = rowsP
            .take(2)
            .map((t) => '${t['uuid']} مبلغ=${t['amount']} محذوفة=${t['del']} لي=${t['mine']} '
                'عميل=${t['cust'] == null ? 'بلا' : (truth.customers[t['cust']]?.name ?? 'غير معروف')} '
                'فاتورة=${t['inv'] ?? '-'}')
            .join(' | ');
        errs.add('${h.name}: $pend معاملة لم تُرفع: $det');
      }
      final stocks = (st['products'] as Map?)?.cast<String, Object?>() ?? const {};
      for (final e in truth.products.entries) {
        final v = stocks[e.key] as double?;
        if (truth.survivor(e.key) != e.key) {
          // نسخة خاسرة: دُمجت في الباقية ولا يبقى لها صف
          if (v != null) {
            errs.add('${h.name}: نسخة مكررة من المنتج ${e.value.name} ($v) '
                'والباقية ${truth.survivor(e.key)}');
          }
          continue;
        }
        final want = truth.stock(e.key);
        if (v == null) {
          errs.add('${h.name}: المنتج ${e.value.name} غائب');
        } else if ((v - want).abs() > 0.01) {
          errs.add('${h.name}: مخزون ${e.value.name} = $v والصحيح $want');
        }
      }
      if (st['recovering'] == true) errs.add('${h.name}: ما زال في وضع الاستعادة');
      if (st['bootstrapping'] == true) errs.add('${h.name}: ما زال في التمهيد');
    }
    if (cloud.internalErrors.isNotEmpty) {
      errs.add('أخطاء داخل السحابة الوهمية: ${cloud.internalErrors.first}');
    }
    return errs;
  }

  /// شرح مفصّل لكمية منتج: الحقيقة، ثم حركات وبنود كل جهاز.
  Future<String> explainStock(String prod) async {
    final p = truth.products[prod]!;
    final b = StringBuffer();
    b.writeln('══ المنتج $prod (${p.name}) الحقيقة=${truth.stock(prod)} '
        'افتتاحي=${p.opening} حركات=${p.movements} منشئ=${p.creator} كرتون=${p.carton}');
    truth.invoices.forEach((u, i) {
      final q = i.items[prod];
      if (q != null) b.writeln('  حقيقة فاتورة $u ${i.status} كمية=$q منشئ=${i.creator}');
    });
    final s = truth.survivor(prod);
    final group = truth.products.keys.where((u) => truth.survivor(u) == s).toList();
    if (group.length > 1) {
      b.writeln('  نسخ: $group ← الباقية $s');
      for (final u in group) {
        b.writeln('  نسخة $u منشئ=${truth.products[u]!.creator} '
            'افتتاحي=${truth.products[u]!.opening} حركات=${truth.products[u]!.movements} '
            'مستند=${cloud.collection('products')[u]?['last_modified_at']}');
      }
    }
    for (final h in devices.values) {
      for (final u in group) {
        final r = (await h.call('stockDetail', {'prod': u}) as Map).cast<String, Object?>();
        b.writeln('── ${h.name} [$u] كمية=${r['stock']}');
        for (final m in (r['movements'] as List)) {
          b.writeln('   حركة $m');
        }
        for (final it in (r['items'] as List)) {
          b.writeln('   بند $it');
        }
      }
      if (group.length > 1) {
        b.writeln('   تحويلات ${await h.call('productAliases')}');
      }
    }
    return b.toString();
  }

  /// شرح مفصّل لعميل: الحقيقة، ثم كل جهاز، ثم السحابة.
  Future<String> explain(String cust) async {
    final b = StringBuffer();
    b.writeln('══ العميل $cust (${truth.customers[cust]?.name}) الحقيقة=${truth.balance(cust)}');
    truth.txs.forEach((u, t) {
      if (t.cust == cust) b.writeln('  حقيقة معاملة $u ${t.amount} ${t.deleted ? "محذوفة" : ""} مالك=${t.owner}');
    });
    truth.invoices.forEach((u, i) {
      if (i.cust == cust) {
        b.writeln('  حقيقة فاتورة $u ${i.ptype} total=${i.total} paid=${i.paid} '
            'مساهمة=${i.contribution} منشئ=${i.creator}${i.voided ? " مُبطلة" : ""}');
      }
    });
    for (final h in devices.values) {
      final r = (await h.call('custDetail', {'cust': cust}) as Map).cast<String, Object?>();
      b.writeln('── ${h.name}');
      for (final i in (r['invoices'] as List? ?? const [])) {
        b.writeln('   فاتورة $i');
      }
      for (final t in (r['txs'] as List? ?? const [])) {
        b.writeln('   معاملة $t');
      }
    }
    b.writeln('── السحابة');
    cloud.collection('invoices').forEach((id, d) {
      if (d['customer_sync_uuid'] == cust) {
        final txs = (d['transactions'] as List? ?? const [])
            .map((t) => '(${(t as Map)['transaction_uuid']} ${t['amount_changed']} del=${t['is_deleted']})')
            .join(' ');
        b.writeln('   فاتورة $id ${d['payment_type']} total=${d['total_amount']} '
            'paid=${d['amount_paid_on_invoice']} v=${d['version']} رافع=${d['uploaderDeviceId']} $txs');
      }
    });
    cloud.collection('transactions').forEach((id, d) {
      if (d['customerSyncUuid'] == cust) {
        b.writeln('   معاملة $id ${d['amountChanged']} del=${d['isDeleted']} inv=${d['invoiceSyncUuid']} من=${d['deviceId']}');
      }
    });
    return b.toString();
  }

  Future<List<String>> deviceErrors() async {
    final out = <String>[];
    for (final h in devices.values) {
      final e = (await h.call('errors') as List).cast<String>();
      for (final x in e) {
        out.add('${h.name}: $x');
      }
    }
    return out;
  }

  /// [keepFiles]: تجربة فاشلة تُبقي مجلدها (قواعد الأجهزة وسجلاتها) للتشخيص.
  Future<void> dispose({bool keepFiles = false}) async {
    for (final h in devices.values) {
      h.isolate.pause();
      _frozen.add(h.isolate);
      h.replies.close();
    }
    devices.clear();
    for (final iso in _frozen) {
      iso.kill();
    }
    cloud.close();
    if (keepFiles) {
      progress('J kept ${root.path}');
      return;
    }
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  }

  // ─────────────────────────── الفوضى ───────────────────────────

  // لكل عملية اختبار ملفها: دفعات متوازية كانت تخلط سجلاتها في ملف واحد
  static final File _progress = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}sync_harness_progress_$pid.log');
  static void progress(String line) {
    try {
      _progress.writeAsStringSync('${DateTime.now().toIso8601String()} $line\n',
          mode: FileMode.append, flush: true);
    } catch (_) {}
  }

  /// TWINS=true: أصناف جديدة أكثر، وأغلبها بالاسم نفسه لصنف على جهاز آخر
  /// (ضغط على دمج النسخ — 21.6 في الدليل).
  static const _twinsBoost = bool.fromEnvironment('TWINS');

  static const _amounts = [50.0, 100.0, 250.0, 400.0, 1000.0, -60.0, -150.0, -500.0];
  static const _edits = [10.0, 75.0, 300.0, 900.0];

  /// عمليات عشوائية على أجهزة عشوائية (نفس توزيع tools/sync_sim/run.py
  /// لعمليات العملاء والمعاملات).
  Future<void> chaos(int ops, {bool restarts = true, bool invoices = true}) async {
    // 📦 كتالوج بداية: صنف بكرتون، صنف بالقطعة، صنف يبدأ من صفر
    if (truth.products.isEmpty && invoices) {
      final first = devices.keys.first;
      await addProduct(first, 'صنف أ', 100, carton: 12);
      await addProduct(first, 'صنف ب', 50);
      await addProduct(first, 'صنف ج', 0, carton: 6);
    }
    for (var i = 0; i < ops; i++) {
      final names = devices.keys.toList();
      final dev = names[rnd.nextInt(names.length)];
      final r = rnd.nextDouble();
      progress('op $i dev=$dev r=${r.toStringAsFixed(3)}');
      try {
        // 📦 عمليات المخزون: صنف جديد، تعديل يدوي، شراء
        if (invoices) {
          final y = rnd.nextDouble();
          if (y < 0.08) {
            final list = (await d(dev).call('products') as List)
                .cast<Map>()
                .map((m) => m['uuid'] as String)
                .where(truth.products.containsKey)
                .toList();
            if (y < (_twinsBoost ? 0.04 : 0.012) || list.isEmpty) {
              // أحياناً: الاسم نفسه لصنف لم يصل هذا الجهاز بعد (أُنشئ على جهاز
              // آخر) — نسختان من المنتج نفسه تُدمجان عند التزامن
              final here = (await d(dev).call('products') as List)
                  .cast<Map>()
                  .map((m) => m['name'] as String)
                  .toSet();
              final twins = truth.products.values.where((p) => !here.contains(p.name)).toList();
              // (بلا TWINS: nextBool كما كان، فتبقى البذور قابلة للإعادة)
              if (twins.isNotEmpty && (_twinsBoost ? rnd.nextDouble() < 0.8 : rnd.nextBool())) {
                final t = twins[rnd.nextInt(twins.length)];
                // null = وصل الصنف نفسه لحظة الحفظ فرفض التطبيق الاسم المكرر
                if (await addProduct(dev, t.name, [0.0, 10.0, 40.0][rnd.nextInt(3)],
                        carton: t.carton) !=
                    null) {
                  twinProducts++;
                } else {
                  duplicateNamesRefused++;
                }
              } else {
                await addProduct(dev, 'صنف $dev-$i', [0.0, 10.0, 40.0][rnd.nextInt(3)],
                    carton: rnd.nextBool() ? 12 : null);
              }
            } else if (y < 0.045) {
              await adjustStock(dev, list[rnd.nextInt(list.length)],
                  [-5.0, -2.0, 1.0, 3.0, 10.0][rnd.nextInt(5)]);
            } else {
              await purchase(dev, list[rnd.nextInt(list.length)],
                  [6.0, 12.0, 24.0][rnd.nextInt(3)]);
            }
            await Future<void>.delayed(Duration(milliseconds: rnd.nextInt(40)));
            continue;
          }
        }
        if (harsh) {
          final x = rnd.nextDouble();
          if (x < 0.02) {
            cleanups++;
            progress('J smartPipe $dev online=${d(dev).online}');
            await d(dev).call('smartPipe');
            continue;
          } else if (x < 0.035) {
            if (await restoreBackup(dev)) continue;
          } else if (x < 0.06) {
            if (!_backups.containsKey(dev)) await backup(dev);
          } else if (x < 0.07) {
            final vis = (await d(dev).call('visibleCustomers') as List).cast<String>()
                .where(truth.customers.containsKey)
                .toList();
            if (vis.isNotEmpty) {
              armored++;
              final ac = vis[rnd.nextInt(vis.length)];
              progress('J armored $dev cust=$ac online=${d(dev).online}');
              await d(dev).call('armoredPush', {'cust': ac});
            }
            continue;
          } else if (x < 0.085) {
            final vis = (await d(dev).call('visibleCustomers') as List).cast<String>()
                .where(truth.customers.containsKey)
                .toList();
            if (vis.isNotEmpty) {
              await suspendInvoice(dev, vis[rnd.nextInt(vis.length)], [300.0, 800.0][rnd.nextInt(2)],
                  items: await randomItems(dev));
            }
            continue;
          } else if (x < 0.0875 && joins < 2) {
            await joinNewDevice();
            continue;
          }
        }
        if (r < 0.40) {
          final vis = (await d(dev).call('visibleCustomers') as List).cast<String>()
              .where(truth.customers.containsKey)
              .toList();
          if (vis.isEmpty) {
            await addCustomer(dev, 'عميل $dev-$i');
          } else {
            await addTx(dev, vis[rnd.nextInt(vis.length)], _amounts[rnd.nextInt(_amounts.length)]);
          }
        } else if (r < 0.55) {
          final own = (await d(dev).call('ownManualTxs') as List).cast<List>();
          own.removeWhere((x) => !truth.txs.containsKey(x[0]));
          if (own.isNotEmpty) {
            final x = own[rnd.nextInt(own.length)];
            final mag = _edits[rnd.nextInt(_edits.length)];
            await editTx(dev, x[0] as String, x[1] == 'manual_payment' ? -mag : mag);
          }
        } else if (r < 0.60) {
          final own = (await d(dev).call('ownManualTxs') as List).cast<List>();
          own.removeWhere((x) => !truth.txs.containsKey(x[0]));
          if (own.isNotEmpty) await convertTx(dev, own[rnd.nextInt(own.length)][0] as String);
        } else if (r < 0.63) {
          await addCustomer(dev, 'عميل $dev-$i');
        } else if (r < 0.71 && invoices) {
          final vis = (await d(dev).call('visibleCustomers') as List).cast<String>()
              .where(truth.customers.containsKey)
              .toList();
          if (vis.isNotEmpty) {
            final total = [500.0, 1200.0, 3000.0, 750.0][rnd.nextInt(4)];
            final ptype = rnd.nextInt(3) < 2 ? 'دين' : 'نقد';
            var paid = ptype == 'دين' ? 0.0 : total;
            if (ptype == 'دين' && rnd.nextDouble() < 0.3) paid = [100.0, 200.0][rnd.nextInt(2)];
            await saveInvoice(dev, vis[rnd.nextInt(vis.length)], total, paid, ptype,
                items: await randomItems(dev));
          }
        } else if (r < 0.76 && invoices && rnd.nextBool() && await returnItems(dev)) {
          // 🔁 إرجاع بتعديل الفاتورة
        } else if (r < 0.76 && invoices) {
          final own = (await d(dev).call('ownInvoices') as List).cast<List>();
          own.removeWhere((x) => !truth.invoices.containsKey(x[0]));
          if (own.isNotEmpty) {
            final x = own[rnd.nextInt(own.length)];
            final total = [400.0, 900.0, 2600.0][rnd.nextInt(3)];
            final ptype = rnd.nextBool() ? 'دين' : 'نقد';
            // أحياناً: نقل الفاتورة لعميل آخر (دينها ينتقل معها)
            var cust = x[1] as String;
            if (rnd.nextDouble() < 0.25) {
              final vis = (await d(dev).call('visibleCustomers') as List).cast<String>()
                  .where(truth.customers.containsKey)
                  .toList();
              if (vis.isNotEmpty) cust = vis[rnd.nextInt(vis.length)];
            }
            await saveInvoice(dev, cust, total, ptype == 'دين' ? 0.0 : total, ptype,
                inv: x[0] as String, items: await randomItems(dev));
          }
        } else if (r < 0.80) {
          final vis = (await d(dev).call('visibleCustomers') as List).cast<String>();
          if (vis.isNotEmpty) await d(dev).call('viewCustomer', {'cust': vis[rnd.nextInt(vis.length)]});
        } else if (r < 0.815) {
          final vis = (await d(dev).call('visibleCustomers') as List).cast<String>()
              .where(truth.customers.containsKey)
              .toList();
          if (vis.isNotEmpty) await deleteCustomer(dev, vis[rnd.nextInt(vis.length)]);
        } else if (r < 0.87) {
          await setOnline(dev, false);
        } else if (r < 0.88 && restarts) {
          await restart(dev);
        } else {
          await setOnline(dev, true);
        }
      } catch (e) {
        opErrors.add('op $i on $dev: $e');
      }
      await Future<void>.delayed(Duration(milliseconds: rnd.nextInt(40)));
    }
  }
}
