// lib/screens/data_import_screen.dart
//
// 📥 «استيراد من Excel» (الإعدادات ← النظام والأدوات) — على نهج البرامج العالمية
// (QuickBooks: ربط الأعمدة ثم المراجعة والتعديل في جدول قبل الحفظ ونسخة احتياطية
// أولاً؛ Xero: الأرصدة الافتتاحية بتاريخ واحد ومطابقة مجموعها مع البرنامج السابق؛
// Odoo: «اختبار» بلا كتابة وتعرّف الأعمدة من عناوينها):
//   0) أين تُستورد؟ دمج مع القاعدة الحالية، أو قاعدة جديدة فارغة (تُؤرشف الحالية).
//   1) الملف ‎.xlsx أو ‎.xls أو ‎.csv ← أوراقه وعدد صفوف كل ورقة.
//   2) الورقة وما تستورده (عملاء / مواد / موردون) وصف العناوين.
//   3) ربط الأعمدة (التطبيق يخمّن ويتذكر ربطك للملفات بالعناوين نفسها).
//   4) تاريخ الرصيد ومعنى الإشارة.
//   5) المراجعة: كل اسم وما سيُضاف عليه — قابل للتعديل والاستبعاد — والمجموع،
//      ومقارنته بمجموع البرنامج السابق إن كتبته.
//   6) الاستيراد بعد التأكيد: نسخة احتياطية، حفظ، ومطابقة المجاميع.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:shared_preferences/shared_preferences.dart';

import '../accounting/screens/acc_ui.dart' show pickDate;
import '../lan/lan_bootstrap.dart' show LanRuntime;
import '../services/database_service.dart';
import '../services/import/data_import.dart';
import '../services/import/fresh_start.dart';
import '../services/import/sheet_reader.dart';
import '../widgets/settings_kit.dart';

String _money(num v) => NumberFormat('#,##0.##', 'en_US').format(v);
String _date(DateTime d) => DateFormat('yyyy/MM/dd').format(d);

enum _Target { merge, fresh }

class DataImportScreen extends StatefulWidget {
  const DataImportScreen({super.key});

  @override
  State<DataImportScreen> createState() => _DataImportScreenState();
}

class _DataImportScreenState extends State<DataImportScreen> {
  _Target _target = _Target.merge;
  List<String> _freshBlockers = const [];
  String? _fileName;
  List<SheetTable> _sheets = const [];
  int _sheet = 0;
  ImportKind _kind = ImportKind.customers;
  Map<String, int?> _map = {};
  final ImportOptions _opt = ImportOptions(openingDate: DateTime(DateTime.now().year, DateTime.now().month, 1));
  ImportPlan? _plan;
  ImportResult? _result;
  FreshStartResult? _fresh;
  String? _error;
  bool _busy = false;
  double _progress = 0;
  String _filter = '';
  final _expected = TextEditingController();
  /// خانات فيها نص لا يُفهم رقماً: مفتاح الخانة ← النص (يبقى ظاهراً ولو مُرّرت القائمة).
  final Map<String, String> _badEdits = {};

  SheetTable? get _table => _sheets.isEmpty ? null : _sheets[_sheet];
  bool get _money3 => _kind != ImportKind.products;

  @override
  void initState() {
    super.initState();
    FreshStart.blockers().then((b) {
      if (mounted) setState(() => _freshBlockers = b);
    });
  }

  @override
  void dispose() {
    _expected.dispose();
    super.dispose();
  }

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

  // ─── تذكّر الربط (للملفات بالعناوين نفسها) ───
  String get _mapKey => 'import_map_${_kind.name}_${_headers.join('|').hashCode}';

  Future<void> _guess() async {
    _map = ColumnGuess.guess(_headers, _kind);
    _plan = null;
    _result = null;
    try {
      final saved = (await SharedPreferences.getInstance()).getString(_mapKey);
      if (saved != null) {
        final m = (jsonDecode(saved) as Map).map((k, v) => MapEntry('$k', v as int?));
        final fields = ImportFields.of(_kind).map((f) => f.key).toSet();
        if (m.keys.every(fields.contains) && m.values.every((v) => v == null || v < _headers.length)) {
          _map = {for (final f in fields) f: m[f]};
        }
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _rememberMap() async {
    try {
      await (await SharedPreferences.getInstance()).setString(_mapKey, jsonEncode(_map));
    } catch (_) {}
  }

  Future<void> _pick() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'xls', 'csv', 'txt', 'htm', 'html', 'xml'],
      withData: true,
      dialogTitle: 'اختر ملف Excel (‎.xlsx أو ‎.xls) أو CSV',
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
      var first = sheets.indexWhere((s) => s.rows.length > 1);
      if (first < 0) first = 0;
      _fileName = f.name;
      _opt.sourceId = DataImport.fileFingerprint(bytes); // يمنع إضافة الملف نفسه مرتين
      _sheets = sheets;
      _sheet = first;
      _opt.headerRow = sheets[first].firstNonEmptyRow;
      await _guess();
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
      _badEdits.clear();
    });
    try {
      final plan = await DataImport.plan(await DatabaseService().database, t, _kind, _map, _opt,
          freshTarget: _target == _Target.fresh);
      await _rememberMap();
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

  // ─── المجاميع ───
  double get _sumIncluded {
    final p = _plan;
    if (p == null) return 0;
    return ImportNumbers.money(p.rows.fold(0.0, (s, r) => s + (_money3 ? r.balance : r.qty)));
  }

  /// null = لم يُكتب مجموع متوقع؛ true = مطابق.
  bool? get _expectedMatches {
    final t = _expected.text.trim();
    if (t.isEmpty || _plan == null || _mixedCurrency) return null;
    final v = ImportNumbers.parse(t);
    if (!v.ok || v.value == null) return false;
    return (ImportNumbers.money(v.value!) - _sumIncluded).abs() < 0.005;
  }

  /// موردون بأكثر من عملة: لا معنى لمجموع واحد — المطابقة لكل عملة من البطاقات أعلاه.
  bool get _mixedCurrency => _money3 && (_plan?.balanceByCurrency.length ?? 0) > 1;

  bool get _canImport =>
      !(_target == _Target.fresh && _freshBlockers.isNotEmpty) &&
      !_busy &&
      _plan != null &&
      _plan!.rows.isNotEmpty &&
      _plan!.undecided.isEmpty &&
      _badEdits.isEmpty &&
      _expectedMatches != false;

  Future<void> _import() async {
    final plan = _plan;
    if (plan == null || !_canImport) return;
    final ok = await _confirm(plan);
    if (ok != true) return;
    setState(() {
      _busy = true;
      _progress = 0;
      _error = null;
    });
    FreshStartResult? fresh;
    try {
      if (_target == _Target.fresh) {
        fresh = await FreshStart.run();
        setState(() => _fresh = fresh);
      }
      final r = await DataImport.execute(plan, _opt, fileName: _fileName ?? '', sheet: _table?.name ?? '',
          onProgress: (d, t) {
        if (mounted) setState(() => _progress = t == 0 ? 1 : d / t);
      });
      setState(() {
        _result = r;
        _plan = null;
      });
    } catch (e) {
      setState(() => _error = fresh == null
          ? 'لم يُستورد شيء: $e'
          : 'أُنشئت القاعدة الجديدة لكن الاستيراد لم يكتمل: $e\n'
              'القاعدة السابقة محفوظة كاملة في: ${fresh.archivePath} — يمكنك استعادتها، أو تصحيح الملف وإعادة الاستيراد.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// تراجع عن «قاعدة جديدة» إن فشل الاستيراد بعدها: يعيد الأرشيف بمسار الاستعادة نفسه.
  Future<void> _restoreArchive() async {
    final f = _fresh;
    if (f == null) return;
    setState(() => _busy = true);
    try {
      final ok = await DatabaseService().restoreDatabaseFromFile(File(f.archivePath));
      if (!mounted) return;
      if (ok) {
        setState(() {
          _fresh = null;
          _error = null;
        });
        setToast(context, 'أُعيدت القاعدة السابقة — أعد تشغيل البرنامج');
      } else {
        setToast(context, 'تعذّرت الاستعادة — الأرشيف باقٍ في: ${f.archivePath}', error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirm(ImportPlan plan) {
    final ctrl = TextEditingController();
    final word = _target == _Target.fresh ? 'قاعدة جديدة' : 'استيراد';
    final rows = plan.rows;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(_target == _Target.fresh
              ? 'قاعدة جديدة واستيراد ${rows.length} ${plan.kind.noun}؟'
              : 'استيراد ${rows.length} ${plan.kind.noun}؟'),
          content: SizedBox(
            width: 480,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (_target == _Target.fresh)
                const SetBanner(
                  'ستُؤرشف القاعدة الحالية كاملة (تبقى ملفاً يُستعاد متى أردت)، ويبدأ البرنامج بقاعدة فارغة: '
                  'لا عملاء ولا فواتير ولا مواد ولا قيود — المستخدمون والحسابات والصناديق والإعدادات تبقى.',
                  kind: SetBannerKind.warn,
                ),
              const SizedBox(height: 8),
              if (_money3)
                for (final e in plan.balanceByCurrency.entries)
                  Text('مجموع الأرصدة الافتتاحية (${e.key}): ${_money(e.value)} — بتاريخ ${_date(_opt.openingDate)}',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
              if (!_money3) Text('مجموع الكميات: ${_money(plan.qtyTotal)}', style: const TextStyle(fontWeight: FontWeight.w800)),
              if (plan.existingRows.isNotEmpty) ...[
                const SizedBox(height: 8),
                SetBanner(
                  '${plan.newRows.length} حساب جديد، و${plan.existingRows.length} موجود عندنا:\n'
                  '${[
                    for (final a in ExistingAction.values)
                      if (plan.existingRows.any((r) => r.action == a))
                        '• ${a.label}: ${plan.existingRows.where((r) => r.action == a).length}',
                  ].join('\n')}'
                  '${plan.balanceByCurrency.length <= 1 ? '\nتغيّر ديون الموجودين: ${_money(plan.existingDelta)}' : ''}\n'
                  'كل تغيير معاملة يُذكر فيها الملف والصف واسمك.',
                  kind: SetBannerKind.warn,
                ),
              ],
              if (rows.any((r) => r.edited))
                Text('عدّلت ${rows.where((r) => r.edited).length} قيمة عن الملف.', style: const TextStyle(color: kSetOrange)),
              const SizedBox(height: 6),
              Text('لن يُستورد ${plan.skipped.length + plan.allRows.length - rows.length} صف (مكرر، مستورد سابقاً، خطأ، أو استبعدته).'),
              const SizedBox(height: 8),
              const SetBanner('تُؤخذ نسخة احتياطية كاملة قبل الحفظ. إن لم تطابق المجاميع المحفوظة هذه المراجعة يُلغى الاستيراد كله.'),
              const SizedBox(height: 10),
              TextField(
                controller: ctrl,
                autofocus: true,
                onChanged: (_) => setD(() {}),
                decoration: InputDecoration(labelText: 'للتأكيد اكتب: $word', border: const OutlineInputBorder()),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _target == _Target.fresh ? kSetOrange : kSetGreen),
              onPressed: ctrl.text.trim() == word ? () => Navigator.pop(ctx, true) : null,
              child: Text(_target == _Target.fresh ? 'أنشئ واستورد' : 'استيراد'),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════ الواجهة ═══════════════════════════

  @override
  Widget build(BuildContext context) {
    final t = _table;
    return SettingsScaffold(
      title: 'استيراد من Excel',
      icon: Icons.upload_file_rounded,
      subtitle: 'عملاء وأرصدتهم، مواد، موردون — من ملف أي برنامج آخر',
      maxWidth: 980,
      children: [
        _targetCard(),
        _fileCard(),
        if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: SetBanner(_error!, kind: SetBannerKind.error)),
        if (_fresh != null && _result == null && !_busy)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                onPressed: _restoreArchive,
                icon: const Icon(Icons.settings_backup_restore_rounded),
                label: const Text('إعادة القاعدة السابقة كما كانت'),
              ),
            ),
          ),
        if (t != null) ...[
          _whatCard(t),
          _mapCard(t),
          if (_money3) _balanceCard(),
          _actionsRow(),
          if (_busy && _progress > 0)
            Padding(padding: const EdgeInsets.only(bottom: 12), child: LinearProgressIndicator(value: _progress)),
          if (_plan != null) _reviewCard(_plan!),
          if (_result != null) _resultCard(_result!),
        ],
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _targetCard() {
    Widget option(_Target v, IconData icon, String title, String sub, {bool disabled = false}) {
      final sel = _target == v;
      final c = v == _Target.fresh ? kSetOrange : kSetGreen;
      return Expanded(
        child: Opacity(
          opacity: disabled ? 0.5 : 1,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: disabled || _busy
                ? null
                : () {
                    setState(() {
                      _target = v;
                      _plan = null;
                      _result = null;
                    });
                    FreshStart.blockers().then((b) {
                      if (mounted) setState(() => _freshBlockers = b);
                    });
                  },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: sel ? c.withValues(alpha: 0.08) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: sel ? c : kSetBorder, width: sel ? 1.6 : 1),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(sel ? Icons.radio_button_checked : Icons.radio_button_off, color: sel ? c : kSetMuted, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(icon, size: 18, color: c),
                      const SizedBox(width: 6),
                      Flexible(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, color: kSetText))),
                    ]),
                    const SizedBox(height: 4),
                    Text(sub, style: const TextStyle(fontSize: 12.5, color: kSetMuted, height: 1.45)),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      );
    }

    return SetCard(
      title: '0. أين تُستورد البيانات؟',
      icon: Icons.storage_rounded,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          option(_Target.merge, Icons.merge_rounded, 'دمج مع القاعدة الحالية',
              'يُضاف الجديد فقط. أي اسم موجود يُتجاوز ولا يُمس رصيده ولا سعره.'),
          const SizedBox(width: 10),
          option(_Target.fresh, Icons.fiber_new_rounded, 'قاعدة بيانات جديدة',
              'تُؤرشف الحالية كاملة ويبدأ البرنامج فارغاً بما في الملف فقط. المستخدمون والحسابات والصناديق والإعدادات تبقى.',
              disabled: _freshBlockers.isNotEmpty),
        ]),
        if (_freshBlockers.isNotEmpty) ...[
          const SizedBox(height: 10),
          SetBanner('«قاعدة جديدة» غير متاحة الآن:\n• ${_freshBlockers.join('\n• ')}', kind: SetBannerKind.warn),
        ] else if (_target == _Target.fresh) ...[
          const SizedBox(height: 10),
          const SetBanner(
            'بعد البداية الجديدة لا تربط البرنامج بمشروع المزامنة السحابية القديم — سيعيد إليه البيانات القديمة.',
            kind: SetBannerKind.warn,
          ),
        ],
      ]),
    );
  }

  Widget _fileCard() => SetCard(
        title: '1. الملف',
        subtitle: _fileName == null ? 'Excel ‏(‎.xlsx أو ‎.xls) أو CSV — الملف نفسه لا يتغير' : _fileName!,
        icon: Icons.description_outlined,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SetBanner('يقبل ‎.xlsx و‎.xls (حتى ملفات Excel 97–2003 وExcel 95) و‎.csv. '
              'اجعل كل عمود بعنوان واضح في الصف الأول (الاسم، الهاتف، الرصيد...) — التطبيق يتعرّف عليه.'),
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
                  onSelected: (_) {
                    _sheet = i;
                    _opt.headerRow = _sheets[i].firstNonEmptyRow;
                    _guess();
                  },
                ),
            ]),
          const SizedBox(height: 10),
          SegmentedButton<ImportKind>(
            segments: [for (final k in ImportKind.values) ButtonSegment(value: k, label: Text(k.label))],
            selected: {_kind},
            onSelectionChanged: (s) {
              _kind = s.first;
              _guess();
            },
          ),
          const SizedBox(height: 10),
          Row(children: [
            const Text('صف العناوين: '),
            Expanded(
              child: DropdownButton<int>(
                isExpanded: true,
                value: _opt.headerRow.clamp(0, t.rows.isEmpty ? 0 : (t.rows.length < 15 ? t.rows.length - 1 : 14)).toInt(),
                items: [
                  for (var r = 0; r < t.rows.length && r < 15; r++)
                    DropdownMenuItem(
                      value: r,
                      child: Text('الصف ${r + 1}: ${t.rows[r].where((c) => c.trim().isNotEmpty).take(4).join(' | ')}',
                          overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) {
                  _opt.headerRow = v ?? 0;
                  _guess();
                },
              ),
            ),
          ]),
        ]),
      );

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
      subtitle: 'لكل حقل اختر العمود الذي فيه قيمته — أو «لا يُستورد». يُتذكَّر ربطك للملفات بالعناوين نفسها.',
      icon: Icons.link_rounded,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final f in ImportFields.of(_kind))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              SizedBox(
                width: 180,
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
                    if (v != null) {
                      for (final k in _map.keys.toList()) {
                        if (_map[k] == v) _map[k] = null; // العمود الواحد لحقل واحد
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
      title: '4. الرصيد الافتتاحي',
      subtitle: 'يُسجَّل بمعاملة «رصيد افتتاحي» بتاريخ واحد (يظهر في كشف الحساب والقيود)',
      icon: Icons.account_balance_wallet_outlined,
      color: kSetGreen,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          const Text('تاريخ الرصيد:'),
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
          const Text('(عادةً اليوم الذي تبدأ فيه العمل بهذا البرنامج)', style: TextStyle(fontSize: 12, color: kSetMuted)),
        ]),
        const SizedBox(height: 10),
        const Text('الرقم الموجب في الملف يعني:', style: TextStyle(fontWeight: FontWeight.w700)),
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
        const SizedBox(height: 10),
        Text(
          cust
              ? 'عميل موجود عندنا بالاسم نفسه: تختار له في المراجعة — دمج الدينين، أو مبلغ الملف هو الصحيح، أو دينه الحالي هو الصحيح.'
              : 'مورد موجود عندنا بالاسم نفسه: تختار له في المراجعة — دمج الرصيدين، أو مبلغ الملف هو الصحيح، أو رصيده الحالي هو الصحيح.',
          style: const TextStyle(fontSize: 12.5, color: kSetMuted, height: 1.5),
        ),
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
            icon: const Icon(Icons.fact_check_outlined),
            label: Text(_plan == null ? '5. مراجعة (لا يُكتب شيء)' : 'إعادة المراجعة من الملف'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: _target == _Target.fresh ? kSetOrange : kSetGreen),
            onPressed: _canImport ? _import : null,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.download_done_rounded),
            label: Text(_plan == null
                ? 'استيراد (بعد المراجعة)'
                : '${_target == _Target.fresh ? 'قاعدة جديدة + ' : ''}استيراد ${_plan!.rows.length} ${_kind.noun}'),
          ),
        ]),
      );

  // ─── المراجعة: كل اسم ومبلغه، قابل للتعديل والاستبعاد ───

  Widget _reviewCard(ImportPlan plan) {
    final all = plan.allRows;
    final q = _filter.trim();
    final shown = q.isEmpty ? all : all.where((r) => r.name.contains(q) || '${r.line}' == q).toList();
    final included = plan.rows;
    final match = _expectedMatches;
    return SetCard(
      title: '5. المراجعة — ${included.length} ${plan.kind.noun}',
      subtitle: 'كل اسم وما سيُضاف عليه. عدّل أي قيمة خاطئة أو استبعد الصف قبل الاستيراد.',
      icon: Icons.fact_check_outlined,
      color: kSetBlue,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _totalsBar(plan),
        if (!_mixedCurrency) ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _expected,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  isDense: true,
                  border: const OutlineInputBorder(),
                  labelText: _money3
                      ? 'المجموع في البرنامج السابق (اختياري — للمطابقة)'
                      : 'مجموع الكميات في البرنامج السابق (اختياري)',
                  suffixIcon: match == null
                      ? null
                      : Icon(match ? Icons.check_circle : Icons.error, color: match ? kSetGreen : kSetRed),
                ),
              ),
            ),
          ]),
          if (match == false)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'غير مطابق: الفرق ${_money(_sumIncluded - (ImportNumbers.parse(_expected.text).value ?? 0))} — '
                'راجع الأعمدة المختارة أو القيم أو الصفوف المستبعدة. الاستيراد متوقف حتى يتطابق أو تمسح المجموع.',
                style: const TextStyle(color: kSetRed, fontWeight: FontWeight.w700),
              ),
            ),
        ],
        if (plan.errors.isNotEmpty) ...[
          const SizedBox(height: 10),
          SetBanner('${plan.errors.length} صف فيه خطأ لن يُستورد (انظر «ما لن يُستورد» أدناه).', kind: SetBannerKind.warn),
        ],
        const SizedBox(height: 10),
        TextField(
          onChanged: (v) => setState(() => _filter = v),
          decoration: const InputDecoration(
            isDense: true,
            prefixIcon: Icon(Icons.search),
            hintText: 'ابحث باسم أو رقم صف',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        if (plan.existingRows.isNotEmpty) _existingBar(plan),
        _gridHeader(),
        Container(
          height: 420,
          decoration: BoxDecoration(border: Border.all(color: kSetBorder), borderRadius: BorderRadius.circular(12)),
          child: ListView.separated(
            itemCount: shown.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFEEF2F7)),
            itemBuilder: (_, i) => _gridRow(shown[i]),
          ),
        ),
        if (plan.skipped.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('ما لن يُستورد (${plan.skipped.length})', style: const TextStyle(fontWeight: FontWeight.w700)),
            trailing: TextButton.icon(
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('نسخ القائمة'),
              onPressed: () {
                Clipboard.setData(ClipboardData(
                    text: plan.skipped.map((s) => 'الصف ${s.line}\t${s.name}\t${s.reason}').join('\n')));
                setToast(context, 'نُسخت القائمة — الصقها في Excel لتصحيح الملف');
              },
            ),
            children: [
              for (final s in plan.skipped.take(500))
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

  Widget _totalsBar(ImportPlan plan) {
    Widget kpi(String label, String value, Color c) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: c.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 12, color: kSetMuted)),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: c)),
              ),
            ]),
          ),
        );
    final rows = plan.rows;
    if (!_money3) {
      return Row(children: [
        kpi('المواد', '${rows.length}', kSetNavy),
        const SizedBox(width: 8),
        kpi('مجموع الكميات', _money(plan.qtyTotal), kSetBlue),
        const SizedBox(width: 8),
        kpi('قيمة المخزون بالكلفة', _money(rows.fold<double>(0, (s, r) => s + r.qty * (r.cost ?? 0))), kSetGreen),
      ]);
    }
    final cust = plan.kind == ImportKind.customers;
    final pos = plan.positiveTotal;
    final neg = -plan.negativeTotal;
    final byCur = plan.balanceByCurrency;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        kpi(cust ? 'العملاء' : 'الموردون', '${rows.length}', kSetNavy),
        if (byCur.length <= 1) ...[
          const SizedBox(width: 8),
          kpi(cust ? 'عليهم لنا' : 'لهم علينا', _money(pos), cust ? kSetRed : kSetOrange),
          const SizedBox(width: 8),
          kpi(cust ? 'لهم عندنا' : 'عليهم لنا', _money(neg), kSetGreen),
          const SizedBox(width: 8),
          kpi('الصافي (المجموع)', _money(_sumIncluded), kSetBlue),
        ] else
          for (final e in byCur.entries) ...[
            const SizedBox(width: 8),
            kpi('الصافي ${e.key == 'USD' ? 'دولار' : 'دينار'}', _money(e.value), kSetBlue),
          ],
      ]),
    ]);
  }

  /// الأسماء الموجودة عندنا: اختيار للكل، وعدد ما بقي بلا اختيار.
  Widget _existingBar(ImportPlan plan) {
    final ex = plan.existingRows;
    final left = plan.undecided.length;
    final cust = plan.kind == ImportKind.customers;
    void all(ExistingAction a) => setState(() {
          for (final r in plan.allRows) {
            if (r.isExisting) r.action = a;
          }
        });
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: left > 0 ? const Color(0xFFFFF7ED) : const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: (left > 0 ? kSetOrange : kSetGreen).withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          '${ex.length} ${cust ? 'عميل' : 'مورد'} في الملف موجود عندنا بالاسم نفسه. '
          '${left > 0 ? 'اختر لكل واحد (أو للكل) أي الدينين هو الصحيح — بقي $left بلا اختيار، والاستيراد متوقف حتى تختار.' : 'تم الاختيار للكل.'}',
          style: TextStyle(fontWeight: FontWeight.w800, color: left > 0 ? kSetOrange : kSetGreen, height: 1.5),
        ),
        const SizedBox(height: 6),
        const Text(
          '• دمج الدينين: يُضاف مبلغ الملف إلى دينه الحالي.\n'
          '• مبلغ الملف هو الصحيح: يصير دينه مبلغ الملف (تُسجَّل تسوية بالفرق).\n'
          '• الدين الحالي هو الصحيح: لا يتغير شيء.',
          style: TextStyle(fontSize: 12.5, color: kSetText, height: 1.6),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          const Text('للكل:', style: TextStyle(fontWeight: FontWeight.w700)),
          for (final a in ExistingAction.values)
            OutlinedButton(
              onPressed: () => all(a),
              style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: _actionColor(a)),
              child: Text(a.label),
            ),
          if (ex.any((r) => r.action != null))
            TextButton(
              onPressed: () => setState(() {
                for (final r in plan.allRows) {
                  r.action = null;
                }
              }),
              child: const Text('مسح الاختيار'),
            ),
        ]),
      ]),
    );
  }

  static Color _actionColor(ExistingAction a) => switch (a) {
        ExistingAction.merge => kSetBlue,
        ExistingAction.useFile => kSetOrange,
        ExistingAction.keep => kSetGreen,
      };

  Widget _gridHeader() {
    const st = TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: kSetMuted);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(children: [
        const SizedBox(width: 40, child: Text('✓', style: st)),
        const SizedBox(width: 56, child: Text('الصف', style: st)),
        const Expanded(flex: 4, child: Text('الاسم', style: st)),
        if (_money3) const Expanded(flex: 3, child: Text('الهاتف', style: st)),
        if (_money3)
          Expanded(flex: 3, child: Text(_kind == ImportKind.suppliers ? 'الرصيد (العملة)' : 'الرصيد', style: st))
        else ...[
          const Expanded(flex: 2, child: Text('سعر البيع', style: st)),
          const Expanded(flex: 2, child: Text('الكمية', style: st)),
        ],
      ]),
    );
  }

  String _cellKey(PlanRow r, String tag) => '${identityHashCode(r)}_$tag';

  Widget _gridRow(PlanRow r) {
    Widget cell(String tag, double value, double? original, void Function(double v) set,
        {bool positiveOnly = false, bool nonZero = false}) {
      final k = _cellKey(r, tag);
      return _NumCell(
        key: ValueKey(k),
        value: value,
        badText: _badEdits[k],
        original: original,
        positiveOnly: positiveOnly,
        nonZero: nonZero,
        onChanged: (raw, v, error) => setState(() {
          if (error != null) {
            _badEdits[k] = raw;
          } else {
            _badEdits.remove(k);
            set(v!);
          }
        }),
      );
    }

    return Opacity(
      opacity: r.include ? 1 : 0.45,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(children: [
          SizedBox(
            width: 40,
            child: Checkbox(
              value: r.include,
              onChanged: (v) => setState(() {
                r.include = v ?? true;
                if (!r.include) {
                  for (final t in const ['bal', 'price', 'qty']) {
                    _badEdits.remove(_cellKey(r, t));
                  }
                }
              }),
            ),
          ),
          SizedBox(width: 56, child: Text('${r.line}', style: const TextStyle(color: kSetMuted))),
          Expanded(
            flex: 4,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(r.name, style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
              if (r.isExisting) ...[
                Text(
                  'موجود${r.existingName != r.name ? ' «${r.existingName}»' : ''} — دينه الآن ${_money(r.existingBalance)}'
                  '${r.action == null ? '' : ' ← بعد: ${_money(r.balanceAfter)}'}',
                  style: TextStyle(
                      fontSize: 11.5, color: r.action == null ? kSetOrange : kSetMuted, fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Wrap(spacing: 4, runSpacing: 4, children: [
                  for (final a in ExistingAction.values)
                    ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                      label: Text(a.label, style: const TextStyle(fontSize: 11)),
                      selected: r.action == a,
                      selectedColor: _actionColor(a).withValues(alpha: 0.18),
                      onSelected: r.include ? (_) => setState(() => r.action = a) : null,
                    ),
                ]),
              ],
            ]),
          ),
          if (_money3) ...[
            Expanded(flex: 3, child: Text(r.phone ?? '—', style: const TextStyle(color: kSetMuted), overflow: TextOverflow.ellipsis)),
            Expanded(
              flex: 3,
              child: Row(children: [
                Expanded(child: cell('bal', r.balance, r.originalBalance, (v) => r.balance = ImportNumbers.money(v))),
                if (_kind == ImportKind.suppliers)
                  Padding(padding: const EdgeInsetsDirectional.only(start: 6), child: Text(r.currency)),
              ]),
            ),
          ] else ...[
            Expanded(
                flex: 2,
                child: cell('price', r.price, r.originalPrice, (v) => r.price = ImportNumbers.money(v), positiveOnly: true, nonZero: true)),
            const SizedBox(width: 6),
            Expanded(flex: 2, child: cell('qty', r.qty, r.originalQty, (v) => r.qty = v, positiveOnly: true)),
          ],
        ]),
      ),
    );
  }

  Widget _resultCard(ImportResult r) => SetCard(
        title: r.verified ? 'تم الاستيراد ✓' : 'تم مع ملاحظات',
        subtitle: 'أُضيف ${r.added} ${_kind.noun} جديد'
            '${r.addedToExisting > 0 ? '، وأُضيفت مبالغ إلى ${r.addedToExisting} حساب موجود' : ''}',
        icon: r.verified ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
        color: r.verified ? kSetGreen : kSetOrange,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (r.verified) const SetBanner('المجاميع المحفوظة في القاعدة طابقت المراجعة.', kind: SetBannerKind.ok),
          for (final p in r.problems) SetBanner(p, kind: SetBannerKind.warn),
          if (r.kept.isNotEmpty)
            Text('بقي ${r.kept.length} حساب موجود كما هو (الدين الحالي هو الصحيح أو لا فرق).',
                style: const TextStyle(color: kSetMuted)),
          if (r.skippedAtSave.isNotEmpty) ...[
            Text('تُجوّز عند الحفظ ${r.skippedAtSave.length}:', style: const TextStyle(fontWeight: FontWeight.w700)),
            for (final x in r.skippedAtSave.take(30))
              Text('• الصف ${x.line} «${x.name}»: ${x.reason}', style: const TextStyle(fontSize: 12.5, color: kSetMuted)),
          ],
          if (_fresh != null) ...[
            const SizedBox(height: 8),
            SelectableText('القاعدة السابقة كاملة (أرشيف): ${_fresh!.archivePath}',
                style: const TextStyle(fontSize: 12.5, color: kSetMuted)),
          ],
          if (r.backupPath.isNotEmpty) ...[
            const SizedBox(height: 6),
            SelectableText('نسخة ما قبل الاستيراد: ${r.backupPath}', style: const TextStyle(fontSize: 12.5, color: kSetMuted)),
            const Text('للتراجع: استعِد هذه النسخة من «النسخ الاحتياطي والمزامنة ← استعادة».',
                style: TextStyle(fontSize: 12.5, color: kSetMuted)),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.icon(
              onPressed: LanRuntime.relaunch,
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('إعادة تشغيل البرنامج (لتظهر البيانات في كل الشاشات)'),
            ),
          ),
        ]),
      );
}

/// خانة رقم قابلة للتعديل: تُظهر القيمة الأصلية من الملف إن عُدّلت، وترفض غير الرقم.
/// النص غير الصالح يحفظه الأب ([badText]) فيبقى ظاهراً بعد تمرير القائمة.
class _NumCell extends StatefulWidget {
  const _NumCell({
    super.key,
    required this.value,
    required this.original,
    required this.onChanged,
    this.badText,
    this.positiveOnly = false,
    this.nonZero = false,
  });
  final double value;
  final double? original;
  final String? badText;
  final bool positiveOnly;
  final bool nonZero;
  final void Function(String raw, double? value, String? error) onChanged;

  @override
  State<_NumCell> createState() => _NumCellState();
}

class _NumCellState extends State<_NumCell> {
  static final _fmt = NumberFormat('#,##0.####', 'en_US');
  late final TextEditingController _c = TextEditingController(text: widget.badText ?? _fmt.format(widget.value));
  late String? _err = widget.badText == null ? null : _check(widget.badText!).$2;

  (double?, String?) _check(String t) {
    final v = ImportNumbers.parse(t);
    if (!v.ok || v.value == null) return (null, 'رقم غير صالح');
    if (widget.positiveOnly && v.value! < 0) return (null, 'لا يُقبل سالب');
    if (widget.nonZero && ImportNumbers.money(v.value!) <= 0) return (null, 'يجب أكبر من صفر');
    return (v.value, null);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final edited = widget.original != null && (widget.original! - widget.value).abs() > 0.00001;
    return Tooltip(
      message: edited ? 'في الملف: ${_fmt.format(widget.original!)}' : '',
      child: TextField(
        controller: _c,
        textAlign: TextAlign.end,
        textDirection: TextDirection.ltr,
        style: TextStyle(fontWeight: FontWeight.w800, color: edited ? kSetOrange : kSetText),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          border: const OutlineInputBorder(),
          errorText: _err,
          errorStyle: const TextStyle(fontSize: 10),
        ),
        onChanged: (t) {
          final (v, e) = _check(t);
          setState(() => _err = e);
          widget.onChanged(t, v, e);
        },
      ),
    );
  }
}
