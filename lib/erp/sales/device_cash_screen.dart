// lib/erp/sales/device_cash_screen.dart
//
// 🖥️ «صندوق ومخزن هذا الجهاز» (المبيعات ← أدوات البيع):
//   • صندوق ومخزن كل شاشة على هذه الحاسبة (تعدد الشاشات) — وتعديلها.
//   • كل الصناديق: رصيدها في الحسابات، ومبيعات اليوم المختار التي سُجّلت عليها
//     (فواتير اليوم كما بيعت، وتعديلات اليوم على فواتير سابقة، والصافي، والمقبوض)
//     ومن يستعملها من الشاشات. أرقام الصندوق المشترك تظهر مرة واحدة هنا لا تحت كل شاشة.
//
// القراءة فقط إلا زر «تعديل» (يكتب إعداد الشاشة على هذا الجهاز، لا يمسّ أي مبلغ)،
// وزر «إنشاء صندوق خاص» (بعد موافقة: صندوق جديد وحسابه برصيد صفر، يُربط بالشاشة).
// الأرقام من محرك وقائع المبيعات نفسه (SalesFacts) فتطابق «مبيعات اليوم» في المركز.
// الفاتورة تُنسب إلى صندوقها (cash_box_id)، والفاتورة بلا صندوق تُنسب إلى الصندوق
// الافتراضي — كما يرحّلها محرك الترحيل.

import 'package:flutter/material.dart';

import '../../accounting/screens/acc_ui.dart' show fmtMoney, pickDate;
import '../../accounting/vouchers_service.dart';
import '../../org/org_service.dart';
import '../../services/reports/sales_facts.dart';
import '../../services/seat_service.dart';
import '../../widgets/settings_kit.dart';
import '../device_defaults.dart';
import '../erp_common.dart' show erpDb;
import '../pickers.dart' show CashBoxDropdown, WarehouseDropdown;

/// أرقام صندوق واحد في اليوم المختار، مفصولة كي لا يُقرأ الصافي كمبيعات:
///   • [count]/[sales]/[paid]: فواتير هذا اليوم كما بيعت في يومها (تعديلها في يوم لاحق
///     لا يغيّر يومها — واقعة ‎−1 من SalesFacts).
///   • [editSales]/[editPaid]: تعديلات بالقلم في هذا اليوم على فواتير أيام سابقة
///     (الإرجاع سالب، والإضافة موجبة) — واقعة ‎+1.
class _BoxDay {
  int count = 0;
  double sales = 0;
  double paid = 0;
  final Set<int> editedInvoices = {};
  double editSales = 0;
  double editPaid = 0;

  double get net => sales + editSales;
  double get netPaid => paid + editPaid;
}

class DeviceCashScreen extends StatefulWidget {
  const DeviceCashScreen({super.key});

  @override
  State<DeviceCashScreen> createState() => _DeviceCashScreenState();
}

class _DeviceCashScreenState extends State<DeviceCashScreen> {
  DateTime _day = DateTime.now();
  bool _loading = true;
  String? _error;
  List<CashBox> _boxes = const [];
  Map<int, double> _balances = const {};
  Map<int, String> _warehouses = const {};
  List<SeatDefaults> _seats = const [];
  Set<int> _openSeats = const {};
  Map<int, _BoxDay> _byBox = const {};
  int? _defaultBoxId;
  int _loadSeq = 0;

  int get _seatCount => SeatService.allowed < 1 ? 1 : SeatService.allowed;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final seq = ++_loadSeq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = await erpDb();
      final svc = VouchersService();
      final boxes = await svc.cashBoxes(activeOnly: false);
      final balances = await svc.cashBoxBalances();
      final wh = await OrgService().warehouses();
      final seats = await DeviceDefaults.allSeats(_seatCount);

      // الشاشات المفتوحة الآن على هذه الحاسبة
      final open = <int>{SeatService.seat};
      try {
        final now = DateTime.now().millisecondsSinceEpoch;
        final r = await db.rawQuery('SELECT seat_no FROM app_seats WHERE device_id = ? AND heartbeat_at >= ?',
            [SeatService.deviceId, now - 75 * 1000]);
        for (final x in r) {
          open.add((x['seat_no'] as num).toInt());
        }
      } catch (_) {}

      // الصندوق الافتراضي كما يختاره محرك الترحيل للفاتورة بلا صندوق
      final def = boxes.where((b) => b.isDefault && b.isActive).toList()..sort((a, b) => a.id.compareTo(b.id));
      final defaultId = def.isEmpty ? null : def.first.id;

      // مبيعات اليوم من محرك الوقائع، ثم صندوق كل فاتورة
      final facts = await SalesFacts.load(db, from: _day, to: _day, includeSalesReturns: false);
      final ids = <int>{for (final i in facts.invoices) i.id, for (final e in facts.edits) e.invoiceId}.toList();
      final boxOf = <int, int?>{};
      for (var i = 0; i < ids.length; i += 500) {
        final chunk = ids.sublist(i, i + 500 > ids.length ? ids.length : i + 500);
        final r = await db.rawQuery(
            'SELECT id, cash_box_id FROM invoices WHERE id IN (${List.filled(chunk.length, '?').join(',')})', chunk);
        for (final x in r) {
          boxOf[x['id'] as int] = (x['cash_box_id'] as num?)?.toInt();
        }
      }
      final known = {for (final b in boxes) b.id};
      int key(int invoiceId) {
        final b = boxOf[invoiceId];
        if (b != null && known.contains(b)) return b;
        return defaultId ?? -1; // -1 = النقدية الرئيسية (لا صندوق افتراضي)
      }

      final byBox = <int, _BoxDay>{};
      for (final inv in facts.invoices) {
        final d = byBox.putIfAbsent(key(inv.id), _BoxDay.new);
        d.count++;
        d.sales += inv.total;
        d.paid += inv.paid;
      }
      for (final e in facts.edits) {
        final d = byBox.putIfAbsent(key(e.invoiceId), _BoxDay.new);
        if (e.sign > 0) {
          // تعديل في هذا اليوم على فاتورة يوم سابق
          d.editedInvoices.add(e.invoiceId);
          d.editSales += e.dTotal;
          d.editPaid += e.dPaid;
        } else {
          // فاتورة هذا اليوم عُدّلت لاحقاً: يُعاد يومها إلى ما بيعت به
          d.sales += e.dTotal;
          d.paid += e.dPaid;
        }
      }

      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _boxes = boxes;
        _balances = balances;
        _warehouses = {for (final w in wh) w.id: w.name};
        _seats = seats;
        _openSeats = open;
        _defaultBoxId = defaultId;
        _byBox = byBox;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  String _boxName(int? id) {
    if (id == null) {
      final d = _boxes.where((b) => b.id == _defaultBoxId).toList();
      return d.isEmpty ? 'الصندوق الافتراضي' : '${d.first.name} (الافتراضي)';
    }
    final b = _boxes.where((x) => x.id == id).toList();
    if (b.isEmpty) return 'صندوق محذوف (#$id)';
    return id == _defaultBoxId ? '${b.first.name} (الافتراضي)' : b.first.name;
  }

  String _whName(int? id) => id == null ? 'المخزن الافتراضي' : (_warehouses[id] ?? 'مخزن محذوف (#$id)');

  /// الصندوق الذي تذهب إليه فعلاً مبيعات الشاشة.
  int? _effectiveBox(SeatDefaults s) => s.cashBoxId ?? _defaultBoxId;

  /// الشاشات الأخرى على هذه الحاسبة التي تذهب مبيعاتها إلى صندوق الشاشة [s] نفسه.
  List<int> _sharers(SeatDefaults s) => [
        for (final o in _seats)
          if (o.seat != s.seat && _effectiveBox(o) == _effectiveBox(s)) o.seat,
      ];

  /// على الصندوق الافتراضي؟ (لا صندوق، أو اختير الافتراضي نفسه صراحة) — وفيه أيضاً
  /// كل فاتورة بلا صندوق (القديمة والواصلة بالمزامنة)، فلا تُنسب مبيعاته لشاشة.
  bool _onDefault(SeatDefaults s) => _effectiveBox(s) == _defaultBoxId;

  /// حالة صندوق الشاشة كما تُعرض: (النص، مضبوط فعلاً؟).
  (String, bool) _boxState(SeatDefaults s) {
    if (s.inherited) return ('غير مضبوطة — تأخذ إعداد الشاشة الأولى', false);
    if (_onDefault(s)) return ('على الصندوق الافتراضي — لا صندوق خاص', false);
    final sh = _sharers(s);
    if (sh.isNotEmpty) return ('صندوق مشترك مع الشاشة ${sh.join(' و ')}', false);
    return ('صندوق خاص مضبوط', true);
  }

  /// اسم لصندوق جديد لا يتكرر بين الصناديق الموجودة.
  String _newBoxName(SeatDefaults s) {
    final base = _seatCount > 1 ? 'درج الشاشة ${s.seat}' : 'درج هذا الجهاز';
    final names = {for (final b in _boxes) b.name.trim()};
    if (!names.contains(base)) return base;
    for (var i = 2;; i++) {
      final n = '$base ($i)';
      if (!names.contains(n)) return n;
    }
  }

  /// ينشئ صندوقاً جديداً (وحسابه برصيد صفر) ويربطه بالشاشة — بعد موافقة صريحة.
  /// لا يُنقل أي مبلغ ولا تُمسّ الفواتير المحفوظة.
  Future<void> _createOwnBox(SeatDefaults s, int? warehouseId) async {
    final name = _newBoxName(s);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('صندوق خاص جديد'),
        content: Text(
          'سيُنشأ صندوق «$name» وحسابه في دليل الحسابات (تحت النقدية) برصيد صفر، '
          'ويُربط ${_seatCount > 1 ? 'بالشاشة ${s.seat}' : 'بهذا الجهاز'}.\n\n'
          'لا يُنقل أي مبلغ، والفواتير المحفوظة تبقى على صندوقها. '
          'الفواتير الجديدة فقط تُسجَّل على الصندوق الجديد.',
          style: const TextStyle(height: 1.6),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إنشاء وربط')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final id = await VouchersService().createCashBox(name);
      await DeviceDefaults.set(seat: s.seat, cashBoxId: id, warehouseId: warehouseId);
      if (!mounted) return;
      setToast(context, 'أُنشئ «$name» ورُبط ${_seatCount > 1 ? 'بالشاشة ${s.seat}' : 'بهذا الجهاز'}');
      _load();
    } catch (e) {
      if (mounted) setToast(context, 'تعذّر إنشاء الصندوق: $e', error: true);
    }
  }

  Future<void> _edit(SeatDefaults s) async {
    int? box = s.cashBoxId;
    int? wh = s.warehouseId;
    final multi = _seatCount > 1;
    final hasOwn = _boxState(s).$2;
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(multi ? 'صندوق ومخزن الشاشة ${s.seat}' : 'صندوق ومخزن هذا الجهاز'),
          content: SizedBox(
            width: 440,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text(
                'كل فاتورة بيع تُحفظ من هذه الشاشة (القائمة والكاشير) تُسجَّل على هذا الصندوق وتُخصم من هذا المخزن. '
                'الفواتير المحفوظة قبل التغيير تبقى على صندوقها.',
                style: TextStyle(height: 1.5),
              ),
              const SizedBox(height: 14),
              CashBoxDropdown(value: box, width: 420, onChanged: (b) => set(() => box = b?.id)),
              const SizedBox(height: 10),
              WarehouseDropdown(value: wh, width: 420, onChanged: (w) => set(() => wh = w?.id)),
              if (!hasOwn) ...[
                const SizedBox(height: 12),
                SetBanner(multi
                    ? 'اجعل لكل شاشة صندوقاً خاصاً بها لتُعرف مبيعات كل شاشة ويُعدّ درج كل كاشير وحده.'
                    : 'هذا الجهاز على الصندوق الافتراضي؛ صندوق خاص يفصل درجه عن بقية الأجهزة.'),
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(ctx, 'new'),
                    icon: const Icon(Icons.add_card_rounded, size: 18),
                    label: Text(multi ? 'إنشاء صندوق خاص لهذه الشاشة' : 'إنشاء صندوق خاص لهذا الجهاز'),
                  ),
                ),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, 'none'), child: const Text('بلا (الافتراضي)')),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('حفظ')),
          ],
        ),
      ),
    );
    if (res == null) return;
    if (res == 'new') {
      await _createOwnBox(s, wh);
      return;
    }
    try {
      if (res == 'none') {
        await DeviceDefaults.set(seat: s.seat);
      } else {
        await DeviceDefaults.set(seat: s.seat, cashBoxId: box, warehouseId: wh);
      }
      if (!mounted) return;
      setToast(context, multi ? 'حُفظ إعداد الشاشة ${s.seat}' : 'حُفظ صندوق ومخزن هذا الجهاز');
      _load();
    } catch (e) {
      if (mounted) setToast(context, 'تعذّر الحفظ: $e', error: true);
    }
  }

  // ═══════════════════════════ الواجهة ═══════════════════════════

  @override
  Widget build(BuildContext context) {
    final multi = _seatCount > 1;
    return SettingsScaffold(
      title: 'صندوق ومخزن هذا الجهاز',
      icon: Icons.point_of_sale_rounded,
      subtitle: multi ? 'لكل شاشة صندوقها — ومبيعات كل صندوق' : 'صندوق فواتير هذا الجهاز ومخزنها — ومبيعات كل صندوق',
      maxWidth: 1040,
      actions: [IconButton(tooltip: 'تحديث', onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      loading: _loading && _boxes.isEmpty,
      children: [
        if (_error != null) SetBanner('تعذّر التحميل: $_error', kind: SetBannerKind.error),
        _hero(),
        _dayBar(),
        _seatsCard(),
        _boxesSection(),
        const SetBanner(
          'الفاتورة تُنسب إلى الصندوق الذي سُجّلت عليه، لا إلى الشاشة. لذلك تظهر مبيعات كل شاشة منفصلة فقط '
          'إن كان لها صندوق خاص بها؛ والأيام التي كانت فيها الشاشات على صندوق واحد لا يمكن فصلها. '
          'الطرفيات على الشبكة لكل منها إعدادها على جهازها، وتظهر مبيعاتها هنا تحت صندوقها.\n'
          'صافي اليوم = فواتير اليوم كما بيعت + تعديلات اليوم بالقلم على فواتير أيام سابقة '
          '(الإرجاع منها يُنقصه وقد يجعله سالباً، والتعديل يبقى على صندوق فاتورته الأصلي).',
        ),
      ],
    );
  }

  Widget _hero() {
    final me = _seats.where((s) => s.seat == SeatService.seat).toList();
    final s = me.isEmpty ? null : me.first;
    final multi = _seatCount > 1;
    return SetHero(
      icon: Icons.point_of_sale_rounded,
      color: kSetGreen,
      title: multi ? 'هذه الشاشة: رقم ${SeatService.seat} من $_seatCount' : 'هذا الجهاز',
      text: s == null
          ? '...'
          : 'تُسجَّل مبيعاتها على «${_boxName(s.cashBoxId)}» وتُخصم من «${_whName(s.warehouseId)}».',
      status: s == null
          ? null
          : SetStatusPill(_boxState(s).$1, ok: _boxState(s).$2),
    );
  }

  Widget _dayBar() {
    final today = DateUtils.isSameDay(_day, DateTime.now());
    final yesterday = DateUtils.isSameDay(_day, DateTime.now().subtract(const Duration(days: 1)));
    void go(DateTime d) {
      setState(() => _day = d);
      _load();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        const Text('مبيعات يوم:', style: TextStyle(fontWeight: FontWeight.w800, color: kSetText)),
        ChoiceChip(label: const Text('اليوم'), selected: today, onSelected: (_) => go(DateTime.now())),
        ChoiceChip(
            label: const Text('أمس'),
            selected: yesterday,
            onSelected: (_) => go(DateTime.now().subtract(const Duration(days: 1)))),
        ActionChip(
          avatar: const Icon(Icons.calendar_month_rounded, size: 18),
          label: Text('${_day.year}/${_day.month.toString().padLeft(2, '0')}/${_day.day.toString().padLeft(2, '0')}'),
          onPressed: () async {
            final d = await pickDate(context, initial: _day);
            if (d != null) go(d);
          },
        ),
        if (_loading) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
      ]),
    );
  }

  // ─── الشاشات ───

  Widget _seatsCard() {
    final multi = _seatCount > 1;
    // شاشات تتشارك صندوقاً واحداً: مبيعاتها لا تنفصل
    final byBox = <int?, List<int>>{};
    for (final s in _seats) {
      byBox.putIfAbsent(_effectiveBox(s), () => []).add(s.seat);
    }
    final shared = byBox.values.where((l) => l.length > 1).toList();
    return SetCard(
      title: multi ? 'الشاشات على هذه الحاسبة' : 'هذا الجهاز',
      subtitle: multi ? 'لكل شاشة صندوقها ومخزنها — الإعداد محفوظ على هذه الحاسبة' : null,
      icon: multi ? Icons.desktop_windows_rounded : Icons.computer_rounded,
      color: kSetNavy,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 8),
        if (multi && shared.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SetBanner(
              [
                for (final l in shared) 'الشاشات ${l.join(' و ')} على الصندوق نفسه — مبيعاتها تظهر مجتمعة.',
              ].join('\n'),
              kind: SetBannerKind.warn,
            ),
          ),
        LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth > 760 ? 3 : (c.maxWidth > 480 ? 2 : 1);
          final w = (c.maxWidth - (cols - 1) * 12) / cols;
          return Wrap(spacing: 12, runSpacing: 12, children: [
            for (final s in _seats) SizedBox(width: w, child: _seatTile(s, multi)),
          ]);
        }),
      ]),
    );
  }

  Widget _seatTile(SeatDefaults s, bool multi) {
    final mine = s.seat == SeatService.seat;
    final open = _openSeats.contains(s.seat);
    final (state, own) = _boxState(s);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: mine ? const Color(0xFFF0F7FF) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: mine ? kSetBlue.withValues(alpha: 0.45) : kSetBorder, width: mine ? 1.4 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: kSetNavy, borderRadius: BorderRadius.circular(11)),
            child: multi
                ? Text('${s.seat}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16))
                : const Icon(Icons.computer_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(multi ? 'الشاشة ${s.seat}' : 'هذا الجهاز',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: kSetText)),
              if (multi)
                Row(children: [
                  Icon(Icons.circle, size: 8, color: open ? kSetGreen : const Color(0xFFCBD5E1)),
                  const SizedBox(width: 5),
                  Text(mine ? 'هذه الشاشة' : (open ? 'مفتوحة' : 'مغلقة'),
                      style: TextStyle(fontSize: 12, color: open ? kSetGreen : kSetMuted, fontWeight: FontWeight.w700)),
                ]),
            ]),
          ),
          IconButton.filledTonal(
            tooltip: 'تعديل',
            onPressed: () => _edit(s),
            icon: const Icon(Icons.edit_rounded, size: 18),
          ),
        ]),
        const SizedBox(height: 12),
        _kv(Icons.account_balance_wallet_rounded, _boxName(s.cashBoxId)),
        const SizedBox(height: 6),
        _kv(Icons.warehouse_rounded, _whName(s.warehouseId)),
        const SizedBox(height: 8),
        Row(children: [
          Icon(own ? Icons.check_circle_rounded : Icons.info_rounded, size: 15, color: own ? kSetGreen : kSetOrange),
          const SizedBox(width: 6),
          Expanded(
            child: Text(state,
                style: TextStyle(fontSize: 11.5, color: own ? kSetGreen : kSetOrange, fontWeight: FontWeight.w700)),
          ),
        ]),
        const Divider(height: 22, color: Color(0xFFEEF2F7)),
        _seatSales(s, own),
      ]),
    );
  }

  /// مبيعات الشاشة تُعرض أرقاماً فقط إن كان صندوقها لها وحدها؛ وإلا فالأرقام أرقام
  /// صندوق مشترك (تظهر مرة واحدة في «كل الصناديق») لا أرقام الشاشة.
  Widget _seatSales(SeatDefaults s, bool own) {
    if (!own) {
      final sh = _sharers(s);
      final why = _onDefault(s)
          ? 'مبيعاتها ضمن الصندوق الافتراضي مع الفواتير بلا صندوق — لا تنفصل عنها.'
          : (sh.isEmpty
              ? 'اضبط لها صندوقاً لتظهر مبيعاتها وحدها.'
              : 'مبيعاتها مجتمعة مع الشاشة ${sh.join(' و ')} في صندوق واحد — لا تنفصل.');
      return Text('$why انظر «كل الصناديق».', style: const TextStyle(fontSize: 12, color: kSetMuted, height: 1.5));
    }
    final d = _byBox[_effectiveBox(s) ?? -1];
    final net = d?.net ?? 0;
    return Row(children: [
      Expanded(child: _mini('فواتير اليوم', '${d?.count ?? 0}')),
      Expanded(child: _mini('صافي اليوم', fmtMoney(net), color: net < 0 ? kSetRed : kSetText)),
    ]);
  }

  /// مبلغ بإشارته الصريحة (+ للإضافة) — للتعديلات فقط.
  String _signed(double v) => v > 0.004 ? '+${fmtMoney(v)}' : fmtMoney(v);

  Widget _kv(IconData i, String v) => Row(children: [
        Icon(i, size: 17, color: kSetMuted),
        const SizedBox(width: 8),
        Expanded(
            child: Text(v,
                style: const TextStyle(fontWeight: FontWeight.w700, color: kSetText), overflow: TextOverflow.ellipsis)),
      ]);

  Widget _mini(String label, String value, {Color color = kSetText}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11.5, color: kSetMuted)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(value, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: color)),
          ),
        ],
      );

  // ─── كل الصناديق ───

  Widget _boxesSection() {
    final rows = <(int, CashBox?)>[
      for (final b in _boxes)
        if (b.isActive || (_balances[b.id] ?? 0).abs() > 0.004 || _byBox.containsKey(b.id)) (b.id, b),
      if (_byBox.containsKey(-1)) (-1, null),
    ];
    final totalSales = _byBox.values.fold<double>(0, (s, d) => s + d.sales);
    final totalEdits = _byBox.values.fold<double>(0, (s, d) => s + d.editSales);
    final totalEdited = _byBox.values.fold<int>(0, (s, d) => s + d.editedInvoices.length);
    final totalNet = totalSales + totalEdits;
    final totalPaid = _byBox.values.fold<double>(0, (s, d) => s + d.netPaid);
    final totalCount = _byBox.values.fold<int>(0, (s, d) => s + d.count);
    return SetCard(
      title: 'كل الصناديق',
      subtitle: 'الرصيد في الحسابات، ومبيعات اليوم المختار المسجّلة على كل صندوق',
      icon: Icons.account_balance_rounded,
      color: kSetGreen,
      trailing: SetStatusPill('$totalCount فاتورة • صافي ${fmtMoney(totalNet)}', ok: totalNet >= 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 8),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('لا صناديق. أضفها من الحسابات ← الصناديق.', style: TextStyle(color: kSetMuted)),
          ),
        LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth > 760 ? 3 : (c.maxWidth > 480 ? 2 : 1);
          final w = (c.maxWidth - (cols - 1) * 12) / cols;
          return Wrap(spacing: 12, runSpacing: 12, children: [
            for (final (id, b) in rows) SizedBox(width: w, child: _boxTile(id, b)),
          ]);
        }),
        if (rows.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              const Expanded(child: Text('المجموع', style: TextStyle(fontWeight: FontWeight.w900))),
              Expanded(child: _mini('فواتير اليوم', '$totalCount')),
              Expanded(child: _mini('مبيعاتها', fmtMoney(totalSales))),
              if (totalEdited > 0)
                Expanded(
                    child: _mini('تعديل $totalEdited فاتورة سابقة', _signed(totalEdits),
                        color: totalEdits < 0 ? kSetRed : kSetText)),
              Expanded(child: _mini('صافي اليوم', fmtMoney(totalNet), color: totalNet < 0 ? kSetRed : kSetText)),
              Expanded(child: _mini('صافي المقبوض', fmtMoney(totalPaid), color: totalPaid < 0 ? kSetRed : kSetGreen)),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _boxTile(int id, CashBox? b) {
    final d = _byBox[id];
    final bal = b == null ? null : _balances[b.id];
    final users = [
      for (final s in _seats)
        if ((_effectiveBox(s) ?? -1) == id) s.seat,
    ];
    final bank = b?.kind == 'bank';
    final color = b == null || !b.isActive ? kSetMuted : (bank ? kSetBlue : kSetGreen);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kSetBorder),
        boxShadow: const [BoxShadow(color: Color(0x080F172A), blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(11)),
            child: Icon(bank ? Icons.account_balance_rounded : Icons.payments_rounded, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(b?.name ?? 'النقدية الرئيسية',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: kSetText),
                  overflow: TextOverflow.ellipsis),
              Wrap(spacing: 6, children: [
                if (b?.isDefault == true) _tag('الافتراضي', kSetNavy),
                if (b != null && !b.isActive) _tag('موقوف', kSetMuted),
                if (b == null) _tag('فواتير بلا صندوق', kSetOrange),
              ]),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        if (bal != null) ...[
          _mini('الرصيد في الحسابات', fmtMoney(bal), color: bal < 0 ? kSetRed : kSetText),
          const SizedBox(height: 10),
        ],
        Row(children: [
          Expanded(child: _mini('فواتير اليوم', '${d?.count ?? 0}')),
          Expanded(child: _mini('مبيعاتها', fmtMoney(d?.sales ?? 0))),
        ]),
        if ((d?.editedInvoices.length ?? 0) > 0) ...[
          const SizedBox(height: 8),
          _mini('تعديل ${d!.editedInvoices.length} فاتورة من أيام سابقة', _signed(d.editSales),
              color: d.editSales < 0 ? kSetRed : kSetText),
        ],
        const Divider(height: 20, color: Color(0xFFEEF2F7)),
        Row(children: [
          Expanded(
              child: _mini('صافي اليوم', fmtMoney(d?.net ?? 0), color: (d?.net ?? 0) < 0 ? kSetRed : kSetText)),
          Expanded(
              child: _mini('صافي المقبوض', fmtMoney(d?.netPaid ?? 0),
                  color: (d?.netPaid ?? 0) < 0 ? kSetRed : kSetGreen)),
        ]),
        if (users.isNotEmpty && _seatCount > 1) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final s in users)
              Chip(
                visualDensity: VisualDensity.compact,
                avatar: const Icon(Icons.desktop_windows_rounded, size: 15),
                label: Text('شاشة $s', style: const TextStyle(fontSize: 12)),
              ),
          ]),
        ],
      ]),
    );
  }

  Widget _tag(String t, Color c) => Container(
        margin: const EdgeInsets.only(top: 3),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(20)),
        child: Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: c)),
      );
}
