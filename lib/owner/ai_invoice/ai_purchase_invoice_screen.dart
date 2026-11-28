// lib/owner/ai_invoice/ai_purchase_invoice_screen.dart
//
// 👑🤖 «فاتورة شراء بالذكاء الاصطناعي» — لحساب المالك واشتراك المزامنة (SyncPerks).
//
// 1) اختر صورة/PDF فاتورة المورد — أو عدة صور لفاتورة من عدة صفحات (تُقرأ فاتورةً واحدة)
// 2) تقرأها نماذج الإعدادات (نموذج يقرأ وآخر يطابق — ai_invoice_engine.dart) وتطابق
//    موادها مع موادنا (مع ما تعلّمه من تصحيحاتك السابقة)
// 3) تراجع كل سطر: تغيّر المادة، الوحدة، التعبئة، الكمية، السعر
// 4) «متابعة» ⇒ تُحفظ تصحيحاتك (ذاكرة الأسماء) وتُفتح فاتورة الشراء العادية معبأة
//    والحفظ هناك يمرّ بكل حمايات الشاشة الأصلية (المخزون، الدين، الفترات المثبّتة).

import 'package:flutter/services.dart' show Clipboard, ClipboardData; // 📋 نسخ رقمنا
import '../../screens/license_screen.dart' show openSupportWhatsApp; // 💬 واتساب الدعم
import '../../services/license_v4/license_config.dart'; // ☎️ رقمنا
import '../../services/admin_unlocks.dart'; // 🔓
import 'dart:async';
import 'dart:convert' show latin1;
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../accounting/screens/acc_ui.dart' show accRoute;
import '../../models/product.dart';
import '../../models/purchase_invoice_item.dart';
import '../../models/supplier.dart';
import '../../screens/create_purchase_invoice_screen.dart';
import '../../services/database_service.dart';
import '../../services/pdf_raster.dart';
import '../../services/ai_models/ai_models_config.dart';
import '../../services/ai_models/ai_vision_client.dart' show AiBlob;
import '../../services/purchase_service.dart';
import '../../services/sync_perks.dart';
import '../../screens/ai_models_settings_screen.dart';
import 'ai_alias_store.dart';
import 'ai_invoice_service.dart';
import 'ai_supplier_picker.dart'; // 🏪 اختيار المورد
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

/// ملف مختار: صورة صفحة، أو ملف PDF واحد.
class _Doc {
  const _Doc(this.bytes, this.name);
  final Uint8List bytes;
  final String name;
  bool get isPdf => name.toLowerCase().endsWith('.pdf');
  String get mime => AiInvoiceService.mimeFor(name);
}

/// ⏳ تقدير مدة القراءة (للعرض فقط): عدد الصفحات من الصور، أو من بنية الـ PDF.
class AiReadEstimate {
  AiReadEstimate._();

  /// عدد صفحات PDF تقريبياً («/Type /Page» دون «/Pages»). 1 على الأقل.
  static int pdfPages(Uint8List pdf) {
    try {
      final n = RegExp(r'/Type\s*/Page(?![s])').allMatches(latin1.decode(pdf, allowInvalid: true)).length;
      return n < 1 ? 1 : n;
    } catch (_) {
      return 1;
    }
  }

  /// ثوانٍ تقريبية: 20 للبدء والمطابقة + 12 لكل صفحة، بحد 4 دقائق.
  static int seconds(int pages) => (20 + 12 * (pages < 1 ? 1 : pages)).clamp(25, 240).toInt();
}

class _Row {
  _Row(this.line);
  final AiInvoiceLine line;
  final qty = TextEditingController();
  final price = TextEditingController();
  final factor = TextEditingController();
  String unit = '';
  List<String> units = const [];

  /// 📅 صلاحية السطر «yyyy-MM-dd» (من الفاتورة أو تُكتب هنا). null = بلا صلاحية.
  String? expiry;

  /// 📦 وحدات المادة الجديدة كما عرّفها المستخدم (null = لم تُعرَّف بعد).
  AiUnitPlan? plan;

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
  bool _hasKeys = true;
  String _status = '';

  /// الملفات المختارة: PDF واحد، أو صورة، أو عدة صور لفاتورة واحدة.
  List<_Doc> _docs = const [];
  static const _maxImages = 20;
  String? _savedPath;
  String? _errorDetail; // تفاصيل تقنية للخطأ (تُفتح بزر — لا تظهر أسماء النماذج في الواجهة)

  // ⏳ عدّاد القراءة: المدة المقدّرة والمنقضية
  final _readWatch = Stopwatch();
  Timer? _ticker;
  int _etaSeconds = 30;

  Uint8List? get _bytes => _docs.isEmpty ? null : _docs.first.bytes;
  String get _fileName => _docs.isEmpty
      ? ''
      : (_docs.length == 1 ? _docs.first.name : '${_docs.length} صور — ${_docs.first.name}…');
  bool get _isPdf => _docs.length == 1 && _docs.first.isPdf;
  Future<List<Uint8List>>? _pdfView; // صور صفحات الـ PDF للعرض (لا pdfrx — انظر pdf_raster.dart)
  double _pdfZoom = 1;

  /// شريط تمرير صفحات الـ PDF مربوط بقائمتها صراحة (على الحاسبة لا «متحكم أساسي»
  /// للقوائم، فكان الشريط يرسم بلا قائمة: «Scrollbar's ScrollController has no ScrollPosition»).
  final _pdfScroll = ScrollController();
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
    _pdfScroll.dispose();
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final suppliers = await context.read<PurchaseService>().getSuppliers();
      final products = (await DatabaseService().getAllProducts()).where((p) => p.id != null && !p.isDeleted).toList();
      final learned = await AiAliasStore.count();
      // «مُعدّ» = نموذج مفعّل له مفتاح (مفتاح بلا نموذج مفعّل لا يقرأ شيئاً)
      final hasKeys = (await AiModelsStore.usableChain()).isNotEmpty;
      if (!mounted) return;
      setState(() {
        _hasKeys = hasKeys;
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
      allowMultiple: true, // 🖼️ فاتورة ضخمة مصوّرة على عدة صور
      withData: true,
    );
    if (res == null || res.files.isEmpty) return;
    final docs = <_Doc>[];
    for (final f in res.files) {
      Uint8List? bytes = f.bytes;
      if (bytes == null && f.path != null) bytes = await File(f.path!).readAsBytes();
      if (bytes != null && bytes.isNotEmpty) docs.add(_Doc(bytes, f.name));
    }
    if (docs.isEmpty || !mounted) return;
    if (docs.length > 1 && docs.any((d) => d.isPdf)) {
      _snack('اختر ملف PDF واحداً، أو عدة صور لفاتورة واحدة — لا تجمع بينهما', _cLow);
      return;
    }
    if (docs.length > _maxImages) {
      _snack('حتى $_maxImages صورة للفاتورة الواحدة', _cLow);
      return;
    }
    final saved = await _saveAttachment(docs);
    if (!mounted) return;
    setState(() {
      _docs = docs;
      _savedPath = saved;
      _pdfView = null;
      _pdfZoom = 1;
    });
    await _read();
  }

  /// 📎 مرفق فاتورة الشراء: الملف نفسه، أو الصور مجمّعة في PDF واحد بترتيب اختيارها.
  Future<String?> _saveAttachment(List<_Doc> docs) async {
    try {
      final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'attachments'));
      if (!await dir.exists()) await dir.create(recursive: true);
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final first = docs.first;
      if (docs.length > 1) {
        try {
          final pdf = pw.Document();
          for (final d in docs) {
            final img = pw.MemoryImage(d.bytes);
            pdf.addPage(pw.Page(
              pageFormat: PdfPageFormat.a4,
              margin: const pw.EdgeInsets.all(12),
              build: (_) => pw.Center(child: pw.Image(img, fit: pw.BoxFit.contain)),
            ));
          }
          final file = File(p.join(dir.path, 'ai_${p.basenameWithoutExtension(first.name)}_${stamp}_${docs.length}p.pdf'));
          await file.writeAsBytes(await pdf.save(), flush: true);
          return file.path;
        } catch (_) {
          // صيغة صورة لا يقبلها مولّد الـ PDF ⇒ نرفق الصورة الأولى على الأقل
        }
      }
      final ext = p.extension(first.name).isEmpty ? '.jpg' : p.extension(first.name);
      final file = File(p.join(dir.path, 'ai_${p.basenameWithoutExtension(first.name)}_$stamp$ext'));
      await file.writeAsBytes(first.bytes, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  void _startClock() {
    final pages = _isPdf ? AiReadEstimate.pdfPages(_docs.first.bytes) : _docs.length;
    _etaSeconds = AiReadEstimate.seconds(pages);
    _readWatch
      ..reset()
      ..start();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _phase == _Phase.reading) setState(() {});
    });
  }

  void _stopClock() {
    _ticker?.cancel();
    _ticker = null;
    _readWatch.stop();
  }

  Future<void> _read() async {
    final docs = _docs;
    if (docs.isEmpty) return;
    setState(() {
      _phase = _Phase.reading;
      _error = null;
      _errorDetail = null;
      _status = '';
    });
    _startClock();
    try {
      final first = docs.first;
      final r = await AiInvoiceService.extract(
        bytes: first.bytes,
        mimeType: first.mime,
        moreImages: [for (final d in docs.skip(1)) AiBlob(d.bytes, d.mime)],
        products: _products,
        supplierId: _supplier?.id,
        supplierName: _supplier?.name ?? '',
        onStatus: (s) {
          if (mounted) setState(() => _status = s);
        },
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
      _stopClock();
      _apply(r);
    } catch (e) {
      _stopClock();
      if (!mounted) return;
      // لا نموذج مفعّل له مفتاح (حُذف أثناء العمل): نفس بطاقة «غير مُعدّة»
      if ('$e'.contains('لا يوجد نموذج مفعّل له مفتاح')) {
        setState(() {
          _phase = _Phase.pick;
          _hasKeys = false;
          _error = null;
          _errorDetail = null;
        });
        return;
      }
      // رسالة مفهومة بلا أسماء نماذج ولا مفاتيح؛ التفاصيل التقنية خلف زر
      final friendly = e is AiInvoiceException && !e.message.startsWith('فشلت قراءة')
          ? e.message
          : 'تعذّرت قراءة الفاتورة — تأكد من الاتصال بالإنترنت ثم أعد المحاولة. إن تكرر تواصل معنا: ${LicenseConfig.supportPhone}';
      setState(() {
        _phase = _Phase.pick;
        _error = friendly;
        _errorDetail = e.toString();
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
      row.expiry = l.expiry;
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
    // مادة جديدة عُرّفت وحداتها: من الأكبر إلى الأصغر، والوحدة المختارة تبقى
    final plan = row.plan;
    if (prod == null && plan != null) {
      row.units = plan.units.reversed.toList();
      if (!row.units.contains(row.unit)) row.unit = row.units.first;
      if (!keepFactor) row.factor.text = _plain(_factorFor(row));
      return;
    }
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
    if (prod == null && row.plan != null) return row.plan!.factorOf(row.unit);
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

  /// اسم الوحدة الأصغر للسطر (للتعبئة و«لكل …»).
  String _baseLabel(_Row row, Product? prod) =>
      prod != null ? AiInvoiceService.baseUnitName(prod) : (row.plan?.baseUnit ?? 'قطعة');

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
    final plans = <String, AiUnitPlan>{};
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
        expiryDate: r.expiry, // 📅 تنتقل إلى دفعة المخزون عند «تأكيد واستلام»
      ));
      if (prod == null) {
        originals[name] = l.originalName;
        // 📦 الوحدات تُعرَّف كاملة في بطاقة المادة من فاتورة الشراء (تفتح بالاسم ووحدة
        //    الفاتورة وسعرها) — لا تعريف وحدات هنا
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
      unitPlans: plans,
    );
    if (learned > 0) _snack('🧠 حُفظت $learned تسمية لهذا المورد — ستُطابَق تلقائياً في الفاتورة القادمة', _cLearned);
    await Navigator.push(context, accRoute<void>(CreatePurchaseInvoiceScreen(preselectedSupplier: _supplier, aiPrefill: prefill)));
    if (mounted) Navigator.pop(context);
  }

  Future<void> _openModelsSettings() async {
    if (!await AdminUnlocks.confirm(context, AdminUnlocks.ai) || !mounted) return; // 🔓
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const AiModelsSettingsScreen()));
    final hasKeys = (await AiModelsStore.usableChain()).isNotEmpty;
    if (mounted) setState(() => _hasKeys = hasKeys);
  }

  void _snack(String msg, Color c) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: c, behavior: SnackBarBehavior.floating));
  }

  // ───────────────────────── الواجهة ─────────────────────────

  @override
  Widget build(BuildContext context) {
    // 👑 حماية ثانية: حتى لو فُتحت الشاشة من مكان آخر، غير المالك لا يستطيع استعمالها
    if (!SyncPerks.enabled) {
      return Scaffold(
        appBar: AppBar(title: const Text('فاتورة بالذكاء الاصطناعي')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.lock_rounded, size: 56, color: _muted),
              SizedBox(height: 12),
              Text('هذه الميزة متاحة لحساب المالك واشتراك المزامنة',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
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
              Text(_supplier == null ? 'قراءة ومطابقة بالذكاء الاصطناعي' : 'المورد: ${_supplier!.name}',
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
          // غير مُعدّ: لا زر للإعدادات هنا — الإعداد عن طريقنا (انظر _notSetUpCard)
          if (_phase != _Phase.reading && _hasKeys)
            IconButton(tooltip: 'النماذج والمفاتيح', icon: const Icon(Icons.tune_rounded), onPressed: _openModelsSettings),
        ],
      );

  // 🏪 نافذة بحث جميلة بدل القائمة المنسدلة الطويلة
  Widget _supplierField({bool dense = false}) {
    return SupplierPickField(
      supplier: _supplier,
      dense: dense,
      onTap: () async {
        final s = await showSupplierPicker(context, suppliers: _suppliers, selected: _supplier);
        if (s != null && mounted) await _changeSupplier(s);
      },
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
    final noKeys = !_hasKeys;
    return Center(
      key: const ValueKey('pick'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(children: [
            if (_error != null) _banner(_error!, _cLow, Icons.error_outline_rounded),
            if (_error != null && _errorDetail != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('التفاصيل التقنية'),
                      content: SingleChildScrollView(child: SelectableText(_errorDetail!, style: const TextStyle(fontSize: 12.5))),
                      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق'))],
                    ),
                  ),
                  icon: const Icon(Icons.info_outline_rounded, size: 18),
                  label: const Text('التفاصيل التقنية'),
                ),
              ),
            if (noKeys) ...[
              _notSetUpCard(),
              const SizedBox(height: 8),
            ],
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
                  const Text('يقرأ المواد والكميات والأسعار والصلاحية ويطابقها مع موادك',
                      textAlign: TextAlign.center, style: TextStyle(color: _muted)),
                  const SizedBox(height: 4),
                  const Text('فاتورة طويلة؟ اختر صورها كلها معاً (حتى 20 صورة)، أو ملف PDF واحد بكل صفحاته',
                      textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: _aiB, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: noKeys ? null : _pick,
                    style: FilledButton.styleFrom(
                        backgroundColor: _aiA, padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                    icon: const Icon(Icons.upload_file_rounded),
                    label: const Text('اختيار الصور أو الملف', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 10),
                  const Text('JPG • PNG • WEBP (عدة صور) • PDF (ملف واحد)', style: TextStyle(fontSize: 12, color: _muted)),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            _supplierField(),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: _miniStat(Icons.inventory_2_rounded, '${_products.length}', 'مادة للمطابقة', _aiA)),
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

  /// 🤖 الذكاء الاصطناعي غير مُعدّ على هذا الجهاز: رسالة واحدة واضحة + التواصل معنا.
  /// (بلا ذكر للمفاتيح أو المزوّدين، وبلا زر للإعدادات — الإعداد يتم عن طريقنا)
  Widget _notSetUpCard() {
    const phone = LicenseConfig.supportPhone;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _aiA.withValues(alpha: 0.22)),
        boxShadow: [BoxShadow(color: _aiA.withValues(alpha: 0.08), blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: _aiA.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.auto_awesome_rounded, color: _aiA, size: 24),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('إعدادات الذكاء الاصطناعي غير مُعدّة على هذا الجهاز',
                  style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: Color(0xFF1E293B), height: 1.4)),
              SizedBox(height: 4),
              Text('يجب إعدادها أولاً. للإعداد تواصل معنا.',
                  style: TextStyle(fontSize: 13.5, color: _muted, height: 1.5)),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          FilledButton.icon(
            onPressed: openSupportWhatsApp,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF16A34A),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.chat_rounded, size: 19),
            label: const Text('واتساب', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(const ClipboardData(text: phone));
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('نُسخ الرقم $phone'), duration: Duration(seconds: 2)),
              );
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF1E293B),
              side: const BorderSide(color: Color(0xFFCBD5E1)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.call_rounded, size: 19),
            label: const Text(phone,
                textDirection: TextDirection.ltr,
                style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.6, fontFeatures: [FontFeature.tabularFigures()])),
          ),
        ]),
      ]),
    );
  }

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

  // ── 2) القراءة — بلا اسم نموذج: ما يحدث الآن والمدة المتبقية فقط
  Widget _readingView() {
    final elapsed = _readWatch.elapsed.inSeconds;
    final left = _etaSeconds - elapsed;
    final progress = (elapsed / _etaSeconds).clamp(0.02, 0.96).toDouble();
    final step = _status.isEmpty ? 'يقرأ الفاتورة…' : _status;
    return Center(
      key: const ValueKey('reading'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
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
            Text(
              left > 0 ? 'انتظر نحو ${_secondsText(left)}' : 'لحظات قليلة ويكتمل…',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: _ink),
            ),
            const SizedBox(height: 6),
            Text(step, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: _aiA)),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: _aiA.withValues(alpha: 0.12),
                color: _aiA,
              ),
            ),
            const SizedBox(height: 8),
            Text('مرّ ${_secondsText(elapsed)} • $_fileName',
                textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: _muted)),
            const SizedBox(height: 18),
            for (final s in const [
              'استخراج المواد والكميات والأسعار والصلاحية',
              'مطابقة الأسماء مع موادك',
              'تطبيق ما تعلّمه من تصحيحاتك السابقة',
            ])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.check_circle_outline_rounded, size: 17, color: _aiB),
                  const SizedBox(width: 6),
                  Flexible(child: Text(s, style: const TextStyle(color: _muted))),
                ]),
              ),
          ]),
        ),
      ),
    );
  }

  static String _secondsText(int s) {
    if (s < 60) return '$s ثانية';
    final m = s ~/ 60, r = s % 60;
    return r == 0 ? '$m دقيقة' : '$m دقيقة و$r ثانية';
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
    return Container(
      color: const Color(0xFF1E1B4B),
      child: _isPdf
          ? _pdfPages(bytes)
          : (_docs.length > 1
              ? _imagePages()
              : InteractiveViewer(
                  maxScale: 6,
                  child: Center(child: Image.memory(bytes, fit: BoxFit.contain)),
                )),
    );
  }

  /// 🖼️ صور الفاتورة صفحةً تحت صفحة؛ الضغط على صفحة يفتحها للتكبير.
  Widget _imagePages() {
    return Scrollbar(
      controller: _pdfScroll,
      child: ListView.separated(
        controller: _pdfScroll,
        padding: const EdgeInsets.all(12),
        itemCount: _docs.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => GestureDetector(
          onTap: () => showDialog<void>(
            context: context,
            builder: (ctx) => Dialog.fullscreen(
              backgroundColor: Colors.black,
              child: Stack(children: [
                InteractiveViewer(maxScale: 8, child: Center(child: Image.memory(_docs[i].bytes, fit: BoxFit.contain))),
                PositionedDirectional(
                  top: 12,
                  end: 12,
                  child: IconButton.filled(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
              ]),
            ),
          ),
          child: Stack(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(_docs[i].bytes, fit: BoxFit.fitWidth, gaplessPlayback: true),
            ),
            PositionedDirectional(
              top: 8,
              start: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(20)),
                child: Text('صفحة ${i + 1} من ${_docs.length}', style: const TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  /// صفحات الـ PDF صوراً (تحويل واحد لكل ملف) مع تكبير/تصغير.
  Widget _pdfPages(Uint8List bytes) {
    const msg = TextStyle(color: Colors.white70);
    return FutureBuilder<List<Uint8List>>(
      future: _pdfView ??= PdfRaster2Png.pages(bytes, dpi: 144, max: 40),
      builder: (context, s) {
        if (s.hasError) return const Center(child: Text('تعذّر عرض الـ PDF', style: msg));
        final pages = s.data;
        if (pages == null) {
          return const Center(child: CircularProgressIndicator(color: Colors.white70, strokeWidth: 2.5));
        }
        if (pages.isEmpty) return const Center(child: Text('الملف لا يحوي صفحات', style: msg));
        return LayoutBuilder(builder: (context, c) {
          final w = (c.maxWidth - 24) * _pdfZoom;
          return Stack(children: [
            Scrollbar(
              controller: _pdfScroll,
              child: ListView.separated(
                controller: _pdfScroll,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 64),
                itemCount: pages.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: w,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(pages[i], fit: BoxFit.fitWidth, gaplessPlayback: true, filterQuality: FilterQuality.medium),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      tooltip: 'تصغير',
                      icon: const Icon(Icons.zoom_out, color: Colors.white),
                      onPressed: _pdfZoom <= 1 ? null : () => setState(() => _pdfZoom = (_pdfZoom - 0.5).clamp(1.0, 3.0).toDouble()),
                    ),
                    Text('${(_pdfZoom * 100).round()}%  ·  ${pages.length} ص', style: const TextStyle(color: Colors.white, fontSize: 12.5)),
                    IconButton(
                      tooltip: 'تكبير',
                      icon: const Icon(Icons.zoom_in, color: Colors.white),
                      onPressed: _pdfZoom >= 3 ? null : () => setState(() => _pdfZoom = (_pdfZoom + 0.5).clamp(1.0, 3.0).toDouble()),
                    ),
                  ]),
                ),
              ),
            ),
          ]);
        });
      },
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
    final nExp = included.where((x) => x.expiry != null).length;
    final expected = r.grandTotal > 0 ? r.grandTotal + r.discount - r.shipping : 0.0;
    final diff = expected > 0 ? (sum - expected).abs() : 0.0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        // ملاحظة المحرك بلا أسماء نماذج (اسم النموذج لا يظهر في الواجهة)
        if (r.engineNote.isNotEmpty)
          _banner('لم تكتمل المطابقة الذكية — طابقتُ الأسطر محلياً، راجعها قبل المتابعة.', _cMid, Icons.info_outline_rounded),
        // 🔢 أسطر مرقّمة في الفاتورة لم تُقرأ حتى بعد إعادة طلبها
        if (r.missingRows.isNotEmpty)
          _banner(
              'لم تُقرأ ${r.missingRows.length == 1 ? 'السطر رقم' : 'الأسطر رقم'} ${r.missingRows.join('، ')} من جدول الفاتورة. '
              'قارن بالصورة: أعد القراءة (↻)، أو أضفه بعد المتابعة في فاتورة الشراء بزر «إضافة منتج».',
              _cLow,
              Icons.playlist_remove_rounded),
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
                    onChanged: (_) => setState(() {}),
                  ),
                ),
            ]),
          ]),
        ),
        const SizedBox(height: 12),
        _totalsCard(r, sum, expected),
        const SizedBox(height: 12),
        // ملخص
        Wrap(spacing: 8, runSpacing: 8, children: [
          _pill(Icons.check_circle_rounded, 'مطابق $nOk', _cGood),
          if (nLearned > 0) _pill(Icons.psychology_rounded, 'منها من التعلّم $nLearned', _cLearned),
          _pill(Icons.help_rounded, 'راجِع $nCheck', nCheck > 0 ? _cMid : _muted),
          _pill(Icons.fiber_new_rounded, 'جديدة $nNew', nNew > 0 ? _cNew : _muted),
          if (nExp > 0) _pill(Icons.event_available_rounded, 'بصلاحية $nExp', _cLearned),
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

  /// 💰 مبلغ الفاتورة كبيراً، مع مجموع الأسطر والمدفوع والباقي.
  Widget _totalsCard(AiInvoiceResult r, double sum, double expected) {
    final total = expected > 0 ? expected : sum;
    final paid = _cash ? total : _Row._parse(_paidCtl.text).clamp(0, total).toDouble();
    final rest = (total - paid).clamp(0, double.infinity).toDouble();
    final match = expected <= 0 || (sum - expected).abs() <= (expected * 0.005 > 1 ? expected * 0.005 : 1);
    final cur = _currency == 'USD' ? 'دولار' : 'دينار';
    Widget metric(String label, String value, Color c, {IconData? icon, String? hint}) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: c.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                if (icon != null) ...[Icon(icon, size: 15, color: c), const SizedBox(width: 4)],
                Flexible(child: Text(label, style: const TextStyle(fontSize: 12, color: _muted), overflow: TextOverflow.ellipsis)),
              ]),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: c)),
              ),
              if (hint != null)
                Text(hint, style: const TextStyle(fontSize: 11, color: _muted), maxLines: 2, overflow: TextOverflow.ellipsis),
            ]),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _aiA.withValues(alpha: 0.25)),
        boxShadow: [BoxShadow(color: _aiA.withValues(alpha: 0.08), blurRadius: 22, offset: const Offset(0, 8))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(gradient: const LinearGradient(colors: [_aiA, _aiB]), borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.receipt_long_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(expected > 0 ? 'مبلغ الفاتورة (كما في فاتورة المورد)' : 'مبلغ الفاتورة (مجموع الأسطر)',
                  style: const TextStyle(fontSize: 12.5, color: _muted)),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: _fmt.format(total), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: _ink, letterSpacing: 0.3)),
                  TextSpan(text: '  $cur', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _muted)),
                ])),
              ),
            ]),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: (_cash ? _cGood : _cNew).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(_cash ? 'نقد' : (paid > 0 ? 'دين — مدفوع جزء' : 'دين'),
                style: TextStyle(fontWeight: FontWeight.w800, color: _cash ? _cGood : _cNew)),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          metric('مجموع الأسطر', _fmt.format(sum), match ? _cGood : _cMid,
              icon: match ? Icons.check_circle_rounded : Icons.error_outline_rounded,
              hint: match ? 'يطابق الإجمالي' : 'يختلف عن الإجمالي'),
          const SizedBox(width: 8),
          metric('المدفوع', _fmt.format(paid), _cGood,
              icon: Icons.payments_rounded, hint: r.paymentEvidence.isEmpty ? null : 'من الفاتورة: ${r.paymentEvidence}'),
          const SizedBox(width: 8),
          metric('الباقي ديناً', _fmt.format(rest), rest > 0 ? _cNew : _muted, icon: Icons.account_balance_wallet_rounded),
        ]),
        if (r.previousBalance > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('رصيد المورد السابق المكتوب في الفاتورة: ${_fmt.format(r.previousBalance)} — للعلم فقط، لا يدخل هذه الفاتورة.',
                style: const TextStyle(fontSize: 12, color: _muted)),
          ),
      ]),
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
                      // رقم السطر كما في جدول الفاتورة (للمقارنة بالورقة)، وإلا ترتيبه هنا
                      child: Text('${l.rowNo ?? i + 1}', style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 12)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('«${l.originalName}»',
                          maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted, fontSize: 12.5)),
                    ),
                    if (l.isFree) ...[
                      _pill(Icons.card_giftcard_rounded, l.repGift ? 'هدية مندوب' : 'بونص', l.repGift ? _cManual : _cLearned),
                      const SizedBox(width: 6),
                    ],
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
                                  ? 'مادة جديدة — تُعرَّف تلقائياً عند حفظ فاتورة الشراء بالوحدة والتعبئة والسعر هنا، أو اضغط لاختيار مادة'
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
                      message: 'كم ${_baseLabel(row, prod)} في «${row.unit}»',
                      child: _numField('التعبئة', row.factor, 90),
                    ),
                    _numField('السعر', row.price, 120),
                    _expiryField(row),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(12)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        const Text('الإجمالي', style: TextStyle(fontSize: 11, color: _muted)),
                        Text(_fmt.format(row.total), style: const TextStyle(fontWeight: FontWeight.w800, color: _ink)),
                      ]),
                    ),
                    if (row.f > 1 && row.pr > 0)
                      Text('= ${_fmt.format(row.pr / row.f)} لكل ${_baseLabel(row, prod)}',
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

  /// 📅 الصلاحية: من الفاتورة إن وُجدت، وإلا فارغة — تُكتب أو تُمسح هنا.
  Widget _expiryField(_Row row) {
    final d = DateTime.tryParse(row.expiry ?? '');
    final now = DateTime.now();
    final expired = d != null && d.isBefore(DateTime(now.year, now.month, now.day));
    final soon = d != null && !expired && d.difference(now).inDays < 180;
    final color = d == null ? _muted : (expired ? _cLow : (soon ? _cMid : _ink));
    String two(int x) => x.toString().padLeft(2, '0');
    return SizedBox(
      width: 160,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: d ?? DateTime(now.year + 1, now.month, 1),
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
            helpText: 'تاريخ انتهاء الصلاحية',
          );
          if (picked != null && mounted) {
            setState(() => row.expiry = '${picked.year}-${two(picked.month)}-${two(picked.day)}');
          }
        },
        child: InputDecorator(
          decoration: _dec('الصلاحية', null, dense: true).copyWith(
            suffixIcon: d == null
                ? const Icon(Icons.event_rounded, size: 18, color: _muted)
                : IconButton(
                    tooltip: 'بلا صلاحية',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close_rounded, size: 17),
                    onPressed: () => setState(() => row.expiry = null),
                  ),
          ),
          child: Text(
            d == null ? '—' : '${expired ? 'منتهية ' : ''}${d.year}/${two(d.month)}/${two(d.day)}',
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
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
