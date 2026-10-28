// screens/edit_invoices_screen.dart
// screens/edit_invoices_screen.dart
import '../erp/sales/sales_return_screen.dart';
import '../erp/sales/sales_return_service.dart' show SalesReturnService;
import '../services/auth_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb; // 🌐
import 'package:flutter/material.dart';
import '../models/invoice.dart';
import 'create_invoice_screen.dart';
import 'package:intl/intl.dart' hide TextDirection; // NumberFormat (TextDirection من Flutter)
import '../services/database_service.dart'; // Added for DatabaseService
import '../models/invoice_adjustment.dart'; // Added for InvoiceAdjustment model
import 'package:share_plus/share_plus.dart';
import 'package:printing/printing.dart'; // 🌐 مشاركة وطباعة الويب
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/services.dart' show rootBundle;
import 'dart:io';
import '../services/invoice_pdf_service.dart';
import 'package:alnaser/services/settings_manager.dart';
import 'package:alnaser/models/app_settings.dart';
import 'dart:async'; // Added for Timer
import '../widgets/app_side_nav.dart';
import '../accounting/screens/acc_ui.dart' show accAppBar;

class EditInvoicesScreen extends StatefulWidget {
  const EditInvoicesScreen({super.key});

  @override
  State<EditInvoicesScreen> createState() => _EditInvoicesScreenState();
}

class _EditInvoicesScreenState extends State<EditInvoicesScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _idController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _searchName = '';
  String _searchId = '';
  final List<Invoice> _invoices = [];
  bool _loading = true;
  bool _isFetchingMore = false;
  bool _hasMoreData = true;
  int _currentPage = 0;
  final int _pageSize = 50;
  Timer? _debounce;
  final Map<int, List<InvoiceAdjustment>> _invoiceAdjustments = {};
  final Map<int, double> _settlementTotals = {}; // إجمالي التسويات لكل فاتورة
  AppSettings? _appSettings;
  String? _statusFilter; // محفوظة | معلقة
  String? _paymentFilter; // نقد | دين

  @override
  void initState() {
    super.initState();
    _fetchInvoices(refresh: true);
    _loadSettings();
    _nameController.addListener(_onSearchChanged);
    _idController.addListener(_onSearchChanged);
    _scrollController.addListener(_onScroll);
  }

  Future<void> _loadSettings() async {
    final settings = await SettingsManager.getAppSettings();
    if (mounted) setState(() => _appSettings = settings);
  }

  void _onSearchChanged() {
    setState(() {}); // زر المسح داخل الحقل
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _searchName = _nameController.text.trim();
      _searchId = _idController.text.trim();
      _fetchInvoices(refresh: true);
    });
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      _fetchInvoices();
    }
  }

  Future<void> _fetchInvoices({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _loading = true;
        _currentPage = 0;
        _hasMoreData = true;
        _invoices.clear();
        _invoiceAdjustments.clear();
        _settlementTotals.clear();
      });
    } else {
      if (_isFetchingMore || !_hasMoreData) return;
      setState(() => _isFetchingMore = true);
    }
    
    final db = DatabaseService();
    try {
      final newInvoices = await db.getInvoicesPaginated(
        limit: _pageSize,
        offset: _currentPage * _pageSize,
        searchName: _searchName,
        searchId: _searchId,
        status: _statusFilter,
        paymentType: _paymentFilter,
      );
      
      if (newInvoices.isEmpty) {
        setState(() {
          _hasMoreData = false;
          _loading = false;
          _isFetchingMore = false;
        });
        return;
      }
      
      final newInvoiceIds = newInvoices.map((e) => e.id!).toList();
      final adjustmentsMap = await db.getInvoiceAdjustmentsMapForIds(newInvoiceIds);
      
      Map<int, List<InvoiceAdjustment>> adjustments = {};
      Map<int, double> totals = {};
      
      for (final invoice in newInvoices) {
        final invoiceAdjustments = adjustmentsMap[invoice.id!] ?? [];
        adjustments[invoice.id!] = invoiceAdjustments;
        
        double total = 0.0;
        for (final adj in invoiceAdjustments) {
          total += adj.amountDelta;
        }
        totals[invoice.id!] = total;
      }
      
      setState(() {
        _currentPage++;
        _invoices.addAll(newInvoices);
        _invoiceAdjustments.addAll(adjustments);
        _settlementTotals.addAll(totals);
        if (newInvoices.length < _pageSize) {
          _hasMoreData = false;
        }
      });
    } catch (e) {
      debugPrint("Error fetching paginated invoices: $e");
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _isFetchingMore = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _nameController.removeListener(_onSearchChanged);
    _idController.removeListener(_onSearchChanged);
    _scrollController.removeListener(_onScroll);
    _nameController.dispose();
    _idController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ═══════════════════════════ الواجهة ═══════════════════════════

  static const _navy = Color(0xFF0F3460);
  static const _bg = Color(0xFFF3F6FB);
  static const _border = Color(0xFFE3E9F1);
  static const _text = Color(0xFF1E293B);
  static const _muted = Color(0xFF64748B);
  static const _green = Color(0xFF047857);
  static const _orange = Color(0xFFC2410C);
  static const _teal = Color(0xFF0F766E);
  static const _blue = Color(0xFF1D4ED8);

  String formatCurrency(num value) => NumberFormat('#,##0', 'en_US').format(value);

  void _setFilter({String? status, String? payment}) {
    setState(() {
      _statusFilter = status;
      _paymentFilter = payment;
    });
    _fetchInvoices(refresh: true);
  }

  Future<void> _openInvoice(Invoice invoice) async {
    // 🛡️ اقرأ الفاتورة من قاعدة البيانات قبل فتحها: كائن القائمة قد يكون قديماً.
    Invoice freshInvoice = invoice;
    try {
      if (invoice.id != null) {
        final loaded = await DatabaseService().getInvoiceById(invoice.id!);
        if (loaded != null) freshInvoice = loaded;
      }
    } catch (e) {
      debugPrint('تعذّر تحديث الفاتورة قبل الفتح: $e');
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreateInvoiceScreen(
          existingInvoice: freshInvoice,
          // المحفوظة أو المستوردة للعرض فقط
          isViewOnly: freshInvoice.status == 'محفوظة' || !freshInvoice.isCreatedByMe,
        ),
      ),
    );
    if (mounted) _fetchInvoices(refresh: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: accAppBar(
        'تعديل الفواتير',
        icon: Icons.edit_note_rounded,
        subtitle: 'ابحث عن فاتورة لعرضها أو تعديلها أو إرجاع مواد منها',
        actions: [
          IconButton(
            tooltip: 'تحديث',
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: () => _fetchInvoices(refresh: true),
          ),
        ],
      ),
      body: Row(children: [
        if (_appSettings != null && AppSideNav.shouldShow(context, _appSettings!))
          const AppSideNav(currentRoute: '/edit_invoices'),
        Expanded(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Column(children: [
                Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 6), child: _searchBar()),
                Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 6), child: _filters()),
                Expanded(child: _list()),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  InputDecoration _field(String label, IconData icon) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: _navy),
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _border)),
        focusedBorder:
            OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _navy, width: 1.6)),
      );

  Widget _searchBar() {
    final name = TextField(
      controller: _nameController,
      decoration: _field('اسم العميل (كلمة أو أكثر)', Icons.person_search_rounded).copyWith(
        suffixIcon: _nameController.text.isEmpty
            ? null
            : IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => _nameController.clear()),
      ),
    );
    final number = TextField(
      controller: _idController,
      decoration: _field('رقم الفاتورة المطبوع', Icons.confirmation_number_outlined).copyWith(
        suffixIcon: _idController.text.isEmpty
            ? null
            : IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => _idController.clear()),
      ),
      keyboardType: TextInputType.number,
    );
    return LayoutBuilder(
      builder: (context, c) => c.maxWidth < 620
          ? Column(children: [name, const SizedBox(height: 10), number])
          : Row(children: [Expanded(flex: 3, child: name), const SizedBox(width: 12), Expanded(flex: 2, child: number)]),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap, {Color color = _navy, IconData? icon}) => Padding(
        padding: const EdgeInsetsDirectional.only(end: 6),
        child: ChoiceChip(
          avatar: icon == null ? null : Icon(icon, size: 16, color: selected ? Colors.white : color),
          label: Text(label),
          selected: selected,
          showCheckmark: false,
          selectedColor: color,
          backgroundColor: Colors.white,
          side: BorderSide(color: selected ? color : _border),
          labelStyle: TextStyle(color: selected ? Colors.white : _text, fontWeight: FontWeight.w700),
          onSelected: (_) => onTap(),
        ),
      );

  Widget _filters() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        _chip('الكل', _statusFilter == null && _paymentFilter == null, () => _setFilter()),
        _chip('محفوظة', _statusFilter == 'محفوظة', () => _setFilter(status: 'محفوظة', payment: _paymentFilter),
            color: _green, icon: Icons.check_circle_outline_rounded),
        _chip('معلّقة', _statusFilter == 'معلقة', () => _setFilter(status: 'معلقة', payment: _paymentFilter),
            color: _orange, icon: Icons.pause_circle_outline_rounded),
        const SizedBox(width: 10),
        _chip('نقد', _paymentFilter == 'نقد', () => _setFilter(status: _statusFilter, payment: _paymentFilter == 'نقد' ? null : 'نقد'),
            color: _teal, icon: Icons.payments_outlined),
        _chip('آجل', _paymentFilter == 'دين', () => _setFilter(status: _statusFilter, payment: _paymentFilter == 'دين' ? null : 'دين'),
            color: _orange, icon: Icons.schedule_rounded),
        const SizedBox(width: 12),
        if (!_loading) Text('${_invoices.length}${_hasMoreData ? '+' : ''} فاتورة', style: const TextStyle(color: _muted)),
      ]),
    );
  }

  Widget _list() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: _navy));
    if (_invoices.isEmpty) {
      final searching = _searchName.isNotEmpty || _searchId.isNotEmpty || _statusFilter != null || _paymentFilter != null;
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(searching ? Icons.search_off_rounded : Icons.receipt_long_outlined, size: 56, color: _border),
          const SizedBox(height: 10),
          Text(searching ? 'لا فواتير مطابقة' : 'لا فواتير بعد',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _text)),
          if (searching)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('جرّب جزءاً من الاسم أو من رقم الفاتورة، أو أزل التصفية.', style: TextStyle(color: _muted)),
            ),
        ]),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 30),
      itemCount: _invoices.length + (_isFetchingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _invoices.length) {
          return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(color: _navy)));
        }
        return _invoiceCard(_invoices[index]);
      },
    );
  }

  String? _returnBlock(Invoice invoice) => SalesReturnService.returnBlockReasonFor(
        createdByMe: invoice.isCreatedByMe,
        creatorUsername: invoice.createdByUsername,
        currentUsername: AuthService().currentUser?.username,
      );

  Widget _pill(String text, Color c, {IconData? icon}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 13, color: c), const SizedBox(width: 4)],
          Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: c)),
        ]),
      );

  Widget _invoiceCard(Invoice invoice) {
    final pending = invoice.status == 'معلقة';
    final cash = invoice.paymentType == 'نقد';
    final statusColor = pending ? _orange : _green;
    final adjs = _invoiceAdjustments[invoice.id] ?? const <InvoiceAdjustment>[];
    final adjTotal = _settlementTotals[invoice.id] ?? 0.0;
    final paid = cash ? invoice.totalAmount : invoice.amountPaidOnInvoice;
    final remaining = cash ? 0.0 : (invoice.totalAmount - invoice.amountPaidOnInvoice);
    final time = '${invoice.invoiceDate.hour.toString().padLeft(2, '0')}:${invoice.invoiceDate.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: _border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openInvoice(invoice),
          child: Container(
            decoration: BoxDecoration(border: BorderDirectional(start: BorderSide(color: statusColor, width: 4))),
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text('فاتورة ${invoice.formattedInvoiceNumber}',
                        textDirection: TextDirection.rtl,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _navy)),
                    _pill(pending ? 'معلّقة' : 'محفوظة', statusColor,
                        icon: pending ? Icons.pause_circle_outline_rounded : Icons.check_circle_outline_rounded),
                    _pill(cash ? 'نقد' : 'آجل', cash ? _teal : _orange),
                    if (!invoice.isCreatedByMe) _pill('مستوردة', _blue, icon: Icons.cloud_download_outlined),
                    if (adjs.isNotEmpty)
                      _pill('عُدّلت ${adjs.length} مرة (${adjTotal >= 0 ? '+' : '−'}${formatCurrency(adjTotal.abs())})', _blue,
                          icon: Icons.edit_note_rounded),
                  ]),
                  const SizedBox(height: 6),
                  Text(invoice.customerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _text)),
                  const SizedBox(height: 2),
                  Text(
                    [
                      '${invoice.formattedInvoiceDate}  $time',
                      if (invoice.discount > 0) 'خصم ${formatCurrency(invoice.discount)}',
                      if (invoice.loadingFee > 0) 'تحميل ${formatCurrency(invoice.loadingFee)}',
                      if (invoice.returnAmount > 0) 'راجع ${formatCurrency(invoice.returnAmount)}',
                    ].join(' • '),
                    style: const TextStyle(fontSize: 12.5, color: _muted),
                  ),
                  if (invoice.notes != null && invoice.notes!.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('📝 ${invoice.notes!.trim()}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5, color: Color(0xFF92400E))),
                    ),
                ]),
              ),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(formatCurrency(invoice.totalAmount),
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: _text)),
                const Text('المجموع', style: TextStyle(fontSize: 11, color: _muted)),
                if (!cash) ...[
                  const SizedBox(height: 4),
                  Text(remaining > 0.5 ? 'المتبقي ${formatCurrency(remaining)}' : 'مدفوعة كاملة',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: remaining > 0.5 ? _orange : _green)),
                  if (paid > 0.5 && remaining > 0.5)
                    Text('دُفع ${formatCurrency(paid)}', style: const TextStyle(fontSize: 11.5, color: _muted)),
                ],
              ]),
              const SizedBox(width: 4),
              Column(children: [
                IconButton(
                  tooltip: 'مشاركة الفاتورة PDF',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.share_rounded, color: _muted),
                  onPressed: () => _shareInvoicePdf(invoice),
                ),
                // ↩️ مرتجع من هذه الفاتورة (مستند مستقل، موادها فقط).
                // 🔒 فاتورة المزامنة: من جهازها أو بحساب محاسبها فقط.
                if (!pending && invoice.id != null && _returnBlock(invoice) != null)
                  IconButton(
                    tooltip: _returnBlock(invoice)!,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.lock_outline_rounded, color: _muted),
                    onPressed: () => ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(_returnBlock(invoice)!), duration: const Duration(seconds: 5))),
                  )
                else if (!pending && invoice.id != null)
                  IconButton(
                    tooltip: 'مرتجع من هذه الفاتورة',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.assignment_return_outlined, color: _orange),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => SalesReturnScreen(invoiceId: invoice.id)),
                    ).then((_) => _fetchInvoices(refresh: true)),
                  ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _shareInvoicePdf(Invoice invoice) async {
    try {
      final db = DatabaseService();
      final items = await db.getInvoiceItems(invoice.id!);
      final products = await db.getAllProducts();

      // تحميل الخطوط والشعار
      final fontData = await rootBundle.load('assets/fonts/Amiri-Regular.ttf');
      final alnaserFontData = await rootBundle.load('assets/fonts/PTBLDHAD.TTF');
      final logoBytes = await rootBundle.load('assets/icon/alnasser.jpg');
      final font = pw.Font.ttf(fontData);
      final alnaserFont = pw.Font.ttf(alnaserFontData);
      final logoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());

      // تحميل الإعدادات العامة
      final appSettings = await SettingsManager.getAppSettings();

      // نفس حساب الطباعة الجماعية: كان التحميل = المجموع − البنود (يدخل فيه الخصم
      // والتسويات)، ثم يُطرح الخصم مرة ثانية من «بعد الخصم» و«المتبقي».
      final double itemsTotal =
          items.fold(0.0, (sum, item) => sum + item.itemTotal);
      final double loadingFee = invoice.loadingFee;
      final double afterDiscount = (itemsTotal + loadingFee) - invoice.discount;
      final double remaining = invoice.paymentType == 'نقد' ? 0.0 : afterDiscount - invoice.amountPaidOnInvoice;

      final doc = await InvoicePdfService.generateInvoicePdf(
        invoiceItems: items,
        allProducts: products,
        customerName: invoice.customerName,
        customerAddress: invoice.customerAddress ?? '',
        customerPhone: invoice.customerPhone,
        invoiceId: invoice.id ?? 0,
        selectedDate: invoice.invoiceDate,
        discount: invoice.discount,
        loadingFee: loadingFee,
        paid: invoice.amountPaidOnInvoice,
        paymentType: invoice.paymentType,
        invoiceToManage: invoice,
        previousDebt: 0,
        currentDebt: 0,
        afterDiscount: afterDiscount,
        remaining: remaining,
        font: font,
        alnaserFont: alnaserFont,
        logoImage: logoImage,
        createdAt: invoice.createdAt,
        appSettings: appSettings,
      );

      // حفظ الملف
      final safeCustomerName = invoice.customerName.replaceAll(RegExp(r'[^\w\u0600-\u06FF]+'), '_');
      final formattedDate = DateFormat('yyyy-MM-dd').format(invoice.invoiceDate);
      final fileName = '${safeCustomerName}_$formattedDate.pdf';

      // 🌐 الويب: مشاركة وتنزيل PDF مباشرة عبر المتصفح دون مجلدات مؤقتة
      if (kIsWeb) {
        final bytes = await doc.save();
        await Printing.sharePdf(
          bytes: bytes,
          filename: fileName,
        );
        return;
      }

      final directory = Directory('${Platform.environment['USERPROFILE']}/Documents/invoices');
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      final filePath = '${directory.path}/$fileName';
      final file = File(filePath);
      await file.writeAsBytes(await doc.save());

      await Share.shareXFiles([XFile(file.path)], text: 'فاتورة ${invoice.customerName}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل مشاركة الفاتورة: $e')),
        );
      }
    }
  }

}
