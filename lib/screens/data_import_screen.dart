// lib/screens/data_import_screen.dart
//
// 📥 «استيراد من Excel» (الإعدادات ← النظام والأدوات):
//   1) اختر ملف ‎.xlsx أو ‎.csv ← تظهر أوراقه وعدد صفوف كل ورقة.
//   2) اختر الورقة وما تستورده (عملاء / مواد / موردون).
//   3) اربط الأعمدة: لكل حقل قائمة بأعمدة الملف (العنوان + مثال من البيانات).
//      التطبيق يخمّن الربط من العناوين، وأنت تعدّله.
//   4) «معاينة» — لا يُكتب شيء: ما سيُضاف، ومجموع الأرصدة، وما سيُتجاوز ولماذا.
//   5) «استيراد» بعد التأكيد — نسخة احتياطية أولاً، ثم الحفظ مع مطابقة المجاميع.

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../accounting/screens/acc_ui.dart' show pickDate;
import '../services/database_service.dart';
import '../services/import/data_import.dart';
import '../services/import/sheet_reader.dart';
import '../widgets/settings_kit.dart';

String _money(num v) => NumberFormat('#,##0.##', 'en_US').format(v);
String _date(DateTime d) => DateFormat('yyyy/MM/dd').format(d);

class DataImportScreen extends StatefulWidget {
  const DataImportScreen({super.key});

  @override
  State<DataImportScreen> createState() => _DataImportScreenState();
}

class _DataImportScreenState extends State<DataImportScreen> {
  String? _fileName;
  List<SheetTable> _sheets = const [];
  int _sheet = 0;
  ImportKind _kind = ImportKind.customers;
  Map<String, int?> _map = {};
  final ImportOptions _opt = ImportOptions(openingDate: DateTime(DateTime.now().year, DateTime.now().month, 1));
  ImportPlan? _plan;
  ImportResult? _result;
  String? _error;
  bool _busy = false;
  double _progress = 0;

  SheetTable? get _table => _sheets.isEmpty ? null : _sheets[_sheet];

  List<String> get _headers {
    final t = _table;
    if (t == null) return const [];
    return [
      for (var c = 0; c < t.columnCount; c++)
        t.cell(_opt.headerRow, c).trim().isEmpty ? 'عمود ${_colName(c)}' : t.cell(_opt.headerRow, c).trim(),
    ];
  }

  static String _colName(int c) {
    var n = c + 1;
    var s = '';
    while (n > 0) {
      final r = (n - 1) % 26;
      s = String.fromCharCode(65 + r) + s;
      n = (n - 1) ~/ 26;
    }
    return s;
  }

  void _guess() {
    _map = ColumnGuess.guess(_headers, _kind);
    _plan = null;
    _result = null;
  }

  Future<void> _pick() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'csv', 'xls', 'txt'],
      withData: true,
      dialogTitle: 'اختر ملف Excel (‎.xlsx) أو CSV',
    );
    if (res == null || res.files.isEmpty) return;
    final f = res.files.single;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      Uint8List? bytes = f.bytes;
      if (bytes == null && f.path != null) bytes = await File(f.path!).readAsBytes();
      if (bytes == null) throw SheetReadException('تعذّرت قراءة الملف');
      final sheets = SheetReader.read(bytes, f.name);
      // الورقة الافتراضية: أول ورقة فيها بيانات
      var first = sheets.indexWhere((s) => s.rows.length > 1);
      if (first < 0) first = 0;
      setState(() {
        _fileName = f.name;
        _sheets = sheets;
        _sheet = first;
        _opt.headerRow = sheets[first].firstNonEmptyRow;
        _guess();
      });
    } catch (e) {
      setState(() {
        _sheets = const [];
        _fileName = f.name;
        _error = '$e';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _preview() async {
    final t = _table;
    if (t == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final plan = await DataImport.plan(await DatabaseService().database, t, _kind, _map, _opt);
      setState(() => _plan = plan);
    } catch (e) {
      setState(() {
        _plan = null;
        _error = e is ArgumentError ? '${e.message}' : '$e';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final plan = _plan;
    if (plan == null || plan.rows.isEmpty) return;
    final ok = await _confirm(plan);
    if (ok != true) return;
    setState(() {
      _busy = true;
      _progress = 0;
      _error = null;
    });
    try {
      final r = await DataImport.execute(plan, _opt,
          fileName: _fileName ?? '', sheet: _table?.name ?? '', onProgress: (d, t) {
        if (mounted) setState(() => _progress = t == 0 ? 1 : d / t);
      });
      setState(() {
        _result = r;
        _plan = null;
      });
    } catch (e) {
      setState(() => _error = 'لم يُستورد شيء: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirm(ImportPlan plan) {
    final ctrl = TextEditingController();
    final money = plan.kind != ImportKind.products;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('استيراد ${plan.rows.length} ${plan.kind.noun}؟'),
          content: SizedBox(
            width: 460,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (money)
                for (final e in plan.balanceByCurrency.entries)
                  Text('مجموع الأرصدة الافتتاحية (${e.key}): ${_money(e.value)} — بتاريخ ${_date(_opt.openingDate)}',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
              if (!money) Text('مجموع الكميات: ${_money(plan.qtyTotal)}', style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text('سيُتجاوز ${plan.skipped.length} صف (موجود أو مكرر أو فيه خطأ) ولن يُمس أي شيء موجود.'),
              const SizedBox(height: 8),
              const SetBanner('تُؤخذ نسخة احتياطية كاملة قبل الاستيراد. إن لم تُطابق المجاميع المحفوظة المعاينة يُلغى الاستيراد كله.',
                  kind: SetBannerKind.info),
              const SizedBox(height: 10),
              TextField(
                controller: ctrl,
                autofocus: true,
                onChanged: (_) => setD(() {}),
                decoration: const InputDecoration(labelText: 'للتأكيد اكتب: استيراد', border: OutlineInputBorder()),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(
              onPressed: ctrl.text.trim() == 'استيراد' ? () => Navigator.pop(ctx, true) : null,
              child: const Text('استيراد'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = _table;
    return SettingsScaffold(
      title: 'استيراد من Excel',
      icon: Icons.upload_file_rounded,
      subtitle: 'عملاء وأرصدتهم، مواد، موردون — من ملف أي برنامج آخر',
      children: [
        _fileCard(),
        if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: SetBanner(_error!, kind: SetBannerKind.error)),
        if (t != null) ...[
          _whatCard(t),
          _mapCard(t),
          if (_kind != ImportKind.products) _balanceCard(),
          _actionsRow(),
          if (_busy && _progress > 0) Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: LinearProgressIndicator(value: _progress),
          ),
          if (_plan != null) _planCard(_plan!),
          if (_result != null) _resultCard(_result!),
        ],
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _fileCard() => SetCard(
        title: '1. الملف',
        subtitle: _fileName == null ? 'Excel ‏(‎.xlsx) أو CSV — الملف لا يتغير' : _fileName!,
        icon: Icons.description_outlined,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SetBanner(
            'ملف ‎.xls القديم: افتحه في Excel واحفظه «مصنف Excel ‎(.xlsx)». الاستيراد يضيف الجديد فقط: '
            'أي عميل أو مادة أو مورد موجود بالاسم نفسه يُتجاوز ولا يُغيَّر رصيده ولا سعره.',
          ),
          const SizedBox(height: 10),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.icon(
              onPressed: _busy ? null : _pick,
              icon: const Icon(Icons.folder_open_rounded),
              label: Text(_fileName == null ? 'اختر الملف' : 'اختر ملفاً آخر'),
            ),
          ),
        ]),
      );

  Widget _whatCard(SheetTable t) => SetCard(
        title: '2. الورقة وما تستورده',
        subtitle: '${t.rows.length} صف في «${t.name}»',
        icon: Icons.table_chart_outlined,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (_sheets.length > 1)
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (var i = 0; i < _sheets.length; i++)
                ChoiceChip(
                  label: Text('${_sheets[i].name} (${_sheets[i].rows.length})'),
                  selected: _sheet == i,
                  onSelected: (_) => setState(() {
                    _sheet = i;
                    _opt.headerRow = _sheets[i].firstNonEmptyRow;
                    _guess();
                  }),
                ),
            ]),
          const SizedBox(height: 10),
          SegmentedButton<ImportKind>(
            segments: [
              for (final k in ImportKind.values) ButtonSegment(value: k, label: Text(k.label)),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() {
              _kind = s.first;
              _guess();
            }),
          ),
          const SizedBox(height: 10),
          Row(children: [
            const Text('صف العناوين: '),
            DropdownButton<int>(
              value: _opt.headerRow.clamp(0, t.rows.isEmpty ? 0 : (t.rows.length < 15 ? t.rows.length - 1 : 14)).toInt(),
              items: [
                for (var r = 0; r < t.rows.length && r < 15; r++)
                  DropdownMenuItem(
                    value: r,
                    child: Text('الصف ${r + 1}: ${t.rows[r].where((c) => c.trim().isNotEmpty).take(3).join(' | ')}',
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setState(() {
                _opt.headerRow = v ?? 0;
                _guess();
              }),
            ),
          ]),
        ]),
      );

  /// أول قيمة غير فارغة في العمود (مثال للمستخدم).
  String _sample(SheetTable t, int c) {
    for (var r = _opt.headerRow + 1; r < t.rows.length && r < _opt.headerRow + 30; r++) {
      final v = t.cell(r, c).trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  Widget _mapCard(SheetTable t) {
    final headers = _headers;
    return SetCard(
      title: '3. اربط الأعمدة',
      subtitle: 'لكل حقل اختر العمود الذي فيه قيمته — أو «لا يُستورد»',
      icon: Icons.link_rounded,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final f in ImportFields.of(_kind))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              SizedBox(
                width: 170,
                child: Text('${f.label}${f.required ? ' *' : ''}',
                    style: TextStyle(fontWeight: FontWeight.w700, color: f.required ? kSetRed : kSetText)),
              ),
              Expanded(
                child: DropdownButton<int?>(
                  isExpanded: true,
                  value: _map[f.key],
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('— لا يُستورد —')),
                    for (var c = 0; c < headers.length; c++)
                      DropdownMenuItem<int?>(
                        value: c,
                        child: Text(
                          '${_colName(c)} • ${headers[c]}${_sample(t, c).isEmpty ? '' : '   (مثال: ${_sample(t, c)})'}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() {
                    // العمود الواحد لحقل واحد
                    if (v != null) {
                      for (final k in _map.keys.toList()) {
                        if (_map[k] == v) _map[k] = null;
                      }
                    }
                    _map[f.key] = v;
                    _plan = null;
                    _result = null;
                  }),
                ),
              ),
            ]),
          ),
      ]),
    );
  }

  Widget _balanceCard() {
    final cust = _kind == ImportKind.customers;
    return SetCard(
      title: '4. الرصيد',
      subtitle: 'يُسجَّل رصيداً افتتاحياً بمعاملة (يظهر في كشف الحساب والقيود)',
      icon: Icons.account_balance_wallet_outlined,
      color: kSetGreen,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Text('تاريخ الرصيد: '),
          OutlinedButton.icon(
            onPressed: () async {
              final d = await pickDate(context, initial: _opt.openingDate);
              if (d != null) {
                setState(() {
                  _opt.openingDate = DateTime(d.year, d.month, d.day);
                  _plan = null;
                });
              }
            },
            icon: const Icon(Icons.calendar_month_rounded, size: 18),
            label: Text(_date(_opt.openingDate)),
          ),
        ]),
        const SizedBox(height: 8),
        Text('الرقم الموجب في الملف يعني:', style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ChoiceChip(
            label: Text(cust ? 'عليه دين لنا (المعتاد)' : 'له علينا — ندين له (المعتاد)'),
            selected: _opt.positiveIsNormal,
            onSelected: (_) => setState(() {
              _opt.positiveIsNormal = true;
              _plan = null;
            }),
          ),
          ChoiceChip(
            label: Text(cust ? 'له رصيد عندنا' : 'عليه لنا'),
            selected: !_opt.positiveIsNormal,
            onSelected: (_) => setState(() {
              _opt.positiveIsNormal = false;
              _plan = null;
            }),
          ),
        ]),
        if (!cust) ...[
          const SizedBox(height: 10),
          Row(children: [
            const Text('العملة إن لم تُذكر في الملف: '),
            DropdownButton<String>(
              value: _opt.defaultCurrency,
              items: const [
                DropdownMenuItem(value: 'IQD', child: Text('دينار')),
                DropdownMenuItem(value: 'USD', child: Text('دولار')),
              ],
              onChanged: (v) => setState(() {
                _opt.defaultCurrency = v ?? 'IQD';
                _plan = null;
              }),
            ),
          ]),
        ],
      ]),
    );
  }

  Widget _actionsRow() => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Wrap(spacing: 10, runSpacing: 10, children: [
          OutlinedButton.icon(
            onPressed: _busy ? null : _preview,
            icon: const Icon(Icons.visibility_outlined),
            label: const Text('معاينة (لا يُكتب شيء)'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: kSetGreen),
            onPressed: _busy || _plan == null || _plan!.rows.isEmpty ? null : _import,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.download_done_rounded),
            label: Text(_plan == null ? 'استيراد (بعد المعاينة)' : 'استيراد ${_plan!.rows.length} ${_kind.noun}'),
          ),
        ]),
      );

  Widget _planCard(ImportPlan plan) {
    final money = plan.kind != ImportKind.products;
    return SetCard(
      title: 'المعاينة',
      subtitle: 'سيُضاف ${plan.rows.length} • يُتجاوز ${plan.skipped.length - plan.errors.length} • أخطاء ${plan.errors.length}',
      icon: Icons.fact_check_outlined,
      color: kSetBlue,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (money) ...[
          for (final e in plan.balanceByCurrency.entries)
            Text('صافي الأرصدة (${e.key}): ${_money(e.value)}', style: const TextStyle(fontWeight: FontWeight.w800)),
          Text(plan.kind == ImportKind.customers
              ? 'عليهم لنا: ${_money(plan.positiveTotal)} • لهم عندنا: ${_money(-plan.negativeTotal)}'
              : 'لهم علينا: ${_money(plan.positiveTotal)} • عليهم لنا: ${_money(-plan.negativeTotal)}'),
        ] else
          Text('مجموع الكميات: ${_money(plan.qtyTotal)}', style: const TextStyle(fontWeight: FontWeight.w800)),
        if (plan.errors.isNotEmpty) ...[
          const SizedBox(height: 8),
          SetBanner('${plan.errors.length} صف فيه خطأ لن يُستورد — صحّحه في الملف وأعد المعاينة إن أردته.',
              kind: SetBannerKind.warn),
        ],
        const SizedBox(height: 10),
        if (plan.rows.isNotEmpty) ...[
          const Text('أول ما سيُضاف:', style: TextStyle(fontWeight: FontWeight.w700)),
          for (final r in plan.rows.take(30))
            Text(
              money
                  ? 'الصف ${r.line}: ${r.name}${r.phone == null ? '' : ' • ${r.phone}'} • ${_money(r.balance)}'
                      '${plan.kind == ImportKind.suppliers ? ' ${r.currency}' : ''}'
                  : 'الصف ${r.line}: ${r.name} • سعر ${_money(r.price)}'
                      '${r.cost == null ? '' : ' • كلفة ${_money(r.cost!)}'} • كمية ${_money(r.qty)}',
              style: const TextStyle(fontSize: 12.5, color: kSetMuted),
            ),
          if (plan.rows.length > 30) Text('… و${plan.rows.length - 30} غيرها', style: const TextStyle(color: kSetMuted)),
        ],
        if (plan.skipped.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('ما لن يُستورد (${plan.skipped.length})', style: const TextStyle(fontWeight: FontWeight.w700)),
            children: [
              for (final s in plan.skipped.take(300))
                ListTile(
                  dense: true,
                  leading: Icon(s.error ? Icons.error_outline : Icons.skip_next_rounded,
                      color: s.error ? kSetRed : kSetMuted, size: 18),
                  title: Text('الصف ${s.line}${s.name.isEmpty ? '' : ': ${s.name}'}'),
                  subtitle: Text(s.reason),
                ),
            ],
          ),
      ]),
    );
  }

  Widget _resultCard(ImportResult r) => SetCard(
        title: r.verified ? 'تم الاستيراد ✓' : 'تم مع ملاحظات',
        subtitle: 'أُضيف ${r.added} ${_kind.noun}',
        icon: r.verified ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
        color: r.verified ? kSetGreen : kSetOrange,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (r.verified)
            const SetBanner('المجاميع المحفوظة في القاعدة طابقت المعاينة.', kind: SetBannerKind.ok),
          for (final p in r.problems) SetBanner(p, kind: SetBannerKind.warn),
          if (r.skippedAtSave.isNotEmpty)
            Text('تُجوّز عند الحفظ ${r.skippedAtSave.length} (أُضيفت بالاسم نفسه بعد المعاينة).'),
          if (r.backupPath.isNotEmpty) ...[
            const SizedBox(height: 8),
            SelectableText('نسخة ما قبل الاستيراد: ${r.backupPath}',
                style: const TextStyle(fontSize: 12.5, color: kSetMuted)),
            const Text('للتراجع: استعِد هذه النسخة من «النسخ الاحتياطي والمزامنة ← استعادة».',
                style: TextStyle(fontSize: 12.5, color: kSetMuted)),
          ],
        ]),
      );
}
