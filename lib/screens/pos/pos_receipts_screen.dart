// lib/screens/pos/pos_receipts_screen.dart
//
// 🧾 إيصالات الكاشير — على طريقة أنظمة البيع العالمية (Square، Loyverse، Odoo POS):
//   • إيصالات الكاشير فقط (فواتير «إنشاء فاتورة» في «تعديل الفواتير»). العلامة في
//     جدول invoice_tags؛ الإيصالات القديمة قبل هذه العلامة لا تظهر هنا.
//   • تحميل تدريجي: أول 50 إيصالاً، ثم 50 أخرى كلما وصلت آخر القائمة — تبقى
//     الشاشة سريعة حتى مع آلاف الإيصالات.
//   • ملخص الفترة (المبيعات، النقد، الآجل، المرتجعات، الصافي) لمن لديه صلاحية
//     «رؤية الكلفة والأرباح» فقط؛ الكاشير العادي لا يراه.
//   • الإيصال المكتمل لا يُعدَّل من الكاشير: التصحيح بـ«مرتجع» ثم بيع جديد،
//     وتبقى إعادة الطباعة متاحة («نسخة»).
//
// قراءة فقط: هذه الشاشة لا تغيّر أي رصيد أو مخزون بنفسها.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../accounting/screens/acc_ui.dart' show requirePermission;
import '../../erp/sales/sales_return_screen.dart';
import '../../models/app_user.dart';
import '../../models/invoice.dart';
import '../../models/invoice_item.dart';
import '../../services/auth_service.dart';
import '../../services/database_service.dart';
import '../../services/invoice_upload_tracker.dart';
import '../../services/thermal_receipt_service.dart';
import '../create_invoice_screen.dart';

enum _Range { today, yesterday, week, month, all }

class PosReceiptsScreen extends StatefulWidget {
  const PosReceiptsScreen({super.key});

  @override
  State<PosReceiptsScreen> createState() => _PosReceiptsScreenState();
}

class _Row {
  _Row(this.m);
  final Map<String, Object?> m;
  int get id => m['id'] as int;
  String get number {
    final n = m['invoice_number'] as String?;
    return (n != null && n.isNotEmpty) ? n : '#${id.toString().padLeft(5, '0')}';
  }

  String get customer => (m['customer_name'] as String?)?.trim().isNotEmpty == true ? m['customer_name'] as String : 'عميل نقدي';
  double get total => (m['total_amount'] as num?)?.toDouble() ?? 0;
  double get returned => (m['returned'] as num?)?.toDouble() ?? 0;
  String get payment => (m['payment_type'] as String?) ?? 'نقد';
  String get status => (m['status'] as String?) ?? 'محفوظة';
  String? get cashier => m['created_by_username'] as String?;
  DateTime get date => DateTime.tryParse('${m['invoice_date']}') ?? DateTime.now();
}

// ألوان الشاشة (نفس كحلي رؤوس البرنامج)
const _navy = Color(0xFF0F3460);
const _navyDeep = Color(0xFF020F2B);
const _bg = Color(0xFFF2F5F9);
const _line = Color(0xFFE3E9F1);
const _muted = Color(0xFF64748B);
const _green = Color(0xFF15803D);
const _orange = Color(0xFFC2410C);
const _red = Color(0xFFB91C1C);
const _blue = Color(0xFF1D4ED8);

class _PosReceiptsScreenState extends State<PosReceiptsScreen> {
  static final _money = NumberFormat('#,##0.##', 'en');
  static final _time = DateFormat('HH:mm');
  static const _pageSize = 50;

  final _search = TextEditingController();
  final _scroll = ScrollController();
  _Range _range = _Range.today;
  String? _payment; // null = الكل
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _loadSeq = 0; // يتجاهل نتائج تحميل قديم إذا غيّر المستخدم الفلتر أثناءه
  List<_Row> _rows = const [];
  _Row? _selected;

  // ملخص الفترة (لمن يرى الأرباح فقط)
  late final bool _canSeeTotals = AuthService().hasPermission(AppPermissions.viewCostProfit);
  int _count = 0;
  double _cash = 0, _credit = 0, _returns = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore || _loading) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 300) _loadMore();
  }

  (String?, String?) _bounds() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    String d(DateTime x) => DateFormat('yyyy-MM-dd').format(x);
    switch (_range) {
      case _Range.today:
        return (d(today), d(today.add(const Duration(days: 1))));
      case _Range.yesterday:
        return (d(today.subtract(const Duration(days: 1))), d(today));
      case _Range.week:
        return (d(today.subtract(const Duration(days: 6))), d(today.add(const Duration(days: 1))));
      case _Range.month:
        return (d(DateTime(now.year, now.month, 1)), d(today.add(const Duration(days: 1))));
      case _Range.all:
        return (null, null);
    }
  }

  /// شروط القائمة (الفترة + الدفع + البحث) — إيصالات الكاشير فقط
  (List<String>, List<Object?>) _where() {
    final (from, to) = _bounds();
    final where = <String>['COALESCE(i.is_deleted, 0) = 0', InvoiceUploadTracker.isPosSql('i')];
    final args = <Object?>[];
    if (from != null) {
      where.add('i.invoice_date >= ? AND i.invoice_date < ?');
      args.addAll([from, to]);
    }
    if (_payment != null) {
      where.add('i.payment_type = ?');
      args.add(_payment);
    }
    final q = _search.text.trim();
    if (q.isNotEmpty) {
      final isNum = RegExp(r'^\d+$').hasMatch(q);
      where.add('(i.invoice_number LIKE ? OR i.customer_name LIKE ?${isNum ? ' OR i.id = ?' : ''})');
      args.addAll(['%$q%', '%$q%', if (isNum) int.parse(q)]);
    }
    return (where, args);
  }

  Future<List<_Row>> _page(int offset) async {
    final db = await DatabaseService().database;
    final (where, args) = _where();
    final rows = await db.rawQuery('''
      SELECT i.id, i.invoice_number, i.customer_name, i.total_amount, i.payment_type, i.status,
             i.invoice_date, i.created_by_username,
             (SELECT COALESCE(SUM(r.total), 0) FROM sales_returns r
               WHERE r.original_invoice_id = i.id AND r.status = 'posted') AS returned
      FROM invoices i
      WHERE ${where.join(' AND ')}
      ORDER BY i.invoice_date DESC, i.id DESC
      LIMIT $_pageSize OFFSET $offset
    ''', args);
    return rows.map((m) => _Row(m)).toList();
  }

  Future<void> _load() async {
    final seq = ++_loadSeq;
    setState(() => _loading = true);
    try {
      final db = await DatabaseService().database;
      await InvoiceUploadTracker.ensure(db);
      final list = await _page(0);

      // ملخص الفترة (بلا البحث) — إيصالات الكاشير فقط، ولمن يرى الأرباح فقط
      int count = 0;
      double cash = 0, credit = 0, returns = 0;
      if (_canSeeTotals) {
        final (from, to) = _bounds();
        final sumWhere = <String>[
          'COALESCE(i.is_deleted, 0) = 0',
          "COALESCE(i.status, '') != 'معلقة'",
          InvoiceUploadTracker.isPosSql('i'),
        ];
        final sumArgs = <Object?>[];
        if (from != null) {
          sumWhere.add('i.invoice_date >= ? AND i.invoice_date < ?');
          sumArgs.addAll([from, to]);
        }
        final sums = await db.rawQuery('''
          SELECT COUNT(*) AS c,
                 COALESCE(SUM(CASE WHEN i.payment_type = 'نقد' THEN i.total_amount ELSE 0 END), 0) AS cash,
                 COALESCE(SUM(CASE WHEN i.payment_type != 'نقد' THEN i.total_amount ELSE 0 END), 0) AS credit
          FROM invoices i WHERE ${sumWhere.join(' AND ')}
        ''', sumArgs);
        count = (sums.first['c'] as num?)?.toInt() ?? 0;
        cash = (sums.first['cash'] as num?)?.toDouble() ?? 0;
        credit = (sums.first['credit'] as num?)?.toDouble() ?? 0;
        try {
          final r = await db.rawQuery('''
            SELECT COALESCE(SUM(r.total), 0) AS t FROM sales_returns r
            WHERE r.status = 'posted'
              AND EXISTS (SELECT 1 FROM invoice_tags t WHERE t.invoice_id = r.original_invoice_id AND t.source = 'pos')
              ${from != null ? 'AND r.return_date >= ? AND r.return_date < ?' : ''}
          ''', [if (from != null) ...[from, to]]);
          returns = (r.first['t'] as num?)?.toDouble() ?? 0;
        } catch (_) {}
      }

      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _rows = list;
        _hasMore = list.length == _pageSize;
        _count = count;
        _cash = cash;
        _credit = credit;
        _returns = returns;
        final keep = _selected == null ? const <_Row>[] : list.where((r) => r.id == _selected!.id).toList();
        _selected = keep.isNotEmpty ? keep.first : (list.isEmpty ? null : list.first);
        _loading = false;
      });
      if (_scroll.hasClients) _scroll.jumpTo(0);
    } catch (e) {
      if (!mounted || seq != _loadSeq) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذّر تحميل الإيصالات: $e')));
    }
  }

  Future<void> _loadMore() async {
    final seq = _loadSeq;
    setState(() => _loadingMore = true);
    try {
      final more = await _page(_rows.length);
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _rows = [..._rows, ...more];
        _hasMore = more.length == _pageSize;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  // ─────────────────────────── الواجهة ───────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Column(
        children: [
          _header(),
          if (_canSeeTotals) _summaryStrip(),
          _filters(),
          Expanded(
            child: LayoutBuilder(builder: (context, c) {
              final wide = c.maxWidth >= 900;
              final list = _list(onTap: (r) {
                setState(() => _selected = r);
                if (!wide) _openDetailSheet(r);
              });
              if (!wide) return list;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 440, child: list),
                  Expanded(
                    child: Container(
                      margin: const EdgeInsetsDirectional.fromSTEB(0, 0, 14, 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _line),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _selected == null
                          ? _emptyState(Icons.receipt_long_outlined, 'اختر إيصالاً لعرضه')
                          : _ReceiptDetail(key: ValueKey(_selected!.id), row: _selected!, onChanged: _load),
                    ),
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [_navyDeep, _navy], begin: Alignment.topCenter, end: Alignment.bottomCenter),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 14),
          child: Row(children: [
            const BackButton(color: Colors.white),
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.receipt_long_rounded, color: Colors.white),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text('إيصالات الكاشير', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                Text('إعادة طباعة، مرتجع، وعرض كامل', style: TextStyle(color: Color(0xFFB8C7DC), fontSize: 12.5)),
              ]),
            ),
            SizedBox(
              width: 300,
              child: TextField(
                controller: _search,
                onSubmitted: (_) => _load(),
                onChanged: (v) {
                  if (v.isEmpty) _load();
                },
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'رقم الإيصال أو اسم العميل ثم Enter',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 11),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'تحديث',
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            ),
          ]),
        ),
      ),
    );
  }

  void _openDetailSheet(_Row r) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.88,
        child: _ReceiptDetail(row: r, onChanged: _load),
      ),
    );
  }

  Widget _summaryStrip() {
    Widget kpi(String label, double v, Color c, IconData icon, {String? hint}) => Container(
          width: 196,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _line),
          ),
          child: Row(children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: c, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: const TextStyle(fontSize: 12, color: _muted)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(_money.format(v), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c)),
                ),
                if (hint != null) Text(hint, style: const TextStyle(fontSize: 11, color: _muted)),
              ]),
            ),
          ]),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      child: Wrap(spacing: 10, runSpacing: 10, children: [
        kpi('المبيعات', _cash + _credit, _blue, Icons.point_of_sale_rounded, hint: '$_count إيصال'),
        kpi('نقداً', _cash, _green, Icons.payments_rounded),
        kpi('آجل (دين)', _credit, _orange, Icons.schedule_rounded),
        kpi('المرتجعات', _returns, _red, Icons.assignment_return_rounded),
        kpi('الصافي', _cash + _credit - _returns, _navy, Icons.account_balance_wallet_rounded),
      ]),
    );
  }

  Widget _pill(String label, bool selected, VoidCallback onTap, {IconData? icon}) {
    return Material(
      color: selected ? _navy : Colors.white,
      shape: StadiumBorder(side: BorderSide(color: selected ? _navy : _line)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: selected ? Colors.white : _muted),
              const SizedBox(width: 6),
            ],
            Text(label,
                style: TextStyle(
                  color: selected ? Colors.white : const Color(0xFF1E293B),
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 13,
                )),
          ]),
        ),
      ),
    );
  }

  Widget _filters() {
    const labels = {
      _Range.today: 'اليوم',
      _Range.yesterday: 'أمس',
      _Range.week: 'آخر 7 أيام',
      _Range.month: 'هذا الشهر',
      _Range.all: 'الكل',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final e in labels.entries)
            _pill(e.value, _range == e.key, () {
              setState(() => _range = e.key);
              _load();
            }),
          Container(width: 1, height: 22, color: _line, margin: const EdgeInsets.symmetric(horizontal: 4)),
          for (final p in const [null, 'نقد', 'دين'])
            _pill(
              p == null ? 'كل الدفعات' : (p == 'نقد' ? 'نقداً' : 'آجل'),
              _payment == p,
              () {
                setState(() => _payment = p);
                _load();
              },
              icon: p == null ? Icons.all_inclusive_rounded : (p == 'نقد' ? Icons.payments_outlined : Icons.schedule_rounded),
            ),
        ],
      ),
    );
  }

  Widget _emptyState(IconData icon, String text) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: _navy.withValues(alpha: 0.06), shape: BoxShape.circle),
            child: Icon(icon, size: 34, color: _navy.withValues(alpha: 0.5)),
          ),
          const SizedBox(height: 12),
          Text(text, style: const TextStyle(color: _muted, fontSize: 15)),
        ]),
      );

  Widget _list({required void Function(_Row) onTap}) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_rows.isEmpty) return _emptyState(Icons.receipt_long_outlined, 'لا توجد إيصالات كاشير في هذه الفترة');

    // تجميع حسب اليوم: [عنوان يوم، إيصال، إيصال...] ثم تذييل التحميل
    final entries = <Object>[];
    String? lastDay;
    for (final r in _rows) {
      final day = DateFormat('yyyy/MM/dd').format(r.date);
      if (day != lastDay) {
        lastDay = day;
        entries.add(day);
      }
      entries.add(r);
    }

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
      itemCount: entries.length + 1,
      itemBuilder: (context, i) {
        if (i == entries.length) return _footer();
        final e = entries[i];
        if (e is String) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
            child: Text(_dayLabel(e), style: const TextStyle(fontWeight: FontWeight.w800, color: _muted, fontSize: 13)),
          );
        }
        return _card(e as _Row, onTap);
      },
    );
  }

  String _dayLabel(String day) {
    final now = DateTime.now();
    final f = DateFormat('yyyy/MM/dd');
    if (day == f.format(now)) return 'اليوم — $day';
    if (day == f.format(now.subtract(const Duration(days: 1)))) return 'أمس — $day';
    return day;
  }

  Widget _footer() {
    if (_loadingMore) {
      return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)));
    }
    if (_hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Center(
          child: OutlinedButton.icon(onPressed: _loadMore, icon: const Icon(Icons.expand_more_rounded), label: const Text('تحميل المزيد')),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Center(child: Text('${_rows.length} إيصال — انتهت القائمة', style: const TextStyle(color: _muted, fontSize: 12))),
    );
  }

  Widget _card(_Row r, void Function(_Row) onTap) {
    final sel = _selected?.id == r.id;
    final fullyReturned = r.returned > 0 && r.returned >= r.total - 0.5;
    final cash = r.payment == 'نقد';
    final accent = r.status == 'معلقة' ? Colors.grey : (cash ? _green : _orange);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: sel ? const Color(0xFFEAF1FB) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: sel ? _navy.withValues(alpha: 0.45) : _line, width: sel ? 1.5 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onTap(r),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(width: 4, color: accent),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Row(children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: accent.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)),
                      child: Icon(cash ? Icons.payments_rounded : Icons.schedule_rounded, size: 20, color: accent),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Flexible(
                            child: Text(r.number,
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                            decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(8)),
                            child: Text(_time.format(r.date), style: const TextStyle(fontSize: 11.5, color: _muted)),
                          ),
                        ]),
                        const SizedBox(height: 2),
                        Text(
                          (r.cashier ?? '').isNotEmpty ? '${r.customer} · ${r.cashier}' : r.customer,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5, color: _muted),
                        ),
                      ]),
                    ),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                      Text(_money.format(r.total),
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15.5,
                            color: const Color(0xFF0F172A),
                            decoration: fullyReturned ? TextDecoration.lineThrough : null,
                          )),
                      if (r.status == 'معلقة')
                        _badge('معلقة', Colors.grey)
                      else if (fullyReturned)
                        _badge('مرتجع كلي', _red)
                      else if (r.returned > 0)
                        _badge('مرتجع جزئي', Colors.deepOrange)
                      else if (!cash)
                        _badge('دين', _orange),
                    ]),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  static Widget _badge(String t, Color c) => Container(
        margin: const EdgeInsets.only(top: 3),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
        child: Text(t, style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.bold)),
      );
}

// ─────────────────────────── تفاصيل الإيصال ───────────────────────────

class _ReceiptDetail extends StatefulWidget {
  const _ReceiptDetail({super.key, required this.row, required this.onChanged});
  final _Row row;
  final VoidCallback onChanged;

  @override
  State<_ReceiptDetail> createState() => _ReceiptDetailState();
}

class _ReceiptDetailState extends State<_ReceiptDetail> {
  static final _money = NumberFormat('#,##0.##', 'en');
  static final _qty = NumberFormat('#,##0.###', 'en');

  Invoice? _inv;
  List<InvoiceItem> _items = const [];
  List<Map<String, Object?>> _returns = const [];
  bool _loading = true;
  bool _printing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dbs = DatabaseService();
    try {
      final inv = await dbs.getInvoiceById(widget.row.id);
      final items = await dbs.getInvoiceItems(widget.row.id);
      List<Map<String, Object?>> returns = const [];
      try {
        final db = await dbs.database;
        returns = await db.rawQuery(
          "SELECT id, return_no, return_date, total, refund_mode FROM sales_returns "
          "WHERE original_invoice_id = ? AND status = 'posted' ORDER BY id",
          [widget.row.id],
        );
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _inv = inv;
        _items = items;
        _returns = returns;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  double _soldQty(InvoiceItem it) =>
      (it.quantityLargeUnit ?? 0) > 0 ? it.quantityLargeUnit! : (it.quantityIndividual ?? 0);

  Future<void> _reprint() async {
    final inv = _inv;
    if (inv == null) return;
    setState(() => _printing = true);
    final subtotal = _items.fold<double>(0, (s, it) => s + it.itemTotal);
    final ok = await ThermalReceiptService().printReceipt(ReceiptData(
      invoiceId: inv.formattedInvoiceNumber,
      dateTime: inv.invoiceDate,
      items: [
        for (final it in _items)
          ReceiptItem(name: it.productName, quantity: _soldQty(it), price: it.appliedPrice, unit: it.saleType),
      ],
      subtotal: subtotal,
      discount: inv.discount,
      total: inv.totalAmount,
      paidAmount: inv.amountPaidOnInvoice,
      customerName: inv.customerName,
      paymentType: inv.paymentType,
      isCopy: true,
    ));
    if (!mounted) return;
    setState(() => _printing = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? 'أُرسلت نسخة الإيصال إلى الطابعة'
          : 'لم تُطبع: لم تُحدَّد طابعة حرارية (الإعدادات ← الطابعات). يمكنك «عرض كامل» ثم الطباعة A4'),
      backgroundColor: ok ? Colors.green : Colors.orange,
    ));
  }

  void _refund() {
    if (!requirePermission(context, AppPermissions.salesDocs)) return;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => SalesReturnScreen(invoiceId: widget.row.id)))
        .then((_) {
      _load();
      widget.onChanged();
    });
  }

  void _openFull() {
    final inv = _inv;
    if (inv == null) return;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => CreateInvoiceScreen(existingInvoice: inv, isViewOnly: true)))
        .then((_) {
      _load();
      widget.onChanged();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final inv = _inv;
    if (inv == null) return const Center(child: Text('تعذّر فتح الإيصال'));
    final subtotal = _items.fold<double>(0, (s, it) => s + it.itemTotal);
    final returned = _returns.fold<double>(0, (s, r) => s + ((r['total'] as num?)?.toDouble() ?? 0));
    final remaining = (inv.totalAmount - inv.amountPaidOnInvoice).clamp(0, double.infinity);
    final held = inv.status == 'معلقة';
    final dt = DateFormat('yyyy/MM/dd  HH:mm').format(inv.invoiceDate);

    Widget line(String a, String b, {bool bold = false, Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Text(a, style: TextStyle(fontWeight: bold ? FontWeight.bold : null, color: color)),
            const Spacer(),
            Text(b, style: TextStyle(fontWeight: bold ? FontWeight.bold : null, color: color, fontSize: bold ? 16 : null)),
          ]),
        );

    return Column(children: [
      // شريط الإجراءات
      Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Wrap(spacing: 10, runSpacing: 8, children: [
          FilledButton.icon(
            onPressed: _printing ? null : _reprint,
            icon: const Icon(Icons.print),
            label: const Text('إعادة طباعة'),
          ),
          if (!held)
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.deepOrange),
              onPressed: _refund,
              icon: const Icon(Icons.assignment_return_outlined),
              label: const Text('مرتجع (كلي أو جزئي)'),
            ),
          OutlinedButton.icon(
            onPressed: _openFull,
            icon: const Icon(Icons.open_in_new),
            label: Text(held ? 'فتح الفاتورة المعلقة' : 'عرض كامل'),
          ),
        ]),
      ),
      const Divider(height: 1),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 460),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12)],
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('إيصال ${inv.formattedInvoiceNumber}',
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text(dt, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
                const SizedBox(height: 8),
                line('العميل', inv.customerName),
                line('الدفع', inv.paymentType == 'نقد' ? 'نقداً' : 'آجل (دين)'),
                if ((inv.createdByUsername ?? '').isNotEmpty) line('الكاشير', inv.createdByUsername!),
                if (held) line('الحالة', 'معلقة (لم تُحفظ بعد)', color: Colors.grey),
                const Divider(height: 20),
                // المواد
                const Row(children: [
                  Expanded(flex: 5, child: Text('المادة', style: TextStyle(fontSize: 12, color: Colors.black54))),
                  Expanded(flex: 3, child: Text('الكمية', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.black54))),
                  Expanded(flex: 3, child: Text('السعر', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.black54))),
                  Expanded(flex: 3, child: Text('المجموع', textAlign: TextAlign.left, style: TextStyle(fontSize: 12, color: Colors.black54))),
                ]),
                const SizedBox(height: 4),
                for (final it in _items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(flex: 5, child: Text(it.productName)),
                      Expanded(
                        flex: 3,
                        child: Text('${_qty.format(_soldQty(it))} ${it.saleType ?? ''}'.trim(), textAlign: TextAlign.center),
                      ),
                      Expanded(flex: 3, child: Text(_money.format(it.appliedPrice), textAlign: TextAlign.center)),
                      Expanded(flex: 3, child: Text(_money.format(it.itemTotal), textAlign: TextAlign.left)),
                    ]),
                  ),
                const Divider(height: 20),
                line('المجموع', _money.format(subtotal)),
                if (inv.discount > 0) line('الخصم', '- ${_money.format(inv.discount)}', color: Colors.red),
                line('الإجمالي', _money.format(inv.totalAmount), bold: true),
                line('المدفوع', _money.format(inv.amountPaidOnInvoice)),
                if (remaining > 0) line('المتبقي (دين)', _money.format(remaining), color: Colors.orange.shade800),
                if (_returns.isNotEmpty) ...[
                  const Divider(height: 20),
                  const Text('المرتجعات من هذا الإيصال', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                  for (final r in _returns)
                    line(
                      'مرتجع رقم ${r['return_no']} — ${'${r['return_date']}'.split('T').first}',
                      '- ${_money.format((r['total'] as num?) ?? 0)}',
                      color: Colors.red,
                    ),
                  line('الصافي بعد المرتجع', _money.format(inv.totalAmount - returned), bold: true),
                ],
                const SizedBox(height: 12),
                const Text(
                  'الإيصال المكتمل لا يُعدَّل من الكاشير. للتصحيح: «مرتجع» ثم بيع جديد.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Colors.black45),
                ),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }
}
