// lib/owner/ai_invoice/ai_purchase_invoice_screen.dart
//
// 👑🤖 «فاتورة شراء بالذكاء الاصطناعي» — لحساب المالك فقط.
//
// 1) اختر صورة/PDF فاتورة المورد
// 2) يقرأها Gemini ويطابق موادها مع موادنا (مع ما تعلّمه من تصحيحاتك السابقة)
// 3) تراجع كل سطر: تغيّر المادة، الوحدة، التعبئة، الكمية، السعر
// 4) «متابعة» ⇒ تُحفظ تصحيحاتك (ذاكرة الأسماء) وتُفتح فاتورة الشراء العادية معبأة
//    والحفظ هناك يمرّ بكل حمايات الشاشة الأصلية (المخزون، الدين، الفترات المثبّتة).

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';

import '../../accounting/screens/acc_ui.dart' show accRoute;
import '../../models/product.dart';
import '../../models/purchase_invoice_item.dart';
import '../../models/supplier.dart';
import '../../screens/create_purchase_invoice_screen.dart';
import '../../services/database_service.dart';
import '../../services/purchase_service.dart';
import '../owner_access.dart';
import 'ai_alias_store.dart';
import 'ai_invoice_service.dart';
import 'ai_purchase_prefill.dart';

// ───────────────────────── ألوان ─────────────────────────
const _aiA = Color(0xFF4F46E5);
const _aiB = Color(0xFF7C3AED);
const _ink = Color(0xFF0F172A);
const _muted = Color(0xFF64748B);
const _bg = Color(0xFFF5F6FB);
const _line = Color(0xFFE2E8F0);
const _cLearned = Color(0xFF0D9488);
const _cGood = Color(0xFF16A34A);
const _cMid = Color(0xFFD97706);
const _cLow = Color(0xFFEA580C);
const _cNew = Color(0xFF2563EB);
const _cManual = Color(0xFF7C3AED);

enum _Phase { pick, reading, review }

class _Row {
  _Row(this.line);
  final AiInvoiceLine line;
  final qty = TextEditingController();
  final price = TextEditingController();
  final factor = TextEditingController();
  String unit = '';
  List<String> units = const [];

  double get q => _parse(qty.text);
  double get pr => _parse(price.text);
  double get f {
    final v = _parse(factor.text);
    return v > 0 ? v : 1;
  }

  double get total => q * pr;

  void dispose() {
    qty.dispose();
    price.dispose();
    factor.dispose();
  }

  static double _parse(String s) => double.tryParse(s.replaceAll(',', '').replaceAll('٫', '.').trim()) ?? 0;
}

class AiPurchaseInvoiceScreen extends StatefulWidget {
  const AiPurchaseInvoiceScreen({super.key, this.supplier});
  final Supplier? supplier;

  @override
  State<AiPurchaseInvoiceScreen> createState() => _AiPurchaseInvoiceScreenState();
}

class _AiPurchaseInvoiceScreenState extends State<AiPurchaseInvoiceScreen> {
  static final _fmt = intl.NumberFormat('#,##0.##', 'en_US');

  _Phase _phase = _Phase.pick;
  List<Supplier> _suppliers = [];
  List<Product> _products = [];
  Map<int, Product> _byId = {};
  Supplier? _supplier;
  int _learnedCount = 0;
  bool _loading = true;

  Uint8List? _bytes;
  String _fileName = '';
  String? _savedPath;
  String? _error;
  AiInvoiceResult? _result;
  final List<_Row> _rows = [];

  final _numberCtl = TextEditingController();
  final _paidCtl = TextEditingController(text: '0');
  DateTime _date = DateTime.now();
  String _currency = 'IQD';
  bool _cash = false;
  bool _showDoc = false; // للشاشات الضيقة

  @override
  void initState() {
    super.initState();
    _supplier = widget.supplier;
    _currency = widget.supplier?.currency == 'USD' ? 'USD' : 'IQD';
    _load();
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    _numberCtl.dispose();
    _paidCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final suppliers = await context.read<PurchaseService>().getSuppliers();
      final products = (await DatabaseService().getAllProducts()).where((p) => p.id != null && !p.isDeleted).toList();
      final learned = await AiAliasStore.count();
      if (!mounted) return;
      setState(() {
        _suppliers = suppliers;
        _products = products;
        _byId = {for (final p in products) p.id!: p};
        _learnedCount = learned;
        if (_supplier != null) {
          final i = suppliers.indexWhere((s) => s.id == _supplier!.id);
          if (i >= 0) _supplier = suppliers[i];
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذّر تحميل المواد والموردين: $e';
      });
    }
  }

  // ───────────────────────── الملف ─────────────────────────

  Future<void> _pick() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
      withData: true,
    );
    if (res == null || res.files.isEmpty) return;
    final f = res.files.single;
    Uint8List? bytes = f.bytes;
    if (bytes == null && f.path != null) bytes = await File(f.path!).readAsBytes();
    if (bytes == null) return;
    String? saved;
    try {
      final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'attachments'));
      if (!await dir.exists()) await dir.create(recursive: true);
      final ext = p.extension(f.name).isEmpty ? '.jpg' : p.extension(f.name);
      final file = File(p.join(dir.path, 'ai_${p.basenameWithoutExtension(f.name)}_${DateTime.now().millisecondsSinceEpoch}$ext'));
      await file.writeAsBytes(bytes, flush: true);
      saved = file.path;
    } catch (_) {
      saved = f.path; // نعرض ونرفق من مكانه الأصلي
    }
    if (!mounted) return;
    setState(() {
      _bytes = bytes;
      _fileName = f.name;
      _savedPath = saved;
    });
    await _read();
  }

  Future<void> _read() async {
    final bytes = _bytes;
    if (bytes == null) return;
    setState(() {
      _phase = _Phase.reading;
      _error = null;
    });
    try {
      final r = await AiInvoiceService.extract(
        bytes: bytes,
        mimeType: AiInvoiceService.mimeFor(_fileName),
        products: _products,
        supplierId: _supplier?.id,
        supplierName: _supplier?.name ?? '',
      );
      if (!mounted) return;
      // مورد غير محدد: نحاول معرفته من رأس الفاتورة ثم نعيد تطبيق ما تعلّمناه له
      if (_supplier == null && r.supplierName.isNotEmpty) {
        final n = AiAliasStore.normalize(r.supplierName);
        for (final s in _suppliers) {
          final sn = AiAliasStore.normalize(s.name);
          if (sn.isNotEmpty && (n.contains(sn) || sn.contains(n))) {
            _supplier = s;
            final aliases = await AiAliasStore.forSupplier(s.id);
            AiInvoiceService.applyMatching(r.lines, _products, aliases, s.id);
            break;
          }
        }
      }
      if (!mounted) return;
      _apply(r);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.pick;
        _error = e.toString();
      });
    }
  }

  void _apply(AiInvoiceResult r) {
    for (final row in _rows) {
      row.dispose();
    }
    _rows.clear();
    for (final l in r.lines) {
      final row = _Row(l);
      row.qty.text = _plain(l.qty);
      row.price.text = _plain(l.price);
      _setupUnits(row, keepFactor: false);
      _rows.add(row);
    }
    setState(() {
      _result = r;
      _numberCtl.text = r.invoiceNumber;
      if (r.date != null && r.date!.year > 2000) _date = r.date!;
      _currency = r.currency;
      _cash = r.isCash;
      _paidCtl.text = _plain(r.isCash ? 0.0 : r.amountPaid);
      _phase = _Phase.review;
    });
  }

  static String _plain(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  /// وحدات السطر حسب المادة المطابقة + وحدة فاتورة المورد، والتعبئة المناسبة
  void _setupUnits(_Row row, {required bool keepFactor}) {
    final l = row.line;
    final prod = l.productId == null ? null : _byId[l.productId];
    final units = <String>[];
    if (prod != null) units.addAll(AiInvoiceService.unitsOf(prod));
    String sale = l.saleUnit.trim();
    if (sale.isEmpty && l.unitsCount > 1) sale = l.unitType == 'meter' ? 'لفة' : 'كرتون';
    String? chosen;
    if (sale.isNotEmpty) {
      final n = AiAliasStore.normalize(sale);
      chosen = units.firstWhere((u) => AiAliasStore.normalize(u) == n, orElse: () => '');
      if (chosen.isEmpty) {
        units.add(sale);
        chosen = sale;
      }
    }
    if (units.isEmpty) units.add('قطعة');
    row.units = units;
    row.unit = chosen ?? units.first;
    if (!keepFactor) row.factor.text = _plain(_factorFor(row));
  }

  double _factorFor(_Row row) {
    final prod = row.line.productId == null ? null : _byId[row.line.productId];
    if (prod != null) {
      final f = AiInvoiceService.factorFromProduct(prod, row.unit);
      if (f != null) return f;
    }
    final base = prod == null ? 'قطعة' : AiInvoiceService.baseUnitName(prod);
    return row.unit == base ? 1.0 : (row.line.unitsCount > 0 ? row.line.unitsCount : 1.0);
  }

  Future<void> _changeSupplier(Supplier? s) async {
    setState(() => _supplier = s);
    if (s != null && _result != null) {
      final aliases = await AiAliasStore.forSupplier(s.id);
      AiInvoiceService.applyMatching(_result!.lines, _products, aliases, s.id);
      if (!mounted) return;
      setState(() {
        for (final r in _rows) {
          if (!r.line.userChanged) _setupUnits(r, keepFactor: false);
        }
      });
    }
  }

  Future<void> _changeProduct(_Row row) async {
    final picked = await showDialog<_PickResult>(
      context: context,
      builder: (_) => _ProductPickerDialog(products: _products, query: row.line.cleanName, original: row.line.originalName),
    );
    if (picked == null || !mounted) return;
    setState(() {
      row.line.productId = picked.product?.id;
      row.line.userChanged = true;
      row.line.source = picked.product == null ? AiMatchSource.none : AiMatchSource.manual;
      row.line.confidence = picked.product == null ? 0 : 1;
      row.line.reason = picked.product == null ? 'حدّدتها مادة جديدة' : 'اخترتها يدوياً — سأتذكّر هذا الاسم';
      _setupUnits(row, keepFactor: false);
    });
  }

  // ───────────────────────── المتابعة ─────────────────────────

  Future<void> _continue() async {
    final rows = _rows.where((r) => r.line.include).toList();
    if (_supplier == null) {
      _snack('اختر المورد أولاً', _cLow);
      return;
    }
    if (rows.isEmpty) {
      _snack('لا توجد مواد محددة', _cLow);
      return;
    }
    if (rows.any((r) => r.q <= 0 || r.pr < 0)) {
      _snack('يوجد سطر بكمية صفر أو سعر سالب', _cLow);
      return;
    }
    final items = <PurchaseInvoiceItem>[];
    final originals = <String, String>{};
    var learned = 0;
    for (final r in rows) {
      final l = r.line;
      final prod = l.productId == null ? null : _byId[l.productId];
      final name = prod?.name ?? l.cleanName;
      items.add(PurchaseInvoiceItem(
        productId: prod?.id ?? -1,
        productName: name,
        unitName: r.unit,
        quantity: r.q,
        unitPrice: r.pr,
        conversionFactor: r.f,
        totalPrice: r.total,
      ));
      if (prod == null) {
        originals[name] = l.originalName;
        continue;
      }
      // 🧠 نتعلّم ما صحّحتَه، وما أكّدتَه بمطابقة قوية (لا نتعلّم التقريبي غير المؤكد)
      final teach = l.userChanged ||
          l.source == AiMatchSource.learned ||
          (l.source == AiMatchSource.ai && l.confidence >= 0.85);
      if (teach) {
        try {
          await AiAliasStore.learn(supplierId: _supplier!.id, alias: l.originalName, productId: prod.id!, productName: prod.name);
          if (AiAliasStore.normalize(l.originalName) != AiAliasStore.normalize(prod.name)) learned++;
        } catch (_) {}
      }
    }
    if (!mounted) return;
    final prefill = AiPurchasePrefill(
      items: items,
      invoiceNumber: _numberCtl.text.trim(),
      date: _date,
      currency: _currency,
      isCash: _cash,
      paidAmount: _cash ? 0 : _Row._parse(_paidCtl.text),
      attachmentPath: _savedPath,
      supplierId: _supplier!.id,
      originalNames: originals,
    );
    if (learned > 0) _snack('🧠 حُفظت $learned تسمية لهذا المورد — ستُطابَق تلقائياً في الفاتورة القادمة', _cLearned);
    await Navigator.push(context, accRoute<void>(CreatePurchaseInvoiceScreen(preselectedSupplier: _supplier, aiPrefill: prefill)));
    if (mounted) Navigator.pop(context);
  }

  void _snack(String msg, Color c) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: c, behavior: SnackBarBehavior.floating));
  }

  // ───────────────────────── الواجهة ─────────────────────────

  @override
  Widget build(BuildContext context) {
    // 👑 حماية ثانية: حتى لو فُتحت الشاشة من مكان آخر، غير المالك لا يستطيع استعمالها
    if (!OwnerAccess.enabled) {
      return Scaffold(
        appBar: AppBar(title: const Text('فاتورة بالذكاء الاصطناعي')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.lock_rounded, size: 56, color: _muted),
              SizedBox(height: 12),
              Text('هذه الميزة متاحة لحساب المالك فقط', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: _bg,
      appBar: _appBar(),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              child: switch (_phase) {
                _Phase.pick => _pickView(),
                _Phase.reading => _readingView(),
                _Phase.review => _reviewView(),
              },
            ),
      bottomNavigationBar: _phase == _Phase.review ? _bottomBar() : null,
    );
  }

  PreferredSizeWidget _appBar() => AppBar(
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: LinearGradient(colors: [_aiA, _aiB], begin: Alignment.centerRight, end: Alignment.centerLeft)),
        ),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.auto_awesome_rounded, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('فاتورة شراء بالذكاء الاصطناعي', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              Text(_supplier == null ? 'Gemini • حساب المالك' : 'المورد: ${_supplier!.name}',
                  style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.85))),
            ]),
          ),
        ]),
        actions: [
          if (_phase == _Phase.review && MediaQuery.of(context).size.width < 1000)
            IconButton(
              tooltip: _showDoc ? 'المراجعة' : 'المستند',
              icon: Icon(_showDoc ? Icons.fact_check_rounded : Icons.description_rounded),
              onPressed: () => setState(() => _showDoc = !_showDoc),
            ),
          if (_phase == _Phase.review)
            IconButton(tooltip: 'إعادة القراءة', icon: const Icon(Icons.refresh_rounded), onPressed: _read),
          if (_phase != _Phase.reading)
            IconButton(tooltip: 'ملف آخر', icon: const Icon(Icons.upload_file_rounded), onPressed: _pick),
        ],
      );

  Widget _supplierField({bool dense = false}) {
    return DropdownButtonFormField<int>(
      initialValue: _suppliers.any((s) => s.id == _supplier?.id) ? _supplier?.id : null,
      isExpanded: true,
      decoration: _dec('المورد', Icons.storefront_rounded, dense: dense),
      items: [for (final s in _suppliers) if (s.id != null) DropdownMenuItem(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis))],
      onChanged: (id) => _changeSupplier(_suppliers.firstWhere((s) => s.id == id)),
    );
  }

  InputDecoration _dec(String label, IconData? icon, {bool dense = false}) => InputDecoration(
        labelText: label,
        prefixIcon: icon == null ? null : Icon(icon, size: 19, color: _aiA),
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: dense ? 10 : 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _line)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _line)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _aiA, width: 1.6)),
      );

  // ── 1) اختيار الملف
  Widget _pickView() {
    final noKeys = !AiInvoiceService.hasKeys;
    return Center(
      key: const ValueKey('pick'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(children: [
            if (_error != null) _banner(_error!, _cLow, Icons.error_outline_rounded),
            if (noKeys)
              _banner('لا يوجد مفتاح Gemini في ملف ‎.env — أضف GEMINI_API_KEY ثم أعد تشغيل البرنامج', _cLow, Icons.key_off_rounded),
            const SizedBox(height: 8),
            InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: noKeys ? null : _pick,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 46, horizontal: 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: _aiA.withValues(alpha: 0.35), width: 1.5),
                  boxShadow: [BoxShadow(color: _aiA.withValues(alpha: 0.10), blurRadius: 30, offset: const Offset(0, 12))],
                ),
                child: Column(children: [
                  Container(
                    width: 86,
                    height: 86,
                    decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [_aiA, _aiB])),
                    child: const Icon(Icons.document_scanner_rounded, color: Colors.white, size: 42),
                  ),
                  const SizedBox(height: 18),
                  const Text('اختر صورة أو PDF فاتورة المورد',
                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: _ink)),
                  const SizedBox(height: 6),
                  const Text('يقرأ المواد والكميات والأسعار ويطابقها مع موادك',
                      textAlign: TextAlign.center, style: TextStyle(color: _muted)),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: noKeys ? null : _pick,
                    style: FilledButton.styleFrom(
                        backgroundColor: _aiA, padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                    icon: const Icon(Icons.upload_file_rounded),
                    label: const Text('اختيار الملف', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 10),
                  const Text('JPG • PNG • WEBP • PDF', style: TextStyle(fontSize: 12, color: _muted)),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            _supplierField(),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: _miniStat(Icons.inventory_2_rounded, '${_products.length}', 'مادة تُرسل للمطابقة', _aiA)),
              const SizedBox(width: 10),
              Expanded(child: _miniStat(Icons.psychology_rounded, '$_learnedCount', 'تسمية تعلّمها من تصحيحاتك', _cLearned)),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _miniStat(IconData i, String v, String l, Color c) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: _line)),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Icon(i, color: c, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(v, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: c)),
              Text(l, style: const TextStyle(fontSize: 12, color: _muted)),
            ]),
          ),
        ]),
      );

  Widget _banner(String text, Color c, IconData icon) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14), border: Border.all(color: c.withValues(alpha: 0.35))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: c),
          const SizedBox(width: 10),
          Expanded(child: SelectableText(text, style: TextStyle(color: c.withValues(alpha: 0.95), height: 1.45))),
        ]),
      );

  // ── 2) القراءة
  Widget _readingView() {
    return Center(
      key: const ValueKey('reading'),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 110,
          height: 110,
          child: Stack(alignment: Alignment.center, children: [
            const SizedBox(width: 110, height: 110, child: CircularProgressIndicator(strokeWidth: 5, color: _aiA)),
            Container(
              width: 74,
              height: 74,
              decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [_aiA, _aiB])),
              child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 36),
            ),
          ]),
        ),
        const SizedBox(height: 22),
        const Text('يقرأ Gemini الفاتورة…', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _ink)),
        const SizedBox(height: 8),
        Text(_fileName, style: const TextStyle(color: _muted)),
        const SizedBox(height: 18),
        for (final s in const ['استخراج المواد والكميات والأسعار', 'مطابقة الأسماء مع موادك', 'تطبيق ما تعلّمه من تصحيحاتك السابقة'])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.check_circle_outline_rounded, size: 17, color: _aiB),
              const SizedBox(width: 6),
              Text(s, style: const TextStyle(color: _muted)),
            ]),
          ),
        const SizedBox(height: 10),
        const Text('قد يستغرق 10–60 ثانية حسب حجم الفاتورة', style: TextStyle(fontSize: 12, color: _muted)),
      ]),
    );
  }

  // ── 3) المراجعة
  Widget _reviewView() {
    return LayoutBuilder(
      key: const ValueKey('review'),
      builder: (context, c) {
        final wide = c.maxWidth >= 1000;
        if (!wide) return _showDoc ? _docPane() : _reviewPane();
        return Row(children: [
          SizedBox(width: c.maxWidth * 0.38, child: _docPane()),
          const VerticalDivider(width: 1, color: _line),
          Expanded(child: _reviewPane()),
        ]);
      },
    );
  }

  Widget _docPane() {
    final bytes = _bytes;
    if (bytes == null) return const SizedBox();
    final isPdf = _fileName.toLowerCase().endsWith('.pdf');
    return Container(
      color: const Color(0xFF1E1B4B),
      child: isPdf
          ? (_savedPath != null && File(_savedPath!).existsSync()
              ? PdfViewer.file(_savedPath!)
              : const Center(child: Text('تعذّر عرض الـ PDF', style: TextStyle(color: Colors.white70))))
          : InteractiveViewer(
              maxScale: 6,
              child: Center(child: Image.memory(bytes, fit: BoxFit.contain)),
            ),
    );
  }

  Color _colorOf(AiInvoiceLine l) {
    if (l.productId == null) return _cNew;
    switch (l.source) {
      case AiMatchSource.learned:
        return _cLearned;
      case AiMatchSource.manual:
        return _cManual;
      case AiMatchSource.exact:
        return _cGood;
      default:
        return l.confidence >= 0.85 ? _cGood : (l.confidence >= 0.6 ? _cMid : _cLow);
    }
  }

  String _badgeOf(AiInvoiceLine l) {
    if (l.productId == null) return 'مادة جديدة';
    switch (l.source) {
      case AiMatchSource.learned:
        return 'تعلّم سابق';
      case AiMatchSource.manual:
        return 'اختيارك';
      case AiMatchSource.exact:
        return 'مطابق';
      case AiMatchSource.local:
        return 'تقريبي ${(l.confidence * 100).round()}%';
      default:
        return '${(l.confidence * 100).round()}%';
    }
  }

  Widget _reviewPane() {
    final r = _result!;
    final included = _rows.where((x) => x.line.include).toList();
    final sum = included.fold<double>(0, (s, x) => s + x.total);
    final nLearned = included.where((x) => x.line.source == AiMatchSource.learned && x.line.productId != null).length;
    final nNew = included.where((x) => x.line.productId == null).length;
    final nCheck = included.where((x) => x.line.productId != null && _colorOf(x.line) != _cGood && _colorOf(x.line) != _cLearned && _colorOf(x.line) != _cManual).length;
    final nOk = included.length - nNew - nCheck;
    final expected = r.grandTotal > 0 ? r.grandTotal + r.discount - r.shipping : 0.0;
    final diff = expected > 0 ? (sum - expected).abs() : 0.0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        // رأس الفاتورة
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: _line)),
          child: Column(children: [
            Wrap(spacing: 10, runSpacing: 10, children: [
              SizedBox(width: 260, child: _supplierField(dense: true)),
              SizedBox(
                width: 170,
                child: TextField(controller: _numberCtl, decoration: _dec('رقم فاتورة المورد', Icons.tag_rounded, dense: true)),
              ),
              SizedBox(
                width: 170,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () async {
                    final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2015), lastDate: DateTime(2100));
                    if (d != null) setState(() => _date = d);
                  },
                  child: InputDecorator(
                    decoration: _dec('التاريخ', Icons.event_rounded, dense: true),
                    child: Text(intl.DateFormat('yyyy/MM/dd').format(_date)),
                  ),
                ),
              ),
              SegmentedButton<String>(
                segments: const [ButtonSegment(value: 'IQD', label: Text('دينار')), ButtonSegment(value: 'USD', label: Text('دولار'))],
                selected: {_currency},
                onSelectionChanged: (s) => setState(() => _currency = s.first),
              ),
              SegmentedButton<bool>(
                segments: const [ButtonSegment(value: false, label: Text('دين')), ButtonSegment(value: true, label: Text('نقد'))],
                selected: {_cash},
                onSelectionChanged: (s) => setState(() => _cash = s.first),
              ),
              if (!_cash)
                SizedBox(
                  width: 150,
                  child: TextField(
                    controller: _paidCtl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: _dec('المدفوع', Icons.payments_rounded, dense: true),
                  ),
                ),
            ]),
          ]),
        ),
        const SizedBox(height: 12),
        // ملخص
        Wrap(spacing: 8, runSpacing: 8, children: [
          _pill(Icons.check_circle_rounded, 'مطابق $nOk', _cGood),
          if (nLearned > 0) _pill(Icons.psychology_rounded, 'منها من التعلّم $nLearned', _cLearned),
          _pill(Icons.help_rounded, 'راجِع $nCheck', nCheck > 0 ? _cMid : _muted),
          _pill(Icons.fiber_new_rounded, 'جديدة $nNew', nNew > 0 ? _cNew : _muted),
        ]),
        if (diff > 1 && diff > expected * 0.005)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: _banner(
                'مجموع الأسطر ${_fmt.format(sum)} يختلف عن إجمالي الفاتورة المقروء ${_fmt.format(expected)} '
                '(الفرق ${_fmt.format(diff)}). تحقّق من الكميات والأسعار أو من سطر لم يُقرأ.',
                _cMid,
                Icons.warning_amber_rounded),
          ),
        const SizedBox(height: 12),
        if (_rows.isEmpty) _banner('لم يُستخرج أي سطر من الفاتورة — جرّب صورة أوضح', _cLow, Icons.search_off_rounded),
        for (var i = 0; i < _rows.length; i++) _lineCard(i, _rows[i]),
      ],
    );
  }

  Widget _pill(IconData i, String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(30)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(i, size: 16, color: c),
          const SizedBox(width: 5),
          Text(t, style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 12.5)),
        ]),
      );

  Widget _lineCard(int i, _Row row) {
    final l = row.line;
    final c = _colorOf(l);
    final prod = l.productId == null ? null : _byId[l.productId];
    final off = !l.include;
    // تعبئة الفاتورة تختلف عن تعريف المادة عندنا؟ (مثلاً كرتون 24 وعندنا 20)
    final ourFactor = prod == null ? null : AiInvoiceService.factorFromProduct(prod, row.unit);
    final packMismatch = ourFactor != null && l.unitsCount > 1 && (ourFactor - l.unitsCount).abs() > 0.001;
    final notes = [
      if (l.note.isNotEmpty) l.note,
      if (packMismatch)
        'الفاتورة تقول تعبئة «${row.unit}» = ${_fmt.format(l.unitsCount)} وتعريف مادتك = ${_fmt.format(ourFactor)} — عدّل حقل التعبئة إن تغيّرت',
    ];
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: off ? 0.45 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.withValues(alpha: 0.35)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              width: 6,
              decoration: BoxDecoration(color: c, borderRadius: const BorderRadius.horizontal(right: Radius.circular(16))),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 10, 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), shape: BoxShape.circle),
                      child: Text('${i + 1}', style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 12)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('«${l.originalName}»',
                          maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted, fontSize: 12.5)),
                    ),
                    if (l.isFree) ...[_pill(Icons.card_giftcard_rounded, 'بونص', _cLearned), const SizedBox(width: 6)],
                    _pill(l.source == AiMatchSource.learned ? Icons.psychology_rounded : Icons.auto_awesome_rounded, _badgeOf(l), c),
                    Checkbox(
                      value: l.include,
                      activeColor: _aiA,
                      onChanged: (v) => setState(() => l.include = v ?? true),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _changeProduct(row),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(color: c.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12)),
                      child: Row(children: [
                        Icon(prod == null ? Icons.add_box_rounded : Icons.inventory_2_rounded, color: c, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(prod?.name ?? l.cleanName,
                                style: const TextStyle(fontWeight: FontWeight.w800, color: _ink, fontSize: 14.5)),
                            Text(
                              prod == null
                                  ? 'غير موجودة عندك — تُعرَّف في شاشة الشراء أو اضغط لاختيار مادة'
                                  : [
                                      if ((prod.costPrice ?? 0) > 0) 'الكلفة الحالية ${_fmt.format(prod.costPrice!)}',
                                      if (l.reason.isNotEmpty) l.reason,
                                    ].join(' • '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11.5, color: _muted),
                            ),
                          ]),
                        ),
                        const Icon(Icons.swap_horiz_rounded, color: _muted, size: 20),
                      ]),
                    ),
                  ),
                  for (final n in notes)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Icon(Icons.info_outline_rounded, size: 15, color: _cMid),
                        const SizedBox(width: 5),
                        Expanded(child: Text(n, style: const TextStyle(fontSize: 11.5, color: _cMid))),
                      ]),
                    ),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    _numField('الكمية', row.qty, 100),
                    SizedBox(
                      width: 130,
                      child: DropdownButtonFormField<String>(
                        initialValue: row.units.contains(row.unit) ? row.unit : null,
                        isExpanded: true,
                        decoration: _dec('الوحدة', null, dense: true),
                        items: [for (final u in row.units) DropdownMenuItem(value: u, child: Text(u, overflow: TextOverflow.ellipsis))],
                        onChanged: (u) => setState(() {
                          row.unit = u ?? row.unit;
                          row.factor.text = _plain(_factorFor(row));
                        }),
                      ),
                    ),
                    Tooltip(
                      message: 'كم ${prod == null ? 'قطعة' : AiInvoiceService.baseUnitName(prod)} في «${row.unit}»',
                      child: _numField('التعبئة', row.factor, 90),
                    ),
                    _numField('السعر', row.price, 120),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(12)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        const Text('الإجمالي', style: TextStyle(fontSize: 11, color: _muted)),
                        Text(_fmt.format(row.total), style: const TextStyle(fontWeight: FontWeight.w800, color: _ink)),
                      ]),
                    ),
                    if (row.f > 1 && row.pr > 0)
                      Text('= ${_fmt.format(row.pr / row.f)} لكل ${prod == null ? 'قطعة' : AiInvoiceService.baseUnitName(prod)}',
                          style: const TextStyle(fontSize: 11.5, color: _muted)),
                  ]),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _numField(String label, TextEditingController ctl, double w) => SizedBox(
        width: w,
        child: TextField(
          controller: ctl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          decoration: _dec(label, null, dense: true),
        ),
      );

  Widget _bottomBar() {
    final included = _rows.where((x) => x.line.include).toList();
    final sum = included.fold<double>(0, (s, x) => s + x.total);
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 14, offset: const Offset(0, -4))]),
        child: Row(children: [
          Expanded(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${_fmt.format(sum)} $_currency', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: _ink)),
              Text('${included.length} مادة • تصحيحاتك تُحفظ ليتعلّم أسماء هذا المورد',
                  style: const TextStyle(fontSize: 11.5, color: _muted), overflow: TextOverflow.ellipsis),
            ]),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: _continue,
            style: FilledButton.styleFrom(
                backgroundColor: _aiA, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('متابعة إلى فاتورة الشراء', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ]),
      ),
    );
  }
}

// ───────────────────────── اختيار مادة ─────────────────────────

class _PickResult {
  const _PickResult(this.product);
  final Product? product; // null = مادة جديدة
}

class _ProductPickerDialog extends StatefulWidget {
  const _ProductPickerDialog({required this.products, required this.query, required this.original});
  final List<Product> products;
  final String query;
  final String original;
  @override
  State<_ProductPickerDialog> createState() => _ProductPickerDialogState();
}

class _ProductPickerDialogState extends State<_ProductPickerDialog> {
  late final TextEditingController _q = TextEditingController(text: widget.query);

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  List<Product> get _filtered {
    final words = AiAliasStore.normalize(_q.text).replaceAll('x', ' ').split(' ').where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return widget.products.take(200).toList();
    final scored = <(Product, int)>[];
    for (final p in widget.products) {
      final n = AiAliasStore.normalize(p.name).replaceAll('x', ' ');
      final hits = words.where(n.contains).length;
      if (hits > 0) scored.add((p, hits));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return scored.take(200).map((e) => e.$1).toList();
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('اختر المادة المقابلة', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _ink)),
            const SizedBox(height: 4),
            Text('في فاتورة المورد: «${widget.original}» — سأتذكّر اختيارك لهذا المورد',
                style: const TextStyle(fontSize: 12, color: _muted)),
            const SizedBox(height: 12),
            TextField(
              controller: _q,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'ابحث بالاسم أو المقاس…',
                prefixIcon: const Icon(Icons.search_rounded),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              dense: true,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              tileColor: _cNew.withValues(alpha: 0.07),
              leading: const Icon(Icons.add_box_rounded, color: _cNew),
              title: const Text('مادة جديدة — أعرّفها في شاشة الشراء', style: TextStyle(fontWeight: FontWeight.w700, color: _cNew)),
              onTap: () => Navigator.pop(context, const _PickResult(null)),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: list.isEmpty
                  ? const Center(child: Text('لا توجد نتائج', style: TextStyle(color: _muted)))
                  : ListView.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, color: _line),
                      itemBuilder: (_, i) {
                        final p = list[i];
                        return ListTile(
                          dense: true,
                          title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                              '${AiInvoiceService.unitsOf(p).join(' / ')}${(p.costPrice ?? 0) > 0 ? ' • كلفة ${p.costPrice}' : ''}',
                              style: const TextStyle(fontSize: 11.5)),
                          onTap: () => Navigator.pop(context, _PickResult(p)),
                        );
                      },
                    ),
            ),
          ]),
        ),
      ),
    );
  }
}
