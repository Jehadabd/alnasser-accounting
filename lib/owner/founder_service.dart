// lib/owner/founder_service.dart
//
// 👷 المؤسسون / الفنيون ونقاطهم (ميزة حساب المالك).
//
// مصدر النقاط هو الفاتورة نفسها، لا سجل محلي منفصل:
//   نقاط الفاتورة = (صافي الفاتورة ÷ 100,000) × معدل نقاط الفاتورة
//   صافي الفاتورة = الإجمالي + التسويات المرتبطة بها − مستندات المرتجع المرحّلة عليها
// لأن installer_name و points_rate يُزامَنان مع الفاتورة، تظهر الأرقام نفسها على
// كل الأجهزة، والتعديل (أو تغيير المؤسس، أو الحذف) يصحّح النقاط تلقائياً بلا «فروقات».
//
// الحركات اليدوية (إضافة / خصم / صرف جائزة) تُحفظ في installer_points بلا
// invoice_id، وتدخل في الرصيد.
//
// 📥 قاعدة مستوردة من debt_book: هناك كانت نقاط كل فاتورة تُسجَّل في installer_points
// (مع invoice_id) وقت الحفظ، ورصيد المؤسس = مجموعها. تلك النقاط المسجّلة هي ما
// يعرفه المحل والمؤسسون، فتُعتمد كما هي لفواتيرها (لا يُعاد حسابها بمعدل اليوم).
// وحين تُعدَّل الفاتورة في الناصر يُمحى سجلها القديم وتُحسب من الفاتورة نفسها.
//
// معدل النقاط الافتراضي (لكل 100,000) في الإعدادات، ويمكن تعديله لكل فاتورة.

import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../services/database_service.dart';

/// فاتورة لمؤسس، مع نقاطها
class FounderInvoice {
  FounderInvoice({
    required this.id,
    required this.number,
    required this.date,
    required this.customer,
    required this.founder,
    required this.total,
    required this.adjustments,
    required this.returns,
    required this.rate,
  });

  final int id;
  final String number;
  final DateTime date;
  final String customer;
  final String founder;
  final double total;
  final double adjustments;
  final double returns;
  final double rate;

  /// نقاط مسجّلة لهذه الفاتورة في قاعدة مستوردة (debt_book) — تُعتمد بدل الحساب
  double? recorded;

  bool get isImported => recorded != null;
  double get net => math.max(0, total + adjustments - returns);
  double get points => recorded ?? FounderService.pointsFor(net, rate);
}

/// حركة نقاط يدوية
class FounderMove {
  FounderMove({required this.id, required this.points, required this.reason, required this.at});
  final int id;
  final double points;
  final String reason;
  final DateTime at;
  bool get isPayout => reason.startsWith(FounderService.payoutPrefix);

  /// خصم تلقائي بسبب «تسديد دين راجع» على فاتورة له
  bool get isReturnDeduction => reason.startsWith(FounderService.returnPrefix);

  /// حركة مستوردة مجمّعة (نقاط فاتورة غير موجودة الآن) — لا تُحذف من هنا
  bool get deletable => id > 0;
}

/// مؤسس مع إحصاءاته
class FounderStats {
  FounderStats({required this.name, this.id, this.phone = '', this.notes = ''});

  final String name;
  int? id;
  String phone;
  String notes;

  /// كل فواتيره (كل الفترات) مرتبة من الأحدث
  final List<FounderInvoice> invoices = [];
  final List<FounderMove> moves = [];

  double get earnedAll => invoices.fold(0.0, (s, i) => s + i.points);
  double get manualAll => moves.fold(0.0, (s, m) => s + m.points);

  /// كل ما خرج من رصيده يدوياً: صرف جوائز + خصم يدوي + خصم «تسديد دين راجع».
  /// (كان يعدّ الحركات التي تبدأ بـ«صرف نقاط» فقط، فيظهر صفراً لمن صُرفت نقاطه
  /// في debt_book بخصم يدوي عادي.)
  double get paidOut => -moves.where((m) => m.id > 0 && m.points < 0).fold(0.0, (s, m) => s + m.points);

  /// منها: صرف جوائز فقط
  double get rewardsOut => -moves.where((m) => m.isPayout).fold(0.0, (s, m) => s + m.points);

  /// منها: خصم بسبب تسديد دين راجع
  double get returnsOut => -moves.where((m) => m.isReturnDeduction).fold(0.0, (s, m) => s + m.points);

  /// إضافات يدوية + فروق منقولة من البرنامج السابق (قد تكون سالبة)
  double get addedAndCarried => moves.where((m) => m.id <= 0 || m.points > 0).fold(0.0, (s, m) => s + m.points);

  /// الرصيد = المكتسب + الإضافات والفروق − المصروف (يُسمح بالسالب)
  double get balance => FounderService.round2(earnedAll + manualAll);

  List<FounderInvoice> inRange(DateTime? from, DateTime? to) => invoices
      .where((i) => (from == null || !i.date.isBefore(from)) && (to == null || i.date.isBefore(to)))
      .toList();

  DateTime? get lastInvoice => invoices.isEmpty ? null : invoices.first.date;
  DateTime? get firstInvoice => invoices.isEmpty ? null : invoices.last.date;
}

class FounderService {
  FounderService._();

  static const _kRate = 'owner_founder_points_per_100k';
  static const payoutPrefix = 'صرف نقاط';
  static const returnPrefix = 'تسديد دين راجع';
  static const _ownTag = '(الناصر)';
  static const double defaultRateFallback = 1.0;

  static double round2(double v) => (v * 100).roundToDouble() / 100;
  static double pointsFor(double amount, double rate) => rate <= 0 || amount <= 0 ? 0 : round2(amount / 100000.0 * rate);

  // ═════════════ الإعداد: نقاط لكل 100,000 ═════════════

  static Future<double> defaultRate() async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getDouble(_kRate) ?? defaultRateFallback;
    } catch (_) {
      return defaultRateFallback;
    }
  }

  static Future<void> setDefaultRate(double v) async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_kRate, v < 0 ? 0 : v);
  }

  // ═════════════ الجداول ═════════════

  static bool _schemaOk = false;

  static Future<Database> _db() async {
    final db = await DatabaseService().database;
    if (!_schemaOk) {
      await _ensureSchema(db);
      _schemaOk = true;
    }
    return db;
  }

  static Future<void> _ensureSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS installers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        phone TEXT,
        points REAL DEFAULT 0,
        billed_amount REAL DEFAULT 0,
        total_points REAL DEFAULT 0.0
      )''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS installer_points (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        installer_id INTEGER NOT NULL,
        invoice_id INTEGER,
        points REAL NOT NULL,
        reason TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (installer_id) REFERENCES installers (id) ON DELETE CASCADE,
        FOREIGN KEY (invoice_id) REFERENCES invoices (id) ON DELETE SET NULL
      )''');
    final cols = (await db.rawQuery('PRAGMA table_info(installers)')).map((r) => '${r['name']}').toSet();
    for (final c in const [
      ['phone', 'TEXT'],
      ['notes', 'TEXT'],
      ['created_at', 'TEXT'],
      ['total_billed_amount', 'REAL DEFAULT 0'], // يستعمله نموذج Installer القديم
    ]) {
      if (!cols.contains(c[0])) await db.execute('ALTER TABLE installers ADD COLUMN ${c[0]} ${c[1]}');
    }
  }

  static Future<bool> _tableExists(Database db, String t) async =>
      (await db.rawQuery("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", [t])).isNotEmpty;

  // ═════════════ المؤسسون ═════════════

  /// أسماء كل المؤسسين (المسجلين + الموجودين في الفواتير) للإكمال التلقائي
  static Future<List<String>> names() async {
    final db = await _db();
    final rows = await db.rawQuery('''
      SELECT name FROM installers
      UNION
      SELECT TRIM(installer_name) FROM invoices
       WHERE TRIM(COALESCE(installer_name, '')) <> '' AND COALESCE(is_deleted, 0) = 0
      ORDER BY 1''');
    return rows.map((r) => '${r.values.first ?? ''}'.trim()).where((s) => s.isNotEmpty).toList();
  }

  /// يضيف المؤسس إن لم يكن موجوداً (عند حفظ فاتورة باسم جديد)
  static Future<int?> ensureFounder(String name, {String? phone}) async {
    final n = name.trim();
    if (n.isEmpty) return null;
    final db = await _db();
    await db.rawInsert(
      'INSERT OR IGNORE INTO installers (name, phone, created_at) VALUES (?, ?, ?)',
      [n, phone, DateTime.now().toIso8601String()],
    );
    final r = await db.query('installers', columns: ['id'], where: 'name = ?', whereArgs: [n], limit: 1);
    return r.isEmpty ? null : r.first['id'] as int;
  }

  static Future<void> updateInfo(int id, {String? phone, String? notes}) async {
    final db = await _db();
    final values = <String, Object?>{};
    if (phone != null) values['phone'] = phone;
    if (notes != null) values['notes'] = notes;
    if (values.isEmpty) return;
    await db.update('installers', values, where: 'id = ?', whereArgs: [id]);
  }

  /// حذف مؤسس: فقط إن لم تبقَ له فواتير
  static Future<String?> delete(FounderStats f) async {
    if (f.invoices.isNotEmpty) return 'لا يمكن الحذف: للمؤسس ${f.invoices.length} فاتورة. أزل اسمه منها أولاً.';
    if (f.id == null) return null;
    final db = await _db();
    await db.delete('installer_points', where: 'installer_id = ?', whereArgs: [f.id]);
    await db.delete('installers', where: 'id = ?', whereArgs: [f.id]);
    return null;
  }

  /// حركة يدوية: موجبة = إضافة، سالبة = خصم. [payout] = صرف نقاط (جائزة / مكافأة).
  static Future<void> addMove(FounderStats f, double points, String reason, {bool payout = false}) async {
    if (points == 0) return;
    final id = f.id ?? await ensureFounder(f.name);
    if (id == null) return;
    final db = await _db();
    final text = reason.trim();
    await db.insert('installer_points', {
      'installer_id': id,
      'invoice_id': null,
      'points': payout ? -points.abs() : points,
      'reason': payout ? '$payoutPrefix${text.isEmpty ? '' : ' — $text'}' : (text.isEmpty ? (points > 0 ? 'إضافة يدوية' : 'خصم يدوي') : text),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// آخر نقاط فاتورة مسجّلة (قاعدة debt_book مستوردة)؛ null = قاعدة الناصر الأصلية
  static Future<DateTime?> _importedThreshold(DatabaseExecutor db) async {
    try {
      // سجلات الناصر نفسه (بعد الاستيراد) لا تُحسب: الحدّ هو آخر ما سجّله debt_book
      final r = await db.rawQuery("SELECT MAX(created_at) AS d FROM installer_points "
          "WHERE invoice_id IS NOT NULL AND COALESCE(reason, '') NOT LIKE '%$_ownTag'");
      final v = r.first['d'];
      return v == null ? null : DateTime.tryParse('$v');
    } catch (_) {
      return null;
    }
  }

  /// بعد أن يحفظ المستخدم فاتورة: في القاعدة المستوردة تُسجَّل نقاطها من الفاتورة
  /// نفسها (المؤسس والمعدل والصافي الحاليين) بدل سجلها القديم. في قاعدة الناصر
  /// الأصلية لا شيء (النقاط تُحسب من الفاتورة دائماً).
  static Future<void> refreshInvoicePoints(int invoiceId) async {
    final db = await _db();
    if (await _importedThreshold(db) == null) return;
    final list = await invoices(id: invoiceId);
    await db.delete('installer_points', where: 'invoice_id = ?', whereArgs: [invoiceId]);
    if (list.isEmpty) return; // بلا مؤسس الآن، أو محذوفة/معلّقة
    final inv = list.first;
    final insId = await ensureFounder(inv.founder);
    if (insId == null) return;
    await db.insert('installer_points', {
      'installer_id': insId,
      'invoice_id': invoiceId,
      'points': pointsFor(inv.net, inv.rate),
      'reason': 'فاتورة رقم ${inv.number} $_ownTag',
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  static Future<void> deleteMove(int moveId) async {
    final db = await _db();
    await db.delete('installer_points', where: 'id = ? AND invoice_id IS NULL', whereArgs: [moveId]);
    try {
      await db.delete('founder_return_links', where: 'move_id = ?', whereArgs: [moveId]);
    } catch (_) {}
  }

  // ═════════════ تسديد دين راجع ═════════════
  //
  // مثال: فاتورة بمليون ومعدلها نقطة لكل 100 ألف ⇒ 10 نقاط للمؤسس. رجع منها
  // 200 ألف ⇒ يُخصم 10 × 200,000 ÷ 1,000,000 = نقطتان.
  // الخصم نسبةً من نقاط الفاتورة الفعلية (المسجّلة في القاعدة المستوردة، أو
  // المحسوبة)، فلا يُخصم أكثر مما أُعطي عليها، ومجموع الراجع على فاتورة لا
  // يتجاوز صافيها.

  static Future<void> _ensureReturnLinks(DatabaseExecutor db) => db.execute('''
      CREATE TABLE IF NOT EXISTS founder_return_links (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        move_id INTEGER,
        invoice_id INTEGER NOT NULL,
        transaction_id INTEGER,
        amount REAL NOT NULL,
        points REAL NOT NULL,
        created_at TEXT NOT NULL
      )''');

  /// فاتورة واحدة بنقاطها كما تدخل في رصيد مؤسسها (null = بلا مؤسس / محذوفة)
  static Future<FounderInvoice?> invoiceWithPoints(int invoiceId) async {
    final db = await _db();
    final list = await invoices(id: invoiceId);
    if (list.isEmpty) return null;
    final inv = list.first;
    final ins = await db.query('installers', columns: ['id'], where: 'TRIM(name) = ?', whereArgs: [inv.founder], limit: 1);
    if (ins.isNotEmpty) {
      final r = await db.rawQuery(
          'SELECT COUNT(*) AS k, COALESCE(SUM(points), 0) AS p FROM installer_points WHERE invoice_id = ? AND installer_id = ?',
          [invoiceId, ins.first['id']]);
      if (((r.first['k'] as num?) ?? 0) > 0) {
        inv.recorded = (r.first['p'] as num?)?.toDouble() ?? 0;
        return inv;
      }
    }
    final threshold = await _importedThreshold(db);
    if (threshold != null && !inv.date.isAfter(threshold)) inv.recorded = 0;
    return inv;
  }

  /// ما سبق تسجيله راجعاً على الفاتورة (مبلغ، نقاط)
  static Future<(double, double)> returnedOn(int invoiceId) async {
    final db = await _db();
    await _ensureReturnLinks(db);
    final r = await db.rawQuery(
        'SELECT COALESCE(SUM(amount), 0) AS a, COALESCE(SUM(points), 0) AS p FROM founder_return_links WHERE invoice_id = ?',
        [invoiceId]);
    return ((r.first['a'] as num?)?.toDouble() ?? 0, (r.first['p'] as num?)?.toDouble() ?? 0);
  }

  /// النقاط التي ستُخصم لو رجع [amount] من الفاتورة (للمعاينة قبل الحفظ)
  static Future<double> previewReturnDeduction(int invoiceId, double amount) async {
    final inv = await invoiceWithPoints(invoiceId);
    if (inv == null || amount <= 0 || inv.net <= 0 || inv.points <= 0) return 0;
    final (_, donePts) = await returnedOn(invoiceId);
    final want = round2(inv.points * math.min(1.0, amount / inv.net));
    return round2(math.max(0, math.min(want, inv.points - donePts)));
  }

  /// يخصم من مؤسس الفاتورة نقاط المبلغ الراجع. يعيد النقاط المخصومة (0 = لا مؤسس / لا نقاط).
  static Future<double> deductForReturnedPayment({
    required int invoiceId,
    required double amount,
    required String customer,
    int? transactionId,
    String? note,
  }) async {
    final inv = await invoiceWithPoints(invoiceId);
    if (inv == null) return 0;
    final pts = await previewReturnDeduction(invoiceId, amount);
    final db = await _db();
    await _ensureReturnLinks(db);
    final insId = await ensureFounder(inv.founder);
    if (insId == null) return 0;
    final now = DateTime.now().toIso8601String();
    int? moveId;
    if (pts > 0) {
      moveId = await db.insert('installer_points', {
        'installer_id': insId,
        'invoice_id': null, // حركة يدوية: لا تُخلط بنقاط الفاتورة نفسها
        'points': -pts,
        'reason': '$returnPrefix — فاتورة ${inv.number} — $customer'
            '${note == null || note.trim().isEmpty ? '' : ' — ${note.trim()}'}',
        'created_at': now,
      });
    }
    await db.insert('founder_return_links', {
      'move_id': moveId,
      'invoice_id': invoiceId,
      'transaction_id': transactionId,
      'amount': amount,
      'points': pts,
      'created_at': now,
    });
    return pts;
  }

  // ═════════════ التحميل الكامل ═════════════

  /// كل الفواتير ذات المؤسس (المحفوظة غير المحذوفة) — للتقارير
  static Future<List<FounderInvoice>> invoices({String? founder, int? id}) async {
    final db = await _db();
    final hasAdj = await _tableExists(db, 'invoice_adjustments');
    final hasRet = await _tableExists(db, 'sales_returns');
    final rows = await db.rawQuery('''
      SELECT i.id, i.invoice_number, i.invoice_date, i.customer_name, TRIM(i.installer_name) AS founder,
             COALESCE(i.total_amount, 0) AS total, COALESCE(i.points_rate, 0) AS rate,
             ${hasAdj ? 'COALESCE((SELECT SUM(a.amount_delta) FROM invoice_adjustments a WHERE a.invoice_id = i.id), 0)' : '0'} AS adj,
             ${hasRet ? "COALESCE((SELECT SUM(r.total) FROM sales_returns r WHERE r.original_invoice_id = i.id AND r.status = 'posted'), 0)" : '0'} AS ret
        FROM invoices i
       WHERE TRIM(COALESCE(i.installer_name, '')) <> ''
         AND COALESCE(i.is_deleted, 0) = 0
         AND COALESCE(i.status, 'محفوظة') = 'محفوظة'
         ${founder != null ? 'AND TRIM(i.installer_name) = ?' : ''}
         ${id != null ? 'AND i.id = ?' : ''}
       ORDER BY i.invoice_date DESC, i.id DESC''', [if (founder != null) founder.trim(), if (id != null) id]);
    return rows.map((r) {
      double d(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
      return FounderInvoice(
        id: r['id'] as int,
        number: '${r['invoice_number'] ?? r['id']}',
        date: DateTime.tryParse('${r['invoice_date']}') ?? DateTime(2000),
        customer: '${r['customer_name'] ?? ''}',
        founder: '${r['founder'] ?? ''}',
        total: d(r['total']),
        adjustments: d(r['adj']),
        returns: d(r['ret']),
        rate: d(r['rate']),
      );
    }).toList();
  }

  /// كل المؤسسين بإحصاءاتهم
  static Future<List<FounderStats>> loadAll() async {
    final db = await _db();
    final map = <String, FounderStats>{};
    for (final r in await db.query('installers')) {
      final name = '${r['name'] ?? ''}'.trim();
      if (name.isEmpty) continue;
      map[name] = FounderStats(
        name: name,
        id: r['id'] as int?,
        phone: '${r['phone'] ?? ''}',
        notes: '${r['notes'] ?? ''}',
      );
    }
    for (final inv in await invoices()) {
      (map[inv.founder] ??= FounderStats(name: inv.founder)).invoices.add(inv);
    }
    final idToName = {for (final f in map.values) if (f.id != null) f.id!: f.name};

    // 📥 نقاط مسجّلة لفواتير (قاعدة debt_book): تُعتمد لفاتورتها، وما لا فاتورة له
    //    الآن (محذوفة/معلّقة/مؤسس آخر) يبقى حركة في رصيد صاحبه — فيطابق الرصيدُ ما
    //    كان يعرفه المحل تماماً.
    final invById = <int, FounderInvoice>{
      for (final f in map.values)
        for (final i in f.invoices) i.id: i,
    };
    final threshold = await _importedThreshold(db);
    try {
      final linked = await db.rawQuery('''
        SELECT invoice_id AS inv, installer_id AS ins, SUM(points) AS p, MAX(created_at) AS at, COUNT(*) AS k
        FROM installer_points WHERE invoice_id IS NOT NULL
        GROUP BY invoice_id, installer_id''');
      for (final r in linked) {
        final insName = idToName[r['ins']];
        if (insName == null) continue;
        final p = (r['p'] as num?)?.toDouble() ?? 0;
        final inv = invById[r['inv']];
        if (inv != null && inv.founder == insName) {
          inv.recorded = (inv.recorded ?? 0) + p;
        } else if (p.abs() > 0.0001) {
          map[insName]!.moves.add(FounderMove(
            id: -((r['inv'] as int?) ?? 0),
            points: p,
            reason: 'نقاط فاتورة ${r['inv']} (مسجّلة سابقاً)',
            at: DateTime.tryParse('${r['at']}') ?? DateTime(2000),
          ));
        }
      }
    } catch (_) {}
    // فاتورة قديمة (من قبل آخر نقاط سجّلها debt_book) بلا نقاط مسجّلة = لم يُحتسب لها
    // شيء هناك، فتبقى صفراً كما كان رصيد المؤسس. ما بعد ذلك يُحسب من الفاتورة.
    if (threshold != null) {
      for (final i in invById.values) {
        if (i.recorded == null && !i.date.isAfter(threshold)) i.recorded = 0;
      }
    }

    final moves = await db.query('installer_points', where: 'invoice_id IS NULL', orderBy: 'created_at DESC');
    for (final m in moves) {
      final name = idToName[m['installer_id']];
      if (name == null) continue;
      map[name]!.moves.add(FounderMove(
        id: m['id'] as int,
        points: (m['points'] as num?)?.toDouble() ?? 0,
        reason: '${m['reason'] ?? ''}',
        at: DateTime.tryParse('${m['created_at']}') ?? DateTime(2000),
      ));
    }
    // 📥 القاعدة المستوردة: رصيد كل مؤسس يوم الاستيراد = ما كان يعرضه debt_book
    //    (installers.total_points). سجلات debt_book نفسها لا تطابق أرصدته أحياناً
    //    (تغيير مؤسس الفاتورة هناك يحدّث الرصيد ولا ينقل السجل)، فيُحفظ الفرق مرة
    //    واحدة كحركة «فرق رصيد منقول» — وما بعد الاستيراد يُحسب طبيعياً فوقه.
    if (threshold != null) {
      try {
        final opening = await _openingAdjust(db, map, threshold);
        opening.forEach((name, pts) {
          map[name]?.moves.add(FounderMove(
            id: 0,
            points: pts,
            reason: 'فرق رصيد منقول من البرنامج السابق',
            at: threshold,
          ));
        });
      } catch (_) {}
    }

    final list = map.values.toList()..sort((a, b) => b.balance.compareTo(a.balance));
    return list;
  }

  static const _doneMark = '__done__';

  static Future<Map<String, double>> _openingAdjust(
      DatabaseExecutor db, Map<String, FounderStats> map, DateTime threshold) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS founder_opening (
        name TEXT PRIMARY KEY,
        points REAL NOT NULL,
        created_at TEXT
      )''');
    final saved = await db.query('founder_opening');
    if (saved.isNotEmpty) {
      return {
        for (final r in saved)
          if (r['name'] != _doneMark) '${r['name']}': (r['points'] as num?)?.toDouble() ?? 0,
      };
    }
    // أول فتح بعد الاستيراد: الفرق = رصيد debt_book − ما نحسبه نحن لما قبل الاستيراد
    final totals = <String, double>{};
    for (final r in await db.rawQuery('SELECT TRIM(name) AS n, SUM(COALESCE(total_points, 0)) AS t FROM installers GROUP BY TRIM(name)')) {
      totals['${r['n']}'] = (r['t'] as num?)?.toDouble() ?? 0;
    }
    final out = <String, double>{};
    final now = DateTime.now().toIso8601String();
    for (final f in map.values) {
      final total = totals[f.name];
      if (total == null) continue;
      final pre = f.invoices.where((i) => !i.date.isAfter(threshold)).fold(0.0, (s, i) => s + i.points) +
          f.moves.where((m) => !m.at.isAfter(threshold)).fold(0.0, (s, m) => s + m.points);
      final diff = round2(total - pre);
      if (diff.abs() >= 0.01) {
        out[f.name] = diff;
        await db.insert('founder_opening', {'name': f.name, 'points': diff, 'created_at': now});
      }
    }
    await db.insert('founder_opening', {'name': _doneMark, 'points': 0, 'created_at': now});
    return out;
  }

  /// إجمالي مبيعات المحل في فترة (لنسبة مبيعات المؤسسين)
  static Future<double> allSales(DateTime? from, DateTime? to) async {
    final db = await _db();
    final where = <String>["COALESCE(is_deleted, 0) = 0", "COALESCE(status, 'محفوظة') = 'محفوظة'"];
    final args = <Object>[];
    if (from != null) {
      where.add('invoice_date >= ?');
      args.add(from.toIso8601String());
    }
    if (to != null) {
      where.add('invoice_date < ?');
      args.add(to.toIso8601String());
    }
    final r = await db.rawQuery('SELECT COALESCE(SUM(total_amount), 0) AS s FROM invoices WHERE ${where.join(' AND ')}', args);
    final v = r.first['s'];
    return v is num ? v.toDouble() : 0;
  }
}
