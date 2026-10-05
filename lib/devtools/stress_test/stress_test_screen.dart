// lib/devtools/stress_test/stress_test_screen.dart
//
// 🧪 شاشة اختبار التحمّل الحقيقي (للمدير فقط):
//   الإعدادات ← النظام والأدوات ← «اختبار التحمّل والحسابات»
//
// المراحل:
//   1) المرحلة الكبيرة (المزامنة متوقفة): عملاء + معاملات يدوية وتعديلاتها + فواتير
//      وتعديلاتها ونقلها + تغيير أسماء العملاء وهواتفهم — كلها في القاعدة الحقيقية.
//   2) «التحقق من الحسابات»: يقارن كل رقم في القاعدة بالمتوقع.
//   3) تفعيل المزامنة ← انتظار «المعلّق للرفع» حتى الصفر ← «نشر البصمة».
//   4) الحاسوب الثاني: تفعيل المزامنة وانتظار التنزيل ← «نشر البصمة» ← «مقارنة الحاسوبين».
//   5) «الجولة الحيّة» على الحاسوبين معاً والمزامنة مفعّلة ← نشر ← مقارنة.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/app_provider.dart';
import 'stress_engine.dart';
import 'stress_model.dart';

class StressTestScreen extends StatefulWidget {
  const StressTestScreen({super.key});

  @override
  State<StressTestScreen> createState() => _StressTestScreenState();
}

class _StressTestScreenState extends State<StressTestScreen> {
  // محرّك واحد طوال عمر البرنامج: يمكن إغلاق الشاشة وإعادة فتحها والاختبار يعمل
  static StressEngine? _shared;
  late final StressEngine _e;

  final _customers = TextEditingController(text: '500');
  final _invoices = TextEditingController(text: '10');
  final _edits = TextEditingController(text: '10');
  final _tx = TextEditingController(text: '10');
  final _txMin = TextEditingController(text: '2');
  final _txMax = TextEditingController(text: '3');
  final _products = TextEditingController(text: '40');
  final _liveCount = TextEditingController(text: '50');

  Map<String, int>? _pending;
  List<String> _blockBulk = const [];
  List<String> _blockLive = const [];
  Timer? _timer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final created = _shared == null;
    _e = _shared ??= StressEngine(Provider.of<AppProvider>(context, listen: false));
    if (created) _e.load();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in [_customers, _invoices, _edits, _tx, _txMin, _txMax, _products, _liveCount]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final p = await _e.pendingCounts();
      final b1 = await _e.blockers(needSyncOff: true);
      final b2 = await _e.blockers(needSyncOff: false);
      if (!mounted) return;
      setState(() {
        _pending = p;
        _blockBulk = b1;
        _blockLive = b2;
      });
    } catch (_) {}
  }

  int _int(TextEditingController c, int def) => int.tryParse(c.text.trim()) ?? def;

  void _preset(int customers) => setState(() {
        _customers.text = '$customers';
        _invoices.text = '10';
        _edits.text = '10';
        _tx.text = '10';
        _txMin.text = '2';
        _txMax.text = '3';
        _products.text = customers >= 100 ? '40' : '15';
      });

  String _two(int v) => v.toString().padLeft(2, '0');

  Future<void> _startNew() async {
    final now = DateTime.now();
    final cfg = StressConfig(
      customers: _int(_customers, 500).clamp(1, 5000),
      invoicesPerCustomer: _int(_invoices, 10).clamp(1, 50),
      editsPerInvoice: _int(_edits, 10).clamp(0, 50),
      txPerCustomer: _int(_tx, 10).clamp(0, 50),
      txEditsMin: _int(_txMin, 2).clamp(0, 10),
      txEditsMax: _int(_txMax, 3).clamp(_int(_txMin, 2).clamp(0, 10), 10),
      products: _int(_products, 40).clamp(3, 500),
      seed: now.millisecondsSinceEpoch % 1000000,
      tag: 'T${_two(now.month)}${_two(now.day)}${_two(now.hour)}${_two(now.minute)}',
    );
    final ok = await _confirmTyped(
      title: 'بدء تشغيلة جديدة (${cfg.tag})',
      body: 'سيُكتب في قاعدة البيانات الحقيقية:\n'
          '• ${cfg.customers} عميل باسم «$kStressCustomerPrefix ${cfg.tag}-…»\n'
          '• ${cfg.customers * cfg.txPerCustomer} معاملة يدوية تُعدَّل ${cfg.txEditsMin}–${cfg.txEditsMax} مرات\n'
          '• ${cfg.customers * cfg.invoicesPerCustomer} فاتورة، كل منها تُعدَّل ${cfg.editsPerInvoice} مرات '
          '(${cfg.totalInvoiceSaves} عملية حفظ)\n'
          '• ${cfg.products} مادة باسم «$kStressProductPrefix ${cfg.tag}-…»\n\n'
          'هذه بيانات حقيقية تبقى في القاعدة (وتُرفع لفايربيس عند تفعيل المزامنة). '
          'يُنصح بأخذ نسخة احتياطية أولاً، وعدم استعمال البرنامج لعمل آخر أثناء الاختبار، '
          'ومنع الحاسوب من السكون.',
      word: 'ابدأ',
    );
    if (!ok) return;
    await _e.newRun(cfg);
    unawaited(_e.runBulk());
  }

  Future<bool> _confirmTyped({required String title, required String body, required String word}) async {
    final c = TextEditingController();
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          surfaceTintColor: Colors.transparent,
          title: Text(title),
          content: SizedBox(
            width: 520,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(body, style: const TextStyle(height: 1.6)),
              const SizedBox(height: 14),
              Text('للتأكيد اكتب «$word»:', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              TextField(controller: c, autofocus: true, onChanged: (_) => setD(() {})),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(
              onPressed: c.text.trim() == word ? () => Navigator.pop(ctx, true) : null,
              child: const Text('تأكيد'),
            ),
          ],
        ),
      ),
    );
    c.dispose();
    return r == true;
  }

  Future<void> _run(Future<StressReport?> Function() f) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final rep = await f();
      if (rep != null && mounted) _showReport(rep);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      unawaited(_refresh());
    }
  }

  void _showReport(StressReport rep) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        surfaceTintColor: Colors.transparent,
        title: Row(children: [
          Icon(rep.ok ? Icons.verified : Icons.error_outline, color: rep.ok ? Colors.green : Colors.red),
          const SizedBox(width: 8),
          Expanded(child: Text(rep.ok ? 'مطابق 100% (${rep.checks} فحص)' : '${rep.problems.length} خلل من ${rep.checks} فحص')),
        ]),
        content: SizedBox(
          width: 760,
          height: 520,
          child: SingleChildScrollView(child: SelectableText(rep.toText(), style: const TextStyle(fontSize: 13, height: 1.5))),
        ),
        actions: [
          TextButton(onPressed: _openReports, child: const Text('فتح مجلد التقارير')),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
        ],
      ),
    );
  }

  Future<void> _openReports() async {
    final d = await _e.reportsDir();
    if (Platform.isWindows) {
      await Process.run('explorer', [d.path]);
    }
  }

  Future<void> _live(bool primary) async {
    final ok = await _confirmTyped(
      title: 'الجولة الحيّة — ${primary ? 'الحاسوب الأول' : 'الحاسوب الثاني'}',
      body: 'تعمل والمزامنة مفعّلة على أول ${_int(_liveCount, 50)} عميل اختبار: معاملتان يدويتان وتعديل، '
          'وفاتورة دين بأربعة تعديلات منها نقلها لعميل آخر'
          '${primary ? '، وتغيير اسم وهاتف أول 10 عملاء' : ''}.\n'
          'شغّلها على الحاسوبين في الوقت نفسه، ثم انتظر حتى يصير «المعلّق للرفع» صفراً على الاثنين، '
          'ثم «نشر البصمة» على الاثنين، ثم «مقارنة الحاسوبين».',
      word: 'ابدأ',
    );
    if (!ok) return;
    unawaited(_e.runLive(primary: primary, customers: _int(_liveCount, 50).clamp(2, 500)));
  }

  // ─────────────────────────── الواجهة ───────────────────────────

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F6FA),
        appBar: AppBar(
          title: const Text('اختبار التحمّل والحسابات'),
          actions: [
            TextButton.icon(onPressed: _openReports, icon: const Icon(Icons.folder_open), label: const Text('التقارير')),
            const SizedBox(width: 8),
          ],
        ),
        body: AnimatedBuilder(
          animation: _e,
          builder: (context, _) => LayoutBuilder(builder: (context, box) {
            final wide = box.maxWidth > 1000;
            final left = Column(children: [
              _warningCard(),
              const SizedBox(height: 12),
              _runCard(),
              const SizedBox(height: 12),
              _configCard(),
            ]);
            final right = Column(children: [
              _syncCard(),
              const SizedBox(height: 12),
              _logCard(),
            ]);
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: wide
                  ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: left),
                      const SizedBox(width: 16),
                      Expanded(child: right),
                    ])
                  : Column(children: [left, const SizedBox(height: 12), right]),
            );
          }),
        ),
      ),
    );
  }

  Widget _card({required IconData icon, required Color color, required String title, required List<Widget> children}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE3E8EF)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: color),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        ]),
        const SizedBox(height: 12),
        ...children,
      ]),
    );
  }

  Widget _warningCard() {
    final blocks = _blockBulk;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFC56B)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.warning_amber_rounded, color: Color(0xFFB26A00)),
          SizedBox(width: 8),
          Text('اختبار حقيقي — يكتب في قاعدة البيانات الحقيقية', style: TextStyle(fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 6),
        const Text(
          'كل عملية تمر بالمسار نفسه الذي تستعمله الشاشات (حفظ الفاتورة، إضافة وتعديل المعاملات، تعديل العملاء). '
          'بيانات الاختبار تحمل أسماء تبدأ بـ«عميل اختبار» و«مادة اختبار» ورمز التشغيلة. '
          'المرحلة الكبيرة تعمل والمزامنة متوقفة، ثم تُفعَّل فيُرفع كل شيء.',
          style: TextStyle(height: 1.5, fontSize: 13),
        ),
        if (blocks.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final b in blocks)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('⛔ '),
                Expanded(child: Text(b, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600))),
              ]),
            ),
        ],
      ]),
    );
  }

  Widget _runCard() {
    final c = _e.cfg;
    final truth = _e.truth;
    final hasBulk = c != null && c.customers > 0;
    final progress = hasBulk && c.totalInvoiceSaves > 0 ? (_e.saves / c.totalInvoiceSaves).clamp(0.0, 1.0) : 0.0;
    return _card(
      icon: Icons.play_circle_outline,
      color: Colors.indigo,
      title: c == null ? 'لا توجد تشغيلة' : 'التشغيلة ${c.tag}',
      children: [
        Text(_e.status, style: TextStyle(color: _e.running ? Colors.indigo : Colors.black87, fontWeight: FontWeight.w600)),
        if (hasBulk) ...[
          const SizedBox(height: 10),
          LinearProgressIndicator(value: progress, minHeight: 8, borderRadius: BorderRadius.circular(6)),
          const SizedBox(height: 6),
          Text(
            'العملاء ${_e.nextCustomer}/${c.customers} • حفظ الفواتير ${_e.saves}/${c.totalInvoiceSaves} '
            '• ${(progress * 100).toStringAsFixed(1)}%',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
        if (c != null) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            _chip('عملاء', truth.customers.length),
            _chip('فواتير', truth.invoices.length),
            _chip('معاملات يدوية', truth.customers.values.fold<int>(0, (a, x) => a + x.manual.length)),
            _chip('معاملات حيّة', truth.liveManual.length),
            _chip('مواد', truth.products.length),
            _chip('رفضها البرنامج', truth.refusals.values.fold<int>(0, (a, b) => a + b),
                color: truth.refusals.isEmpty ? null : Colors.orange),
          ]),
        ],
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (_e.running)
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: _e.requestStop,
              icon: const Icon(Icons.stop),
              label: const Text('إيقاف'),
            ),
          if (!_e.running && hasBulk && !_e.bulkDone)
            FilledButton.icon(
              onPressed: _blockBulk.isEmpty ? () => unawaited(_e.runBulk()) : null,
              icon: const Icon(Icons.play_arrow),
              label: Text(_e.nextCustomer == 0 ? 'بدء' : 'متابعة من العميل ${_e.nextCustomer + 1}'),
            ),
          OutlinedButton.icon(
            onPressed: (_e.running || _busy || c == null) ? null : () => _run(() => _e.verify()),
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('التحقق من الحسابات'),
          ),
        ]),
        if (_e.ops.isNotEmpty) ...[
          const SizedBox(height: 10),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('تفاصيل العمليات', style: TextStyle(fontSize: 13)),
            children: [
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final e in (_e.ops.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))) _chip(e.key, e.value),
              ]),
            ],
          ),
        ],
      ],
    );
  }

  Widget _chip(String label, int v, {Color? color}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: (color ?? Colors.indigo).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text('$label: $v', style: TextStyle(fontSize: 12, color: color ?? Colors.indigo.shade700)),
      );

  Widget _num(String label, TextEditingController c) => SizedBox(
        width: 150,
        child: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder()),
        ),
      );

  Widget _configCard() {
    return _card(
      icon: Icons.tune,
      color: Colors.teal,
      title: 'تشغيلة جديدة',
      children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          ActionChip(avatar: const Icon(Icons.bolt, size: 16), label: const Text('تجربة سريعة (20 عميلاً)'), onPressed: () => _preset(20)),
          ActionChip(avatar: const Icon(Icons.all_inclusive, size: 16), label: const Text('الاختبار الكامل (500 عميل)'), onPressed: () => _preset(500)),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 10, runSpacing: 12, children: [
          _num('عدد العملاء', _customers),
          _num('فواتير لكل عميل', _invoices),
          _num('تعديلات لكل فاتورة', _edits),
          _num('معاملات يدوية لكل عميل', _tx),
          _num('أقل تعديل للمعاملة', _txMin),
          _num('أكثر تعديل للمعاملة', _txMax),
          _num('عدد المواد', _products),
        ]),
        const SizedBox(height: 12),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: Colors.teal),
          onPressed: (_e.running || _blockBulk.isNotEmpty) ? null : _startNew,
          icon: const Icon(Icons.rocket_launch_outlined),
          label: const Text('بدء تشغيلة جديدة'),
        ),
        if (_e.cfg != null && !_e.bulkDone && _e.nextCustomer > 0)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('التشغيلة الحالية لم تكتمل — «متابعة» أعلاه يكملها؛ تشغيلة جديدة تبدأ من الصفر برمز جديد.',
                style: TextStyle(fontSize: 12, color: Colors.black54)),
          ),
      ],
    );
  }

  Widget _syncCard() {
    final p = _pending;
    final pendingTotal = p?.values.where((v) => v > 0).fold<int>(0, (a, b) => a + b) ?? 0;
    return _card(
      icon: Icons.cloud_sync_outlined,
      color: Colors.blue,
      title: 'المزامنة والمقارنة بين الحاسوبين',
      children: [
        Row(children: [
          const Text('المعلّق للرفع: ', style: TextStyle(fontWeight: FontWeight.w600)),
          if (p == null)
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
          else
            Expanded(
              child: Text(
                p.entries.map((e) => '${e.key} ${e.value}').join(' • '),
                style: TextStyle(color: pendingTotal == 0 ? Colors.green.shade700 : Colors.orange.shade800),
              ),
            ),
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh, size: 18), tooltip: 'تحديث'),
        ]),
        const SizedBox(height: 4),
        const Text(
          'بعد التحقق من المرحلة الكبيرة: فعّل المزامنة وانتظر حتى يصير المعلّق صفراً، ثم «نشر البصمة». '
          'على الحاسوب الثاني: فعّل المزامنة وانتظر التنزيل، ثم «نشر البصمة» و«مقارنة الحاسوبين».',
          style: TextStyle(fontSize: 12, color: Colors.black54, height: 1.5),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
            onPressed: (_e.running || _busy)
                ? null
                : () => _run(() async {
                      await _e.publish();
                      return null;
                    }),
            icon: const Icon(Icons.cloud_upload_outlined),
            label: const Text('نشر البصمة'),
          ),
          FilledButton.icon(
            onPressed: (_e.running || _busy) ? null : () => _run(() => _e.compareDevices()),
            icon: const Icon(Icons.compare_arrows),
            label: const Text('مقارنة الحاسوبين'),
          ),
        ]),
        const Divider(height: 28),
        const Text('الجولة الحيّة (المزامنة مفعّلة، الحاسوبان معاً)', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        if (_blockLive.isNotEmpty)
          for (final b in _blockLive) Text('⛔ $b', style: const TextStyle(color: Colors.red, fontSize: 12)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          _num('عدد العملاء', _liveCount),
          FilledButton.tonalIcon(
            onPressed: (_e.running || _blockLive.isNotEmpty) ? null : () => _live(true),
            icon: const Icon(Icons.looks_one_outlined),
            label: const Text('الحاسوب الأول'),
          ),
          FilledButton.tonalIcon(
            onPressed: (_e.running || _blockLive.isNotEmpty) ? null : () => _live(false),
            icon: const Icon(Icons.looks_two_outlined),
            label: const Text('الحاسوب الثاني'),
          ),
        ]),
      ],
    );
  }

  Widget _logCard() {
    return _card(
      icon: Icons.receipt_long_outlined,
      color: Colors.blueGrey,
      title: 'السجل',
      children: [
        Container(
          height: 360,
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xFF1E2430), borderRadius: BorderRadius.circular(10)),
          child: _e.log.isEmpty
              ? const Text('—', style: TextStyle(color: Colors.white54))
              : ListView.builder(
                  itemCount: _e.log.length,
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: SelectableText(
                      _e.log[i],
                      style: TextStyle(
                        color: _e.log[i].contains('❌')
                            ? const Color(0xFFFF8A80)
                            : _e.log[i].contains('✅')
                                ? const Color(0xFFA5D6A7)
                                : Colors.white70,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
