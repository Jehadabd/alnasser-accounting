// screens/overdue_debts_screen.dart
//
// ⏳ المتأخرون عن السداد — عملاء عليهم دين ولم يشتروا ولم يسدّدوا منذ مدة:
//   • المدة شرائح ظاهرة (3/6/12/24 شهراً أو مدة أخرى)، وأقل مبلغ دين، ومصدر البيانات.
//   • بحث بالاسم أو الهاتف (يتجاهل المسافات) وترتيب (الأقدم توقفاً / الأكبر ديناً).
//   • مجموعات حسب شدة التأخر: أكثر من سنتين، سنة إلى سنتين، أقل من سنة.
//   • لكل عميل: آخر دين، آخر تسديد، مدة التوقف، والمبلغ — الضغط يفتح حسابه.
// مجموع ديون المتأخرين يظهر للمدير فقط.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:intl/intl.dart' hide TextDirection;

import '../accounting/screens/acc_ui.dart' show accAppBar;
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../services/reports_service.dart';
import '../widgets/report_kit.dart' show SourceMenu;
import 'customer_details_screen.dart';

class _K {
  static const bg = Color(0xFFF3F6FB);
  static const navy = Color(0xFF0F3460);
  static const text = Color(0xFF1E293B);
  static const muted = Color(0xFF64748B);
  static const border = Color(0xFFE3E9F1);
  static const severe = Color(0xFFB91C1C);
  static const high = Color(0xFFC2410C);
  static const mid = Color(0xFFB45309);
}

final NumberFormat _nf = NumberFormat('#,##0', 'en_US');
String _fmt(num v) => _nf.format(v);
String _date(DateTime d) => DateFormat('yyyy/MM/dd', 'en').format(d);

/// نافذة اختيار مدة التوقف (تُستعمل من سجل الديون ومن هذه الشاشة).
Future<int?> pickOverdueMonths(BuildContext context, {int initial = 12}) {
  final ctrl = TextEditingController(text: '$initial');
  var selected = initial;
  const presets = [3, 6, 12, 24];
  return showDialog<int>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) {
        void submit() {
          final n = int.tryParse(ctrl.text.trim());
          if (n != null && n > 0) Navigator.of(ctx).pop(n);
        }

        return AlertDialog(
          icon: const Icon(Icons.hourglass_empty_rounded, color: _K.high, size: 32),
          title: const Text('المتأخرون عن السداد', textAlign: TextAlign.center),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text(
                'عملاء عليهم دين ولم يشتروا ولم يسدّدوا منذ:',
                textAlign: TextAlign.center,
                style: TextStyle(color: _K.muted),
              ),
              const SizedBox(height: 14),
              Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
                for (final m in presets)
                  ChoiceChip(
                    label: Text('${m == 12 ? 'سنة' : (m == 24 ? 'سنتين' : '$m أشهر')} فأكثر'),
                    selected: selected == m,
                    showCheckmark: false,
                    selectedColor: _K.navy,
                    labelStyle: TextStyle(color: selected == m ? Colors.white : _K.text, fontWeight: FontWeight.w700),
                    onSelected: (_) => setD(() {
                      selected = m;
                      ctrl.text = '$m';
                    }),
                  ),
              ]),
              const SizedBox(height: 14),
              TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                decoration: InputDecoration(
                  labelText: 'أو اكتب عدد الأشهر',
                  suffixText: 'شهر',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onChanged: (v) => setD(() => selected = int.tryParse(v.trim()) ?? -1),
                onSubmitted: (_) => submit(),
              ),
            ]),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('إلغاء')),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: _K.navy),
              onPressed: (int.tryParse(ctrl.text.trim()) ?? 0) > 0 ? submit : null,
              icon: const Icon(Icons.search_rounded),
              label: const Text('عرض المتأخرين'),
            ),
          ],
        );
      },
    ),
  );
}

class OverdueDebtsScreen extends StatefulWidget {
  final int initialMonths;
  const OverdueDebtsScreen({super.key, this.initialMonths = 12});

  @override
  State<OverdueDebtsScreen> createState() => _OverdueDebtsScreenState();
}

class _Row {
  _Row(this.map)
      : id = map['id'] as int?,
        name = map['name']?.toString() ?? 'غير معروف',
        phone = map['phone']?.toString() ?? '',
        address = map['address']?.toString() ?? '',
        debt = (map['current_total_debt'] as num?)?.toDouble() ?? 0,
        last = DateTime.tryParse('${map['last_transaction_date'] ?? ''}'),
        lastPay = DateTime.tryParse('${map['last_payment_date'] ?? ''}'),
        lastDebt = DateTime.tryParse('${map['last_debt_date'] ?? ''}');
  final Map<String, dynamic> map;
  final int? id;
  final String name;
  final String phone;
  final String address;
  final double debt;
  final DateTime? last;
  final DateTime? lastPay;
  final DateTime? lastDebt;

  /// أشهر التوقف (999 = لا حركة إطلاقاً).
  int get months => last == null ? 999 : (DateTime.now().difference(last!).inDays / 30).floor();

  String get durationText {
    if (last == null) return 'لا حركة مسجلة';
    final m = months;
    if (m >= 12) {
      final y = m ~/ 12, r = m % 12;
      return 'متوقف منذ ${y == 1 ? 'سنة' : (y == 2 ? 'سنتين' : '$y سنوات')}${r > 0 ? ' و$r شهر' : ''}';
    }
    return 'متوقف منذ $m شهر';
  }
}

class _OverdueDebtsScreenState extends State<OverdueDebtsScreen> {
  final ReportsService _reportsService = ReportsService();
  final DatabaseService _db = DatabaseService();
  final _search = TextEditingController();
  List<_Row> _rows = [];
  bool _isLoading = true;
  late int _selectedMonths;
  double _minimumDebt = 0;
  String _source = 'all';
  bool _byAmount = false;

  bool get _isAdmin => AuthService().isAdmin;

  @override
  void initState() {
    super.initState();
    _selectedMonths = widget.initialMonths;
    _search.addListener(() => setState(() {}));
    _loadData();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      _reportsService.reportSourceFilter = _source;
      final debts = await _reportsService.getOverdueDebtsInMonths(
        monthsInactivity: _selectedMonths,
        minimumDebt: _minimumDebt,
      );
      if (!mounted) return;
      setState(() {
        _rows = [for (final d in debts) _Row(Map<String, dynamic>.from(d))];
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ في تحميل البيانات: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _setMonths(int m) {
    setState(() => _selectedMonths = m);
    _loadData();
  }

  /// بحث يتجاهل المسافات والهمزات: «عبدالرحمن» = «عبد الرحمن».
  static String _norm(String s) => s
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll(RegExp('[أإآ]'), 'ا')
      .replaceAll('ة', 'ه')
      .replaceAll('ى', 'ي')
      .replaceAll('ؤ', 'و')
      .replaceAll('ئ', 'ي')
      .toLowerCase();

  List<_Row> get _visible {
    final q = _norm(_search.text);
    final list = [
      for (final r in _rows)
        if (q.isEmpty || _norm(r.name).contains(q) || _norm(r.phone).contains(q)) r
    ];
    if (_byAmount) list.sort((a, b) => b.debt.compareTo(a.debt));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _visible;
    return Scaffold(
      backgroundColor: _K.bg,
      appBar: accAppBar(
        'المتأخرون عن السداد',
        icon: Icons.hourglass_empty_rounded,
        subtitle: 'عليهم دين ولم يشتروا أو يسدّدوا منذ ${_monthsLabel(_selectedMonths)} أو أكثر',
        actions: [
          SourceMenu(
            value: _source,
            onChanged: (v) {
              _source = v;
              _loadData();
            },
          ),
          IconButton(
            tooltip: 'تحديث',
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _loadData,
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(children: [
            Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 0), child: _controls()),
            if (!_isLoading && _rows.isNotEmpty)
              Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: _summary(rows)),
            Expanded(child: _list(rows)),
          ]),
        ),
      ),
    );
  }

  static String _monthsLabel(int m) => m == 12 ? 'سنة' : (m == 24 ? 'سنتين' : '$m شهر');

  Widget _chip(String label, bool selected, VoidCallback onTap, {IconData? icon}) => Padding(
        padding: const EdgeInsetsDirectional.only(end: 6),
        child: ChoiceChip(
          avatar: icon == null ? null : Icon(icon, size: 16, color: selected ? Colors.white : _K.muted),
          label: Text(label),
          selected: selected,
          showCheckmark: false,
          selectedColor: _K.navy,
          backgroundColor: Colors.white,
          side: BorderSide(color: selected ? _K.navy : _K.border),
          labelStyle: TextStyle(color: selected ? Colors.white : _K.text, fontWeight: FontWeight.w700),
          onSelected: (_) => onTap(),
        ),
      );

  Widget _controls() {
    const presets = [3, 6, 12, 24];
    const minimums = [0.0, 100000.0, 500000.0, 1000000.0];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          const Text('متوقف منذ:', style: TextStyle(color: _K.muted, fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          // «سنة» = سنة فأكثر: من توقف سنة و3 أشهر يظهر أيضاً (آخر حركة قبل تاريخ القطع)
          for (final m in presets) _chip('${_monthsLabel(m)} فأكثر', _selectedMonths == m, () => _setMonths(m)),
          _chip(
            presets.contains(_selectedMonths) ? 'مدة أخرى…' : '$_selectedMonths شهر فأكثر',
            !presets.contains(_selectedMonths),
            () async {
              final m = await pickOverdueMonths(context, initial: _selectedMonths);
              if (m != null) _setMonths(m);
            },
            icon: Icons.tune_rounded,
          ),
          const SizedBox(width: 14),
          const Text('الدين أكثر من:', style: TextStyle(color: _K.muted, fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          for (final v in minimums)
            _chip(v == 0 ? 'أي مبلغ' : _fmt(v), _minimumDebt == v, () {
              setState(() => _minimumDebt = v);
              _loadData();
            }),
        ]),
      ),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _search,
            decoration: InputDecoration(
              hintText: 'بحث بالاسم أو الهاتف',
              prefixIcon: const Icon(Icons.search_rounded, color: _K.navy),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(icon: const Icon(Icons.close_rounded), onPressed: _search.clear),
              filled: true,
              fillColor: Colors.white,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _K.border)),
              enabledBorder:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _K.border)),
              focusedBorder:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _K.navy, width: 1.6)),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('الأقدم توقفاً'), icon: Icon(Icons.history_rounded, size: 16)),
            ButtonSegment(value: true, label: Text('الأكبر ديناً'), icon: Icon(Icons.trending_up_rounded, size: 16)),
          ],
          selected: {_byAmount},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => _byAmount = s.first),
        ),
      ]),
    ]);
  }

  Widget _summary(List<_Row> rows) {
    final total = rows.fold<double>(0, (s, r) => s + r.debt);
    final oldest = rows.isEmpty ? 0 : rows.map((r) => r.months).reduce((a, b) => a > b ? a : b);
    Widget tile(String label, String value, IconData icon, Color c) => Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _K.border),
            ),
            child: Row(children: [
              Icon(icon, color: c, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: const TextStyle(fontSize: 12, color: _K.muted)),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: c)),
                  ),
                ]),
              ),
            ]),
          ),
        );
    return Row(children: [
      tile('عدد المتأخرين', '${rows.length} عميل', Icons.groups_rounded, _K.navy),
      if (_isAdmin) ...[
        const SizedBox(width: 10),
        tile('مجموع ديونهم', _fmt(total), Icons.account_balance_wallet_rounded, _K.severe),
      ],
      const SizedBox(width: 10),
      tile('أطول توقف', oldest >= 999 ? 'بلا حركة' : (oldest >= 12 ? '${oldest ~/ 12} سنة و${oldest % 12} شهر' : '$oldest شهر'),
          Icons.hourglass_bottom_rounded, _K.high),
    ]);
  }

  Widget _list(List<_Row> rows) {
    if (_isLoading) return const Center(child: CircularProgressIndicator(color: _K.navy));
    if (rows.isEmpty) {
      final searching = _search.text.trim().isNotEmpty;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(searching ? Icons.search_off_rounded : Icons.verified_rounded, size: 60,
                color: searching ? _K.border : const Color(0xFF86EFAC)),
            const SizedBox(height: 12),
            Text(
              searching ? 'لا متأخر يطابق البحث' : 'لا متأخرين منذ ${_monthsLabel(_selectedMonths)}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _K.text),
            ),
            const SizedBox(height: 4),
            Text(
              searching ? 'جرّب جزءاً من الاسم أو آخر أرقام الهاتف.' : 'كل من عليه دين اشترى أو سدّد خلال هذه المدة.',
              style: const TextStyle(color: _K.muted),
            ),
          ]),
        ),
      );
    }
    // مجموعات حسب شدة التأخر (بترتيب الأشد أولاً، إلا عند الترتيب بالمبلغ)
    final groups = <(String, Color, List<_Row>)>[
      ('أكثر من سنتين', _K.severe, [for (final r in rows) if (r.months >= 24) r]),
      ('من سنة إلى سنتين', _K.high, [for (final r in rows) if (r.months >= 12 && r.months < 24) r]),
      ('أقل من سنة', _K.mid, [for (final r in rows) if (r.months < 12) r]),
    ];
    final children = <Widget>[];
    if (_byAmount) {
      for (var i = 0; i < rows.length; i++) {
        children.add(_card(rows[i], i + 1, _colorFor(rows[i])));
      }
    } else {
      var n = 0;
      for (final g in groups) {
        if (g.$3.isEmpty) continue;
        final sum = g.$3.fold<double>(0, (s, r) => s + r.debt);
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
          child: Row(children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: g.$2, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text(g.$1, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: g.$2)),
            const SizedBox(width: 8),
            Text('${g.$3.length} عميل${_isAdmin ? ' • ${_fmt(sum)}' : ''}', style: const TextStyle(color: _K.muted)),
            const SizedBox(width: 10),
            const Expanded(child: Divider(color: _K.border)),
          ]),
        ));
        for (final r in g.$3) {
          children.add(_card(r, ++n, g.$2));
        }
      }
    }
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 30), children: children),
    );
  }

  Color _colorFor(_Row r) => r.months >= 24 ? _K.severe : (r.months >= 12 ? _K.high : _K.mid);

  Widget _card(_Row r, int n, Color c) {
    final initial = r.name.trim().isEmpty ? '؟' : r.name.trim().substring(0, 1);
    final contact = [if (r.phone.isNotEmpty) r.phone, if (r.address.isNotEmpty) r.address];
    Widget info(IconData icon, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: _K.muted),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(fontSize: 12.5, color: _K.muted)),
        ]);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: _K.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openCustomerDetails(r),
          child: Container(
            decoration: BoxDecoration(border: BorderDirectional(start: BorderSide(color: c, width: 4))),
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Row(children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: c.withValues(alpha: 0.10),
                child: Text(initial, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: c)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _K.text)),
                  if (contact.isNotEmpty)
                    Text(contact.join(' • '),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: _K.muted)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 14, runSpacing: 4, children: [
                    info(Icons.add_circle_outline_rounded, r.lastDebt == null ? 'لا دين مسجل' : 'آخر دين ${_date(r.lastDebt!)}'),
                    info(Icons.payments_outlined, r.lastPay == null ? 'لم يسدّد أبداً' : 'آخر تسديد ${_date(r.lastPay!)}'),
                  ]),
                ]),
              ),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(_fmt(r.debt),
                    textDirection: TextDirection.ltr,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: c)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(20)),
                  child: Text(r.durationText, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: c)),
                ),
              ]),
              if (r.phone.isNotEmpty)
                IconButton(
                  tooltip: 'نسخ الهاتف',
                  icon: const Icon(Icons.copy_rounded, size: 18, color: _K.muted),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: r.phone));
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('نُسخ رقم الهاتف'), duration: Duration(seconds: 1)));
                  },
                ),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _openCustomerDetails(_Row r) async {
    if (r.id == null) return;
    try {
      final customer = await _db.getCustomerById(r.id!);
      if (customer != null && mounted) {
        await Navigator.push(context, MaterialPageRoute(builder: (context) => CustomerDetailsScreen(customer: customer)));
        if (mounted) _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ في فتح تفاصيل العميل: $e')));
      }
    }
  }
}
