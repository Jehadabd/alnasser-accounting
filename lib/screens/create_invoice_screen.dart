// screens/create_invoice_screen.dart
// screens/create_invoice_screen.dart
import 'package:flutter/foundation.dart' show kIsWeb; // 🌐 حراسة الويب
import 'package:flutter/material.dart';
import '../models/product.dart';
import '../services/database_service.dart';
import '../services/database/business/customer_name_rule.dart'; // 📞 هاتف العميل من بطاقته
import '../services/database/business/invoice_customer_claim.dart';
import '../models/invoice_item.dart';
import '../models/invoice.dart';

import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:flutter/services.dart';
import '../models/transaction.dart';
import '../models/customer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alnaser/models/printer_device.dart';
import 'package:alnaser/services/printing_service.dart';
import 'dart:io';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:share_plus/share_plus.dart';
import 'package:path/path.dart' as p;
import 'package:alnaser/services/settings_manager.dart';
import 'package:alnaser/models/app_settings.dart';
import '../widgets/app_side_nav.dart';
import 'package:path_provider/path_provider.dart' as pp;
import '../services/invoice_pdf_service.dart';
import '../services/smart_pricing_service.dart';
import '../widgets/formatters.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:alnaser/providers/app_provider.dart';
import 'package:alnaser/services/printing_service_factory.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import '../models/invoice_adjustment.dart';
// removed duplicate imports
import 'invoice_actions.dart';
import 'invoice_history_screen.dart';
import '../utils/money_calculator.dart'; // Added for profit calculation fix
import '../services/smart_search/smart_search.dart'; // 🧠 البحث الذكي
import '../services/product_codes.dart'; // 🏷️ رمز المادة والباركود
import '../services/keyboard_layout/keyboard_layout.dart'; // ⌨️
import '../services/auth_service.dart'; // 👤 User authentication
import '../models/app_user.dart' show AppPermissions;
import '../services/logo_service.dart'; // 🖼️ Custom logo loading
import '../utils/number_formatter.dart'; // 🔢 Number formatting
import '../erp/erp_common.dart' show PeriodLock, askNumber;
import '../erp/sales/invoice_side_panel.dart';
import '../models/invoice_entry_layout.dart'; // 🧩 أعمدة الجدول وعرضها
import 'invoice_entry_layout_screen.dart';
import '../widgets/line_discount_dialog.dart';
import '../widgets/profit_discount_dialog.dart'; // ٪
import '../services/debt_reminders.dart'; // 📅
import '../widgets/debt_reminder_editor.dart';
import '../owner/owner_access.dart';
import '../services/held_invoices.dart'; // ⏸️
import '../owner/cost_stamp.dart';
import '../owner/founder_service.dart';
import '../services/seat_service.dart';
import '../owner/founder_invoice_chip.dart'; // 🏷️ خصم السطر
import '../services/personal_pricing_service.dart'; // 👤 تسعير شخصي 101–103
import '../services/invoice_staff_service.dart'; // 👷 المجهز والمحاسب

// Helper: format product ID - show raw value without zero-padding
String formatProductId5(int? id) {
  if (id == null) return '';
  return id.toString();
}

// تعريف EditableInvoiceItemRow موجود هنا (أو تأكد من وجوده قبل استخدامه في ListView)
// إذا كان التعريف موجود بالفعل، لا داعي لأي تعديل إضافي هنا.
// إذا لم يكن موجودًا، أضف الكود الذي تم إنشاؤه في الخطوة السابقة هنا.

class CreateInvoiceScreen extends StatefulWidget {
  final Invoice? existingInvoice;
  final bool isViewOnly;
  final DebtTransaction? relatedDebtTransaction;
  // إذا كانت غير null فهذا يعني فتح الشاشة بوضع تسوية لفاتورة محفوظة
  final Invoice? settlementForInvoice;

  const CreateInvoiceScreen({
    super.key,
    this.existingInvoice,
    this.isViewOnly = false,
    this.relatedDebtTransaction,
    this.settlementForInvoice,
  });

  @override
  State<CreateInvoiceScreen> createState() => _CreateInvoiceScreenState();
}

class _CreateInvoiceScreenState extends State<CreateInvoiceScreen> with InvoiceActionsMixin {
  @override
  final formKey = GlobalKey<FormState>();
  @override
  final customerNameController = TextEditingController();
  @override
  final customerPhoneController = TextEditingController();
  @override
  final customerAddressController = TextEditingController();
  // 👷 المجهز والمحاسب (من «المزيد»)
  @override
  final preparerController = TextEditingController();
  @override
  final accountantController = TextEditingController();
  @override
  final installerNameController = TextEditingController();

  /// 👷 نقاط المؤسس لكل 100,000 لهذه الفاتورة (حساب المالك)
  @override
  double founderPointsRate = FounderService.defaultRateFallback;

  Future<void> _loadFounderDefaultRate() async {
    final v = await FounderService.defaultRate();
    if (mounted) setState(() => founderPointsRate = v);
  }

  double _founderInvoiceTotal() =>
      double.tryParse(_totalAmountController.text.replaceAll(',', '')) ?? 0.0;

  AppSettings? _appSettings;

  
  final _productSearchController = TextEditingController();
  final _quantityController = TextEditingController();
  final FocusNode _quantityFocusNode = FocusNode(); // FocusNode لحقل الكمية
  final _itemsController = TextEditingController();
  final _totalAmountController = TextEditingController();
  @override
  DateTime selectedDate = DateTime.now();
  @override
  String paymentType = 'نقد';
  @override
  final paidAmountController = TextEditingController();
  @override
  double discount = 0.0;
  final discountController = TextEditingController();

  // 🔧 متغيرات اختيار الوحدة في شريط الإدخال
  List<String> currentUnitOptions = ['قطعة'];
  String selectedUnitForItem = 'قطعة';
  List<Map<String, dynamic>> _currentUnitHierarchy = [];

  final _priceController = TextEditingController();
  // 🏷️ خصم الصنف في شريط الإدخال: قيمة + نوع (نسبة/مبلغ) + هدية
  final _entryDiscountController = TextEditingController();
  bool _entryDiscountPercent = true;
  bool _entryGift = false;
  final _priceFocusNode = FocusNode(); // 🔧 FocusNode لحقل السعر
  final GlobalKey _entryBarUnitDropdownKey = GlobalKey(); // 🔧 مفتاح لقائمة الوحدات في شريط البحث



  @override
  String formatNumber(num value, {bool forceDecimal = false}) {
    if (value == 0 && !forceDecimal) return '0';
    return NumberFormatter.format(value, forceDecimal: forceDecimal);
  }
  
  double _adHocProfitPercentage = 10.0;
  bool _allowNegativeStock = false;
  bool _isEntryLocked = false; // 🔒 قفل حقول الإدخال عند نفاد المخزون
  
  Future<void> _loadProfitSettings() async {
    try {
      final settings = await SettingsManager.getAppSettings();
      if (mounted) {
        setState(() {
          _appSettings = settings;
          _adHocProfitPercentage = settings.defaultAdHocProfitPercentage;
          _allowNegativeStock = settings.allowNegativeStock;
        });
        // Recalculate profit with new percentage
        _calculateProfit();
      }
    } catch (e) {
      debugPrint('Error loading profit settings: $e');
    }
  }
  


  // kept unused helper removed; global formatProductId5 is used instead

  List<Product> _searchResults = [];
  Product? _selectedProduct;
  @override
  List<InvoiceItem> invoiceItems = [];

  @override
  final DatabaseService db = DatabaseService();
  final TextEditingController _productIdController = TextEditingController();
  @override
  PrinterDevice? selectedPrinter;
  @override
  late final PrintingService printingService;
  @override
  Invoice? invoiceToManage;

  // إضافة متغيرات للحفظ التلقائي
  @override
  final storage = const FlutterSecureStorage();
  @override
  bool savedOrSuspended = false;
  Timer? debounceTimer;
  Timer? liveDebtTimer;
  Timer? _invoiceLockHeartbeat;
  // 🔒 حجز اسم العميل بين الأجهزة (فاتورة قيد الإنشاء/التعديل)
  late final InvoiceCustomerClaim _custClaim = InvoiceCustomerClaim(db.lockingService);
  Timer? _custClaimDebounce;
  bool _custClaimDialogOpen = false;
  
  // متغير لتتبع التغييرات غير المحفوظة
  @override
  bool hasUnsavedChanges = false;
  
  // متغير لمنع الحفظ المزدوج
  @override
  bool isSaving = false;

  // Profit Display State
  final bool _isProfitVisible = false;

  // 👑 Ctrl+D (حساب المالك): ضغط مستمر = إظهار عمود الكلفة وتاريخ آخر تحديث لها، رفع = إخفاء
  bool _ownerCostPeek = false;
  Map<int, DateTime>? _costDates;

  /// شريط ربح الفاتورة (يظهر ما دام Ctrl+D مضغوطاً، لحساب المالك فقط).
  /// الربح = (سعر البيع − الكلفة) لكل سطر مكتمل − الخصم، والنسبة من صافي الفاتورة
  /// (المواد + أجور النقل − الخصم) — نفس حساب debt_book.
  Widget _ownerProfitStrip() {
    _calculateProfit();
    final items = invoiceItems.where(_isInvoiceItemComplete).fold<double>(0, (s, i) => s + i.itemTotal);
    final fee = double.tryParse(loadingFeeController.text.replaceAll(',', '')) ?? 0.0;
    final net = items + fee - discount;
    final pct = net > 0 ? _currentInvoiceProfit / net * 100 : 0.0;
    final good = _currentInvoiceProfit >= 0;
    final c = good ? const Color(0xFF067647) : const Color(0xFFB42318);
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        Icon(good ? Icons.trending_up_rounded : Icons.trending_down_rounded, color: c),
        const SizedBox(width: 8),
        Text(good ? 'ربح هذه الفاتورة' : 'خسارة هذه الفاتورة',
            style: TextStyle(fontWeight: FontWeight.w800, color: c, fontSize: 15)),
        const Spacer(),
        Text(formatNumber(_currentInvoiceProfit.abs()),
            textDirection: TextDirection.ltr,
            style: TextStyle(fontWeight: FontWeight.w900, color: c, fontSize: 18)),
        const SizedBox(width: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(20)),
          child: Text('${pct.toStringAsFixed(1)}%',
              textDirection: TextDirection.ltr,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        ),
      ]),
    );
  }

  bool _onOwnerCostPeekKey(KeyEvent event) {
    if (!mounted) return false;
    final isD = event.logicalKey == LogicalKeyboardKey.keyD || event.physicalKey == PhysicalKeyboardKey.keyD;
    final isCtrl = event.logicalKey == LogicalKeyboardKey.controlLeft || event.logicalKey == LogicalKeyboardKey.controlRight;
    if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
        isD &&
        HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isShiftPressed) {
      // شاشة أخرى فوق الفاتورة (مصمم الطباعة يستعمل Ctrl+D) أو ليس مالكاً ⇒ لا نتدخل
      if (!(ModalRoute.of(context)?.isCurrent ?? false) || !OwnerAccess.enabled) return false;
      if (!_ownerCostPeek) {
        setState(() => _ownerCostPeek = true);
        CostStamp.all().then((m) {
          if (mounted) setState(() => _costDates = m);
        });
      }
      return true;
    }
    if (_ownerCostPeek && event is KeyUpEvent && (isD || isCtrl)) {
      setState(() => _ownerCostPeek = false);
      return true;
    }
    return false;
  }
  
  // التمرير التلقائي
  final ScrollController _scrollController = ScrollController();
  final ScrollController _hScrollController = ScrollController(); // 🧩 تمرير أفقي لجدول المواد
  bool _sidePanelOpen = true; // 🧩 اللوحة الجانبية أو الشريط السفلي — يُختار من الإعدادات فقط
  bool _ensuringEmptyRow = false;

  /// بدون شريط الإدخال العلوي يُكتب في آخر سطر فارغ من الجدول (كما في الإداري)
  void _ensureTrailingEmptyRow() {
    if (isViewOnly || InvoiceEntryLayout.current.showEntryBar || _ensuringEmptyRow) return;
    if (invoiceItems.isNotEmpty && invoiceItems.last.productName.trim().isEmpty) return;
    _ensuringEmptyRow = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensuringEmptyRow = false;
      if (!mounted) return;
      // قد يكون Enter أضاف السطر الفارغ في الإطار نفسه ⇒ لا نضيف سطراً ثانياً
      if (invoiceItems.isNotEmpty && invoiceItems.last.productName.trim().isEmpty) return;
      setState(() {
        invoiceItems.add(InvoiceItem(
          invoiceId: 0,
          productName: '',
          unit: '',
          unitPrice: 0.0,
          appliedPrice: 0.0,
          itemTotal: 0.0,
          uniqueId: 'placeholder_${DateTime.now().microsecondsSinceEpoch}',
        ));
        focusNodesList.add(LineItemFocusNodes());
      });
    });
  }

  /// 🧭 Enter على آخر خانة في السطر ⇒ «اسم المادة» في السطر الذي يليه مباشرة.
  /// يُضاف سطر جديد فقط إذا كان هذا آخر سطر. (سابقاً كان يُضاف سطر في كل مرة،
  /// فيتخطّى المؤشر السطر الفارغ الذي يضيفه الجدول تلقائياً.)
  void _focusRowAfter(String uid) {
    final i = invoiceItems.indexWhere((it) => it.uniqueId == uid);
    if (i == -1) return;
    final next = i + 1;
    if (next >= invoiceItems.length) {
      setState(() {
        invoiceItems.add(InvoiceItem(
          invoiceId: 0,
          productName: '',
          unit: '',
          unitPrice: 0,
          appliedPrice: 0,
          itemTotal: 0,
          uniqueId: 'row_${DateTime.now().microsecondsSinceEpoch}',
        ));
      });
    }
    while (focusNodesList.length < invoiceItems.length) {
      focusNodesList.add(LineItemFocusNodes());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || next >= focusNodesList.length) return;
      focusNodesList[next].details.requestFocus();
    });
  }

  /// 🧩 الشريط السفلي (حين تُختار «شريط سفلي» من الإعدادات): مضغوط ليبقى للجدول
  /// أكبر مساحة. المجاميع الأربعة فوق بعض، الخصم وأجور النقل يُكتبان هنا مباشرة،
  /// نقد/دين والمبلغ الواصل، والصافي مع زر الحفظ. (الحساب نفسه في اللوحة الجانبية)
  /// 🏷️ خصم بنسبة من ربح الفاتورة: 10% من ربح 200,000 = خصم 20,000.
  /// الخصم لا يتجاوز الربح أبداً، فلا تُباع الفاتورة بخسارة من هذا الزر.
  Future<void> _askProfitDiscount() async {
    _calculateProfit();
    final profitBefore = _currentInvoiceProfit + discount; // الربح قبل أي خصم
    if (profitBefore <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('لا ربح في هذه الفاتورة يُخصم منه (أضف مواد بأسعار بيع أعلى من الكلفة)'),
      ));
      return;
    }
    final canSeeProfit = AuthService().hasPermission(AppPermissions.viewCostProfit);
    final apply = await showProfitDiscountDialog(
      context,
      profit: profitBefore,
      invoiceTotal: invoiceItems.fold(0.0, (s, it) => s + it.itemTotal),
      defaultPercent: _appSettings?.discountProfitPercent ?? 10.0,
      canSeeProfit: canSeeProfit,
      currentDiscount: discount,
    );
    if (apply == null || !mounted) return;
    setState(() {
      discount = apply;
      discountController.text = formatNumber(apply);
      _guardDiscount();
      _updatePaidAmountIfCash();
      _calculateProfit();
      hasUnsavedChanges = true;
    });
  }

  Widget _buildCompactTotalsBar() {
    final totalBeforeDiscount = invoiceItems.fold(0.0, (s, it) => s + it.itemTotal);
    final total = totalBeforeDiscount - discount;
    final loading = double.tryParse(loadingFeeController.text.replaceAll(',', '')) ?? 0.0;
    final adj = _invoiceAdjustments.isNotEmpty ? _totalSettlementAmount : 0.0;
    final net = total + loading + adj;
    final cashSettlements = _invoiceAdjustments
        .where((a) => (a.settlementPaymentType ?? 'نقد') == 'نقد')
        .fold(0.0, (s, a) => s + a.amountDelta);
    final entered = double.tryParse(paidAmountController.text.replaceAll(',', '')) ?? 0.0;
    final isCash = paymentType == 'نقد';
    final paid = isCash ? net : entered + cashSettlements;
    final rest = isCash ? 0.0 : net - paid;
    final canEdit = !isViewOnly;
    final feeEditable = !isViewOnly && !(invoiceToManage?.isLocked ?? false);
    const navy = Color(0xFF0F3460);
    const line = Color(0xFFE2E8F0);

    Widget card(Widget child) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: line),
          ),
          child: child,
        );

    Widget amount(String label, double v, Color c) => Expanded(
          child: Row(children: [
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, height: 1.15, fontWeight: FontWeight.w600, color: Colors.grey.shade800)),
            ),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerEnd,
                child: Text(formatNumber(v),
                    style: TextStyle(fontSize: 17, height: 1.15, fontWeight: FontWeight.w800, color: c)),
              ),
            ),
          ]),
        );

    Widget input(String label, IconData icon, TextEditingController c,
            {required bool enabled,
            required ValueChanged<String> onChanged,
            Widget? suffix,
            double height = 40,
            double fontSize = 16,
            VoidCallback? onLabelTap,
            String? labelTip}) {
      final labelText = Text(label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: onLabelTap != null ? const Color(0xFF1D4ED8) : Colors.grey.shade800,
            decoration: onLabelTap != null ? TextDecoration.underline : null,
            decorationStyle: TextDecorationStyle.dotted,
          ));
      return SizedBox(
          height: height,
          child: Row(children: [
            Icon(icon, size: 18, color: Colors.blueGrey.shade400),
            const SizedBox(width: 6),
            SizedBox(
              width: 76,
              child: onLabelTap == null
                  ? labelText
                  : Tooltip(
                      message: labelTip ?? '',
                      child: InkWell(onTap: onLabelTap, borderRadius: BorderRadius.circular(4), child: labelText),
                    ),
            ),
            Expanded(
              child: TextFormField(
                controller: c,
                enabled: enabled,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [ThousandSeparatorDecimalInputFormatter()],
                textAlign: TextAlign.left,
                style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w700),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: '0',
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  suffixIcon: suffix,
                  suffixIconConstraints: const BoxConstraints(minHeight: 30, minWidth: 0),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: line),
                  ),
                ),
                onChanged: onChanged,
              ),
            ),
          ]),
        );
    }

    Widget payBtn(String type, IconData icon, Color c) {
      final sel = paymentType == type;
      return Expanded(
        child: InkWell(
          onTap: !canEdit || sel
              ? null
              : () => setState(() {
                    paymentType = type;
                    if (type == 'نقد') {
                      _updatePaidAmountIfCash();
                    } else {
                      paidAmountController.text = formatNumber(0);
                    }
                    _autoSave();
                  }),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              // المختار: خلفية ممتلئة (نقد أخضر، دين أحمر)؛ غير المختار: لون خفيف من نفس اللون
              color: sel ? c : c.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: sel ? c : c.withValues(alpha: 0.35), width: sel ? 1.6 : 1),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 20, color: sel ? Colors.white : c),
              const SizedBox(width: 6),
              Text(type,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: sel ? Colors.white : c)),
            ]),
          ),
        ),
      );
    }

    // 1) المجاميع الأربعة فوق بعض
    final totalsCard = card(Column(children: [
      amount('الإجمالي قبل الخصم', totalBeforeDiscount, Colors.grey.shade800),
      amount('الإجمالي بعد الخصم', total, Colors.blue.shade700),
      amount('المبلغ المسدد', paid, Colors.green.shade700),
      amount('المبلغ المتبقي', rest, rest > 0 ? Colors.red.shade700 : Colors.green.shade700),
    ]));

    // 2) الخصم وأجور التحميل والنقل — تُكتب هنا مباشرة
    final inputsCard = card(Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      input('الخصم', Icons.local_offer_outlined, discountController,
          enabled: canEdit,
          onLabelTap: canEdit ? _askProfitDiscount : null,
          labelTip: 'اضغط: خصم بنسبة من ربح الفاتورة', onChanged: (val) {
        setState(() {
          discount = double.tryParse(val.replaceAll(',', '')) ?? 0.0;
          _guardDiscount();
          _updatePaidAmountIfCash();
          _calculateProfit();
        });
      }),
      const SizedBox(height: 4),
      input('أجور النقل', Icons.local_shipping_outlined, loadingFeeController, enabled: feeEditable, onChanged: (_) {
        setState(() {
          _guardDiscount();
          _updatePaidAmountIfCash();
          _calculateProfit();
        });
      }),
    ]));

    // 3) نقد / دين والمبلغ الواصل
    final payCard = card(Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Row(children: [
        payBtn('نقد', Icons.attach_money, const Color(0xFF15803D)),
        const SizedBox(width: 6),
        payBtn('دين', Icons.account_balance_wallet_outlined, const Color(0xFFDC2626)),
      ]),
      const SizedBox(height: 4),
      if (!isCash && canEdit)
        input('الواصل', Icons.payments_outlined, paidAmountController,
            enabled: true,
            height: 44,
            fontSize: 20,
            onChanged: (_) => setState(() {}),
            suffix: TextButton(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: const Size(0, 30),
              ),
              onPressed: () => setState(() => paidAmountController.text = formatNumber(net)),
              child: const Text('%100', style: TextStyle(fontSize: 12)),
            ))
      else
        SizedBox(
          height: 40,
          child: Center(
            child: Text(isCash ? 'نقداً — يُسدَّد كامل المبلغ' : 'دين',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
          ),
        ),
    ]));

    // 4) الصافي للدفع وزر الحفظ
    final saveCard = Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: BoxDecoration(color: navy, borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Text('الصافي للدفع', style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerEnd,
              child: Text('${formatNumber(net)} د.ع',
                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
            ),
          ),
        ]),
        const Spacer(),
        if (!isViewOnly)
          SizedBox(
            height: 44,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF48BB78),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: isSaving ? null : saveInvoice,
              icon: const Icon(Icons.save_alt, size: 19),
              label: const Text('حفظ الفاتورة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
      ]),
    );

    final cards = <Widget>[totalsCard, inputsCard, payCard, saveCard];
    const flexes = [4, 4, 4, 3];
    const widths = [280.0, 280.0, 270.0, 230.0];
    return Container(
      width: double.infinity,
      height: 132,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: LayoutBuilder(builder: (context, box) {
        if (box.maxWidth >= 880) {
          return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(flex: flexes[i], child: cards[i]),
            ],
          ]);
        }
        // شاشة أضيق: البطاقات بعرض ثابت مع تمرير أفقي
        return ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: cards.length,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (_, i) => SizedBox(width: widths[i], child: cards[i]),
        );
      }),
    );
  }

  // ═══════════════════════════ 🧩 «المزيد» ═══════════════════════════
  // ما لا تحتاجه أغلب الفواتير: الجوال والعنوان والطباعة بعد الحفظ.
  // (أجور النقل في لوحة المجاميع، وعرض الجدول من زر الأعمدة فوق الجدول)

  int get _invoiceExtrasCount =>
      (customerPhoneController.text.trim().isNotEmpty ? 1 : 0) +
      (customerAddressController.text.trim().isNotEmpty ? 1 : 0);

  Widget _buildHeaderInfoChip(IconData icon, String text) => Padding(
        padding: const EdgeInsetsDirectional.only(end: 6),
        child: InkWell(
          onTap: _openInvoiceMore,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 42,
            constraints: const BoxConstraints(maxWidth: 170),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 15, color: Colors.white60),
              const SizedBox(width: 5),
              Flexible(
                child: Text(text,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ]),
          ),
        ),
      );

  Widget _buildHeaderMoreButton() {
    final n = _invoiceExtrasCount;
    return Tooltip(
      message: 'الجوال والعنوان والطباعة بعد الحفظ',
      child: InkWell(
        onTap: _openInvoiceMore,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white24),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.tune, color: Colors.white, size: 18),
            const SizedBox(width: 6),
            const Text('المزيد', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
            if (n > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: const Color(0xFF00B4D8), borderRadius: BorderRadius.circular(10)),
                child: Text('$n', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  void _openInvoiceHistory() {
    final id = invoiceToManage?.id;
    if (id == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => InvoiceHistoryScreen(invoiceId: id, customerName: customerNameController.text),
      ),
    );
  }

  /// 🧩 تغيّر اختيار «لوحة جانبية / شريط سفلي» من الإعدادات ⇒ يُطبَّق فوراً
  void _onSidePanelPrefChanged() {
    final v = InvoiceSidePanelPref.notifier.value;
    if (mounted && v != _sidePanelOpen) setState(() => _sidePanelOpen = v);
  }

  Future<void> _openColumnsSettings() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const InvoiceEntryLayoutScreen()));
    await InvoiceEntryLayout.load();
    if (mounted) setState(() {});
  }

  Widget _buildMoreActionsMenu() {
    final hasItems = invoiceItems.isNotEmpty && !isSaving;
    PopupMenuItem<String> item(String value, IconData icon, String label, {bool enabled = true}) => PopupMenuItem<String>(
          value: value,
          enabled: enabled,
          height: 42,
          child: Row(children: [
            Icon(icon, size: 19, color: enabled ? const Color(0xFF334155) : Colors.grey),
            const SizedBox(width: 12),
            Text(label, style: TextStyle(fontSize: 14, color: enabled ? const Color(0xFF1E293B) : Colors.grey)),
          ]),
        );
    return PopupMenuButton<String>(
      tooltip: 'خيارات أخرى',
      icon: const Icon(Icons.more_vert),
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      itemBuilder: (_) => [
        item('extras', Icons.tune, 'تفاصيل إضافية (الجوال، العنوان)'),
        item('columns', Icons.view_column_outlined, 'أعمدة الجدول وعرضها…'),
        const PopupMenuDivider(),
        item('picking', Icons.print_disabled, 'طباعة تجهيز (بدون أسعار)', enabled: hasItems),
        item('share', Icons.share, 'مشاركة الفاتورة PDF', enabled: hasItems),
        if (invoiceToManage?.id != null) item('history', Icons.history, 'سجل التعديلات'),
      ],
      onSelected: (v) {
        switch (v) {
          case 'extras':
            _openInvoiceMore();
            break;
          case 'columns':
            _openColumnsSettings();
            break;
          case 'picking':
            _printPickingList();
            break;
          case 'share':
            shareInvoice();
            break;
          case 'history':
            _openInvoiceHistory();
            break;
        }
      },
    );
  }

  /// ⚙️ زر صغير في رأس الجدول: إظهار/إخفاء الأعمدة وارتفاع السطر فوراً.
  Widget _buildColumnsQuickButton() {
    final layout = InvoiceEntryLayout.current;
    final canSeeCost = AuthService().hasPermission(AppPermissions.viewCostProfit);
    final heights = <double, String>{30: 'سطر مضغوط', 34: 'سطر عادي', 42: 'سطر واسع'};
    return PopupMenuButton<String>(
      tooltip: 'أعمدة الجدول',
      icon: const Icon(Icons.view_column_outlined, size: 18, color: Color(0xFF475569)),
      padding: EdgeInsets.zero,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      itemBuilder: (_) => [
        const PopupMenuItem<String>(
          enabled: false,
          height: 30,
          child: Text('الأعمدة الظاهرة', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        ),
        for (final k in InvoiceEntryLayout.keys)
          if (!InvoiceEntryLayout.required.contains(k) && (canSeeCost || !InvoiceEntryLayout.costColumns.contains(k)))
            CheckedPopupMenuItem<String>(
              value: 'col:$k',
              checked: layout.show(k),
              height: 36,
              child: Text(InvoiceEntryLayout.labels[k]!),
            ),
        const PopupMenuDivider(),
        for (final e in heights.entries)
          CheckedPopupMenuItem<String>(
            value: 'h:${e.key}',
            checked: layout.rowHeight == e.key,
            height: 36,
            child: Text(e.value),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'settings',
          height: 38,
          child: Row(children: [Icon(Icons.tune, size: 18), SizedBox(width: 8), Text('عرض الأعمدة ومسار زر Enter…')]),
        ),
      ],
      onSelected: (v) async {
        final l = InvoiceEntryLayout.current;
        if (v.startsWith('col:')) {
          final k = v.substring(4);
          final hidden = {...l.hidden};
          if (!hidden.remove(k)) hidden.add(k);
          await l.copyWith(hidden: hidden).save();
        } else if (v.startsWith('h:')) {
          await l.copyWith(rowHeight: double.parse(v.substring(2))).save();
        } else if (v == 'settings') {
          await _openColumnsSettings();
        }
        if (mounted) setState(() {});
      },
    );
  }

  /// حقل موظف: يُكتب أو يُختار من الموظفين (أصحاب المسمى المطلوب أولاً)
  Widget _staffField(BuildContext ctx, StateSetter setD, TextEditingController c, String label, IconData icon,
      String title,
      {required bool enabled, required InputDecoration Function(String, IconData, {String? suffix}) dec}) {
    return Row(children: [
      Expanded(
        child: TextField(
          controller: c,
          enabled: enabled,
          decoration: dec(label, icon),
          onChanged: (_) => setD(() {}),
        ),
      ),
      const SizedBox(width: 6),
      PopupMenuButton<String>(
        enabled: enabled,
        tooltip: 'اختيار من الموظفين',
        icon: const Icon(Icons.people_alt_outlined, color: Color(0xFF0F3460)),
        itemBuilder: (_) {
          // أصحاب المسمى المطلوب أولاً، ثم بقية الموظفين
          final list = [..._staffCache]
            ..sort((a, b) => (b.title.contains(title) ? 1 : 0).compareTo(a.title.contains(title) ? 1 : 0));
          if (list.isEmpty) {
            return const [
              PopupMenuItem<String>(enabled: false, child: Text('لا موظفين — أضفهم من «الموظفون والصلاحيات»')),
            ];
          }
          return [
            for (final s in list)
              PopupMenuItem<String>(
                value: s.name,
                child: Row(children: [
                  Expanded(child: Text(s.name)),
                  if (s.title.isNotEmpty)
                    Container(
                      margin: const EdgeInsetsDirectional.only(start: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                      decoration: BoxDecoration(
                        color: (s.title.contains(title) ? const Color(0xFF7C3AED) : Colors.blueGrey).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(s.title,
                          style: TextStyle(
                              fontSize: 11.5,
                              color: s.title.contains(title) ? const Color(0xFF7C3AED) : Colors.blueGrey)),
                    ),
                ]),
              ),
          ];
        },
        onSelected: (v) => setD(() => c.text = v),
      ),
    ]);
  }

  List<({String name, String title})> _staffCache = const [];

  Future<void> _openInvoiceMore() async {
    // 👷 المحاسب الافتراضي: المستخدم الحالي
    if (accountantController.text.trim().isEmpty && !isViewOnly) {
      accountantController.text = AuthService().currentUser?.shownName ?? '';
    }
    final staffList = await InvoiceStaff.staff();
    _staffCache = staffList;
    if (!mounted) return;
    // أجور النقل في لوحة المجاميع، وعرض الجدول من زر الأعمدة فوق الجدول — لا تكرار هنا
    final editable = !isViewOnly;
    const border = Color(0xFFE2E8F0);
    InputDecoration dec(String label, IconData icon, {String? suffix}) => InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 19),
          suffixText: suffix,
          isDense: true,
          filled: true,
          fillColor: const Color(0xFFF6F8FB),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: border)),
          disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: border)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5)),
        );
    Widget section(String title, String hint, IconData icon, Color color, List<Widget> children) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: border),
          ),
          child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(9)),
                child: Icon(icon, size: 17, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5)),
                  Text(hint, style: TextStyle(fontSize: 11.5, color: Colors.blueGrey.shade400)),
                ]),
              ),
            ]),
            const SizedBox(height: 12),
            ...children,
          ]),
          ),
          ),
        );
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          insetPadding: const EdgeInsets.all(24),
          backgroundColor: const Color(0xFFF7F9FC),
          surfaceTintColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640, maxHeight: 680),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 14, 10, 14),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                  border: Border(bottom: BorderSide(color: border)),
                ),
                child: Row(children: [
                  const Icon(Icons.tune, color: Color(0xFF0F3460)),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('تفاصيل إضافية للفاتورة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      Text('أمور لا تحتاجها أغلب الفواتير', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ]),
                  ),
                  IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
                ]),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    section('بيانات العميل الإضافية', 'تظهر في الفاتورة المطبوعة وتُحفظ مع العميل',
                        Icons.person_outline, const Color(0xFF2563EB), [
                      TextField(
                        controller: customerPhoneController,
                        enabled: editable,
                        keyboardType: TextInputType.phone,
                        decoration: dec('رقم الجوال', Icons.phone_outlined),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: customerAddressController,
                        enabled: editable,
                        decoration: dec('العنوان', Icons.location_on_outlined),
                        onChanged: (_) => setState(() {}),
                      ),
                    ]),
                    section('المجهز والمحاسب', 'يُطبعان في الفاتورة (التصاميم الجاهزة) ويُحفظان معها',
                        Icons.engineering_outlined, const Color(0xFF7C3AED), [
                      _staffField(ctx, setD, preparerController, 'المجهز', Icons.inventory_2_outlined, 'مجهز',
                          enabled: editable, dec: dec),
                      const SizedBox(height: 10),
                      _staffField(ctx, setD, accountantController, 'المحاسب', Icons.calculate_outlined, 'محاسب',
                          enabled: editable, dec: dec),
                    ]),
                    // 📅 موعد المطالبة — لفواتير الدين فقط
                    if (paymentType == 'دين')
                      section('موعد المطالبة', 'تذكير بهذا الدين عند تشغيل البرنامج في أيام تختارها',
                          Icons.event_repeat_rounded, const Color(0xFF4F46E5), [_reminderMoreBody(ctx, setD)]),
                    section('بعد الحفظ', 'يُحفظ لهذا الجهاز', Icons.print_outlined, const Color(0xFF0F766E), [
                      FutureBuilder<SharedPreferences>(
                        future: SharedPreferences.getInstance(),
                        builder: (context, snap) {
                          final prefs = snap.data;
                          final on = prefs?.getBool('invoice_auto_print_after_save') ?? false;
                          return SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: const Text('طباعة الفاتورة تلقائياً بعد الحفظ'),
                            subtitle: const Text('بنوع الطباعة المختار في الإعدادات (A4 أو حرارية)'),
                            value: on,
                            onChanged: prefs == null
                                ? null
                                : (v) async {
                                    await prefs.setBool('invoice_auto_print_after_save', v);
                                    setD(() {});
                                  },
                          );
                        },
                      ),
                    ]),
                  ]),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(18)),
                  border: Border(top: BorderSide(color: border)),
                ),
                child: Row(children: [
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0F3460),
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('تم'),
                  ),
                ]),
              ),
            ]),
          ),
        );
      }),
    );
    if (mounted) setState(() {});
  }


  // ═══════════════ 📅 موعد المطالبة (من «المزيد») ═══════════════

  Widget _reminderMoreBody(BuildContext ctx, StateSetter setD) {
    final invId = invoiceToManage?.id;
    const accent = Color(0xFF4F46E5);

    double remaining() {
      final items = invoiceItems.fold(0.0, (s, it) => s + it.itemTotal);
      final fee = double.tryParse(loadingFeeController.text.replaceAll(',', '')) ?? 0.0;
      final paid = double.tryParse(paidAmountController.text.replaceAll(',', '')) ?? 0.0;
      return (items + fee - discount - paid).clamp(0.0, double.infinity).toDouble();
    }

    Future<void> edit({DebtReminder? existing}) async {
      final name = customerNameController.text.trim();
      if (name.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اكتب اسم العميل أولاً')));
        return;
      }
      final now = DateTime.now();
      final rest = remaining();
      final base = existing ??
          DebtReminders.pendingForNewInvoice ??
          DebtReminder(
            startYear: now.month == 12 ? now.year + 1 : now.year,
            startMonth: (now.month % 12) + 1,
            members: [
              ReminderMember(
                customerId: invoiceToManage?.customerId ?? 0,
                customerName: name,
                invoiceId: invId,
                amount: rest > 0 ? rest : null,
              ),
            ],
          );
      for (final m in base.members) {
        if (m.invoiceId == invId || m.customerId == 0) m.customerName = name;
      }
      final r = await showDebtReminderEditor(ctx, initial: base, lockMembers: true);
      if (r == null) return;
      if (invId == null) {
        DebtReminders.pendingForNewInvoice = r; // يُحفظ مع الفاتورة
      } else {
        final cid = invoiceToManage?.customerId ?? await DebtReminders.customerIdByName(name);
        if (cid == null) {
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('العميل غير موجود في سجل الديون بعد — احفظ الفاتورة أولاً')));
          }
          return;
        }
        for (final m in r.members) {
          if (m.customerId == 0) {
            m
              ..customerId = cid
              ..invoiceId = invId;
          }
        }
        await DebtReminders.save(r);
      }
      setD(() {});
    }

    Widget line(DebtReminder r, {required VoidCallback onEdit, required VoidCallback onRemove}) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: accent.withValues(alpha: 0.22)),
          ),
          child: Row(children: [
            const Icon(Icons.notifications_active_outlined, size: 19, color: accent),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.describe(), style: const TextStyle(fontWeight: FontWeight.w700, height: 1.4)),
                if (r.members.isNotEmpty && r.members.first.amount != null)
                  Text('المطلوب ${formatNumber(r.members.first.amount!)}',
                      style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade500)),
              ]),
            ),
            IconButton(tooltip: 'تعديل', onPressed: onEdit, icon: const Icon(Icons.edit_outlined, size: 19)),
            IconButton(
                tooltip: 'إزالة',
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline_rounded, size: 19, color: Color(0xFFB91C1C))),
          ]),
        );

    final addBtn = OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: accent,
        side: BorderSide(color: accent.withValues(alpha: 0.4)),
        minimumSize: const Size(0, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: () => edit(),
      icon: const Icon(Icons.add_alarm_rounded, size: 19),
      label: const Text('تحديد موعد مطالبة'),
    );

    if (invId == null) {
      final p = DebtReminders.pendingForNewInvoice;
      if (p == null) return addBtn;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        line(p, onEdit: () => edit(existing: p), onRemove: () => setD(() => DebtReminders.pendingForNewInvoice = null)),
        Text('يُحفظ مع الفاتورة عند الضغط على «حفظ الفاتورة»',
            style: TextStyle(fontSize: 11.5, color: Colors.blueGrey.shade400)),
      ]);
    }
    return FutureBuilder<List<DebtReminder>>(
      future: DebtReminders.list(invoiceId: invId),
      builder: (context, snap) {
        final list = snap.data ?? const <DebtReminder>[];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final r in list)
            line(r, onEdit: () => edit(existing: r), onRemove: () async {
              await DebtReminders.delete(r.id!);
              setD(() {});
            }),
          addBtn,
        ]);
      },
    );
  }

  // ═══════════════ 🧩 تغيير مستوى السعر على الأصناف الموجودة ═══════════════

  double? _levelPriceOf(Product p, String level) {
    switch (level) {
      case 'مفرد 2':
        return p.price2;
      case 'منزل':
        return p.price3;
      case 'جملة':
        return p.price4;
      case 'جملة 2':
        return p.price5;
      case 'أخرى':
        return p.price6;
      default:
        return p.price1;
    }
  }

  /// عند تغيير «نوع الفاتورة» (مستوى السعر): يُسأل المستخدم هل يطبّق المستوى
  /// الجديد على الأصناف المدخلة. أصناف الخصم والهدايا لا تتغيّر.
  Future<void> _maybeApplyListTypeToItems(String level) async {
    if (isViewOnly) return;
    final filled = invoiceItems.where((it) => it.productName.trim().isNotEmpty).toList();
    final candidates = filled.where((it) => !it.isGift && !it.hasLineDiscount).toList();
    if (candidates.isEmpty) return;
    final skipped = filled.length - candidates.length;
    // يُطبَّق تلقائياً (بلا سؤال)؛ «تراجع» في الإشعار يعيد الأسعار السابقة،
    // وأي سعر يبقى قابلاً للتعديل يدوياً في سطره.
    final previous = {for (final it in candidates) it.uniqueId: it};
    final updated = <String, InvoiceItem>{};
    var missing = 0;
    for (final it in candidates) {
      // المادة بالمعرّف، وإلا بالاسم (أسطر المسودات المستعادة قد تكون بلا معرّف)
      Product? p;
      final name = it.productName.trim();
      for (final x in _allProductsForUnits ?? const <Product>[]) {
        if ((it.productId != null && x.id == it.productId) || (it.productId == null && x.name.trim() == name)) {
          p = x;
          break;
        }
      }
      if (p == null) {
        try {
          p = it.productId != null ? await db.getProductById(it.productId!) : await db.getProductByName(name);
        } catch (_) {}
      }
      final base = p == null ? null : _levelPriceOf(p, level);
      if (base == null || base <= 0) {
        missing++;
        continue;
      }
      final isLarge = (it.quantityLargeUnit ?? 0) > 0;
      final newPrice = base * (isLarge ? (it.unitsInLargeUnit ?? 1.0) : 1.0);
      if ((newPrice - it.appliedPrice).abs() < 0.005) continue;
      updated[it.uniqueId] = it.copyWith(appliedPrice: newPrice, itemTotal: it.soldQuantity * newPrice);
    }
    if (!mounted) return;
    setState(() {
      for (var i = 0; i < invoiceItems.length; i++) {
        final u = updated[invoiceItems[i].uniqueId];
        if (u != null) invoiceItems[i] = u;
      }
      if (updated.isNotEmpty && invoiceToManage != null) hasUnsavedChanges = true;
      _recalculateTotals();
      _calculateProfit();
    });
    if (updated.isNotEmpty) _scheduleLiveDebtSync();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('تغيّر سعر ${updated.length} صنف إلى «$level»'
          '${missing > 0 ? ' — $missing صنف بلا سعر في هذا المستوى بقي كما هو' : ''}'
          '${skipped > 0 ? ' — $skipped صنف عليه خصم أو هدية لم يتغيّر' : ''}'),
      backgroundColor: missing > 0 ? Colors.orange : Colors.green,
      duration: const Duration(seconds: 6),
      persist: false,
      action: updated.isEmpty
          ? null
          : SnackBarAction(
              label: 'تراجع',
              textColor: Colors.white,
              onPressed: () {
                if (!mounted) return;
                setState(() {
                  for (var i = 0; i < invoiceItems.length; i++) {
                    final id = invoiceItems[i].uniqueId;
                    // يُعاد فقط ما لم يُعدَّل بعد التحويل
                    if (updated[id] != null && identical(invoiceItems[i], updated[id])) {
                      invoiceItems[i] = previous[id]!;
                    }
                  }
                  _recalculateTotals();
                  _calculateProfit();
                });
                _scheduleLiveDebtSync();
              },
            ),
    ));
  }

  double _currentInvoiceProfit = 0.0;

  void _calculateProfit() {
    double totalProfit = 0.0;
    
    // Create a map of products for faster lookup
    final Map<String, Product> productMap = {
      for (var p in (_allProductsForUnits ?? [])) p.name: p
    };

    for (var item in invoiceItems) {
      if (!_isInvoiceItemComplete(item)) continue;
      
      final double sellingPrice = item.appliedPrice;
      // Priority 1: Actual Cost Price (if specific batch/item cost is set)
      final double? acp = item.actualCostPrice;
      // Priority 4 (Fallback): Base Cost Price
      final double itemBaseCost = item.costPrice ?? 0.0;
      
      final String saleType = item.saleType ?? '';
      final double qi = item.quantityIndividual ?? 0.0;
      final double ql = item.quantityLargeUnit ?? 0.0;
      final double uilu = item.unitsInLargeUnit ?? 0.0;
      
      // Resolve product data
      final Product? product = productMap[item.productName];
      final String productUnit = product?.unit ?? '';
      final double lengthPerUnit = product?.lengthPerUnit ?? 1.0;
      final double productBaseCost = product?.costPrice ?? 0.0;
      final Map<String, double> unitCosts = product?.getUnitCostsMap() ?? {};

      final bool soldAsLargeUnit = ql > 0;
      final double saleUnitsCount = soldAsLargeUnit ? ql : qi;

      double costPerSaleUnit;
      
      if (acp != null && acp > 0) {
        // Priority 1: Use actual cost price if available
        costPerSaleUnit = acp;
      } else if (soldAsLargeUnit) {
        // Priority 2 & 3: Handle large units (Carton, Roll, etc.)
        
        // Check if specific cost exists for this sale type (e.g. cost of 'Carton')
        if (unitCosts.containsKey(saleType)) {
           costPerSaleUnit = unitCosts[saleType]!;
        } else if (productUnit == 'meter' && saleType == 'لفة') {
           // Special case for Rolls: Cost = Base Cost * Length
           costPerSaleUnit = productBaseCost * lengthPerUnit;
        } else {
           // Default: Cost = Base Cost * Units in Large Unit
           costPerSaleUnit = productBaseCost * (uilu > 0 ? uilu : 1.0);
        }
      } else {
        // Priority 4: Selling in base units (Piece, Meter)
        // Use item's stored cost if available, otherwise product's base cost
        costPerSaleUnit = itemBaseCost > 0 ? itemBaseCost : productBaseCost;
      }


      // 🔧 استخدام نسبة الربح المحددة في الإعدادات
      if (costPerSaleUnit <= 0 && sellingPrice > 0) {
        costPerSaleUnit = MoneyCalculator.getEffectiveCost(
          0, 
          sellingPrice, 
          profitMargin: _adHocProfitPercentage / 100.0
        );
      }

      final double lineAmount = sellingPrice * saleUnitsCount;
      final double lineCostTotal = costPerSaleUnit * saleUnitsCount;
      
      totalProfit += (lineAmount - lineCostTotal);
    }
    
    // Subtract discount from profit
    _currentInvoiceProfit = totalProfit - discount;
  }

  
  // دالة لإظهار Dialog الحفظ عند الرجوع
  Future<bool> _showSaveDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('تعديلات غير محفوظة'),
          content: const Text('هل تريد حفظ التعديلات قبل الخروج؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false), // تجاهل
              child: const Text('تجاهل'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true), // حفظ
              child: const Text('حفظ'),
            ),
          ],
        );
      },
    );
    return result ?? false; // إذا أغلقت Dialog، نعتبرها تجاهل
  }
  
  // دالة لاعتراض زر الرجوع
  Future<bool> _onWillPop() async {
    // للفواتير الجديدة: حفظ مؤقت قبل الخروج
    if (invoiceToManage == null && !isViewOnly && !savedOrSuspended) {
      // حفظ البيانات مؤقتاً قبل الخروج
      await _autoSave();
      return true;
    }
    
    // إذا كانت في وضع العرض فقط، اخرج مباشرة
    if (isViewOnly) {
      return true;
    }
    
    // إذا لا توجد تغييرات غير محفوظة، اخرج مباشرة
    if (!hasUnsavedChanges) {
      return true;
    }
    
    // إظهار Dialog الحفظ
    final shouldSave = await _showSaveDialog();
    
    if (shouldSave) {
      // حفظ الفاتورة
      final savedInvoice = await saveInvoice();
      if (savedInvoice != null) {
        // تم الحفظ بنجاح، hasUnsavedChanges تم إعادة تعيينه في _saveInvoice
        return true; // اخرج
      } else {
        return false; // فشل الحفظ، ابق في الشاشة
      }
    } else {
      // تجاهل التعديلات - إعادة تحميل البيانات الأصلية
      await _loadInvoiceItems();
      hasUnsavedChanges = false;
      return true; // اخرج
    }
  }

  @override
  bool isViewOnly = false;

  /// آخر هاتف عُبّئ تلقائياً من بطاقة عميل — ما كتبه المستخدم بيده لا يُستبدل.
  String? _autoFilledPhone;

  /// 📞 اختيار عميل من القائمة يعبّئ هاتفه من بطاقته (لا حاجة لإعادة كتابته).
  /// يُستبدل الحقل إن كان فارغاً أو يحمل هاتفاً عُبّئ تلقائياً لعميل سابق؛
  /// أما رقم كتبه المستخدم بيده فيبقى كما هو.
  Future<void> _fillPhoneFromCustomerCard(String name) async {
    final row = await CustomerNameRule.findActive(await db.database, name);
    if (!mounted) return;
    final current = customerPhoneController.text.trim();
    final typedByUser = current.isNotEmpty && current != _autoFilledPhone;
    if (typedByUser) return;
    final phone = ((row?['phone'] as String?) ?? '').trim();
    setState(() {
      customerPhoneController.text = phone;
      _autoFilledPhone = phone.isEmpty ? null : phone;
    });
  }

  // تسوية الفاتورة - حالة الواجهة
  bool settlementPanelVisible = false; // عند اختيار "بند"
  
  
  // معلومات التسويات
  List<InvoiceAdjustment> _invoiceAdjustments = [];
  double _totalSettlementAmount = 0.0;
  
  // جلب معلومات التسويات
  Future<void> _loadSettlementInfo() async {
    if (invoiceToManage?.id != null) {
      try {
        final adjustments = await db.getInvoiceAdjustments(invoiceToManage!.id!);
        setState(() {
          _invoiceAdjustments = adjustments;
          _totalSettlementAmount = adjustments.fold(0.0, (sum, adj) {
            return sum + (adj.type == 'debit' ? adj.amountDelta : -adj.amountDelta);
          });
        });
      } catch (e) {
        debugPrint('Error loading settlement info: $e');
      }
    }
  }
  
  // 🧠 تهيئة سياق البحث الذكي
  void _initSmartSearchContext() async {
    // 🆕 تحميل الماركات المكتشفة تلقائياً أولاً
    await SmartSearchService.instance.loadAutoDiscoveredBrands();
    
    // بدء جلسة جديدة
    SmartSearchService.instance.startNewSession(
      customerName: invoiceToManage?.customerName,
      customerId: invoiceToManage?.customerId,
      installerName: invoiceToManage?.installerName,
    );
    
    // إذا كانت فاتورة موجودة، أضف المنتجات الحالية للسياق
    if (invoiceToManage != null && invoiceItems.isNotEmpty) {
      for (final item in invoiceItems) {
        if (item.productName.isNotEmpty) {
          SmartSearchService.instance.addProductToSession(
            item.productId,
            item.productName,
          );
        }
      }
    }
  }

  

  

  final FocusNode _searchFocusNode = FocusNode(); // FocusNode جديد لحقل البحث
  bool suppressSearch = false; // لمنع البحث التلقائي عند اختيار منتج
  bool quantityAutofocus = false; // للتحكم في autofocus لحقل الكمية

  // أضف متغير نوع القائمة (يظل موجوداً ولكن بدون واجهة مستخدم لتغييره)
  String _selectedListType = 'مفرد';


  // متغير للتحكم في السعر المخصص
  bool isCustomPrice = false;

  List<Product>? _allProductsForUnits;

  @override
  late TextEditingController loadingFeeController;

  List<LineItemFocusNodes> focusNodesList = [];



  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onOwnerCostPeekKey);
    _loadHeldCount(); // ⏸️ شارة عدد الفواتير المعلّقة
    // 🧩 تخطيط أعمدة الجدول كما ضبطه المستخدم في الإعدادات
    InvoiceEntryLayout.load().then((_) {
      if (mounted) setState(() {});
    });
    // 🏷️ رموز المواد (تُقرأ من جديد كل مرة تُفتح الشاشة لتظهر الرموز المضافة حديثاً)
    ProductCodes.refresh().then((_) {
      if (mounted) setState(() {});
    });
    _sidePanelOpen = InvoiceSidePanelPref.notifier.value;
    InvoiceSidePanelPref.notifier.addListener(_onSidePanelPrefChanged);
    InvoiceSidePanelPref.load().then((_) => _onSidePanelPrefChanged());
    try {
      printingService = getPlatformPrintingService();
      invoiceToManage = widget.existingInvoice;
      isViewOnly = widget.isViewOnly;
      // تفعيل وضع التسوية: افتح واجهة إدخال أصناف جديدة، لكن اربطها بالفاتورة الأساسية
      if (widget.settlementForInvoice != null) {
        // في وضع التسوية: اجعل الشاشة قابلة للإدخال، ولا تعدّل الأصناف الأصلية
        isViewOnly = false;
        invoiceToManage = widget.settlementForInvoice; // للربط ولأخذ العميل/التاريخ إن لزم
        // نظف أي بيانات إدخال قديمة وابدأ بقائمة فارغة لتسوية جديدة
        invoiceItems.clear();
        _totalAmountController.text = '0';
        // أضف صف فارغ كبداية
        invoiceItems.add(InvoiceItem(
          invoiceId: 0,
          productName: '',
          unit: '',
          unitPrice: 0.0,
          appliedPrice: 0.0,
          itemTotal: 0.0,
          uniqueId: 'placeholder_${DateTime.now().microsecondsSinceEpoch}',
        ));
      }
      loadingFeeController = TextEditingController();
      _loadAutoSavedData();
      _loadSettlementInfo(); // جلب معلومات التسويات
      
      // 🧠 تهيئة سياق البحث الذكي
      _initSmartSearchContext();
      
      // 💰 تحميل إعدادات الأرباح
      _loadProfitSettings();
      

      
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          _allProductsForUnits = await db.getAllProducts();
          setState(() {});
        } catch (e) {
          debugPrint('Error loading products: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Error loading products. Please restart app.')),
            );
          }
        }
      });
      
      // 🔒 [Locking System] Invoice Lock Logic
      // If editing an existing invoice, try to acquire lock immediately
      if (widget.existingInvoice != null && !widget.isViewOnly) {
         WidgetsBinding.instance.addPostFrameCallback((_) async {
           final lockResult = await db.lockingService.acquireLock(
             resourceType: 'invoice', 
             resourceId: widget.existingInvoice!.id!
           );
           
           if (!lockResult.success && mounted) {
             // ⛔ Locked by another user
             await showDialog(
               context: context,
               barrierDismissible: false,
               builder: (ctx) => AlertDialog(
                 title: const Text('⚠️ الفاتورة قيد التعديل'),
                 content: Text(
                   'عذراً، هذه الفاتورة مفتوحة حالياً من قبل:\n\n👤 ${lockResult.lockedBy ?? "مستخدم آخر"}\n\nلا يمكن تعديلها في نفس الوقت لمنع تضارب البيانات.'
                 ),
                 actions: [
                   // 👁️ الدخول الثاني يرى الفاتورة للقراءة فقط (بلا تعديل ولا حفظ)
                   TextButton(
                     onPressed: () {
                        Navigator.of(ctx).pop();
                        if (mounted) setState(() => isViewOnly = true);
                     },
                     child: const Text('عرض للقراءة فقط'),
                   ),
                   TextButton(
                     onPressed: () {
                        Navigator.of(ctx).pop(); // Close Dialog
                        Navigator.of(context).pop(); // Exit Screen
                     },
                     child: const Text('حسناً، خروج'),
                   )
                 ],
               )
             );
           } else {
             // ✅ Lock acquired - Start heartbeat
             _startInvoiceLockHeartbeat();
           }
         });
      }


      // إضافة استماع للتغيرات في الحقول
      customerNameController.addListener(_onFieldChanged);
      customerNameController.addListener(_onCustomerChanged); // 🧠 تحديث سياق البحث الذكي
      customerPhoneController.addListener(_onFieldChanged);
      customerAddressController.addListener(_onFieldChanged);
      installerNameController.addListener(_onFieldChanged);
      installerNameController.addListener(_onInstallerChanged); // 🧠 تحديث سياق البحث الذكي
      paidAmountController.addListener(_onFieldChanged);
      discountController.addListener(_onFieldChanged);
      discountController.addListener(_onDiscountChanged);

      if (invoiceToManage != null) {
        customerNameController.text = invoiceToManage!.customerName;
        customerPhoneController.text = invoiceToManage!.customerPhone ?? '';
        customerAddressController.text =
            invoiceToManage!.customerAddress ?? '';
        installerNameController.text = invoiceToManage!.installerName ?? '';
        founderPointsRate = invoiceToManage!.pointsRate;
        selectedDate = invoiceToManage!.invoiceDate;
        paymentType = invoiceToManage!.paymentType;
        // 👷 المجهز والمحاسب المحفوظان لهذه الفاتورة
        final staffId = invoiceToManage!.id;
        if (staffId != null) {
          InvoiceStaff.load(staffId).then((s) {
            if (s == null || !mounted) return;
            preparerController.text = s.preparer;
            accountantController.text = s.accountant;
          });
        }
        _totalAmountController.text = formatNumber(invoiceToManage!.totalAmount);
        paidAmountController.text =
            formatNumber(invoiceToManage!.amountPaidOnInvoice);
        discount = invoiceToManage!.discount;
        discountController.text = formatNumber(discount);
        // تهيئة قيمة أجور التحميل من الفاتورة الحالية
        try {
          loadingFeeController.text = formatNumber(invoiceToManage!.loadingFee);
        } catch (_) {
          loadingFeeController.text = invoiceToManage!.loadingFee.toString();
        }
        


        _loadInvoiceItems();
      } else {
        _totalAmountController.text = '0';
        _loadFounderDefaultRate();
      }
      // تهيئة FocusNode
      _quantityFocusNode.addListener(_onFieldChanged);
      // إضافة مستمع لحقل البحث
      _productSearchController.addListener(() {
        if (suppressSearch) {
          suppressSearch = false;
          return;
        }
        if (_productSearchController.text.isNotEmpty) {
          _searchProducts(_productSearchController.text);
        }
        if (_productSearchController.text.isEmpty) {
          setState(() {
            _searchResults = [];
            _selectedProduct = null;
          });
        }
      });
    } catch (e) {
      debugPrint('Error in initState: $e');
    }
    if (invoiceItems.isEmpty) {
      invoiceItems.add(InvoiceItem(
        invoiceId: 0,
        productName: '',
        unit: '',
        unitPrice: 0.0,
        appliedPrice: 0.0,
        itemTotal: 0.0,
        uniqueId: 'placeholder_${DateTime.now().microsecondsSinceEpoch}',
      ));
    }
  }

  // 🔹 Start Heartbeat Method (Locking)
  void _startInvoiceLockHeartbeat() {
    _invoiceLockHeartbeat?.cancel();
    _invoiceLockHeartbeat = Timer.periodic(const Duration(minutes: 2), (timer) async {
      if (invoiceToManage == null || !mounted) {
          timer.cancel();
          return;
      }
      await db.lockingService.keepAlive(
        resourceType: 'invoice', 
        resourceId: invoiceToManage!.id!
      );
    });
  }


  // تحميل البيانات المحفوظة تلقائياً
  Future<void> _loadAutoSavedData() async {
    try {
      if (isViewOnly || widget.existingInvoice != null) {
        return;
      }

      final tempData = await storage.read(key: SeatService.key('temp_invoice_data'));
      if (tempData == null) return;

      final data = jsonDecode(tempData);
      setState(() {
        customerNameController.text = data['customerName'] ?? '';
        customerPhoneController.text = data['customerPhone'] ?? '';
        customerAddressController.text = data['customerAddress'] ?? '';
        installerNameController.text = data['installerName'] ?? '';
        final fr = data['founderPointsRate'];
        if (fr is num) founderPointsRate = fr.toDouble();

        if (data['selectedDate'] != null) {
          selectedDate = DateTime.parse(data['selectedDate']);
        }

        paymentType = data['paymentType'] ?? 'نقد';
        discount = data['discount'] ?? 0;
        discountController.text = formatNumber(discount);
        paidAmountController.text = data['paidAmount'] ?? '';

        invoiceItems = (data['invoiceItems'] as List<dynamic>).map((item) {
          return InvoiceItem(
            invoiceId: 0,
            productName: item['productName'],
            unit: item['unit'],
            unitPrice: item['unitPrice'],
            costPrice: item['costPrice'] ?? 0,
            quantityIndividual: item['quantityIndividual'],
            quantityLargeUnit: item['quantityLargeUnit'],
            appliedPrice: item['appliedPrice'],
            itemTotal: item['itemTotal'],
            saleType: item['saleType'],
            unitsInLargeUnit: item['unitsInLargeUnit'],
            uniqueId: item['uniqueId'] ?? 'item_${DateTime.now().microsecondsSinceEpoch}',
          );
        }).toList();

        double itemsTotal = invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal);
        final double loadingFee = double.tryParse(loadingFeeController.text.replaceAll(',', '')) ?? 0.0;
        _totalAmountController.text = formatNumber(itemsTotal + loadingFee);
        
        // للفواتير النقدية المعدلة: تحديث المبلغ المدفوع تلقائياً
        if (invoiceToManage != null && paymentType == 'نقد' && !isViewOnly) {
          final newTotal = (itemsTotal + loadingFee) - discount;
          paidAmountController.text = formatNumber(newTotal);
        }
      });
    } catch (e) {
      debugPrint('Error loading auto-saved data: $e');
    }
  }

  // حفظ البيانات تلقائياً
  Future<void> _autoSave() async {
    try {
      if (savedOrSuspended || isViewOnly || widget.existingInvoice != null) {
        return;
      }

      final data = {
        'customerName': customerNameController.text,
        'customerPhone': customerPhoneController.text,
        'customerAddress': customerAddressController.text,
        'installerName': installerNameController.text,
        'founderPointsRate': founderPointsRate,
        'selectedDate': selectedDate.toIso8601String(),
        'paymentType': paymentType,
        'discount': discount,
        'paidAmount': paidAmountController.text,
        'invoiceItems': invoiceItems
            .map((item) => {
                  'productName': item.productName,
                  'unit': item.unit,
                  'unitPrice': item.unitPrice,
                  'costPrice': item.costPrice,
                  'quantityIndividual': item.quantityIndividual,
                  'quantityLargeUnit': item.quantityLargeUnit,
                  'appliedPrice': item.appliedPrice,
                  'itemTotal': item.itemTotal,
                  'saleType': item.saleType,
                  'unitsInLargeUnit': item.unitsInLargeUnit,
                  'uniqueId': item.uniqueId,
                })
            .toList(),
      };

      await storage.write(key: SeatService.key('temp_invoice_data'), value: jsonEncode(data));
    } catch (e) {
      debugPrint('Error in autoSave: $e');
    }
  }

  // حفظ البيانات فوراً (يُستخدم عند الخروج من الشاشة)
  void _saveDataImmediately() {
    try {
      if (savedOrSuspended || isViewOnly || widget.existingInvoice != null) {
        return;
      }

      final data = {
        'customerName': customerNameController.text,
        'customerPhone': customerPhoneController.text,
        'customerAddress': customerAddressController.text,
        'installerName': installerNameController.text,
        'founderPointsRate': founderPointsRate,
        'selectedDate': selectedDate.toIso8601String(),
        'paymentType': paymentType,
        'discount': discount,
        'paidAmount': paidAmountController.text,
        'invoiceItems': invoiceItems
            .map((item) => {
                  'productName': item.productName,
                  'unit': item.unit,
                  'unitPrice': item.unitPrice,
                  'costPrice': item.costPrice,
                  'quantityIndividual': item.quantityIndividual,
                  'quantityLargeUnit': item.quantityLargeUnit,
                  'appliedPrice': item.appliedPrice,
                  'itemTotal': item.itemTotal,
                  'saleType': item.saleType,
                  'unitsInLargeUnit': item.unitsInLargeUnit,
                  'uniqueId': item.uniqueId,
                })
            .toList(),
      };

      // حفظ فوري بدون await (fire and forget)
      storage.write(key: SeatService.key('temp_invoice_data'), value: jsonEncode(data));
    } catch (e) {
      debugPrint('Error in _saveDataImmediately: $e');
    }
  }

  // معالج تغيير الحقول مع تأخير
  void _onFieldChanged() {
    try {
      // تحديد أن هناك تغييرات غير محفوظة
      if (invoiceToManage != null && !isViewOnly) {
        hasUnsavedChanges = true;
      }
      
      if (debounceTimer?.isActive ?? false) {
        debounceTimer!.cancel();
      }

      debounceTimer = Timer(const Duration(milliseconds: 300), _autoSave);
    } catch (e) {
      debugPrint('Error in onFieldChanged: $e');
    }
  }

  // 🧠 معالج تغيير اسم العميل (للبحث الذكي)
  void _onCustomerChanged() {
    SmartSearchService.instance.updateSessionCustomer(
      customerName: customerNameController.text.trim(),
      customerId: null, // سيتم تحديثه عند الحفظ
    );
    // 🔒 بعد توقف الكتابة قليلاً: احجز الاسم، أو امنع إن كان مستعملاً في جهاز آخر
    if (!isViewOnly) {
      _custClaimDebounce?.cancel();
      _custClaimDebounce = Timer(const Duration(milliseconds: 900), _claimCustomerName);
    }
  }

  Future<void> _claimCustomerName() async {
    if (!mounted || isViewOnly || _custClaimDialogOpen) return;
    final name = customerNameController.text;
    final msg = await _custClaim.claim(name);
    if (!mounted || msg == null || customerNameController.text != name) return;
    _custClaimDialogOpen = true;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('⛔ العميل مستخدم على جهاز آخر'),
        content: Text(msg, style: const TextStyle(height: 1.6)),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('حسناً'))],
      ),
    );
    _custClaimDialogOpen = false;
    if (mounted && customerNameController.text == name) customerNameController.clear();
  }

  @override
  Future<String?> verifyCustomerClaimBeforeSave() async {
    if (isViewOnly) return null;
    _custClaimDebounce?.cancel();
    return _custClaim.verify(customerNameController.text);
  }

  // 🧠 معالج تغيير اسم المُركّب (للبحث الذكي)
  void _onInstallerChanged() {
    SmartSearchService.instance.updateSessionInstaller(
      installerNameController.text.trim(),
    );
  }

  // معالج تغيير الخصم
  void _onDiscountChanged() {
    try {
      final discountText = discountController.text.replaceAll(',', '');
      final newDiscount = double.tryParse(discountText) ?? 0.0;
      discount = newDiscount;
      
      // تحديد أن هناك تغييرات غير محفوظة
      if (invoiceToManage != null && !isViewOnly) {
        hasUnsavedChanges = true;
      }
      
      // للفواتير النقدية المعدلة: تحديث المبلغ المدفوع تلقائياً
      if (invoiceToManage != null && paymentType == 'نقد' && !isViewOnly) {
        final currentTotalAmount = invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal);
        final newTotal = currentTotalAmount - discount;
        paidAmountController.text = formatNumber(newTotal);
      }
      _calculateProfit(); // Update profit on discount change
      // 🔧 إصلاح: تحديث الواجهة فوراً إذا كان الربح ظاهراً
      if (_isProfitVisible) {
        setState(() {});
      }
      _scheduleLiveDebtSync();
    } catch (e) {
      debugPrint('Error in onDiscountChanged: $e');
    }
  }

  Future<void> _loadInvoiceItems() async {
    try {
      if (invoiceToManage != null && invoiceToManage!.id != null) {
        final items = await db.getInvoiceItems(invoiceToManage!.id!);
        
        // تهيئة الـ controllers لكل صنف
        for (var item in items) {
          item.initializeControllers();
        }
        // تهيئة FocusNodes لكل صنف
        focusNodesList.clear();
        for (var _ in items) {
          focusNodesList.add(LineItemFocusNodes());
        }
        setState(() {
          invoiceItems = items;
          double itemsTotal = invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal);
          final double loadingFee = double.tryParse(loadingFeeController.text.replaceAll(',', '')) ?? 0.0;
          _totalAmountController.text = formatNumber(itemsTotal + loadingFee);
        });
        
        _scheduleLiveDebtSync();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء تحميل أصناف الفاتورة: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    DebtReminders.pendingForNewInvoice = null; // 📅 موعد لم يُحفظ مع فاتورة: لا يتعلق بفاتورة أخرى
    HardwareKeyboard.instance.removeHandler(_onOwnerCostPeekKey);
    InvoiceSidePanelPref.notifier.removeListener(_onSidePanelPrefChanged);
    try {
      // 1. إلغاء المؤقت أولاً لمنع أي عمليات حفظ متأخرة
      debounceTimer?.cancel();
      _custClaimDebounce?.cancel();
      _custClaim.release(); // 🔒 تحرير اسم العميل للأجهزة الأخرى

      // 2. إزالة جميع المستمعين لمنع استدعاء logic بعد التخلص من الكائنات
      customerNameController.removeListener(_onFieldChanged);
      customerNameController.removeListener(_onCustomerChanged);
      customerPhoneController.removeListener(_onFieldChanged);
      customerAddressController.removeListener(_onFieldChanged);
      installerNameController.removeListener(_onFieldChanged);
      installerNameController.removeListener(_onInstallerChanged);
      paidAmountController.removeListener(_onFieldChanged);
      discountController.removeListener(_onFieldChanged);
      discountController.removeListener(_onDiscountChanged);
      _quantityFocusNode.removeListener(_onFieldChanged);
      _productSearchController.removeListener(_onFieldChanged);

      // 3. الحفظ الفوري عند إغلاق الشاشة إذا لزم الأمر
      if (!savedOrSuspended &&
          widget.existingInvoice == null &&
          !isViewOnly) {
        _saveDataImmediately();
      }

      // 🔒 [Locking System] Release Locks
      _invoiceLockHeartbeat?.cancel();
      
      // Release Invoice Lock if we held it
      if (invoiceToManage?.id != null && !isViewOnly) {
         db.lockingService.releaseLock(resourceType: 'invoice', resourceId: invoiceToManage!.id!);
      }
      
      // Release Customer Lock if we held it (New Invoice scenario) or generally just cleanup
      if (invoiceToManage?.customerId != null) {
         db.lockingService.releaseLock(resourceType: 'customer', resourceId: invoiceToManage!.customerId!);
      }
      
      // 4. التخلص من المتحكمات (Controllers)
      customerNameController.dispose();
      customerPhoneController.dispose();
      customerAddressController.dispose();
      preparerController.dispose();
      accountantController.dispose();
      installerNameController.dispose();

      _productSearchController.dispose();
      _quantityController.dispose();
      _itemsController.dispose();
      _totalAmountController.dispose();
      paidAmountController.dispose();
      discountController.dispose();
      loadingFeeController.dispose();
      _productIdController.dispose();
      
      // 5. التخلص من عقد التركيز (FocusNodes)
      _quantityFocusNode.dispose();
      _searchFocusNode.dispose();
      _scrollController.dispose();
      _hScrollController.dispose();

      // 6. التخلص من عقد التركيز لصفوف الفاتورة
      for (final node in focusNodesList) {
        node.dispose();
      }
      focusNodesList.clear();
      
    } catch (e) {
      debugPrint('Error in dispose: $e');
    } finally {
      super.dispose();
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    try {
      final DateTime? picked = await showDatePicker(
        context: context,
        initialDate: selectedDate,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        locale: const Locale('ar', 'SA'),
      );
      if (picked != null && picked != selectedDate) {
        // تحديد أن هناك تغييرات غير محفوظة
        if (invoiceToManage != null && !isViewOnly) {
          hasUnsavedChanges = true;
        }
        
        setState(() {
          selectedDate = picked;
          _autoSave(); // حفظ تلقائي عند تغيير التاريخ
        });
      }
    } catch (e) {
      debugPrint('Error selecting date: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء اختيار التاريخ: $e')),
        );
      }
    }
  }

  /// دالة البحث عن المنتجات - تستخدم خوارزمية البحث الذكية المتعددة الطبقات
  /// تدعم البحث عن "كوب فنار" لإيجاد "كوب واحد سيه فنار"، "كوب اثنين سيات فنار"، إلخ
  Future<void> _searchProducts(String query) async {
    try {
      if (query.isEmpty) {
        setState(() {
          _searchResults = [];
        });
        return;
      }
      // 🧠 استخدام البحث الذكي مع تمرير قائمة المنتجات الحالية في الفاتورة
      // هذا يضمن دقة التحقق من المنتجات المضافة (حتى لو تم حذفها)
      final currentProductNames = invoiceItems
          .where((item) => item.productName.isNotEmpty)
          .map((item) => item.productName)
          .toList();
      final results = await SmartSearchService.instance.smartSearch(
        query,
        currentInvoiceProductNames: currentProductNames,
      );
      setState(() {
        _searchResults = results;
      });
    } catch (e) {
      debugPrint('Error searching products: $e');
      setState(() {
        _searchResults = [];
      });
    }
  }

  // دالة لتحديث المبلغ المسدد تلقائيًا إذا كان الدفع نقد
  void _updatePaidAmountIfCash() {
    try {
      if (paymentType == 'نقد') {
        _guardDiscount();
        final itemsTotal = invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal);
        final double loadingFee = double.tryParse(loadingFeeController.text.replaceAll(',', '')) ?? 0.0;
        final currentTotalAmount = itemsTotal + loadingFee;
        final total = currentTotalAmount - discount;
        paidAmountController.text =
            formatNumber(total.clamp(0, double.infinity));
      }
    } catch (e) {
      debugPrint('Error in updatePaidAmountIfCash: $e');
    }
  }

  // دالة مركزية لحماية الخصم
  void _guardDiscount() {
    try {
      final itemsTotal = invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal);
      final double loadingFee = double.tryParse(loadingFeeController.text.replaceAll(',', '')) ?? 0.0;
      final currentTotalAmount = itemsTotal + loadingFee;
      // الحد الأعلى للخصم هو أقل من نصف الإجمالي
      final maxDiscount = (currentTotalAmount / 2) - 1;
      if (discount > maxDiscount) {
        discount = maxDiscount > 0 ? maxDiscount : 0.0;
        discountController.text = formatNumber(discount);
      }
      if (discount < 0) {
        discount = 0.0;
        discountController.text = formatNumber(0);
      }
      
      // للفواتير النقدية المعدلة: تحديث المبلغ المدفوع تلقائياً عند تغيير الخصم
      if (invoiceToManage != null && paymentType == 'نقد' && !isViewOnly) {
        final newTotal = currentTotalAmount - discount;
        paidAmountController.text = formatNumber(newTotal);
      }
    } catch (e) {
      debugPrint('Error in guardDiscount: $e');
    }
  }

  // --- دالة حساب التكلفة الفعلية بناءً على نوع وحدة البيع (تعامل مع غياب/صفر unit_costs) ---
  // 🔧 Fix: إضافة معامل unitsInLargeUnit للاستخدام كـ fallback
  double _calculateActualCostPrice(Product product, String saleUnit, double quantity, {double? unitsInLargeUnit}) {
    final double baseCost = product.costPrice ?? 0.0;
    // بيع بالوحدة الأساسية
    if ((product.unit == 'piece' && saleUnit == 'قطعة') ||
        (product.unit == 'meter' && saleUnit == 'متر')) {
      return baseCost;
    }

    // جرّب قراءة تكلفة الوحدة المباعة من unit_costs; اعتبر الصفر كأنه غير متوفر
    Map<String, double> unitCosts = const {};
    try { unitCosts = product.getUnitCostsMap(); } catch (_) {}
    final double? stored = unitCosts[saleUnit];
    if (stored != null && stored > 0) {
      return stored;
    }

    // للمتر و"لفة": استخدم طول اللفة عند عدم توفر تكلفة مخزنة
    if (product.unit == 'meter' && saleUnit == 'لفة') {
      final double lengthPerUnit = product.lengthPerUnit ?? 1.0;
      return baseCost * lengthPerUnit;
    }

    // للقطعة مع هرمية: احسب المضاعف التراكمي حتى وحدة البيع المطلوبة
    if (product.unit == 'piece' && product.unitHierarchy != null && product.unitHierarchy!.isNotEmpty) {
      try {
        // 🔧 Robust JSON parsing with fallback
        List<dynamic> hierarchy;
        try {
          hierarchy = jsonDecode(product.unitHierarchy!) as List<dynamic>;
        } catch (_) {
          // Fallback: try with single quote replacement
          hierarchy = jsonDecode(product.unitHierarchy!.replaceAll("'", '"')) as List<dynamic>;
        }
        
        double multiplier = 1.0;
        for (final level in hierarchy) {
          final String unitName = (level['unit_name'] ?? level['name'] ?? '').toString();
          final double qty = (level['quantity'] is num)
              ? (level['quantity'] as num).toDouble()
              : double.tryParse(level['quantity'].toString()) ?? 1.0;
          multiplier *= qty;
          if (unitName == saleUnit) {
            return baseCost * multiplier;
          }
        }
        // 🔧 Fix: إذا لم نجد الوحدة في الهرمية، استخدم المضاعف المحسوب إذا توفر
        if (multiplier > 1.0) {
          return baseCost * multiplier;
        }
      } catch (e) {
        debugPrint('خطأ في حساب التكلفة الهيراركية: $e');
      }
    }

    // 🔧 Fix: للوحدات الكبيرة غير الموجودة في الهرمية، استخدم unitsInLargeUnit كـ fallback
    if (saleUnit != 'قطعة' && saleUnit != 'متر' && unitsInLargeUnit != null && unitsInLargeUnit > 1) {
      return baseCost * unitsInLargeUnit;
    }

    // رجوع آمن
    return baseCost;
  }

  void _addInvoiceItem() {
    try {
      // تحديد أن هناك تغييرات غير محفوظة
      if (invoiceToManage != null && !isViewOnly) {
        hasUnsavedChanges = true;
      }
      
      if (formKey.currentState!.validate() && _selectedProduct != null) {
        final double inputQuantity = safeParseDouble(_quantityController.text) ?? 0.0;
        final double inputPrice = safeParseDouble(_priceController.text) ?? 0.0; // 🔧 المصدر الحقيقي للسعر

        if (inputQuantity <= 0) {
           return;
        }

       // 🔒 التحقق من السعر قبل الإضافة وعرض تحذير
        if (_isEntryPriceBelowCost()) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('⚠️ تنبيه: تم إضافة الصنف بسعر أقل من التكلفة!', style: TextStyle(fontFamily: 'Cairo')),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 3),
              ),
            );
        }

        // 🏷️ السعر المكتوب هو «قبل الخصم»؛ الصافي بعد خصم الصنف (أو صفر للهدية)
        //    هو ما تُحسب عليه الفاتورة والأرباح. بلا خصم: الصافي = السعر المكتوب.
        final double entryDiscValue = safeParseDouble(_entryDiscountController.text) ?? 0.0;
        final String? entryDiscType = _entryGift
            ? 'gift'
            : (entryDiscValue > 0 ? (_entryDiscountPercent ? 'percent' : 'amount') : null);
        double finalAppliedPrice = lineNetPrice(inputPrice, entryDiscType, entryDiscValue);
        if (entryDiscType != null && entryDiscType != 'gift' && finalAppliedPrice <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('الخصم يساوي السعر أو أكبر منه — للمجان اختر «هدية»'),
            backgroundColor: Colors.orange,
          ));
          return;
        }

        double baseUnitsPerSelectedUnit = 1.0;

        debugPrint('🔍 [تشخيص-إضافة-صنف] "${_selectedProduct!.name}" | الوحدة: "$selectedUnitForItem" | الكمية: $inputQuantity | السعر من الحقل: $inputPrice');
        debugPrint('    unit="${_selectedProduct!.unit}" | isWeighable=${_selectedProduct!.isWeighable} | unitHierarchy=${_selectedProduct!.unitHierarchy}');

        // --- حساب معامل التحويل (للمخزون فقط) ---
        if (_selectedProduct!.unit == 'piece' && selectedUnitForItem != 'قطعة') {
          // إذا كان هناك تسلسل هرمي للوحدات
          if (_selectedProduct!.unitHierarchy != null && _selectedProduct!.unitHierarchy!.isNotEmpty) {
            try {
              // 🔧 Robust JSON parsing matching row logic
              List<dynamic> hierarchy;
              try {
                hierarchy = jsonDecode(_selectedProduct!.unitHierarchy!);
              } catch (_) {
                hierarchy = jsonDecode(_selectedProduct!.unitHierarchy!.replaceAll("'", '"'));
              }

              for (final level in hierarchy) {
                final unitName = (level['unit_name'] ?? level['name'] ?? '').toString();
                
                // حساب المضاعف التراكمي: نضرب العوامل (كما في الصفوف)
                // ملاحظة: المنطق هنا يفترض أننا نريد الوصول للوحدة المحددة وحساب معاملها بالنسبة للوحدة الأساسية
                if (unitName == selectedUnitForItem) {
                   // في هذه اللحظة، الكمية هي كمية القطع في هذه الوحدة
                   // ولكن إذا كان هناك تسلسل (كرتون يحتوي 10 باكيت، والباكيت يحتوي 12 قطعة)
                   // فالكود الحالي يحتاج لتحسين إذا كان التسلسل معقداً، لكن سنمشي على نفس منطق الصفوف البسيط
                   // الذي يضرب الكميات حتى يجد الوحدة.
                   
                   // انتظر، منطق الصفوف كان يضرب `multiplier *= qty` حتى يجد الوحدة.
                   // سنطبق نفس المنطق هنا:
                   double multiplier = 1.0;
                   for (final l in hierarchy) {
                      final q = (l['quantity'] is num) ? (l['quantity'] as num).toDouble() : double.tryParse(l['quantity'].toString()) ?? 1.0;
                      multiplier *= q;
                      if ((l['unit_name'] ?? l['name']) == selectedUnitForItem) {
                        break;
                      }
                   }
                   baseUnitsPerSelectedUnit = multiplier;
                   break;
                }
              }
            } catch (e) {
              // fallback: استخدام 1.0 في حال الفشل التام
              debugPrint('Add item JSON parse error: $e');
              baseUnitsPerSelectedUnit = 1.0;
            }
          }
        } else if (_selectedProduct!.unit == 'meter' && selectedUnitForItem == 'لفة') {
          baseUnitsPerSelectedUnit = _selectedProduct!.lengthPerUnit ?? 1.0;
        } else if (selectedUnitForItem != 'قطعة' && selectedUnitForItem != _selectedProduct!.translatedUnit) {
          debugPrint('    ⚠️ [تشخيص-إضافة-صنف] وحدة غير أساسية بلا معامل تحويل! '
              'unit="${_selectedProduct!.unit}" ليست piece/meter → المخزون سيُخصم $inputQuantity فقط (بدل المضاعف)');
        }
        debugPrint('    معامل التحويل للمخزون: $baseUnitsPerSelectedUnit');

        final double totalBaseUnitsSold = inputQuantity * baseUnitsPerSelectedUnit;

        // 🔒 التحقق من المخزون
        if (!_allowNegativeStock && (_selectedProduct!.stockQuantity) < totalBaseUnitsSold) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '⚠️ عذراً، الرصيد غير كافٍ! \n'
                  'المطلوب: ${formatNumber(totalBaseUnitsSold)} قطعة، المتاح: ${formatNumber(_selectedProduct!.stockQuantity)}',
                  style: const TextStyle(fontFamily: 'Cairo'),
                ),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
        // 📦 البيع بلا رصيد كافٍ مسموح (إعداد «السماح بالبيع عند نفاذ الكمية»):
        //    نكمل البيع وننبّه — المخزن مشترك والكمية قد تصير سالبة.
        if (_allowNegativeStock &&
            (_selectedProduct!.stockQuantity) < totalBaseUnitsSold &&
            mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '⚠️ تنبيه: الكمية المتاحة ${formatNumber(_selectedProduct!.stockQuantity)} أقل من '
                'المطلوب $totalBaseUnitsSold — سيصبح المخزون سالباً',
                style: const TextStyle(fontFamily: 'Cairo'),
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        }

        final double finalItemCostPrice = (_selectedProduct!.costPrice ?? 0) * totalBaseUnitsSold;
        final double finalItemTotal = inputQuantity * finalAppliedPrice;
        
        double? quantityIndividual;
        double? quantityLargeUnit;
        if (selectedUnitForItem == _selectedProduct!.translatedUnit || selectedUnitForItem == 'قطعة' || selectedUnitForItem == 'متر') {
          quantityIndividual = inputQuantity;
        } else {
          quantityLargeUnit = inputQuantity;
        }
        
        // حساب التكلفة الفعلية بناءً على نوع الوحدة المباعة
        final actualCostPrice = _calculateActualCostPrice(_selectedProduct!, selectedUnitForItem, inputQuantity, unitsInLargeUnit: baseUnitsPerSelectedUnit);
        
        final newItem = InvoiceItem(
          invoiceId: 0,
          productId: _selectedProduct!.id,
          productName: _selectedProduct!.name,
          unit: _selectedProduct!.unit,
          unitPrice: _selectedProduct!.unitPrice,
          costPrice: finalItemCostPrice,
          actualCostPrice: actualCostPrice,
          quantityIndividual: quantityIndividual,
          quantityLargeUnit: quantityLargeUnit,
          appliedPrice: finalAppliedPrice,
          itemTotal: finalItemTotal,
          saleType: selectedUnitForItem,
          unitsInLargeUnit: baseUnitsPerSelectedUnit != 1.0 ? baseUnitsPerSelectedUnit : null,
          priceBeforeDiscount: entryDiscType != null ? inputPrice : null,
          discountType: entryDiscType,
          discountValue: (entryDiscType == 'percent' || entryDiscType == 'amount') ? entryDiscValue : null,
        );
        setState(() {
          // يُدمج مع سطر موجود فقط إن كان بنفس السعر الصافي ونفس الخصم
          // (الهدية أو الصنف المخصوم يبقى سطراً مستقلاً)
          final existingIndex = invoiceItems.indexWhere((item) =>
              item.productName == newItem.productName &&
              item.saleType == newItem.saleType &&
              item.unit == newItem.unit &&
              item.appliedPriceCents == newItem.appliedPriceCents &&
              item.discountType == newItem.discountType);
          if (existingIndex != -1) {
            final existingItem = invoiceItems[existingIndex];
            invoiceItems[existingIndex] = existingItem.copyWith(
              quantityIndividual: (existingItem.quantityIndividual ?? 0) +
                  (newItem.quantityIndividual ?? 0),
              quantityLargeUnit: (existingItem.quantityLargeUnit ?? 0) +
                  (newItem.quantityLargeUnit ?? 0),
              itemTotal: (existingItem.itemTotal) + (newItem.itemTotal),
              costPrice:
                  (existingItem.costPrice ?? 0) + (newItem.costPrice ?? 0),
              unitsInLargeUnit: newItem.unitsInLargeUnit,
            );
          } else {
            invoiceItems.add(newItem);
          }
          _productSearchController.clear();
          _quantityController.clear();
          _entryDiscountController.clear();
          _entryGift = false;
          _selectedProduct = null;
          _searchResults = [];
          selectedUnitForItem = 'قطعة';
          currentUnitOptions = ['قطعة'];
          _currentUnitHierarchy = [];
          _guardDiscount();
          _updatePaidAmountIfCash();
          _calculateProfit(); // Update profit on item addition
          
          // للفواتير النقدية المعدلة: تحديث المبلغ المدفوع تلقائياً
          if (invoiceToManage != null && paymentType == 'نقد' && !isViewOnly) {
            final newTotal = invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal) - discount;
            paidAmountController.text = formatNumber(newTotal);
          }
          
          _autoSave();
          if (invoiceToManage != null &&
              invoiceToManage!.status == 'معلقة' &&
              (invoiceToManage?.isLocked ?? false)) {
            autoSaveSuspendedInvoice();
          }
          // --- معالجة الصفوف الفارغة ---
          // احذف جميع الصفوف الفارغة (غير المكتملة) مع عقد تركيزها، لتبقى القائمتان
          // متوازيتين (التنقل بـ Enter يعتمد على رقم السطر)
          for (var r = invoiceItems.length - 1; r >= 0; r--) {
            if (_isInvoiceItemComplete(invoiceItems[r])) continue;
            invoiceItems.removeAt(r);
            if (r < focusNodesList.length) {
              final dead = focusNodesList.removeAt(r);
              WidgetsBinding.instance.addPostFrameCallback((_) => dead.dispose());
            }
          }
          // ثم أضف صف فارغ جديد إذا كان آخر صف مكتمل أو القائمة فارغة
          if (invoiceItems.isEmpty ||
              _isInvoiceItemComplete(invoiceItems.last)) {
            invoiceItems.add(InvoiceItem(
              invoiceId: 0,
              productName: '',
              unit: '',
              unitPrice: 0.0,
              appliedPrice: 0.0,
              itemTotal: 0.0,
              uniqueId: 'placeholder_${DateTime.now().microsecondsSinceEpoch}',
            ));
          }
        });
      }
    } catch (e) {
      debugPrint('Error adding invoice item: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء إضافة الصنف: $e')),
        );
      }
    }
  }


  void _removeInvoiceItemByUid(String uid) {
    try {
      // 🔒 شرط 1: منع حذف جميع الأصناف عند تعديل فاتورة محفوظة
      // يجب أن يبقى صنف واحد على الأقل
      final completeItems = invoiceItems.where((item) => 
        item.productName.isNotEmpty && (item.itemTotal > 0 || item.isGift)
      ).toList();
      
      if (invoiceToManage != null && completeItems.length <= 1) {
        // تحقق إذا كان الصنف المراد حذفه هو الصنف الوحيد المكتمل
        final itemToRemove = invoiceItems.firstWhere(
          (it) => it.uniqueId == uid,
          orElse: () => InvoiceItem(
            invoiceId: 0, productName: '', unit: '', unitPrice: 0,
            appliedPrice: 0, itemTotal: 0, uniqueId: '',
          ),
        );
        if (itemToRemove.productName.isNotEmpty && (itemToRemove.itemTotal > 0 || itemToRemove.isGift)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ لا يمكن حذف جميع الأصناف! يجب أن يبقى صنف واحد على الأقل'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
          return;
        }
      }
      
      // تحديد أن هناك تغييرات غير محفوظة
      if (invoiceToManage != null && !isViewOnly) {
        hasUnsavedChanges = true;
      }
      
      setState(() {
        final index = invoiceItems.indexWhere((it) => it.uniqueId == uid);
        if (index == -1) return;
        if (index < focusNodesList.length) {
          // الصف ما زال مبنياً حتى الإطار القادم ويزيل مستمعيه عند إزالته:
          // إتلاف عقده الآن كان يرمي «FocusNode used after being disposed»
          final dead = focusNodesList.removeAt(index);
          WidgetsBinding.instance.addPostFrameCallback((_) => dead.dispose());
        }
        invoiceItems.removeAt(index);
        _guardDiscount();
        _updatePaidAmountIfCash();
        
        // للفواتير النقدية المعدلة: تحديث المبلغ المدفوع تلقائياً
        if (invoiceToManage != null && paymentType == 'نقد' && !isViewOnly) {
          final newTotal = invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal) - discount;
          paidAmountController.text = formatNumber(newTotal);
        }
        
        _recalculateTotals();
        _calculateProfit(); // Update profit on item removal
        _autoSave();
        if (invoiceToManage != null &&
            invoiceToManage!.status == 'معلقة' &&
            (invoiceToManage?.isLocked ?? false)) {
          autoSaveSuspendedInvoice();
        }
      });
      _scheduleLiveDebtSync();
    } catch (e) {
      debugPrint('Error removing invoice item by uid: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء حذف الصنف: $e')),
        );
      }
    }
  }



  // حفظ في مجلد مؤقت مناسب للمشاركة (Android/Windows/macOS)
  Future<String> _saveInvoicePdfToTemp(
      pw.Document pdf, String customerName, DateTime invoiceDate) async {
    final safeCustomerName =
        customerName.replaceAll(RegExp(r'[^\w\u0600-\u06FF]+'), '_');
    final formattedDate = DateFormat('yyyy-MM-dd').format(invoiceDate);
    final fileName = '${safeCustomerName}_$formattedDate.pdf';
    final dir = await pp.getTemporaryDirectory();
    final folder = Directory(p.join(dir.path, 'invoices_share_cache'));
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    final filePath = p.join(folder.path, fileName);
    final file = File(filePath);
    await file.writeAsBytes(await pdf.save(), flush: true);
    return filePath;
  }

  Future<void> _printPickingList() async {
    try {
      // تحميل الخطوط والشعار كما في خدمة PDF
      final fontData = await rootBundle.load('assets/fonts/Amiri-Regular.ttf');
      final alnaserFontData = await rootBundle.load('assets/fonts/PTBLDHAD.TTF');
      final font = pw.Font.ttf(fontData);
      final alnaserFont = pw.Font.ttf(alnaserFontData);
      
      // تحميل الإعدادات العامة
      final appSettings = await SettingsManager.getAppSettings();
      
      // تحميل اللوجو باستخدام خدمة اللوجو (مخصص أو افتراضي)
      final logoImage = await LogoService.getLogoImage(appSettings: appSettings);

      final doc = await InvoicePdfService.generatePickingListPdf(
        invoiceItems: invoiceItems,
        allProducts: await db.getAllProducts(),
        customerName: customerNameController.text,
        invoiceId: invoiceToManage?.id ?? 0,
        selectedDate: selectedDate,
        font: font,
        alnaserFont: alnaserFont,
        logoImage: logoImage,
        appSettings: appSettings,
      );

      // 🌐 الويب: PDF من الذاكرة مباشرة — فتح نافذة طباعة المتصفح مباشرة
      if (kIsWeb) {
        final bytes = await doc.save();
        await Printing.layoutPdf(
          onLayout: (PdfPageFormat format) async => bytes,
          name: 'قائمة_تجهيز_${customerNameController.text.isNotEmpty ? customerNameController.text : "عامة"}.pdf',
        );
        return;
      }

      // احفظ ثم افتح للطباعة على ويندوز
      final filePath = await _saveInvoicePdfToTemp(doc, customerNameController.text, selectedDate);
      if (Platform.isWindows) {
        await Process.start('cmd', ['/c', 'start', '/min', '', filePath, '/p']);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم إرسال قائمة التجهيز للطابعة')),
          );
        }
        return;
      }
      // على أندرويد/منصات أخرى: مشاركة/فتح الملف ليطبعه المستخدم
      final fileName = p.basename(filePath);
      await Share.shareXFiles([
        XFile(
          filePath,
          mimeType: 'application/pdf',
          name: fileName,
        )
      ], text: 'قائمة تجهيز ${customerNameController.text}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل طباعة التجهيز: $e')),
        );
      }
    }
  }


  // دالة تفعيل وضع التعديل
  Future<void> _enableEditMode() async {
    // 👤 تعديل فاتورة محفوظة يحتاج صلاحية «تعديل الفواتير»
    if (!AuthService().hasPermission(AppPermissions.editInvoices)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('ليس لديك صلاحية تعديل الفواتير — يمكنك عمل مرتجع بدلاً من ذلك'),
        backgroundColor: Colors.red,
      ));
      return;
    }
    // 🔒 تثبيت الإدخالات: لا تعديل لفاتورة داخل فترة مثبّتة
    if (!await PeriodLock.guard(context, invoiceToManage?.invoiceDate)) return;
    if (!mounted) return;
    setState(() {
      isViewOnly = false;
    });
    
    // إظهار رسالة تأكيد
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم تفعيل وضع التعديل - يمكنك الآن إضافة أو حذف أصناف'),
        backgroundColor: Colors.blue,
        duration: Duration(seconds: 3),
      ),
    );
  }

  // دالة إلغاء التعديل - تستعيد جميع البيانات الأصلية
  Future<void> _cancelEdit() async {
    if (invoiceToManage == null) return;
    
    // جلب الفاتورة الأصلية من قاعدة البيانات
    final originalInvoice = await db.getInvoiceById(invoiceToManage!.id!);
    if (originalInvoice == null) return;
    
    setState(() {
      // استعادة بيانات العميل
      customerNameController.text = originalInvoice.customerName;
      customerPhoneController.text = originalInvoice.customerPhone ?? '';
      customerAddressController.text = originalInvoice.customerAddress ?? '';
      
      // استعادة بيانات الفني
      installerNameController.text = originalInvoice.installerName ?? '';
      founderPointsRate = originalInvoice.pointsRate;
      
      // استعادة التاريخ
      selectedDate = originalInvoice.invoiceDate;
      
      // استعادة نوع الدفع
      paymentType = originalInvoice.paymentType;
      
      // استعادة الخصم
      discount = originalInvoice.discount;
      discountController.text = formatNumber(discount);
      
      // استعادة المبلغ المدفوع
      paidAmountController.text = formatNumber(originalInvoice.amountPaidOnInvoice);
      
      // استعادة أجور التحميل
      final itemsTotal = invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal);
      final loadingFee = originalInvoice.totalAmount - itemsTotal;
      loadingFeeController.text = loadingFee > 0 ? formatNumber(loadingFee) : '';
      

      
      // تحديث الفاتورة المُدارة
      invoiceToManage = originalInvoice;
      
      // العودة لوضع العرض فقط
      isViewOnly = true;
      hasUnsavedChanges = false;
    });
    
    // إعادة تحميل الأصناف من قاعدة البيانات
    await _loadInvoiceItems();
    
    // تحديث الإجمالي
    _recalculateTotals();
    
    // إظهار رسالة تأكيد
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم إلغاء التعديل - تم استعادة جميع البيانات الأصلية'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }













  // ═══════════════════ ⏸️ الفواتير المعلّقة (Hold) ═══════════════════
  int _heldCount = 0;

  Future<void> _loadHeldCount() async {
    try {
      final n = await HeldInvoices.count();
      if (mounted) setState(() => _heldCount = n);
    } catch (_) {}
  }

  /// الشاشة فُتحت للبيع: فاتورة جديدة، أو فاتورة معلّقة فُتحت لإكمالها
  bool get _holdMode =>
      widget.existingInvoice == null || widget.existingInvoice!.status == HeldInvoices.status;

  double _numOf(TextEditingController c) => double.tryParse(c.text.replaceAll(',', '').trim()) ?? 0.0;

  bool get _hasLines => invoiceItems.any((i) => i.productName.trim().isNotEmpty);

  /// يُعلَّق الجديد أو المعلّق فقط — الفاتورة المحفوظة لها قيد دين وحركة مخزون
  bool get _canHold =>
      !isViewOnly && !isSaving && _hasLines && (invoiceToManage == null || invoiceToManage!.status == HeldInvoices.status);

  Future<bool> _holdCurrentInvoice() async {
    try {
      final held = await HeldInvoices.hold(
        existing: invoiceToManage,
        items: invoiceItems,
        customerName: customerNameController.text,
        customerPhone: customerPhoneController.text,
        customerAddress: customerAddressController.text,
        installerName: OwnerAccess.enabled ? installerNameController.text : null,
        invoiceDate: selectedDate,
        paymentType: paymentType,
        discount: discount,
        loadingFee: _numOf(loadingFeeController),
        paid: _numOf(paidAmountController),
        pointsRate: OwnerAccess.enabled ? founderPointsRate : 0,
        createdByUserId: AuthService().currentUser?.id,
        createdByUsername: AuthService().currentUser?.username,
      );
      setState(() {
        invoiceToManage = null;
        hasUnsavedChanges = false;
      });
      await _performReset();
      await _loadHeldCount();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('⏸️ عُلّقت فاتورة «${held.customerName.isEmpty ? 'بلا عميل' : held.customerName}» — $_heldCount منتظرة'),
          backgroundColor: Colors.orange.shade800,
        ));
      }
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('تعذّر تعليق الفاتورة: ${e is StateError ? e.message : e}'),
          backgroundColor: Colors.red.shade700,
        ));
      }
      return false;
    }
  }

  /// فتح فاتورة معلّقة: إن كان في الشاشة عمل لم يُحفظ نسأل أولاً
  Future<void> _openHeld(Invoice inv) async {
    final same = invoiceToManage?.id != null && invoiceToManage!.id == inv.id;
    if (same) return;
    if (_hasLines) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('في الشاشة فاتورة لم تُحفظ'),
          content: const Text('ماذا نفعل بالفاتورة الحالية قبل فتح المعلّقة؟'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            TextButton(onPressed: () => Navigator.pop(ctx, 'drop'), child: const Text('تجاهلها', style: TextStyle(color: Colors.red))),
            if (_canHold) FilledButton(onPressed: () => Navigator.pop(ctx, 'hold'), child: const Text('علّقها ثم افتح')),
          ],
        ),
      );
      if (choice == null) return;
      if (choice == 'hold' && !await _holdCurrentInvoice()) return;
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => CreateInvoiceScreen(existingInvoice: inv)),
    );
  }

  Future<void> _showHeldInvoices() async {
    List<(Invoice, int)> list;
    try {
      list = await HeldInvoices.list();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذّر تحميل المعلّقة: $e')));
      return;
    }
    if (!mounted) return;
    if (list.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا توجد فواتير معلّقة')));
      return;
    }
    final money = NumberFormat('#,##0.##', 'en');
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => DraggableScrollableSheet(
          initialChildSize: 0.55,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (ctx, scroll) => Column(children: [
            Container(
              width: 42,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(children: [
                Icon(Icons.hourglass_bottom_rounded, color: Colors.orange.shade800),
                const SizedBox(width: 8),
                Text('الفواتير المعلّقة (${list.length})', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const Spacer(),
                const Text('لا تؤثر على المخزون ولا الديون حتى تُحفظ', style: TextStyle(fontSize: 11.5, color: Colors.black45)),
              ]),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scroll,
                padding: const EdgeInsets.all(12),
                itemCount: list.length,
                itemBuilder: (ctx, i) {
                  final (inv, n) = list[i];
                  final who = inv.customerName.isEmpty ? 'بلا عميل' : inv.customerName;
                  final t = inv.lastModifiedAt;
                  final when = '${t.year}/${t.month}/${t.day}  ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: Color(0xFFE3E9F1)),
                    ),
                    child: ListTile(
                      onTap: () {
                        Navigator.pop(ctx);
                        _openHeld(inv);
                      },
                      leading: CircleAvatar(
                        backgroundColor: Colors.orange.shade50,
                        child: Icon(Icons.pause_rounded, color: Colors.orange.shade800),
                      ),
                      title: Text(who, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('$when  •  $n بند  •  ${inv.paymentType}${(inv.createdByUsername ?? '').isNotEmpty ? '  •  ${inv.createdByUsername}' : ''}'),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(money.format(inv.totalAmount), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                        IconButton(
                          tooltip: 'فتح',
                          icon: Icon(Icons.play_circle_fill_rounded, color: Colors.green.shade700),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _openHeld(inv);
                          },
                        ),
                        IconButton(
                          tooltip: 'حذف',
                          icon: Icon(Icons.delete_outline_rounded, color: Colors.red.shade700),
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                              context: ctx,
                              builder: (c) => AlertDialog(
                                title: const Text('حذف فاتورة معلّقة'),
                                content: Text('حذف فاتورة «$who» المعلّقة؟'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
                                  FilledButton(
                                    style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
                                    onPressed: () => Navigator.pop(c, true),
                                    child: const Text('حذف'),
                                  ),
                                ],
                              ),
                            );
                            if (ok != true) return;
                            await HeldInvoices.discard(inv);
                            list.removeAt(i);
                            setSheet(() {});
                            await _loadHeldCount();
                            if (list.isEmpty && ctx.mounted) Navigator.pop(ctx);
                          },
                        ),
                      ]),
                    ),
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
    _loadHeldCount();
  }

  void _resetInvoice() {
    try {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('فاتورة جديدة'),
          content: const Text(
              'هل تريد بدء فاتورة جديدة؟ سيتم مسح جميع البيانات الحالية.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _performReset();
              },
              child: const Text('نعم'),
            ),
          ],
        ),
      );
    } catch (e) {
      debugPrint('Error resetting invoice: $e');
    }
  }

  Future<void> _performReset() async {
    try {
      setState(() {
        customerNameController.clear();
        customerPhoneController.clear();
        customerAddressController.clear();
        installerNameController.clear();
        _loadFounderDefaultRate();
        _productSearchController.clear();
        _quantityController.clear();
        paidAmountController.clear();
        discountController.clear();
        discount = 0.0;
        _selectedProduct = null;
        paymentType = 'نقد';
        selectedDate = DateTime.now();
        invoiceItems.clear(); // حذف جميع الأصناف فورًا
        final dead = List.of(focusNodesList);
        focusNodesList.clear();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          for (final node in dead) {
            node.dispose();
          }
        });
        _searchResults.clear();
        _totalAmountController.text = '0';
        savedOrSuspended = false;
      });
      
      await storage.delete(key: SeatService.key('temp_invoice_data'));

      // بعد ثانية واحدة أضف عنصر فارغ جديد
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          setState(() {
            invoiceItems.add(InvoiceItem(
              invoiceId: 0,
              productName: '',
              unit: '',
              unitPrice: 0.0,
              appliedPrice: 0.0,
              itemTotal: 0.0,
              uniqueId: 'placeholder_${DateTime.now().microsecondsSinceEpoch}',
            ));
            focusNodesList.add(LineItemFocusNodes());
          });
        }
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم بدء فاتورة جديدة')),
      );
    } catch (e) {
      debugPrint('Error performing reset: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء بدء فاتورة جديدة: $e')),
        );
      }
    }
  }


  // دالة الحفظ التلقائي للفواتير المعلقة
  Future<void> autoSaveSuspendedInvoice() async {
    // المزوّد يؤخذ قبل أي انتظار: إغلاق الشاشة أثناء الحفظ لا يقطع تحديث الفاتورة
    final appProvider = context.read<AppProvider>();
    try {
      if (invoiceToManage == null ||
          invoiceToManage!.status != 'معلقة' ||
          (invoiceToManage?.isLocked ?? false)) {
        return;
      }
      // 🛡️ فاتورة من نسخة احتياطية مستعادة والجهاز لم يلحق بالبقية: لا حفظ
      // تلقائي (كان سيغيّر أصنافها ثم يُرفض تحديث الفاتورة نفسها — حفظ ناقص)
      if (await db.isRestoredRecordLocked('invoices', invoiceToManage!.id!)) return;
      Customer? customer;
      if (customerNameController.text.trim().isNotEmpty) {
        final customers = await db.getAllCustomers();
        try {
          // 🛡️ الاسم (بتجاهل المسافات) يحدد الحساب — الهاتف لا يفرّق بين حسابين
          final key = customerNameController.text.replaceAll(' ', '');
          customer = customers.firstWhere((c) => c.name.replaceAll(' ', '') == key);
        } catch (e) {
          customer = null;
        }
        // لا تنشئ عميل جديد هنا، فقط استخدم الموجود إن وجد
      }
      double currentTotalAmount =
          invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal);
      // تضمين أجور التحميل في الإجمالي الفعلي عند الحفظ/التعديل
      final double loadingFee =
          double.tryParse(loadingFeeController.text.replaceAll(',', '')) ??
              0.0;
      double paid =
          double.tryParse(paidAmountController.text.replaceAll(',', '')) ??
              0.0;
      double totalAmount = (currentTotalAmount + loadingFee) - discount;
      Invoice invoice = invoiceToManage!.copyWith(
        customerName: customerNameController.text,
        customerPhone: customerPhoneController.text,
        customerAddress: customerAddressController.text,
        installerName: installerNameController.text.isEmpty
            ? null
            : installerNameController.text,
        invoiceDate: selectedDate,
        paymentType: paymentType,
        totalAmount: totalAmount,
        discount: discount,
        amountPaidOnInvoice: paid,
        loadingFee: loadingFee,
        lastModifiedAt: DateTime.now(),
        customerId: customer?.id,
        // status: 'معلقة',
        isLocked: false,
      );
      int invoiceId = invoiceToManage!.id!;
      // حذف جميع أصناف الفاتورة القديمة وإضافة الجديدة
      final oldItems = await db.getInvoiceItems(invoiceId);
      for (var oldItem in oldItems) {
        await db.deleteInvoiceItem(oldItem.id!);
      }
      for (var item in invoiceItems) {
        item.invoiceId = invoiceId;
        await db.insertInvoiceItem(item);
      }
      await appProvider.updateInvoice(invoice);
      if (!mounted) return;
      setState(() {
        invoiceToManage = invoice;
      });
    } catch (e) {
      debugPrint('Auto-save suspended invoice error: $e');
    }
  }

  // 🔒 التحقق من المخزون عند الكتابة اليدوية في شريط الإدخال
  void _validateEntryStockByManualName(String name) {
    if (_allowNegativeStock) {
      if (_isEntryLocked) setState(() => _isEntryLocked = false);
      return;
    }
    
    final sanitizedInput = name.trim().replaceAll(' ', '');
    if (sanitizedInput.isEmpty) {
       if (_isEntryLocked) setState(() => _isEntryLocked = false);
       return;
    }

    Product? matchingProduct;
    try {
      // مقارنة الاسم بدون فواصل كما طلب المستخدم
      matchingProduct = (_allProductsForUnits ?? []).firstWhere(
        (p) => p.name.trim().replaceAll(' ', '') == sanitizedInput,
      );
    } catch (_) {}

    final shouldLock = matchingProduct != null && matchingProduct.stockQuantity <= 0;
    
    if (shouldLock != _isEntryLocked) {
      setState(() {
        _isEntryLocked = shouldLock;
      });
      
      if (shouldLock) {
         ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ هذا الصنف نافذ من المخزون! تم قفل الإدخال.'),
            backgroundColor: Colors.redAccent,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  // 2. أضف دالة توليد الوحدات:
  void _onProductSelected(Product product) {
    try {
      final bool isOutOfStock = product.stockQuantity <= 0;
      final bool entryLocked = isOutOfStock && !_allowNegativeStock;

      setState(() {
        _selectedProduct = product;
        _isEntryLocked = entryLocked;
        _quantityController.clear();
        _productSearchController.text = product.name;
        
        if (entryLocked) {
           ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ هذا الصنف نافذ من المخزون! تم قفل الإدخال.'),
              backgroundColor: Colors.redAccent,
              duration: Duration(seconds: 2),
            ),
          );
        }

        _currentUnitHierarchy = [];
        currentUnitOptions = [];
        // 🔧 استخدام method موجود في Product model لجلب جميع الوحدات
        final allUnits = product.getAllUnitLevels();
        if (allUnits.isNotEmpty) {
          currentUnitOptions = allUnits;
          selectedUnitForItem = allUnits.first;
          _currentUnitHierarchy = product.getUnitHierarchyList();
        } else {
          // Fallback: إذا لم يكن هناك هرمي، استخدم الوحدة الأساسية
          final baseUnit = product.unit == 'piece' ? 'قطعة' : (product.unit == 'meter' ? 'متر' : product.unit);
          currentUnitOptions = [baseUnit];
          selectedUnitForItem = baseUnit;
          _currentUnitHierarchy = [];
        }
        debugPrint('DEBUG: product.unitHierarchy = \u001b[32m${product.unitHierarchy}\u001b[0m');
        debugPrint('DEBUG: currentUnitOptions = \u001b[36m$currentUnitOptions\u001b[0m');
        // 🔍 تشخيص تحويل الوحدات — لماذا قد لا يتغير السعر للموزونات
        debugPrint('🔍 [تشخيص-اختيار-منتج] "${product.name}" (id=${product.id})');
        debugPrint('    unit="${product.unit}" | isWeighable=${product.isWeighable} | baseWeight=${product.baseWeight}');
        debugPrint('    unitHierarchy=${product.unitHierarchy}');
        debugPrint('    الوحدات المتاحة: $currentUnitOptions | المحددة: $selectedUnitForItem');
        debugPrint('    price1=${product.price1} | costPrice=${product.costPrice}');
        double? newPriceLevel;
        switch (_selectedListType) {
          case 'مفرد':
            newPriceLevel = product.price1;
            break;
          case 'مفرد 2':
            newPriceLevel = product.price2;
            break;
          case 'منزل':
            newPriceLevel = product.price3;
            break;
          case 'جملة':
            newPriceLevel = product.price4;
            break;
          case 'جملة 2':
            newPriceLevel = product.price5;
            break;
          case 'أخرى':
            newPriceLevel = product.price6;
            break;
          default:
            newPriceLevel = product.price1;
        }
        if (newPriceLevel == null || newPriceLevel == 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('المنتج المحدد لا يملك سعر "$_selectedListType".'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        suppressSearch = true;
        _productSearchController.text = product.name;
        _searchResults = [];
        quantityAutofocus = true;
      });
      
      // 🧠 تحديث سياق البحث الذكي
      SmartSearchService.instance.addProductToSession(product.id, product.name);
      
      // 💰 ملء السعر تلقائياً حسب نوع القائمة المختارة
      _updatePriceForSelectedProduct(product);
      
      // 🔧 نقل التركيز إلى حقل الكمية العلوي بعد اختيار المنتج
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _quantityFocusNode.requestFocus();
        }
      });
    } catch (e) {
      debugPrint('Error selecting product: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء اختيار المنتج: $e')),
        );
      }
    }
  }

  // دالة مساعدة لبناء سلسلة التحويل للوحدة المختارة
  String buildUnitConversionString(
      InvoiceItem item, List<Product> allProducts) {
    // المنتجات التي تباع بالامتار
    if (item.unit == 'meter') {
      if (item.saleType == 'لفة' && item.unitsInLargeUnit != null) {
        return item.unitsInLargeUnit!.toString();
      } else {
        return '';
      }
    }
    // المنتجات التي تباع بالقطعة ولها تسلسل هرمي
    final product = allProducts.firstWhere(
      (p) => p.name == item.productName,
      orElse: () => Product(
        id: null,
        name: item.productName,
        unit: item.unit,
        unitPrice: item.unitPrice,
        costPrice: null,
        piecesPerUnit: null,
        lengthPerUnit: null,
        price1: item.unitPrice,
        createdAt: DateTime.now(),
        lastModifiedAt: DateTime.now(),
      ),
    );
    if (product.unitHierarchy == null || product.unitHierarchy!.isEmpty) {
      return item.unitsInLargeUnit?.toString() ?? '';
    }
    try {
      final List<dynamic> hierarchy =
          json.decode(product.unitHierarchy!.replaceAll("'", '"'));
      // ابحث عن تسلسل التحويل للوحدة المختارة
      List<String> factors = [];
      for (int i = 0; i < hierarchy.length; i++) {
        final unitName = hierarchy[i]['unit_name'] ?? hierarchy[i]['name'];
        final quantity = hierarchy[i]['quantity'];
        factors.add(quantity.toString());
        if (unitName == item.saleType) {
          break;
        }
      }
      if (factors.isEmpty) {
        return item.unitsInLargeUnit?.toString() ?? '';
      }
      return factors.join(' × ');
    } catch (e) {
      return item.unitsInLargeUnit?.toString() ?? '';
    }
  }

  void _recalculateTotals() {
    double itemsTotal = invoiceItems.fold(0, (sum, item) => sum + item.itemTotal);
    // إضافة رسوم التحميل إلى الإجمالي المعروض
    final double loadingFee = double.tryParse(loadingFeeController.text.replaceAll(',', '')) ?? 0.0;
    double total = itemsTotal + loadingFee;
    _totalAmountController.text = formatNumber(total);
    if (paymentType == 'نقد') {
      paidAmountController.text = formatNumber(total - discount);
    }
    setState(() {});
    _scheduleLiveDebtSync();
  }

  Future<void> _syncLiveDebt() async {
    try {
      // متاح فقط للفواتير الموجودة ولها عميل
      if (invoiceToManage == null || invoiceToManage!.id == null) return;
      
      // 🔧 إصلاح: لا تنشئ معاملات invoice_live_update للفواتير المحفوظة
      // المعاملات يجب أن تُنشأ فقط عند الحفظ الفعلي في saveInvoice
      // هذا يمنع إنشاء معاملات زائدة عند فتح الفاتورة للتعديل
      if (invoiceToManage!.status == 'محفوظة') {
        return;
      }
      
      final int invoiceId = invoiceToManage!.id!;
      int? customerId = invoiceToManage!.customerId;
      if (customerId == null) {
        // حاول إيجاد العميل بالاسم/الهاتف إذا لم يكن مرتبطاً
        if (customerNameController.text.trim().isEmpty) return;
        final customer = await db.findCustomerByNormalizedName(
          customerNameController.text.trim(),
          phone: customerPhoneController.text.trim().isEmpty
              ? null
              : customerPhoneController.text.trim(),
        );
        if (customer == null || customer.id == null) return;
        customerId = customer.id;
      }
      final int resolvedCustomerId = customerId!;

      // تحقق مما إذا كانت هناك معاملة دين موجودة بالفعل لهذه الفاتورة
      // لتجنب إنشاء معاملات مكررة
      final existingDebtTransaction = await db.getInvoiceDebtTransaction(invoiceId);
      if (existingDebtTransaction != null) {
        // تم بالفعل إنشاء معاملة دين لهذه الفاتورة، لا تقم بإنشاء أخرى
        return;
      }

      double newContribution = 0.0;
      if (paymentType == 'دين') {
        // 🔧 حساب المتبقي بناءً على القيم الحالية في الشاشة (وليس القيم المحفوظة)
        // هذا يضمن أن الخصم الجديد يُؤخذ بعين الاعتبار
        final double itemsTotal = invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal);
        final double loadingFee = double.tryParse(loadingFeeController.text.replaceAll(',', '')) ?? 0.0;
        final double currentTotalAmount = itemsTotal + loadingFee - discount; // الإجمالي بعد الخصم
        final double paidAmount = double.tryParse(paidAmountController.text.replaceAll(',', '')) ?? 0.0;
        final double remaining = currentTotalAmount - paidAmount;
        newContribution = remaining.clamp(0.0, double.infinity);
      } else {
        newContribution = 0.0;
      }

      await db.setInvoiceDebtContribution(
        invoiceId: invoiceId,
        customerId: resolvedCustomerId,
        newContribution: newContribution,
        note: 'تعديل حي لمساهمة فاتورة #$invoiceId',
      );
    } catch (e) {
      // لا تُظهر خطأ للمستخدم أثناء التعديل الحي؛ فقط سجّل
      debugPrint('live debt sync error: $e');
    }
  }

  void _scheduleLiveDebtSync() {
    try {
      liveDebtTimer?.cancel();
      liveDebtTimer = Timer(const Duration(milliseconds: 500), _syncLiveDebt);
    } catch (e) {
      debugPrint('schedule live sync error: $e');
    }
  }

  // ⚠️ حُذفت _persistPaymentTypeLightweight.
  //
  // كانت تكتب amount_paid_on_invoice في جدول الفواتير بلا أي معاملة دين
  // مقابلة، فتُحدث فرقاً دائماً بين الفاتورة وسجل الديون. لم تكن مستدعاة من
  // أي مكان (كود ميت)، لكنها بقيت قنبلة لمن يربطها بزر لاحقاً.
  // المبلغ المسدد لا يُكتب إلا من saveInvoice، ومعه الحارس المحاسبي.

  // ═══════════════════════════════════════════════════════════════════════════
  // 🎨 Helper: بناء صف إجمالي
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildTotalRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
        Text('$value د.ع', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🎨 الشريط الجانبي: المجاميع، الدفع، والإجراءات
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildSidebar(BuildContext context) {
    // ✅ Always show sidebar - removed placeholder message per user request

    final totalBeforeDiscount = invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal);
    final total = totalBeforeDiscount - discount;
    double enteredPaidAmount = double.tryParse(paidAmountController.text.replaceAll(',', '')) ?? 0;
    
    // حساب التسويات
    final double cashSettlements = _invoiceAdjustments
        .where((a) => (a.settlementPaymentType ?? 'نقد') == 'نقد')
        .fold(0.0, (sum, a) => sum + a.amountDelta);
        

    final double totalAfterAdjustments = total + (_invoiceAdjustments.isNotEmpty ? _totalSettlementAmount : 0.0);
    
    double displayedPaidAmount = enteredPaidAmount;
    double displayedRemainingAmount = totalAfterAdjustments - displayedPaidAmount;

    if (paymentType == 'نقد') {
      displayedPaidAmount = totalAfterAdjustments;
      displayedRemainingAmount = 0;
    } else {
      displayedPaidAmount = enteredPaidAmount + cashSettlements;
      displayedRemainingAmount = totalAfterAdjustments - displayedPaidAmount;
    }
    
    // إضافة أجور التحميل
    double loadingFee = double.tryParse(loadingFeeController.text.replaceAll(',', '')) ?? 0.0;
    final totalWithLoading = total + loadingFee;
    final totalAfterAdjustmentsWithLoading = totalWithLoading + (_invoiceAdjustments.isNotEmpty ? _totalSettlementAmount : 0.0);
    
    if (paymentType == 'نقد') {
        displayedPaidAmount = totalAfterAdjustmentsWithLoading;
    } else {
        displayedRemainingAmount = totalAfterAdjustmentsWithLoading - displayedPaidAmount;
    }

    // ألوان التصميم الجديد
    const Color bgColor = Color(0xFFF7FAFC); // Light gray background
    
    return Container(
      color: bgColor,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 🧱 رصيد العميل وسقف دينه وحسمه + حقول إضافية/مرتجع للفاتورة المحفوظة
            ErpInvoiceSidePanel(
              customerName: customerNameController.text,
              invoiceTotal: total,
              isDebt: paymentType == 'دين',
              invoiceId: invoiceToManage?.status == 'محفوظة' ? invoiceToManage?.id : null,
            ),
            // ═══════════════════════════════════════════════════════════════
            // 1. تفاصيل الإجماليات (داخل الـ ScrollView لتصعد للأعلى عند السحب)
            // ═══════════════════════════════════════════════════════════════
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // الإجمالي قبل الخصم
                  _buildTotalRow('الإجمالي قبل الخصم', formatNumber(totalBeforeDiscount), Colors.grey[700]!),
                  const Divider(height: 16),
                  // الإجمالي بعد الخصم
                  _buildTotalRow('الإجمالي بعد الخصم', formatNumber(total), Colors.blue[700]!),
                  const Divider(height: 16),
                  // المبلغ المسدد
                  _buildTotalRow('المبلغ المسدد', formatNumber(displayedPaidAmount), Colors.green[700]!),
                  const Divider(height: 16),
                  // المبلغ المتبقي
                  _buildTotalRow('المبلغ المتبقي', formatNumber(displayedRemainingAmount), 
                      displayedRemainingAmount > 0 ? Colors.red[700]! : Colors.green[700]!),
                ],
              ),
            ),
    
                  
                  // 🧩 أجور التحميل والنقل — تُكتب هنا مباشرة
                  if (!isViewOnly ||
                      (double.tryParse(loadingFeeController.text.replaceAll(',', '')) ?? 0) > 0) ...[
                    _buildStyledInputField(
                      controller: loadingFeeController,
                      label: 'أجور التحميل والنقل',
                      icon: Icons.local_shipping_outlined,
                      enabled: !isViewOnly && !(invoiceToManage?.isLocked ?? false),
                      onChanged: (_) {
                        setState(() {
                          _guardDiscount();
                          _updatePaidAmountIfCash();
                          _calculateProfit();
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                  ],

                  // الخصم المسموح
                  _buildStyledInputField(
                    controller: discountController,
                    label: 'الخصم المسموح',
                    icon: Icons.local_offer_outlined,
                    enabled: !isViewOnly,
                    showWarningIcon: true,
                    onChanged: (val) {
                      setState(() {
                        discount = double.tryParse(val.replaceAll(',', '')) ?? 0.0;
                        _guardDiscount();
                        _updatePaidAmountIfCash();
                        _calculateProfit();
                      });
                    },
                  ),
                  const SizedBox(height: 20),
                  
                  // طريقة الدفع
                  if (!isViewOnly) ...[
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  paymentType = 'نقد';
                                  _updatePaidAmountIfCash();
                                  _autoSave();
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                decoration: BoxDecoration(
                                  color: paymentType == 'نقد' ? const Color(0xFFE6F7F2) : Colors.transparent,
                                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(12)),
                                  border: paymentType == 'نقد' 
                                    ? Border.all(color: const Color(0xFF48BB78), width: 1.5)
                                    : null,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.attach_money, 
                                      color: paymentType == 'نقد' ? const Color(0xFF48BB78) : Colors.grey,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 6),
                                    Text('نقد',
                                      style: TextStyle(
                                        color: paymentType == 'نقد' ? const Color(0xFF48BB78) : Colors.grey.shade700,
                                        fontWeight: paymentType == 'نقد' ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                    if (paymentType == 'نقد')
                                      const Padding(
                                        padding: EdgeInsets.only(right: 4),
                                        child: Icon(Icons.check, color: Color(0xFF48BB78), size: 16),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  paymentType = 'دين';
                                  paidAmountController.text = formatNumber(0);
                                  _autoSave();
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                decoration: BoxDecoration(
                                  color: paymentType == 'دين' ? const Color(0xFFE8F4FD) : Colors.transparent,
                                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
                                  border: paymentType == 'دين' 
                                    ? Border.all(color: const Color(0xFF4299E1), width: 1.5)
                                    : null,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.account_balance_wallet_outlined, 
                                      color: paymentType == 'دين' ? const Color(0xFF4299E1) : Colors.grey,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 6),
                                    Text('دين',
                                      style: TextStyle(
                                        color: paymentType == 'دين' ? const Color(0xFF4299E1) : Colors.grey.shade700,
                                        fontWeight: paymentType == 'دين' ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                    if (paymentType == 'دين')
                                      const Padding(
                                        padding: EdgeInsets.only(right: 4),
                                        child: Icon(Icons.check, color: Color(0xFF4299E1), size: 16),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // المبلغ الواصل (المدفوع) - يظهر فقط في حالة الدين
                    if (paymentType == 'دين') ...[
                      Text('المبلغ الواصل (المدفوع)', 
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                      const SizedBox(height: 6),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Icon(Icons.check_circle_outline, color: Colors.grey, size: 20),
                            ),
                            Expanded(
                              child: TextFormField(
                                controller: paidAmountController,
                                decoration: const InputDecoration(
                                  hintText: '0',
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.symmetric(vertical: 16),
                                ),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [ThousandSeparatorDecimalInputFormatter()],
                                textAlign: TextAlign.left,
                                style: const TextStyle(fontSize: 16),
                                onChanged: (val) => setState(() {}),
                              ),
                            ),
                            // زر تسديد كامل المبلغ
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  paidAmountController.text = formatNumber(totalAfterAdjustmentsWithLoading);
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                margin: const EdgeInsets.only(left: 8),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text('%100', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ],
                  
                  // المتبقي على العميل (يظهر دائماً في حالة الدين)
                  if (paymentType == 'دين')
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFF5F5), Color(0xFFFED7D7)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFEB2B2), width: 1),
                      ),
                      child: Column(
                        children: [
                          Text('المتبقي على العميل', 
                            style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                formatNumber(displayedRemainingAmount),
                                style: TextStyle(
                                  color: Colors.red.shade700,
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text('د.ع', 
                                style: TextStyle(color: Colors.red.shade500, fontSize: 14)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  // 3. زر الحفظ في الأسفل
                  if (!isViewOnly) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton.icon(
                        onPressed: isSaving ? null : saveInvoice,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF48BB78), // Green
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.save_alt, size: 22),
                        label: const Text('حفظ الفاتورة', 
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
  
  
  // Helper: Styled Input Field
  Widget _buildStyledInputField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool enabled = true,
    bool showWarningIcon = false,
    Function(String)? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
            if (showWarningIcon) ...[
              const SizedBox(width: 4),
              Icon(Icons.warning_amber_rounded, size: 14, color: Colors.amber.shade700),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Icon(icon, color: Colors.grey.shade400, size: 20),
              ),
              Expanded(
                child: TextFormField(
                  controller: controller,
                  enabled: enabled,
                  decoration: const InputDecoration(
                    hintText: '0',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 14),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [ThousandSeparatorDecimalInputFormatter()],
                  textAlign: TextAlign.left,
                  style: const TextStyle(fontSize: 16),
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProductEntryBar(BuildContext context) {
      if (isViewOnly) return const SizedBox.shrink();
      
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        decoration: const BoxDecoration(
            color: Colors.white, // 🧩 شريط إدخال نظيف فوق بطاقة الجدول
            border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
        ),
        child: Row(
            children: [
                // 1. البحث عن صنف
                Expanded(
                  flex: 1,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                            Text('البحث عن صنف', 
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                            const SizedBox(height: 4),
                            Stack(
                              children: [
                                SizedBox(
                                    height: 48,
                                    child: LayoutBuilder(
                                      builder: (context, constraints) {
                                        return RawAutocomplete<Product>(
                                            focusNode: _searchFocusNode,
                                            textEditingController: _productSearchController,
                                            optionsBuilder: (TextEditingValue textEditingValue) async {
                                                final query = textEditingValue.text;
                                                if (query.isEmpty) return const Iterable<Product>.empty();
                                                
                                                bool isNumeric = double.tryParse(query) != null;
                                                
                                                if (isNumeric) {
                                                    return await DatabaseService().searchProductsByIdPrefix(query);
                                                } else {
                                                    final currentNames = invoiceItems
                                                        .where((it) => it.productName.trim().isNotEmpty)
                                                        .map((it) => it.productName.trim())
                                                        .toList();
                                                    return await SmartSearchService.instance.smartSearch(
                                                      query,
                                                      currentInvoiceProductNames: currentNames,
                                                    );
                                                }
                                            },
                                            displayStringForOption: (Product p) => p.name,
                                            optionsViewBuilder: (context, onSelected, options) {
                                                return Align(
                                                    alignment: Alignment.topRight,
                                                    child: Material(
                                                        elevation: 8,
                                                        borderRadius: BorderRadius.circular(12),
                                                        // 🔧 اللون على الـ Material نفسه — DecoratedBox فوقه
                                                        // كان يحجب خلفية ListTile ورشّ الحبر (assertion)
                                                        color: Colors.white,
                                                        child: Container(
                                                            width: constraints.maxWidth,
                                                            constraints: const BoxConstraints(maxHeight: 300),
                                                            child: ListView.builder(
                                                                shrinkWrap: true,
                                                                itemCount: options.length,
                                                                itemBuilder: (context, index) {
                                                                    final product = options.elementAt(index);
                                                                    return ListTile(
                                                                        title: Text(product.name, 
                                                                            style: const TextStyle(fontWeight: FontWeight.w600)),
                                                                        subtitle: Row(
                                                                          children: [
                                                                            Text(
                                                                                'السعر: ${formatNumber(product.price1)} | المخزون: ${formatNumber(product.stockQuantity)}',
                                                                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                                                            if (product.stockQuantity <= 0)
                                                                              const Padding(
                                                                                padding: EdgeInsets.only(right: 6),
                                                                                child: Tooltip(
                                                                                  message: 'غير متوفر في المخزون',
                                                                                  child: Icon(Icons.warning_amber_rounded, color: Colors.red, size: 18),
                                                                                ),
                                                                              ),
                                                                          ],
                                                                        ),
                                                                        leading: CircleAvatar(
                                                                            radius: 18,
                                                                            backgroundColor: const Color(0xFFE6F7F2),
                                                                            child: Text('#${product.id}', 
                                                                                style: const TextStyle(fontSize: 10, color: Color(0xFF48BB78), fontWeight: FontWeight.bold)),
                                                                        ),
                                                                        onTap: () => onSelected(product),
                                                                    );
                                                                },
                                                            ),
                                                        ),
                                                    ),
                                                );
                                            },
                                            fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                                                return Container(
                                                    decoration: BoxDecoration(
                                                        color: Colors.white,
                                                        borderRadius: BorderRadius.circular(24),
                                                        boxShadow: [
                                                            BoxShadow(
                                                                color: Colors.black.withValues(alpha: 0.05),
                                                                blurRadius: 8,
                                                                offset: const Offset(0, 2),
                                                            ),
                                                        ],
                                                    ),
                                                    child: TextField(
                                                        controller: controller,
                                                        focusNode: focusNode,
                                                        decoration: const InputDecoration(
                                                            hintText: 'أدخل اسم المنتج أو الرمز...',
                                                            hintStyle: TextStyle(color: Colors.grey, fontSize: 13),
                                                            prefixIcon: Icon(Icons.search, color: Colors.grey),
                                                            border: InputBorder.none,
                                                            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                                        ),
                                                        textAlign: TextAlign.right,
                                                        style: const TextStyle(fontSize: 14),
                                                        onChanged: (val) {
                                                            _validateEntryStockByManualName(val); // 🔍 تحقق عند كل تغييرة
                                                        },
                                                        onSubmitted: (val) {
                                                            _validateEntryStockByManualName(val); // 🔍 تحقق نهائي
                                                            if (!_isEntryLocked) {
                                                                _quantityFocusNode.requestFocus();
                                                            }
                                                        },
                                                    ),
                                                );
                                            },
                                            onSelected: (Product selection) {
                                                _onProductSelected(selection);
                                            },
                                        );
                                      }
                                    ),
                                ),
                                if (_isEntryLocked)
                                  const Positioned(
                                    left: 45,
                                    top: 14,
                                    child: Icon(Icons.block, color: Colors.red, size: 20),
                                  ),
                              ],
                            ),
                        ],
                    ),
                ),
                const SizedBox(width: 16),

                // 2. الكمية
                _buildEntryField(
                    label: 'العدد',
                    width: 100, 
                    controller: _quantityController,
                    focusNode: _quantityFocusNode,
                    enabled: !_isEntryLocked, 
                    initialValue: '1',
                    onSubmitted: () {
                      // 🔧 Fix: فتح قائمة الوحدات إذا كان هناك أكثر من وحدة
                      if (currentUnitOptions.length > 1) {
                         _showUnitSelectionForEntryBar();
                      } else {
                         _priceFocusNode.requestFocus();
                      }
                    },
                ),
                const SizedBox(width: 12),

                // 2.5. نوع الوحدة
                Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                        Text('الوحدة', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                        const SizedBox(height: 4),
                        Container(
                            key: _entryBarUnitDropdownKey, // 🔧 مفتاح لجلب موقع القائمة
                            height: 48,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                    value: currentUnitOptions.contains(selectedUnitForItem) 
                                        ? selectedUnitForItem 
                                        : (currentUnitOptions.isNotEmpty ? currentUnitOptions.first : 'قطعة'),
                                    items: (currentUnitOptions.isEmpty ? ['قطعة'] : currentUnitOptions)
                                        .map((unit) => DropdownMenuItem(
                                            value: unit,
                                            child: Text(unit, style: const TextStyle(fontSize: 14)),
                                        ))
                                        .toList(),
                                    onChanged: _isEntryLocked ? null : (value) {
                                        if (value != null) {
                                            debugPrint('🔍 [تشخيص-تغيير-وحدة-شريط] "$value" '
                                                '(السابقة: $selectedUnitForItem) للمنتج: ${_selectedProduct?.name}');
                                            debugPrint('    السعر قبل التغيير: ${_priceController.text}');
                                            setState(() {
                                                selectedUnitForItem = value;
                                                if (_selectedProduct != null) {
                                                    _updatePriceForSelectedProduct(_selectedProduct!);
                                                }
                                            });
                                        }
                                    },
                                ),
                            ),
                        ),
                    ],
                ),
                const SizedBox(width: 12),
                
                // 3. السعر (مع تحذير التكلفة)
                _buildPriceEntryFieldWithWarning(),
                const SizedBox(width: 12),

                // 3.5 🏷️ الخصم (نسبة/مبلغ) + 🎁 هدية — يُخفى إن أُخفي عمود الخصم من الإعدادات
                if (InvoiceEntryLayout.current.show('discount')) ...[
                  _buildEntryDiscountField(),
                  const SizedBox(width: 12),
                ],
                
                // 4. زر الإضافة
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                          color: _isEntryLocked ? Colors.grey : const Color(0xFF48BB78), 
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                              if (!_isEntryLocked)
                                BoxShadow(
                                    color: const Color(0xFF48BB78).withValues(alpha: 0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                ),
                          ],
                      ),
                      child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: _isEntryLocked ? null : _addInvoiceItem, 
                              child: const Center(
                                  child: Icon(Icons.add, color: Colors.white, size: 28),
                              ),
                          ),
                      ),
                  ),
                ),
            ],
        ),
      );
  }
  
  // 🔧 دالة لفتح قائمة الوحدات في شريط البحث العلوي (مشابهة لـ _showSaleTypeMenu في EditableInvoiceItemRow)
  Future<void> _showUnitSelectionForEntryBar() async {
    if (currentUnitOptions.length <= 1) {
      _priceFocusNode.requestFocus();
      return;
    }

    final RenderBox? renderBox = _entryBarUnitDropdownKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) {
      _priceFocusNode.requestFocus();
      return;
    }

    final Offset offset = renderBox.localToGlobal(Offset.zero);
    final Size size = renderBox.size;

    // فتح قائمة منبثقة مع دعم الكيبورد
    final String? selected = await showDialog<String>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (BuildContext dialogContext) {
        return _SaleTypeDropdownDialog(
          options: currentUnitOptions,
          initialValue: selectedUnitForItem,
          position: offset,
          size: size,
        );
      },
    );

    if (selected != null && selected != selectedUnitForItem) {
      setState(() {
        selectedUnitForItem = selected;
        if (_selectedProduct != null) {
          _updatePriceForSelectedProduct(_selectedProduct!);
        }
      });
    }

    // الانتقال لحقل السعر بعد الاختيار
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _priceFocusNode.requestFocus();
    });
  }

  // 🔧 Fix 3: Helper method للتحقق من أن السعر أقل من التكلفة
  // 🔧 تم إعادة كتابة هذه الدالة لتستخدم نفس منطق _isPriceBelowCost في الصفوف
  bool _isEntryPriceBelowCost() {
    if (_selectedProduct == null) return false;
    
    final double enteredPrice = _entryNetPrice; // 🏷️ الصافي بعد خصم الصنف
    if (enteredPrice <= 0) return false;
    
    double? effectiveCostPerUnit;
    final product = _selectedProduct!;
    final String saleType = selectedUnitForItem;
    
    // جرب من unit_costs أولاً
    try {
      final Map<String, double> unitCosts = product.getUnitCostsMap();
      if (unitCosts.containsKey(saleType) && unitCosts[saleType]! > 0) {
        effectiveCostPerUnit = unitCosts[saleType];
      }
    } catch (_) {}
    
    // ثم من costPrice الأساسي للمنتج مع حساب المضاعف من الهرمية
    if (effectiveCostPerUnit == null && product.costPrice != null && product.costPrice! > 0) {
      // إذا كان البيع بالوحدة الأساسية
      if ((product.unit == 'piece' && saleType == 'قطعة') ||
          (product.unit == 'meter' && saleType == 'متر')) {
        effectiveCostPerUnit = product.costPrice;
      }
      // للمتر و"لفة": استخدم طول اللفة
      else if (product.unit == 'meter' && saleType == 'لفة') {
        final double lengthPerUnit = product.lengthPerUnit ?? 1.0;
        effectiveCostPerUnit = product.costPrice! * lengthPerUnit;
      }
      // إذا كان البيع بوحدة كبيرة، احسب التكلفة من الهرمية
      else if (saleType != 'قطعة' && saleType != 'متر') {
        double multiplier = 1.0;
        
        // 🔧 Fix: استخدام unitHierarchy للحساب الصحيح
        if (product.unitHierarchy != null && product.unitHierarchy!.isNotEmpty) {
          try {
            // محاولة تحليل JSON مع دعم علامات الاقتباس المفردة والمزدوجة
            List<dynamic> hierarchy;
            try {
              hierarchy = json.decode(product.unitHierarchy!);
            } catch (_) {
              hierarchy = json.decode(product.unitHierarchy!.replaceAll("'", '"'));
            }

            for (final level in hierarchy) {
              final String unitName = (level['unit_name'] ?? level['name'] ?? '').toString();
              final double qty = (level['quantity'] is num)
                  ? (level['quantity'] as num).toDouble()
                  : double.tryParse(level['quantity'].toString()) ?? 1.0;
              multiplier *= qty;
              if (unitName == saleType) break;
            }
          } catch (_) {
            // استخدام المضاعف المحسوب من currentUnitOptions إذا توفر
            // fallback: ابحث في الهرمية المحفوظة
            for (final unitInfo in _currentUnitHierarchy) {
              if (unitInfo['unit_name'] == saleType || unitInfo['name'] == saleType) {
                multiplier = (unitInfo['quantity'] as num?)?.toDouble() ?? 1.0;
                break;
              }
            }
          }
        } else {
          // fallback: ابحث في الهرمية المحفوظة
          for (final unitInfo in _currentUnitHierarchy) {
            if (unitInfo['unit_name'] == saleType || unitInfo['name'] == saleType) {
              multiplier = (unitInfo['quantity'] as num?)?.toDouble() ?? 1.0;
              break;
            }
          }
        }
        
        effectiveCostPerUnit = product.costPrice! * multiplier;
      }
    }
    
    if (effectiveCostPerUnit == null || effectiveCostPerUnit <= 0) return false;
    
    const double eps = 1e-6;
    return (enteredPrice + eps) < effectiveCostPerUnit;
  }
  
  // 🔧 Fix 3: Price field with warning icon
  Widget _buildPriceEntryFieldWithWarning() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('السعر', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            // 🧱 أداة سريعة: أدخل الإجمالي ليُحسب السعر (الخصم والهدية لهما حقل مستقل بجانب السعر)
            if (!_isEntryLocked) ...[
              const SizedBox(width: 4),
              _entryTool(Icons.functions, 'أدخل الإجمالي ليُحسب السعر', _applyEntryTotal),
            ],
            if (_isEntryPriceBelowCost()) ...[
              const SizedBox(width: 4),
              Tooltip(
                message: 'السعر أقل من التكلفة!',
                child: Icon(Icons.warning_amber_rounded, size: 16, color: Colors.amber.shade700),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Container(
          width: 130,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: _isEntryPriceBelowCost() 
                ? Border.all(color: Colors.amber.shade700, width: 2)
                : null,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: TextFormField(
            controller: _priceController,
            focusNode: _priceFocusNode,
            enabled: !_isEntryLocked,
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [ThousandSeparatorDecimalInputFormatter()],
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            onChanged: (_) => setState(() {}), // Trigger rebuild for warning + net preview
            onFieldSubmitted: (_) {
              _addInvoiceItem();
              _searchFocusNode.requestFocus();
            },
          ),
        ),
      ],
    );
  }

  /// 🏷️ الصافي الحالي في شريط الإدخال (السعر − الخصم، أو صفر للهدية)
  double get _entryNetPrice {
    final price = safeParseDouble(_priceController.text) ?? 0.0;
    final v = safeParseDouble(_entryDiscountController.text) ?? 0.0;
    final type = _entryGift ? 'gift' : (v > 0 ? (_entryDiscountPercent ? 'percent' : 'amount') : null);
    return lineNetPrice(price, type, v);
  }

  /// 🏷️ حقل خصم الصنف + زر الهدية + معاينة الصافي (بجانب السعر في شريط الإدخال)
  Widget _buildEntryDiscountField() {
    final price = safeParseDouble(_priceController.text) ?? 0.0;
    final v = safeParseDouble(_entryDiscountController.text) ?? 0.0;
    final hasDisc = _entryGift || v > 0;
    final net = _entryNetPrice;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Text('الخصم', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(width: 6),
          // 🎁 هدية مجانية
          Tooltip(
            message: 'هدية مجانية: تخرج من المخزون بسعر صفر ويظهر سعرها الأصلي في الفاتورة',
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: _isEntryLocked ? null : () => setState(() => _entryGift = !_entryGift),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: _entryGift ? Colors.purple.shade600 : Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.card_giftcard, size: 13, color: _entryGift ? Colors.white : Colors.purple),
                  const SizedBox(width: 2),
                  Text('هدية', style: TextStyle(fontSize: 11, color: _entryGift ? Colors.white : Colors.purple)),
                ]),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 4),
        Container(
          width: 120,
          height: 48,
          decoration: BoxDecoration(
            color: _entryGift ? Colors.purple.shade50 : Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: _entryGift
              ? const Center(child: Text('مجاناً 🎁', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purple)))
              : TextField(
                  controller: _entryDiscountController,
                  enabled: !_isEntryLocked,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [ThousandSeparatorDecimalInputFormatter()],
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) {
                    _addInvoiceItem();
                    _searchFocusNode.requestFocus();
                  },
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: '0',
                    contentPadding: const EdgeInsets.only(right: 12, top: 12, bottom: 12),
                    // زر تبديل النوع: % أو مبلغ
                    suffixIcon: InkWell(
                      onTap: () => setState(() => _entryDiscountPercent = !_entryDiscountPercent),
                      child: Container(
                        width: 44,
                        alignment: Alignment.center,
                        margin: const EdgeInsets.all(6),
                        decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(16)),
                        child: Text(_entryDiscountPercent ? '%' : 'مبلغ',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green.shade800)),
                      ),
                    ),
                  ),
                ),
        ),
        if (hasDisc && price > 0)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('الصافي ${formatNumber(net)}', style: TextStyle(fontSize: 11, color: Colors.green.shade700, fontWeight: FontWeight.bold)),
          ),
      ],
    );
  }

  // 🧱 أدوات شريط الإدخال (تعدّل حقل السعر فقط — الحفظ بالمسار الأصلي)
  Widget _entryTool(IconData icon, String tip, VoidCallback onTap) => Tooltip(
        message: tip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Icon(icon, size: 15, color: Colors.blueGrey.shade600),
          ),
        ),
      );

  Future<void> _applyEntryTotal() async {
    final qty = safeParseDouble(_quantityController.text) ?? 0;
    if (qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل الكمية أولاً')));
      return;
    }
    final total = await askNumber(context, 'الإجمالي المطلوب لهذا الصنف', label: 'الإجمالي');
    if (total == null || total < 0) return;
    final newPrice = (total / qty * 100).roundToDouble() / 100;
    setState(() => _priceController.text = formatNumber(newPrice));
  }

  // Helper: Entry Field with label
  Widget _buildEntryField({
    required String label,
    required double width,
    required TextEditingController controller,
    FocusNode? focusNode,
    String? initialValue,
    bool enabled = true, // 🔒 Added enabled parameter
    VoidCallback? onSubmitted,
  }) {
    return Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
            Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            const SizedBox(height: 4),
            Container(
                width: width,
                height: 48,
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                        ),
                    ],
                ),
                child: TextFormField(
                    controller: controller,
                    focusNode: focusNode,
                    enabled: enabled, // 🔒 Use enabled status
                    decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [ThousandSeparatorDecimalInputFormatter()],
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                    onFieldSubmitted: (_) => onSubmitted?.call(),
                ),
            ),
        ],
    );
  }

  // Helper method to update price based on selected list type AND selected unit (with Smart Pricing)
  Future<void> _updatePriceForSelectedProduct(Product product) async {
      double? basePrice;
      switch (_selectedListType) {
          case 'مفرد':
              basePrice = product.price1;
              break;
          case 'مفرد 2':
              basePrice = product.price2;
              break;
          case 'منزل':
              basePrice = product.price3;
              break;
          case 'جملة':
              basePrice = product.price4;
              break;
          case 'جملة 2':
              basePrice = product.price5;
              break;
          case 'أخرى':
              basePrice = product.price6;
              break;
          default:
              basePrice = product.price1;
      }
      
      // 🧠 استشارة محرك التسعير الذكي عند إدخال صنف من جدول الفاتورة
      if (product.id != null) {
        try {
          int? custId;
          final custName = customerNameController.text.trim();
          if (custName.isNotEmpty) {
            final c = await db.findCustomerByNormalizedName(custName);
            if (c != null) custId = c.id;
          }
          final smartResult = await SmartPricingService().getSmartPriceEnhanced(
            productId: product.id!,
            customerId: custId,
            saleType: _selectedListType,
            // 🧠 بقية مواد الفاتورة: يقترح مستوى السعر نفسه (جملة مع جملة)
            invoiceItemsContext: [
              for (final it in invoiceItems)
                if (it.productId != null && it.appliedPrice > 0)
                  {'product_id': it.productId, 'applied_price': it.appliedPrice},
            ],
          );
          if (smartResult != null && smartResult.price > 0) {
            basePrice = smartResult.price;
            debugPrint('    🧠 [تشخيص-تحديث-سعر] التسعير الذكي استبدل السعر الأساسي: ${smartResult.price} (سيُضرب بالمضاعف إن وُجد)');
          }
        } catch (_) {}
      }
      
      if (basePrice == null || basePrice <= 0) {
          _priceController.clear();
          debugPrint('🔍 [تشخيص-تحديث-سعر] لا سعر أساسي — تم تفريغ الحقل (basePrice=$basePrice)');
          return;
      }

      // 🔍 تشخيص تحويل الوحدات — قرار السعر بوحدة "$selectedUnitForItem"
      debugPrint('🔍 [تشخيص-تحديث-سعر] "${product.name}" | unit="${product.unit}" | الوحدة المختارة: "$selectedUnitForItem"');
      debugPrint('    basePrice=$basePrice (قائمة: $_selectedListType) | translatedUnit="${product.translatedUnit}"');
      debugPrint('    unitHierarchy=${product.unitHierarchy != null && product.unitHierarchy!.isNotEmpty ? "موجودة (${product.unitHierarchy!.length} حرف)" : "فارغة/عدم"}');

      // 🔧 Fix 2: حساب السعر بناءً على الوحدة المختارة
      double finalPrice = basePrice;

      // إذا كانت الوحدة المختارة ليست الوحدة الأساسية
      if (selectedUnitForItem != product.translatedUnit && selectedUnitForItem != 'قطعة') {
          // للمتر واللفة
          if (product.unit == 'meter' && selectedUnitForItem == 'لفة') {
              final double lengthPerUnit = product.lengthPerUnit ?? 1.0;
              finalPrice = basePrice * lengthPerUnit;
              debugPrint('    ↪ فرع متر→لفة: ×$lengthPerUnit → $finalPrice');
          }
          // للقطعة مع هرمية الوحدات
          // 🔧 Fix: Robust JSON parsing
          else if (product.unit == 'piece' && product.unitHierarchy != null && product.unitHierarchy!.isNotEmpty) {
              try {
                  List<dynamic> hierarchy;
                  try {
                    hierarchy = json.decode(product.unitHierarchy!);
                  } catch (_) {
                    hierarchy = json.decode(product.unitHierarchy!.replaceAll("'", '"'));
                  }

                  double multiplier = 1.0;
                  for (final level in hierarchy) {
                      final String unitName = (level['unit_name'] ?? level['name'] ?? '').toString();
                      final double qty = (level['quantity'] is num)
                          ? (level['quantity'] as num).toDouble()
                          : double.tryParse(level['quantity'].toString()) ?? 1.0;
                      multiplier *= qty;
                      if (unitName == selectedUnitForItem) {
                          break;
                      }
                  }
                  finalPrice = basePrice * multiplier;
                  debugPrint('    ↪ فرع الهرمية: مضاعف=$multiplier → السعر=$finalPrice');
              } catch (e) {
                  debugPrint('    ↪ ❌ فشل حساب الهرمية: $e (السعر بقي $finalPrice)');
                  debugPrint('خطأ في حساب السعر الهيراركي: $e');
              }
          } else {
              // 🔍 هذا هو الفرع المشبوه: وحدة غير أساسية لكن لا meter ولا piece
              debugPrint('    ↪ ⚠️ لا فرع تحويل: unit="${product.unit}" ليست piece/meter '
                  '→ السعر بقي كما هو ($finalPrice) — هذا سبب خطأ الموزونات');
          }
      } else {
          debugPrint('    ↪ الوحدة المختارة هي الأساسية — السعر بلا تحويل: $finalPrice');
      }

      _priceController.text = formatNumber(finalPrice);
      debugPrint('    ✅ السعر النهائي المكتوب في الحقل: $finalPrice');
  }

  @override
  Widget build(BuildContext context) {
    // تعريف الألوان والثيم العصري
    const Color primaryColor = Color(0xFF3F51B5); // Indigo
    const Color accentColor = Color(0xFF8C9EFF); // Light Indigo Accent
    const Color textColor = Color(0xFF212121);
    const Color lightBackgroundColor = Color(0xFFF8F8F8);
    final Color successColor = Colors.green[600]!;
    final Color errorColor = Colors.red[700]!;

    // استخدم القائمة الكاملة دائمًا لعرض جميع الصفوف بما في ذلك الصف الفارغ الجديد

    // PopScope بدل WillPopScope (نفس السلوك): رجوع المستخدم يمرّ على _onWillPop
    // (حفظ مؤقت/حوار الحفظ) ولا تُغلق الشاشة إلا إذا أعادت true.
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _onWillPop() && mounted) navigator.pop(result);
      },
      child: Theme(
        data: ThemeData(
        colorScheme: ColorScheme.light(
          primary: primaryColor,
          onPrimary: Colors.white,
          secondary: accentColor,
          onSecondary: Colors.black,
          surface: Colors.white,
          onSurface: textColor,
          error: errorColor,
          onError: Colors.white,
          tertiary: successColor,
        ),
        fontFamily: 'Roboto',
        textTheme: TextTheme(
          titleLarge: const TextStyle(
              fontSize: 22.0, fontWeight: FontWeight.bold, color: Colors.white),
          titleMedium: const TextStyle(
              fontSize: 18.0, fontWeight: FontWeight.w600, color: textColor),
          bodyLarge: const TextStyle(fontSize: 16.0, color: textColor),
          bodyMedium: const TextStyle(fontSize: 14.0, color: textColor),
          labelLarge: const TextStyle(
              fontSize: 16.0, color: Colors.white, fontWeight: FontWeight.w600),
          labelMedium: TextStyle(fontSize: 14.0, color: Colors.grey[600]),
          bodySmall: TextStyle(fontSize: 12.0, color: Colors.grey[700]),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10.0),
            borderSide: BorderSide(color: Colors.grey[400]!),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10.0),
            borderSide: BorderSide(color: Colors.grey[400]!),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10.0),
            borderSide: const BorderSide(color: primaryColor, width: 2.0),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10.0),
            borderSide: BorderSide(color: errorColor, width: 2.0),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10.0),
            borderSide: BorderSide(color: errorColor, width: 2.0),
          ),
          labelStyle: TextStyle(color: Colors.grey[700], fontSize: 15.0),
          hintStyle: TextStyle(color: Colors.grey[500], fontSize: 14.0),
          contentPadding:
              const EdgeInsets.symmetric(vertical: 16.0, horizontal: 16.0),
          filled: true,
          fillColor: lightBackgroundColor,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10.0)),
            padding:
                const EdgeInsets.symmetric(vertical: 16.0, horizontal: 20.0),
            elevation: 4,
            textStyle: const TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: primaryColor,
            textStyle: const TextStyle(fontSize: 16.0, fontWeight: FontWeight.w600),
          ),
        ),
        iconTheme: IconThemeData(color: Colors.grey[700], size: 24.0),
        cardTheme: CardThemeData(
          elevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
          margin: EdgeInsets.zero,
        ),
        listTileTheme: ListTileThemeData(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          tileColor: lightBackgroundColor,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0F3460),
          foregroundColor: Colors.white,
          centerTitle: true,
          elevation: 4,
          iconTheme: IconThemeData(color: Colors.white),
          actionsIconTheme: IconThemeData(color: Colors.white),
          titleTextStyle: TextStyle(
            fontSize: 24.0,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
      child: Stack(
        children: [
          // المحتوى الرئيسي
          AbsorbPointer(
            absorbing: isSaving,
            child: Scaffold(
        backgroundColor: const Color(0xFFF3F6FB),
        appBar: AppBar(
          toolbarHeight: 60, // 🔺 Increased height for better visibility
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0F3460), Color(0xFF1B5E8C)],
                begin: Alignment.centerRight,
                end: Alignment.centerLeft,
              ),
            ),
          ),
          title: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                     // 1. Customer Name (Autocomplete)
                    SizedBox(
                      width: 250, // Fixed width for scrollable layout
                      height: 42, // 🔺 Increased Height for better visibility
                      child: Autocomplete<String>(
                        optionsBuilder: (TextEditingValue textEditingValue) async {
                          if (textEditingValue.text == '') {
                            return const Iterable<String>.empty();
                          }
                          final customers = await db.searchCustomers(textEditingValue.text);
                          return customers.map((c) => c.name).toSet();
                        },
                        fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (controller.text != customerNameController.text) {
                              controller.text = customerNameController.text;
                              controller.selection = TextSelection.fromPosition(
                                TextPosition(offset: controller.text.length),
                              );
                            }
                          });
                          return TextFormField(
                            controller: controller,
                            focusNode: focusNode,
                            enabled: !isViewOnly,
                            style: const TextStyle(color: Colors.white, fontSize: 12.5), // 🔻 Smaller Font
                            decoration: InputDecoration(
                              hintText: 'اسم العميل',
                              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
                              prefixIcon: const Icon(Icons.person_outline, color: Colors.white54, size: 18),
                              prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 0),
                              filled: true,
                              fillColor: Colors.white.withValues(alpha: 0.12),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              isDense: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none), // 🔻 Rounded
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Colors.white30, width: 0.5)),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'مطلوب';
                              }
                              return null;
                            },
                            onChanged: (val) {
                              customerNameController.text = val;
                              // تغيّر الاسم يدوياً: هاتف عُبّئ تلقائياً لعميل سابق لا يبقى
                              // (وإلا يُحفظ رقم ذلك العميل على بطاقة العميل الجديد)
                              if (_autoFilledPhone != null &&
                                  customerPhoneController.text.trim() == _autoFilledPhone) {
                                setState(() {
                                  customerPhoneController.clear();
                                  _autoFilledPhone = null;
                                });
                              }
                              _onFieldChanged();
                              if (invoiceToManage != null &&
                                  invoiceToManage!.status == 'معلقة' &&
                                  (invoiceToManage?.isLocked ?? false)) {
                                autoSaveSuspendedInvoice();
                              }
                            },
                          );
                        },
                        onSelected: (String selection) async {
                          // 🔒 [Locking System] Verify Customer Lock
                          final selectedCustomer = await db.findCustomerByNormalizedName(selection);
                          if (selectedCustomer != null && selectedCustomer.id != null) {
                             final isLocked = await db.lockingService.isLockedByOther(
                               resourceType: 'customer', 
                               resourceId: selectedCustomer.id!
                             );
                             
                             if (isLocked) {
                               if (context.mounted) {
                                 ScaffoldMessenger.of(context).showSnackBar(
                                   const SnackBar(
                                     content: Text('⚠️ هذا العميل قيد الاستخدام من قبل مستخدم آخر!'),
                                     backgroundColor: Colors.orange,
                                     duration: Duration(seconds: 4),
                                   ),
                                 );
                                 // Clear selection
                                 customerNameController.clear();
                                 return;
                               }
                             }
                             
                             // Attempt to acquire lock for ourselves
                             if (context.mounted) {
                                final lockResult = await db.lockingService.acquireLock(
                                  resourceType: 'customer',
                                  resourceId: selectedCustomer.id!
                                );
                                if (!lockResult.success) {
                                   // Double check fail (race condition)
                                   customerNameController.clear();
                                   if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                       SnackBar(content: Text(lockResult.message ?? 'فشل حجز العميل')),
                                     );
                                   }
                                   return; 
                                }
                             }
                          }

                          customerNameController.text = selection;
                          _onFieldChanged();
                          await _fillPhoneFromCustomerCard(selection);
                        },
                        optionsViewBuilder: (context, onSelected, options) {
                          return Align(
                            alignment: Alignment.topRight,
                            child: Material(
                              elevation: 4.0,
                              color: const Color(0xFF333333), // Darker dropdown
                              borderRadius: BorderRadius.circular(4),
                              child: SizedBox(
                                height: 200.0,
                                width: constraints.maxWidth * 0.3,
                                child: ListView.builder(
                                  padding: const EdgeInsets.all(4.0),
                                  itemCount: options.length,
                                  itemBuilder: (BuildContext context, int index) {
                                    final String option = options.elementAt(index);
                                    return GestureDetector(
                                      onTap: () {
                                        onSelected(option);
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                                        decoration: const BoxDecoration(
                                          border: Border(bottom: BorderSide(color: Colors.white12, width: 0.5)),
                                        ),
                                        child: Text(option, style: const TextStyle(color: Colors.white)),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(width: 8),

                  // 🧩 الجوال والعنوان انتقلا إلى «المزيد» — يظهران هنا شارة صغيرة إن وُجدا
                  if (customerPhoneController.text.trim().isNotEmpty)
                    _buildHeaderInfoChip(Icons.phone_outlined, customerPhoneController.text.trim()),
                  if (customerAddressController.text.trim().isNotEmpty)
                    _buildHeaderInfoChip(Icons.location_on_outlined, customerAddressController.text.trim()),
                  const SizedBox(width: 4),

                  // 3.5. اسم المستخدم الحالي (الكاشير/المحاسب)
                  Builder(
                    builder: (context) {
                      final username = AuthService().currentUser?.username ?? 'غير معروف';
                      return Container(
                        height: 42,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.person, color: Colors.white54, size: 16),
                            const SizedBox(width: 6),
                            Text(username, style: const TextStyle(color: Colors.white, fontSize: 12)),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 8),

                   // 4. Date Picker
                  InkWell(
                    onTap: isViewOnly ? null : () => _selectDate(context),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      height: 42, // 🔺 Increased Height
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.transparent),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            DateFormat('yyyy-MM-dd').format(selectedDate),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.normal, fontSize: 13),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.calendar_today, color: Colors.white70, size: 15),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  
                  // 5. نوع القائمة (مفرد/جملة/إلخ) - في الـ AppBar
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('نوع الفاتورة', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      const SizedBox(width: 8),
                      Container(
                    height: 42,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedListType,
                        dropdownColor: const Color(0xFF333333),
                        icon: const Icon(Icons.arrow_drop_down, color: Colors.white70, size: 20),
                        items: const [
                          DropdownMenuItem(value: 'مفرد', child: Text('مفرد', style: TextStyle(color: Colors.white))),
                          DropdownMenuItem(value: 'مفرد 2', child: Text('مفرد 2', style: TextStyle(color: Colors.white))),
                          DropdownMenuItem(value: 'منزل', child: Text('منزل', style: TextStyle(color: Colors.white))),
                          DropdownMenuItem(value: 'جملة', child: Text('جملة', style: TextStyle(color: Colors.white))),
                          DropdownMenuItem(value: 'جملة 2', child: Text('جملة 2', style: TextStyle(color: Colors.white))),
                          DropdownMenuItem(value: 'أخرى', child: Text('أخرى', style: TextStyle(color: Colors.white))),
                        ],
                        onChanged: isViewOnly ? null : (value) {
                          final changedLevel = (value ?? 'مفرد') != _selectedListType;
                          setState(() {
                            _selectedListType = value ?? 'مفرد';
                            if (_selectedProduct != null) {
                              _updatePriceForSelectedProduct(_selectedProduct!);
                            }
                          });
                          // 🧩 مثل الإداري: سؤال قبل تطبيق المستوى الجديد على الأصناف الموجودة
                          if (changedLevel) _maybeApplyListTypeToItems(_selectedListType);
                        },
                        style: const TextStyle(fontSize: 13, color: Colors.white),
                      ),
                    ),
                  ),
                  ], // close Row children (نوع الفاتورة)
                ), // close Row (نوع الفاتورة)
                const SizedBox(width: 8),
                // 🧩 «المزيد»: الجوال والعنوان وأجور النقل وعرض الجدول
                // 👷 المؤسس ونقاطه — لحساب المالك فقط (لا يظهر لغيره إطلاقاً)
                if (OwnerAccess.enabled) ...[
                  FounderInvoiceChip(
                    nameController: installerNameController,
                    rate: founderPointsRate,
                    enabled: !isViewOnly,
                    invoiceTotal: _founderInvoiceTotal,
                    onChanged: (name, rate) => setState(() {
                      installerNameController.text = name;
                      founderPointsRate = rate;
                      hasUnsavedChanges = true;
                    }),
                  ),
                  const SizedBox(width: 8),
                ],
                _buildHeaderMoreButton(),
              ], // close Main Row children
            ), // close Main Row
          ); // close SingleChildScrollView
            }
          ),
          centerTitle: true,
          actions: [
            // زر جديد لإعادة التعيين - يظهر دائماً per user request
            IconButton(
              icon: const Icon(Icons.receipt),
              tooltip: 'فاتورة جديدة',
              onPressed: invoiceItems.isNotEmpty ||
                      customerNameController.text.isNotEmpty
                  ? _resetInvoice
                  : null,
            ),
            // ⏸️ التعليق للبيع فقط: يظهر في «إنشاء فاتورة» (أو فاتورة معلّقة فُتحت
            // لإكمالها)، ولا يظهر عند فتح فاتورة محفوظة من «تعديل الفواتير»
            if (_holdMode) ...[
            // ⏸️ تعليق الفاتورة الحالية وفتح شاشة جديدة (للزبون التالي)
            IconButton(
              icon: const Icon(Icons.pause_circle_outline_rounded),
              tooltip: 'تعليق الفاتورة (للزبون التالي)',
              onPressed: _canHold ? _holdCurrentInvoice : null,
            ),
            // ⏳ الفواتير المعلّقة مع عددها
            Badge(
              isLabelVisible: _heldCount > 0,
              label: Text('$_heldCount'),
              backgroundColor: Colors.orange.shade800,
              offset: const Offset(-4, 6),
              child: IconButton(
                icon: const Icon(Icons.hourglass_bottom_rounded),
                tooltip: 'الفواتير المعلّقة',
                onPressed: _showHeldInvoices,
              ),
            ),
            ],
            // زر الطباعة الموجود
            IconButton(
              icon: const Icon(Icons.print),
              tooltip: 'طباعة الفاتورة',
              onPressed: (invoiceItems.isEmpty || isSaving) ? null : printInvoice,
            ),
            // 📋 سجل التعديلات — يظهر هنا فقط إن عُدّلت الفاتورة (وموجود دائماً في القائمة)
            if (invoiceToManage != null)
              FutureBuilder<bool>(
                future: DatabaseService().hasInvoiceBeenModified(invoiceToManage!.id!),
                builder: (context, snapshot) {
                  if (snapshot.data != true) return const SizedBox.shrink();
                  return IconButton(
                    icon: const Icon(Icons.history, color: Colors.orange),
                    tooltip: 'سجل التعديلات (تم التعديل)',
                    onPressed: _openInvoiceHistory,
                  );
                },
              ),
            if (invoiceToManage != null && isViewOnly && invoiceToManage!.isCreatedByMe)
              IconButton(
                icon: const Icon(Icons.edit),
                tooltip: 'تعديل الفاتورة',
                onPressed: isSaving ? null : _enableEditMode,
              ),
            if (invoiceToManage != null && !isViewOnly) ...[
              IconButton(
                icon: const Icon(Icons.save),
                tooltip: 'حفظ التعديلات',
                onPressed: isSaving ? null : saveInvoice,
              ),
              IconButton(
                icon: const Icon(Icons.cancel),
                tooltip: 'إلغاء التعديل',
                onPressed: isSaving ? null : _cancelEdit,
              ),
            ],
            // 🧩 الخيارات الأقل استعمالاً في قائمة واحدة
            _buildMoreActionsMenu(),
            const SizedBox(width: 4),
          ],
        ),
        body: Row(
          children: [
            if (_appSettings != null && AppSideNav.shouldShow(context, _appSettings!))
              const AppSideNav(currentRoute: '/create_invoice'),
            Expanded(
              child: LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= 800;
            return Flex(
              direction: isDesktop ? Axis.horizontal : Axis.vertical,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ═══════════════════════════════════════════════════════════════════════════
                // 1. القسم الرئيسي (جدول المواد + شريط الإدخال) - يأخذ المساحة الأكبر
                // ═══════════════════════════════════════════════════════════════════════════
                Expanded(
                  flex: 3,
                  child: Column(
                    children: [
                  // شريط إدخال المواد (أفقي) - يظهر فقط إذا لم يكن للعرض، ويمكن إخفاؤه من الإعدادات
                  if (InvoiceEntryLayout.current.showEntryBar) _buildProductEntryBar(context),
                  
                  // 🧩 جدول المواد على طريقة الإداري: عرض كل عمود بالبكسل، يتّسع «اسم المادة»
                  //    ليملأ الشاشة، وإن زادت الأعمدة عن العرض يظهر شريط تمرير أفقي.
                  if (invoiceItems.isNotEmpty || !isViewOnly)
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(10, 8, 10, 6),
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 3)),
                          ],
                        ),
                        child: LayoutBuilder(builder: (context, box) {
                        final layout = InvoiceEntryLayout.current;
                        _ensureTrailingEmptyRow();
                        const trailing = 120.0; // أيقونات التنبيه + الحذف
                        final colWidths = layout.resolve(
                          box.maxWidth - trailing - 2 * layout.gridLineWidth - 1,
                          isViewOnly: isViewOnly,
                          canSeeCost: AuthService().hasPermission(AppPermissions.viewCostProfit),
                          force: _ownerCostPeek ? const {'cost'} : const {},
                        );
                        final tableWidth = colWidths.values.fold<double>(0, (a, b) => a + b) + trailing + 2 * layout.gridLineWidth + 1; // حدّا الجدول بسماكة الخطوط المختارة
                        // 🧭 مسار Enter في كل سطر (حسب الإعدادات والأعمدة الظاهرة)
                        final enterStops = layout.enterStops(colWidths.keys);
                        final header = Container(
                          height: 34,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            border: Border(
                              bottom: BorderSide(
                                  color: Color.lerp(const Color(0xFFCBD5E1), layout.gridColor, 0.5)!,
                                  width: layout.gridLineWidth),
                              left: layout.gridSide,
                              right: layout.gridSide,
                            ),
                          ),
                          child: Row(children: [
                            for (final e in colWidths.entries)
                              Container(
                                width: e.value,
                                alignment: Alignment.center,
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                decoration: BoxDecoration(
                                  border: Border(right: layout.gridSide),
                                ),
                                child: Text(InvoiceEntryLayout.headers[e.key]!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12.5,
                                        color: _ownerCostPeek && e.key == 'cost'
                                            ? const Color(0xFF15803D)
                                            : const Color(0xFF334155))),
                              ),
                            // ⚙️ إظهار/إخفاء الأعمدة بسرعة من رأس الجدول
                            SizedBox(width: trailing, child: Center(child: _buildColumnsQuickButton())),
                          ]),
                        );
                        final grid = SizedBox(
                          width: tableWidth,
                          height: box.maxHeight,
                          child: Column(children: [
                            header,
                            Expanded(
                              child: Form(
                      key: formKey,
                      child: Stack(children: [
                      ListView.builder(
                        controller: _scrollController,
                        itemCount: invoiceItems.length,
                        padding: const EdgeInsets.only(bottom: 100), // مساحة في الأسفل
                        itemBuilder: (context, index) {
                          final item = invoiceItems[index];

                          // Ensure focus nodes exist
                          while (focusNodesList.length <= index) {
                             focusNodesList.add(LineItemFocusNodes());
                          }

                          return EditableInvoiceItemRow(
                            columnWidths: colWidths,
                            costDates: _ownerCostPeek ? (_costDates ?? const {}) : null,
                            rowHeight: layout.rowHeight,
                            key: ValueKey(item.uniqueId),
                            item: item,
                            index: index,
                            getCurrentInvoiceProductNames: () {
                              return invoiceItems
                                  .where((it) => it.productName.trim().isNotEmpty && it.uniqueId != item.uniqueId)
                                  .map((it) => it.productName.trim())
                                  .toList();
                            },
                            onItemUpdated: (updatedItem) {
                                if (invoiceToManage != null && !isViewOnly) {
                                  hasUnsavedChanges = true;
                                }
                                setState(() {
                                  final i = invoiceItems.indexWhere((it) => it.uniqueId == updatedItem.uniqueId);
                                  if (i != -1) {
                                    invoiceItems[i] = updatedItem;
                                  }
                                  _recalculateTotals();
                                  _calculateProfit();
                                });
                                _scheduleLiveDebtSync();
                            },
                            onItemRemovedByUid: _removeInvoiceItemByUid,
                            allProducts: _allProductsForUnits ?? [],
                            isViewOnly: isViewOnly,
                            isPlaceholder: false, 
                            
                            detailsFocusNode: !isViewOnly && index < focusNodesList.length ? focusNodesList[index].details : null,
                            quantityFocusNode: !isViewOnly && index < focusNodesList.length ? focusNodesList[index].quantity : null,
                            priceFocusNode: !isViewOnly && index < focusNodesList.length ? focusNodesList[index].price : null,
                            
                            databaseService: db,
                            currentCustomerName: customerNameController.text,
                            currentCustomerPhone: customerPhoneController.text,
                            paymentType: paymentType,
                            allowNegativeStock: _allowNegativeStock, // مرر الإعداد هنا
                            enterStops: enterStops,
                            discountTypedAsPercent: layout.discountTypedAsPercent,
                            // Enter على آخر خانة: اسم المادة في السطر التالي
                            onRowFinished: () => _focusRowAfter(item.uniqueId),
                          );
                        },
                      ),
                      // لا مواد بعد: تلميح هادئ في وسط الجدول
                      if (invoiceItems.isEmpty && !isViewOnly)
                        IgnorePointer(
                          child: Center(
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.receipt_long_outlined, size: 54, color: Colors.blueGrey.shade100),
                              const SizedBox(height: 10),
                              Text('ابدأ بكتابة اسم المادة أو رقمها أو امسح الباركود',
                                  style: TextStyle(color: Colors.blueGrey.shade300, fontSize: 14)),
                            ]),
                          ),
                        ),
                      ]),
                    ),
                            ),
                          ]),
                        );
                        if (tableWidth <= box.maxWidth + 1) return grid;
                        return Scrollbar(
                          controller: _hScrollController,
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            controller: _hScrollController,
                            scrollDirection: Axis.horizontal,
                            child: grid,
                          ),
                        );
                      }),
                      ),
                    ),
                  // 👑 Ctrl+D (المالك فقط): ربح هذه الفاتورة مبلغاً ونسبة
                  if (_ownerCostPeek) _ownerProfitStrip(),
                  // 🧩 اللوحة الجانبية مطوية ⇒ المجاميع والحفظ في شريط سفلي
                  if (!_sidePanelOpen && isDesktop) _buildCompactTotalsBar(),
                ],
              ),
            ),
            
            
            // الفاصل العمودي
            if (_sidePanelOpen || !isDesktop)
            isDesktop
                ? VerticalDivider(width: 1, color: Colors.grey.shade300)
                : Divider(height: 1, color: Colors.grey.shade300),

            // ═══════════════════════════════════════════════════════════════════════════
            // 2. الشريط الجانبي (Totals & Actions) — عرض ثابت، ويُطوى لتوسيع الجدول
            // ═══════════════════════════════════════════════════════════════════════════
            if (!isDesktop)
              Expanded(flex: 2, child: _buildSidebar(context))
            else if (_sidePanelOpen)
              SizedBox(width: 330, child: _buildSidebar(context)),
          ],
        );
      },
    ),
            ),
          ],
        ),
            ), // نهاية Scaffold
          ), // نهاية AbsorbPointer
          // ═══════════════════════════════════════════════════════════════════════════
          // 🔄 مؤشر التحميل أثناء الحفظ
          // ═══════════════════════════════════════════════════════════════════════════
          if (isSaving)
            Container(
              color: Colors.black.withValues(alpha: 0.3),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      strokeWidth: 3,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'جاري حفظ الفاتورة...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'يرجى الانتظار وعدم إغلاق التطبيق',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ], // نهاية Stack children
      ), // نهاية Stack
    ), // نهاية Theme
    ); // نهاية PopScope
  }


}

class EditableInvoiceItemRow extends StatefulWidget {
  final InvoiceItem item;
  final int index;
  final Function(InvoiceItem) onItemUpdated;
  final Function(String) onItemRemovedByUid;
  final List<Product> allProducts;
  final bool isViewOnly;
  final bool isPlaceholder;
  final FocusNode? detailsFocusNode; // جديد: لقبول FocusNode لحقل التفاصيل
  final FocusNode? quantityFocusNode; // جديد: لطلب التركيز على العدد من الخارج
  final FocusNode? priceFocusNode; // جديد: لطلب التركيز على السعر من الخارج
  final DatabaseService? databaseService; // جديد: للبحث الذكي
  final String currentCustomerName; // اسم العميل الحالي لقراءة سجل أسعاره
  final String? currentCustomerPhone; // هاتف العميل لتحسين المطابقة
  /// 🧭 Enter على آخر خانة في السطر (الشاشة تنقل المؤشر إلى السطر التالي)
  final VoidCallback? onRowFinished;
  /// 🧭 مسار Enter داخل السطر: 'details' ثم الخانات حسب إعداد المستخدم
  final List<String> enterStops;
  /// الرقم المكتوب في خانة الخصم: نسبة % (true) أو مبلغ من سعر الوحدة (false)
  final bool discountTypedAsPercent;
  final bool allowNegativeStock; // جديد: للسماح بالبيع بالسالب أو منعه
  final List<String> Function()? getCurrentInvoiceProductNames; // المنتجات الحالية لخفض أولويتها في البحث
  /// 🧩 عرض كل عمود بالبكسل (من InvoiceEntryLayout.resolve) — الأعمدة غير الموجودة لا تُرسم
  final Map<String, double>? columnWidths;
  /// ارتفاع السطر (مضغوط كالإداري أو عادي)
  final double rowHeight;
  /// 👑 Ctrl+D: تاريخ آخر تحديث لكلفة كل مادة (null = لا يُعرض)
  final Map<int, DateTime>? costDates;

  /// نوع دفع الفاتورة (للتسعير الشخصي 101–103: مراجع نقد للنقد، دين للدين)
  final String paymentType;

  const EditableInvoiceItemRow({
    Key? key,
    required this.item,
    required this.index,
    required this.onItemUpdated,
    required this.onItemRemovedByUid,
    required this.allProducts,
    required this.isViewOnly,
    required this.isPlaceholder,
    this.detailsFocusNode,
    this.quantityFocusNode,
    this.priceFocusNode,
    this.databaseService, // جديد: للبحث الذكي
    required this.currentCustomerName,
    this.currentCustomerPhone,
    this.onRowFinished,
    this.enterStops = const ['details', 'qty', 'saleType', 'price'],
    this.discountTypedAsPercent = true,
    this.allowNegativeStock = false, // القيمة الافتراضية
    this.getCurrentInvoiceProductNames,
    this.columnWidths,
    this.rowHeight = 44,
    this.costDates,
    this.paymentType = 'نقد',
  }) : super(key: key);

  @override
  State<EditableInvoiceItemRow> createState() => _EditableInvoiceItemRowState();
}
class _EditableInvoiceItemRowState extends State<EditableInvoiceItemRow> {
  late InvoiceItem _currentItem;
  late TextEditingController _quantityController;
  late TextEditingController _priceController;
  late FocusNode _quantityFocusNode;
  late FocusNode _priceFocusNode;
  late FocusNode _detailsFocusNode;
  late FocusNode _saleTypeFocusNode;
  final FocusNode _discountFocusNode = FocusNode(); // 🏷️ خانة الخصم حين تكون ضمن مسار Enter
  final TextEditingController _discountController = TextEditingController();
  bool _saleMenuOpen = false; // يمنع فتح قائمة الوحدة مرتين
  int _pickSeq = 0; // آخر اختيار مادة هو الذي ينقل المؤشر
  bool _openSaleTypeDropdown = false;
  final GlobalKey _saleTypeKey = GlobalKey(); // مفتاح لفتح قائمة نوع البيع برمجياً
  late TextEditingController _idController;
  Timer? _rowIdDebounce;
  TextEditingController? _detailsController; // reference to details field controller
  TextEditingController? _ownedDetailsController; // controller نملكه للـ RawAutocomplete
  bool _hasShownLowPriceWarning = false;
  bool _isRowLocked = false; // 🔒 قفل السطر في حالة نفاد المخزون
  double? _lowestRecentPrice; // أدنى سعر خلال آخر 3 فواتير
  String? _lowestRecentInfo; // وصف مختصر: التاريخ ونوع البيع
  
  // دالة للتحقق مما إذا كان سعر البيع أقل من سعر التكلفة
  bool _isPriceBelowCost() {
    if (_currentItem.appliedPrice <= 0) return false;
    final effectiveCostPerUnit = _effectiveCostPerUnit();
    if (effectiveCostPerUnit == null || effectiveCostPerUnit <= 0) return false;
    const double eps = 1e-6;
    return (_currentItem.appliedPrice + eps) < effectiveCostPerUnit;
  }

  /// كلفة الوحدة المباعة لهذا السطر (من كلفة السطر المخزنة أو من بطاقة المادة)
  double? _effectiveCostPerUnit() {
    if (_currentItem.productName.isEmpty) return null;
    
    double quantity = _currentItem.quantityIndividual ??
        _currentItem.quantityLargeUnit ?? 1;
    if (quantity <= 0) quantity = 1;
    
    double? effectiveCostPerUnit;
    
    // أولاً: جرب من actualCostPrice
    // 🔧 التحقق الدفاعي: تجاهل actualCostPrice إذا كان يساوي سعر القطعة بينما نبيع بوحدة كبيرة
    // هذا يضمن إعادة الحساب من الهرمية إذا كان التخزين الأولي خاطئاً
    bool useStoredActualCost = false;
    if (_currentItem.actualCostPrice != null && _currentItem.actualCostPrice! > 0) {
       useStoredActualCost = true;
       // إذا كان البيع بوحدة كبيرة (ليست قطعة أو متر)
       if (_currentItem.saleType != 'قطعة' && _currentItem.saleType != 'متر') {
          // جلب سعر القطعة للمقارنة
           final product = widget.allProducts.firstWhere(
            (p) => p.name == _currentItem.productName,
            orElse: () => Product(
              id: null, 
              name: '', 
              unit: '', 
              unitPrice: 0, 
              price1: 0,
              createdAt: DateTime.now(), // 🔧 Added missing parameter
              lastModifiedAt: DateTime.now(), // 🔧 Added missing parameter
            ),
          );
          // إذا كانت التكلفة المخزنة تساوي تكلفة القطعة الواحدة، فهذا يعني أن الحساب الأولي كان خاطئاً
          // لذا نتجاهله وندع الدالة تحسبه من جديد باستخدام المنطق القوي في الأسفل
          final double baseCost = product.costPrice ?? 0.0;
          if ((_currentItem.actualCostPrice! - baseCost).abs() < 0.01) {
             useStoredActualCost = false;
          }
       }
    }

    if (useStoredActualCost) {
      effectiveCostPerUnit = _currentItem.actualCostPrice;
    } 
    // ثانياً: جرب من costPrice (للقطعة الواحدة)
    else if (_currentItem.costPrice != null && _currentItem.costPrice! > 0 && quantity > 1 && (_currentItem.saleType == 'قطعة' || _currentItem.saleType == 'متر')) {
       // هذا الشرط خاص فقط إذا كنا نبيع كمية من القطع، ونريد مقارنة سعر المجموعة (وهو غير مطبق هنا لأن appliedPrice للوحدة)
       // انتظر، effectiveCostPerUnit يجب أن يكون للوحدة الواحدة (التي هي هنا "باكيت" كامل)
       // لذا الشرط السابق كان: costPrice! / quantity وهذا كان يفترض أن costPrice هو للمجموع.
       // دعنا نعتمد على المنطق القوي في الأسفل
    }
    // ثالثاً: جلب التكلفة من المنتج الأصلي (المنطق القوي)
    if (effectiveCostPerUnit == null) {
      final product = widget.allProducts.firstWhere(
        (p) => p.name == _currentItem.productName,
        orElse: () => Product(
          id: null, name: '', unit: 'piece', unitPrice: 0, price1: 0,
          createdAt: DateTime.now(), lastModifiedAt: DateTime.now(),
        ),
      );
      
      if (product.name.isNotEmpty) {
        final String saleType = _currentItem.saleType ?? 'قطعة';
        final Map<String, double> unitCosts = product.getUnitCostsMap();
        
        // جرب من unit_costs أولاً
        if (unitCosts.containsKey(saleType) && unitCosts[saleType]! > 0) {
          effectiveCostPerUnit = unitCosts[saleType];
        }
        // ثم من costPrice الأساسي للمنتج مع حساب المضاعف من الهرمية
        else if (product.costPrice != null && product.costPrice! > 0) {
          // إذا كان البيع بوحدة كبيرة، احسب التكلفة من الهرمية
          if (saleType != 'قطعة' && saleType != 'متر') {
            double multiplier = 1.0;
            
            // 🔧 Fix: استخدام unitHierarchy للحساب الصحيح مع fallback قوي
            if (product.unitHierarchy != null && product.unitHierarchy!.isNotEmpty) {
              try {
                // محاولة تحليل JSON مع دعم علامات الاقتباس المفردة والمزدوجة
                List<dynamic> hierarchy;
                try {
                  hierarchy = jsonDecode(product.unitHierarchy!); 
                } catch (_) {
                  hierarchy = jsonDecode(product.unitHierarchy!.replaceAll("'", '"'));
                }

                for (final level in hierarchy) {
                  final String unitName = (level['unit_name'] ?? level['name'] ?? '').toString();
                  final double qty = (level['quantity'] is num)
                      ? (level['quantity'] as num).toDouble()
                      : double.tryParse(level['quantity'].toString()) ?? 1.0;
                  multiplier *= qty;
                  if (unitName == saleType) break;
                }
              } catch (_) {
                // استخدام unitsInLargeUnit كـ fallback
                multiplier = _currentItem.unitsInLargeUnit ?? 1;
              }
            } else {
              multiplier = _currentItem.unitsInLargeUnit ?? 1;
            }
            
            effectiveCostPerUnit = product.costPrice! * multiplier;
          } else {
            effectiveCostPerUnit = product.costPrice;
          }
        }
      }
    }
    
    return effectiveCostPerUnit;
  }

  // 🧩 فهرس المواد بالاسم (يُبنى مرة لكل قائمة مواد) للأعمدة: الرقم، الرصيد، الكلفة
  static List<Product>? _indexSource;
  static Map<String, Product> _productIndex = {};
  Product? get _rowProduct {
    if (!identical(_indexSource, widget.allProducts)) {
      _indexSource = widget.allProducts;
      _productIndex = {for (final p in widget.allProducts) p.name: p};
    }
    return _productIndex[_currentItem.productName];
  }

  /// خلية بعرض العمود المحدد؛ العمود غير الظاهر لا يُرسم
  Widget _cell(String key, Widget child) {
    final widths = widget.columnWidths;
    if (widths == null) return Expanded(flex: 2, child: child);
    final w = widths[key];
    if (w == null) return const SizedBox.shrink();
    return SizedBox(width: w, child: child);
  }

  double get _vPad => widget.rowHeight < 40 ? 4 : 8;

  // 🔒 التحقق من المخزون عند الكتابة اليدوية لاسم المنتج
  void _validateStockByManualName(String name) {
    if (widget.allowNegativeStock) {
      if (_isRowLocked) setState(() => _isRowLocked = false);
      return;
    }
    
    final sanitizedInput = name.trim().replaceAll(' ', '');
    if (sanitizedInput.isEmpty) {
       if (_isRowLocked) setState(() => _isRowLocked = false);
       return;
    }

    Product? matchingProduct;
    try {
      // مقارنة الاسم بدون فواصل كما طلب المستخدم
      matchingProduct = widget.allProducts.firstWhere(
        (p) => p.name.trim().replaceAll(' ', '') == sanitizedInput,
      );
    } catch (_) {}

    final shouldLock = matchingProduct != null && matchingProduct.stockQuantity <= 0;
    
    if (shouldLock != _isRowLocked) {
      setState(() {
        _isRowLocked = shouldLock;
      });
      
      if (shouldLock) {
         ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ هذا الصنف نافذ من المخزون! تم قفل السطر.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  String _formatNumber(num value) {
    return NumberFormat('#,##0.##', 'en_US').format(value);
  }
  
  // دالة للحصول على أو إنشاء TextEditingController للتفاصيل
  TextEditingController _getOrCreateDetailsController() {
    _ownedDetailsController ??= TextEditingController(text: widget.item.productName);
    return _ownedDetailsController!;
  }

  @override
  void initState() {
    super.initState();
    _currentItem = widget.item;
    // استخدم المتحكمات الجاهزة من كائن الصنف مباشرة
    _quantityController = TextEditingController(
      text: (widget.item.quantityIndividual ??
              widget.item.quantityLargeUnit ??
              '')
          .toString(),
    );
    _priceController = widget.item.appliedPriceController;
    _detailsFocusNode = widget.detailsFocusNode ?? FocusNode();
    _quantityFocusNode = widget.quantityFocusNode ?? FocusNode();
    _priceFocusNode = widget.priceFocusNode ?? FocusNode();
    _saleTypeFocusNode = FocusNode();
    
    // إضافة listener لنقل التركيز إلى Autocomplete عند طلب التركيز على _detailsFocusNode
    _detailsFocusNode.addListener(_onDetailsFocusChanged);
    // 🎯 إضافة listener لتظليل كامل السعر عند استقبال المؤشر
    _priceFocusNode.addListener(_onPriceFocusChanged);
    _quantityFocusNode.addListener(_onQtyFocusChanged);
    _discountFocusNode.addListener(_onDiscountFocusChanged);
    _discountController.text = widget.item.discountLabel;
    
    // Initialize ID controller from current product if resolvable
    final prod = widget.allProducts.firstWhere(
      (p) => p.name == _currentItem.productName,
      orElse: () => Product(
        id: null,
        name: '',
        unit: 'piece',
        unitPrice: 0,
        price1: 0,
        createdAt: DateTime.now(),
        lastModifiedAt: DateTime.now(),
      ),
    );
    _idController = TextEditingController(text: prod.id?.toString() ?? '');
    // احضر أدنى سعر تاريخي بمجرد تهيئة الصف
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchLowestRecentPrice();
    });
  }
  
  // دالة للتعامل مع تغيير التركيز على حقل التفاصيل
  void _onDetailsFocusChanged() {
    // يمكن إضافة منطق هنا إذا لزم الأمر
  }

  // 🎯 دالة لتظليل كامل السعر عند استقبال التركيز
  void _onPriceFocusChanged() {
    if (_priceFocusNode.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_priceFocusNode.hasFocus && _priceController.text.isNotEmpty) {
          _priceController.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _priceController.text.length,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    // إزالة الـ listeners قبل التخلص من FocusNode
    _detailsFocusNode.removeListener(_onDetailsFocusChanged);
    _priceFocusNode.removeListener(_onPriceFocusChanged);
    _quantityFocusNode.removeListener(_onQtyFocusChanged);
    _discountFocusNode.removeListener(_onDiscountFocusChanged);
    _discountFocusNode.dispose();
    _discountController.dispose();
    
    // تنظيف الـ controller الذي نملكه
    _ownedDetailsController?.dispose();
    
    if (widget.detailsFocusNode == null) {
      _detailsFocusNode.dispose();
    }
    if (widget.quantityFocusNode == null) {
      _quantityFocusNode.dispose();
    }
    if (widget.priceFocusNode == null) {
      _priceFocusNode.dispose();
    }
    _saleTypeFocusNode.dispose();
    _rowIdDebounce?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(EditableInvoiceItemRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // مزامنة الحالة الداخلية عندما يتم تحديث العنصر من الخارج
    // هذا يحل مشكلة عدم ظهور التحديثات في واجهة المستخدم عند التعديلات المتكررة
    if (oldWidget.item.uniqueId == widget.item.uniqueId) {
      // تحقق من وجود تغييرات فعلية
      bool hasChanges = false;
      
      if (_currentItem.quantityIndividual != widget.item.quantityIndividual) hasChanges = true;
      if (_currentItem.quantityLargeUnit != widget.item.quantityLargeUnit) hasChanges = true;
      if (_currentItem.appliedPrice != widget.item.appliedPrice) hasChanges = true;
      if (_currentItem.saleType != widget.item.saleType) hasChanges = true;
      if (_currentItem.itemTotal != widget.item.itemTotal) hasChanges = true;
      if (_currentItem.productName != widget.item.productName) hasChanges = true;
      
      if (hasChanges) {
        // تحديث البيانات فوراً داخلياً
        _currentItem = widget.item;
        
        // استخدام post-frame callback لتجنب خطأ markNeedsBuild during build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            // تحديث الـ controllers لتعكس القيم الجديدة
            final q = widget.item.quantityIndividual ?? widget.item.quantityLargeUnit;
            final quantity = q == null ? '' : _qtyText(q);
            if (_quantityController.text != quantity) {
              _quantityController.text = quantity;
            }
            
            final priceText = _formatNumber(widget.item.appliedPrice);
            if (_priceController.text != priceText) {
              _priceController.text = priceText;
            }
            
            // تحديث controller التفاصيل إذا كان موجوداً
            if (_detailsController != null && _detailsController!.text != widget.item.productName) {
              _detailsController!.text = widget.item.productName;
            }
          });
        });
      }
    }
  }

  List<DropdownMenuItem<String>> _getUnitOptions() {
    Product? product = widget.allProducts.firstWhere(
      (p) => p.name == _currentItem.productName,
      orElse: () => Product(
        id: null,
        name: '',
        unit: 'piece',
        unitPrice: 0,
        price1: 0,
        createdAt: DateTime.now(),
        lastModifiedAt: DateTime.now(),
      ),
    );

    // 🧠 Use the centralized method to get all units (base + hierarchy)
    List<String> options = product.getAllUnitLevels();

    // Fallback if empty (should not happen for valid products)
    if (options.isEmpty) {
      if (product.unit == 'piece') {
        options = ['قطعة'];
      } else if (product.unit == 'meter') {
        options = ['متر'];
        if (product.lengthPerUnit != null) options.add('لفة');
      } else {
        options = [product.unit];
      }
    }

    // Ensure valid entries only
    options = options.where((e) => e.isNotEmpty).toSet().toList();

    // Ensure currently selected value is present
    if (_currentItem.saleType != null &&
        _currentItem.saleType!.isNotEmpty &&
        !options.contains(_currentItem.saleType)) {
      options.add(_currentItem.saleType!);
    }

    return options
        .map((unit) => DropdownMenuItem(
              value: unit,
              child: Text(unit, textAlign: TextAlign.center),
            ))
        .toList();
  }


  // ───────────── 🧭 التنقل بزر Enter حسب ترتيب المستخدم ─────────────

  /// Enter على الخانة [from]: إلى الخانة التالية في [EditableInvoiceItemRow.enterStops]،
  /// وبعد آخر خانة إلى «اسم المادة» في السطر التالي (إلا إن كان [finishRow] = false).
  void _goNext(String from, {bool finishRow = true}) {
    if (!mounted || widget.isViewOnly || _isRowLocked) return;
    final stops = widget.enterStops;
    var i = stops.indexOf(from);
    if (i < 0) {
      // خانة ليست ضمن المسار (وصلها المستخدم بالفأرة): التالي حسب ترتيب الأعمدة
      final pos = InvoiceEntryLayout.keys.indexOf(from);
      final after = stops.indexWhere((k) => k != 'details' && InvoiceEntryLayout.keys.indexOf(k) > pos);
      i = after < 0 ? stops.length - 1 : after - 1;
    }
    if (i + 1 >= stops.length) {
      if (finishRow) widget.onRowFinished?.call();
      return;
    }
    _focusStop(stops[i + 1]);
  }

  void _focusStop(String key) {
    switch (key) {
      case 'qty':
        FocusScope.of(context).requestFocus(_quantityFocusNode);
      case 'saleType':
        _showSaleTypeMenu(); // تفتح القائمة ثم تنتقل بنفسها
      case 'price':
        FocusScope.of(context).requestFocus(_priceFocusNode);
      case 'discount':
        FocusScope.of(context).requestFocus(_discountFocusNode);
      default:
        FocusScope.of(context).requestFocus(_detailsFocusNode);
    }
  }

  /// يطبّق المادة على السطر ثم ينتقل للخانة التالية. Enter قد يختار المادة مرتين
  /// (من القائمة ومن المطابقة التامة) ⇒ آخر اختيار فقط هو الذي ينقل المؤشر.
  Future<void> _pickProduct(Product prod) async {
    final seq = ++_pickSeq;
    await _applyProductSelection(prod);
    if (!mounted || seq != _pickSeq) return;
    _goNext('details');
  }

  /// اختيار مادة للسطر من «اسم المادة» أو «رمز المادة» أو «الباركود»: نفس المسار
  /// (فحص الرصيد، تسجيلها في جلسة البحث الذكي، تطبيقها، ثم الخانة التالية).
  bool _onProductChosen(Product selection) {
    // نفس مادة السطر (المرور عليه بـ Enter): لا يُعاد تسعيرها ولا يُمسح خصمها
    if (selection.id != null && selection.id == _currentItem.productId) {
      _pickSeq++; // كي لا ينقل onSubmitted المؤشر مرة ثانية
      _goNext('details');
      return true;
    }
    // 🔒 التحقق من المخزون عند الاختيار من الجدول
    if (!widget.allowNegativeStock && selection.stockQuantity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ هذا الصنف نافذ من المخزون! لا يمكن اختياره.'),
          backgroundColor: Colors.red,
        ),
      );
      // تصفير الحقل أو إعادته للاسم القديم
      _detailsController?.text = _currentItem.productName;
      return false;
    }

    if (_isRowLocked) setState(() => _isRowLocked = false); // إعادة التعيين عند الاختيار الصحيح
    SmartSearchService.instance.addProductToSession(selection.id, selection.name);
    _pickProduct(selection); // يطبّق المادة ثم ينتقل للخانة التالية حسب الترتيب
    return true;
  }

  /// الكمية بلا «.0» زائدة: 5 لا 5.0
  String _qtyText(num q) =>
      q == q.roundToDouble() ? q.toInt().toString() : NumberFormat('0.###', 'en_US').format(q);

  void _onQtyFocusChanged() {
    if (!_quantityFocusNode.hasFocus) return;
    // تظليل الكمية كاملة: ما يُكتب يحلّ محلها (كما في السعر)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _quantityFocusNode.hasFocus && _quantityController.text.isNotEmpty) {
        _quantityController.selection =
            TextSelection(baseOffset: 0, extentOffset: _quantityController.text.length);
      }
    });
  }

  void _onDiscountFocusChanged() {
    if (_discountFocusNode.hasFocus) {
      _discountController.text = _currentItem.discountLabel;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _discountFocusNode.hasFocus) {
          _discountController.selection =
              TextSelection(baseOffset: 0, extentOffset: _discountController.text.length);
        }
      });
    } else {
      // خرج بلا Enter ⇒ يعود النص إلى خصم السطر الفعلي
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_discountFocusNode.hasFocus) {
          _discountController.text = _currentItem.discountLabel;
        }
      });
    }
  }

  static String _latinDigits(String s) {
    const ar = '٠١٢٣٤٥٦٧٨٩';
    const fa = '۰۱۲۳۴۵۶۷۸۹';
    final b = StringBuffer();
    for (final ch in s.split('')) {
      final i = ar.indexOf(ch);
      final j = fa.indexOf(ch);
      b.write(i >= 0 ? '$i' : (j >= 0 ? '$j' : ch));
    }
    return b.toString();
  }

  void _discountError(String msg) {
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.orange.shade800));
  }

  /// 🏷️ خصم مكتوب في خانة الجدول: «10%» نسبة، «500» حسب الإعداد (نسبة أو مبلغ من
  /// سعر الوحدة)، «هدية» مجاناً، فارغ أو 0 بلا خصم. يعيد false إن كان المكتوب غير صالح.
  bool _applyTypedDiscount(String raw) {
    final it = _currentItem;
    final t = _latinDigits(raw.trim()).replaceAll(',', '').replaceAll('٬', '').replaceAll('٫', '.');
    if (t == it.discountLabel.replaceAll(',', '')) return true; // لم يتغير شيء
    final listPrice = it.hasLineDiscount ? (it.priceBeforeDiscount ?? it.appliedPrice) : it.appliedPrice;
    String? type;
    double? value;
    if (t.isEmpty) {
      type = null;
    } else if (t == 'هدية' || t == 'هديه' || t == 'ه') {
      type = 'gift';
    } else {
      final pct = t.endsWith('%') || t.endsWith('٪');
      final n = double.tryParse(t.replaceAll('%', '').replaceAll('٪', '').trim());
      if (n == null || n < 0) {
        _discountError('اكتب رقماً (مثل 10% أو 500) أو كلمة «هدية»');
        return false;
      }
      if (n > 0) {
        final asPct = pct || widget.discountTypedAsPercent;
        if (asPct && n >= 100) {
          _discountError('نسبة الخصم يجب أن تكون أقل من 100%');
          return false;
        }
        if (!asPct && n >= listPrice) {
          _discountError('الخصم أكبر من سعر الوحدة (${formatCurrency(listPrice)})');
          return false;
        }
        type = asPct ? 'percent' : 'amount';
        value = n;
      }
    }
    if (type != null && listPrice <= 0) {
      _discountError('اكتب سعر الوحدة أولاً');
      return false;
    }
    if (type == null && !it.hasLineDiscount) return true; // بلا خصم أصلاً
    final net = type == null ? listPrice : lineNetPrice(listPrice, type, value ?? 0);
    final qty = it.soldQuantity;
    setState(() {
      _currentItem = _currentItem.copyWith(
        appliedPrice: net,
        itemTotal: qty * net,
        priceBeforeDiscount: type == null ? null : listPrice,
        discountType: type,
        discountValue: value,
      );
      _priceController.text = NumberFormat('#,##0.##', 'en_US').format(net);
      _discountController.text = _currentItem.discountLabel;
    });
    widget.onItemUpdated(_currentItem);
    return true;
  }

  bool get _discountIsStop =>
      !widget.isViewOnly && !widget.isPlaceholder && widget.enterStops.contains('discount');

  /// خانة الخصم القابلة للكتابة (حين يكون الخصم ضمن مسار Enter)
  Widget _discountField() {
    final label = _currentItem.discountLabel;
    // مزامنة النص مع السطر حين لا يُكتب فيه (بعد الإطار، لا أثناء البناء)
    if (!_discountFocusNode.hasFocus && _discountController.text != label) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_discountFocusNode.hasFocus) {
          _discountController.text = _currentItem.discountLabel;
        }
      });
    }
    const clear = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(4)),
      borderSide: BorderSide(color: Colors.transparent, width: 1),
    );
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border(right: InvoiceEntryLayout.current.gridSide),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: TextField(
        controller: _discountController,
        focusNode: _discountFocusNode,
        enabled: !_isRowLocked,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: _currentItem.isGift ? Colors.purple : Colors.green.shade800,
            ),
        decoration: InputDecoration(
          isDense: true,
          filled: false,
          hintText: widget.discountTypedAsPercent ? '%' : '0',
          hintStyle: TextStyle(color: Colors.grey.shade400, fontWeight: FontWeight.normal),
          contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: _vPad),
          border: clear,
          enabledBorder: clear,
          disabledBorder: clear,
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
          ),
          suffixIconConstraints: const BoxConstraints(minWidth: 22, minHeight: 22),
          suffixIcon: Tooltip(
            message: 'خصم مفصّل أو هدية',
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: _isRowLocked ? null : _editLineDiscount,
              child: Icon(Icons.local_offer_outlined, size: 14, color: Colors.grey.shade500),
            ),
          ),
        ),
        onSubmitted: (v) {
          if (_applyTypedDiscount(v)) {
            _goNext('discount');
          } else {
            _discountFocusNode.requestFocus();
          }
        },
      ),
    );
  }

  // دالة لفتح قائمة نوع البيع برمجياً مع دعم التنقل بالكيبورد، ثم الانتقال للخانة التالية
  Future<void> _showSaleTypeMenu() async {
    if (_saleMenuOpen) return;
    final RenderBox? renderBox =
        _saleTypeKey.currentContext?.findRenderObject() as RenderBox?;
    // الحصول على خيارات نوع البيع
    final options = _getUnitOptionsStrings();
    if (renderBox == null || options.isEmpty) {
      _goNext('saleType');
      return;
    }

    final Offset offset = renderBox.localToGlobal(Offset.zero);
    final Size size = renderBox.size;

    // خيار واحد فقط: يُختار مباشرة ثم الخانة التالية
    if (options.length == 1) {
      if (_currentItem.saleType != options.first) await _updateSaleType(options.first);
      if (mounted) _goNext('saleType');
      return;
    }

    // تعيين أول خيار كقيمة افتراضية قبل فتح القائمة
    if (_currentItem.saleType == null || _currentItem.saleType!.isEmpty) {
      _updateSaleType(options.first);
    }

    // فتح القائمة المنبثقة المخصصة مع دعم التنقل بالكيبورد
    _saleMenuOpen = true;
    String? selected;
    try {
      selected = await showDialog<String>(
        context: context,
        barrierColor: Colors.transparent,
        builder: (BuildContext dialogContext) {
          return _SaleTypeDropdownDialog(
            options: options,
            initialValue: _currentItem.saleType ?? options.first,
            position: offset,
            size: size,
          );
        },
      );
    } finally {
      _saleMenuOpen = false;
    }
    if (!mounted) return;

    // نفس الوحدة لا يُعاد تسعيرها (كي لا يضيع سعر كُتب قبل الوحدة)
    if (selected != null && selected != _currentItem.saleType) {
      await _updateSaleType(selected);
      if (!mounted) return;
    }

    // الخانة التالية بعد الاختيار أو الإغلاق
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _goNext('saleType');
    });
  }
  
  // دالة مساعدة للحصول على خيارات نوع البيع كـ List<String>
  List<String> _getUnitOptionsStrings() {
    Product? product = widget.allProducts.firstWhere(
      (p) => p.name == _currentItem.productName,
      orElse: () => Product(
        id: null,
        name: '',
        unit: 'piece',
        unitPrice: 0,
        price1: 0,
        createdAt: DateTime.now(),
        lastModifiedAt: DateTime.now(),
      ),
    );
    
    // 🔧 استخدام method موجود في Product model لجلب جميع الوحدات
    List<String> options = product.getAllUnitLevels();
    
    // إذا كانت القائمة فارغة، استخدم الوحدة الأساسية
    if (options.isEmpty) {
      final baseUnit = product.unit == 'piece' ? 'قطعة' : (product.unit == 'meter' ? 'متر' : product.unit);
      options = [baseUnit];
    }
    
    // تنظيف القائمة
    options = options.where((e) => e.isNotEmpty).toSet().toList();
    
    // إضافة نوع البيع الحالي إذا لم يكن موجوداً
    if (_currentItem.saleType != null &&
        _currentItem.saleType!.isNotEmpty &&
        !options.contains(_currentItem.saleType)) {
      options.add(_currentItem.saleType!);
    }
    return options;
  }

  void _updateQuantity(String value) {
    double? newQuantity = safeParseDouble(value);
    if (newQuantity == null || newQuantity <= 0) return;

    // 🔒 التحقق من المخزون
    if (!widget.allowNegativeStock) {
      // جلب المنتج للتأكد من الرصيد الحالي
      final product = widget.allProducts.firstWhere(
        (p) => p.name == _currentItem.productName,
        orElse: () => Product(id: null, name: '', unit: 'piece', unitPrice: 0, price1: 0, 
            createdAt: DateTime.now(), lastModifiedAt: DateTime.now()),
      );
      
      if (product.id != null) {
        // حساب الكمية بالوحدة الأساسية
        double conversionFactor = 1.0;
        if (product.unit == 'piece' && _currentItem.saleType != 'قطعة') {
           try {
             List<dynamic> hierarchy = json.decode(product.unitHierarchy!.replaceAll("'", '"'));
             for (var unit in hierarchy) {
               if ((unit['unit_name'] ?? unit['name']) == _currentItem.saleType) {
                 conversionFactor = (unit['quantity'] as num).toDouble();
                 break;
               }
             }
           } catch (_) {}
        } else if (product.unit == 'meter' && _currentItem.saleType == 'لفة') {
           conversionFactor = product.lengthPerUnit ?? 1.0;
        }
        
        final double totalBaseUnits = newQuantity * conversionFactor;
        if (product.stockQuantity < totalBaseUnits) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('⚠️ الرصيد غير كافٍ! المتاح: ${NumberFormat('#,##0.###', 'en_US').format(product.stockQuantity)}'),
              backgroundColor: Colors.red,
            ),
          );
          // 🔒 BLOCK the update
          return; 
        }
      }
    }

    setState(() {
      // منطق موحد: دائماً المبلغ = السعر الحالي × العدد الحالي مباشرة
      _currentItem = _currentItem.copyWith(
        quantityIndividual:
            (_currentItem.saleType == 'قطعة' || _currentItem.saleType == 'متر')
                ? newQuantity
                : null,
        quantityLargeUnit:
            (_currentItem.saleType != 'قطعة' && _currentItem.saleType != 'متر')
                ? newQuantity
                : null,
        itemTotal: newQuantity * _currentItem.appliedPrice,
      );
      // لا تفرض ".00" عند الكتابة؛ استخدم تنسيق أرقام بدون كسور ثابتة
      _priceController.text = _formatNumber(_currentItem.appliedPrice);
    });
    widget.onItemUpdated(_currentItem);
  }

  Future<void> _updateSaleType(String newType) async {
    debugPrint('🔍 [تشخيص-صف-تغيير-وحدة] "${_currentItem.productName}" → "$newType" '
        '(السابقة: ${_currentItem.saleType} | السعر الحالي: ${_currentItem.appliedPrice})');
    Product? product = widget.allProducts.firstWhere(
      (p) => p.name == _currentItem.productName,
      orElse: () => Product(
        id: null,
        name: '',
        unit: 'piece',
        unitPrice: 0,
        price1: 0,
        createdAt: DateTime.now(),
        lastModifiedAt: DateTime.now(),
      ),
    );
    double conversionFactor = 1.0;
    debugPrint('🔍 [تشخيص-صف] unit="${product.unit}" | unitHierarchy=${product.unitHierarchy} | isWeighable=${product.isWeighable}');
    if (product.unit == 'piece' && newType != 'قطعة') {
      if (product.unitHierarchy != null &&
          product.unitHierarchy!.isNotEmpty) {
        try {
          List<dynamic> hierarchy =
              json.decode(product.unitHierarchy!.replaceAll("'", '"'));
          for (var unit in hierarchy) {
            if ((unit['unit_name'] ?? unit['name']) == newType) {
              conversionFactor = (unit['quantity'] as num).toDouble();
              break;
            }
          }
        } catch (_) {
          // هرمية وحدات تالفة: يبقى معامل التحويل 1
        }
      }
    } else if (product.unit == 'meter' && newType == 'لفة') {
      conversionFactor = product.lengthPerUnit ?? 1.0;
    } else if (newType != 'قطعة') {
      debugPrint('    ⚠️ [تشخيص-صف] لا فرع تحويل: unit="${product.unit}" ليست piece/mتر → معامل=1 (سبب خطأ الموزونات)');
    }
    debugPrint('    معامل التحويل المحسوب: $conversionFactor');

    // 🧠 استشارة محرك التسعير الذكي لنوع البيع المحدد
    double newAppliedPrice = 0.0;
    bool smartPriceFound = false;
    if (product.id != null) {
      try {
        final db = widget.databaseService ?? DatabaseService();
        int? custId;
        final custName = widget.currentCustomerName.trim();
        if (custName.isNotEmpty) {
          final c = await db.findCustomerByNormalizedName(custName);
          if (c != null) custId = c.id;
        }
        final smartResult = await SmartPricingService().getSmartPriceEnhanced(
          productId: product.id!,
          customerId: custId,
          saleType: newType,
        );
        if (smartResult != null && smartResult.price > 0) {
          newAppliedPrice = smartResult.price;
          smartPriceFound = true;
          final double baseForCalc = _currentItem.appliedPrice > 0
              ? _currentItem.appliedPrice
              : product.unitPrice;
          debugPrint('    🧠 [تشخيص-صف] التسعير الذكي طغى على التحويل! سعره=${smartResult.price} '
              '(التحويل الحسابي كان سيعطي: ${baseForCalc * conversionFactor})');
        }
      } catch (_) {}
    }

    if (!smartPriceFound) {
      if ((product.unit == 'piece' && newType != 'قطعة') ||
          (product.unit == 'meter' && newType == 'لفة')) {
        // عند التحويل من قطعة إلى باكيت أو من متر إلى لفة: السعر للوحدة الكبيرة = السعر الحالي × عامل التحويل
        newAppliedPrice = (_currentItem.appliedPrice > 0 ? _currentItem.appliedPrice : product.unitPrice) * conversionFactor;
      } else if ((product.unit == 'piece' &&
              _currentItem.saleType != 'قطعة' &&
              newType == 'قطعة') ||
          (product.unit == 'meter' &&
              _currentItem.saleType == 'لفة' &&
              newType == 'متر')) {
        // عند التحويل من باكيت إلى قطعة أو من لفة إلى متر: السعر للوحدة الصغيرة = السعر الحالي ÷ عامل التحويل
        newAppliedPrice = _currentItem.appliedPrice / conversionFactor;
      } else {
        newAppliedPrice = _currentItem.appliedPrice > 0 ? _currentItem.appliedPrice : product.unitPrice;
      }
    }

    double quantity = _currentItem.quantityIndividual ??
        _currentItem.quantityLargeUnit ??
        1;
    setState(() {
      _currentItem = _currentItem.copyWith(
        saleType: newType,
        appliedPrice: newAppliedPrice,
        unitsInLargeUnit: conversionFactor != 1.0 ? conversionFactor : null,
        itemTotal: quantity * newAppliedPrice,
        quantityIndividual:
            (newType == 'قطعة' || newType == 'متر') ? quantity : null,
        quantityLargeUnit:
            (newType != 'قطعة' && newType != 'متر') ? quantity : null,
      );
      debugPrint('    ✅ [تشخيص-صف] السعر الجديد: $newAppliedPrice | المجموع: ${quantity * newAppliedPrice} | smartPriceUsed=$smartPriceFound');
      _quantityController.text = _qtyText(quantity);
      // لا تفرض ".00" أثناء التحرير؛ اظهر فواصل فقط
      _priceController.text =
          (newAppliedPrice > 0) ? _formatNumber(newAppliedPrice) : '';
      widget.onItemUpdated(_currentItem);
      // (الانتقال بعد اختيار الوحدة يتولاه من استدعى الدالة حسب ترتيب Enter)
    });

    // 🎯 تظليل السعر بالكامل فوراً عند الانتقال
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_priceFocusNode.hasFocus && _priceController.text.isNotEmpty) {
        _priceController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _priceController.text.length,
        );
      }
    });

    // تحديث أقل سعر تاريخي عند تغيير نوع البيع
    _fetchLowestRecentPrice();
  }

  void _updatePrice(String value) {
    if (value.trim().isEmpty) {
      setState(() {
        _currentItem = _currentItem.copyWith(
          appliedPrice: 0.0,
          itemTotal: 0.0,
        );
      });
      widget.onItemUpdated(_currentItem);
      _fetchLowestRecentPrice();
      return;
    }
    double? newPrice = safeParseDouble(value);
    if (newPrice == null || newPrice < 0) return;
    setState(() {
      double quantity = _currentItem.quantityIndividual ??
          _currentItem.quantityLargeUnit ??
          1;
      // منطق السعر المخصص: إذا كان المستخدم أدخل سعراً يدوياً (غير مطابق لسعر الوحدة أو سعر التكلفة)
      
      // 🔧 Fix: استخدم _isPriceBelowCost للتحقق الموحد من التكلفة
      // هذا يشمل حساب التكلفة من الهرمية للوحدات الكبيرة
      // أولاً: حدّث appliedPrice مؤقتاً للتحقق
      _currentItem = _currentItem.copyWith(appliedPrice: newPrice);
      
      if (_isPriceBelowCost()) {
        if (!_hasShownLowPriceWarning) {
          _hasShownLowPriceWarning = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('⚠️ السعر المدخل أقل من سعر التكلفة!'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 5),
              ),
            );
          });
          // إعادة تعيين السماح بعرض التحذير مرة أخرى بعد التعديل التالي إذا لزم
          Future.delayed(const Duration(seconds: 5), () {
            if (mounted) setState(() => _hasShownLowPriceWarning = false);
          });
        }
      }
      // الحساب: المبلغ = السعر * العدد مباشرة بغض النظر عن نوع الوحدة
      _currentItem = _currentItem.copyWith(
        appliedPrice: newPrice,
        itemTotal: quantity * newPrice,
      );
      // اترك المُدخل كما يكتبه المستخدم؛ المُنسق سيضيف الفواصل تلقائياً
    });
    widget.onItemUpdated(_currentItem);
    // تحديث الأيقونة حسب السعر الحالي
    _fetchLowestRecentPrice();
  }

  Future<void> _fetchLowestRecentPrice() async {
    try {
      final db = widget.databaseService;
      if (db == null) return;
      final String customer = widget.currentCustomerName.trim();
      if (customer.isEmpty) return;
      final String productName = _currentItem.productName.trim();
      if (productName.isEmpty) return;
      final results = await db.getLastNPricesForCustomerProduct(
        customerName: customer,
        customerPhone: widget.currentCustomerPhone,
        productName: productName,
        limit: 3,
        saleType: _currentItem.saleType,
      );
      if (results.isEmpty) {
        setState(() {
          _lowestRecentPrice = null;
          _lowestRecentInfo = null;
        });
        return;
      }
      double minPrice = results
          .map((r) => (r['applied_price'] as num).toDouble())
          .reduce((a, b) => a < b ? a : b);
      final minRow = results.firstWhere(
          (r) => (r['applied_price'] as num).toDouble() == minPrice,
          orElse: () => results.first);
      final String dateStr = (minRow['invoice_date'] as String?) ?? '';
      final int? invoiceId = (minRow['invoice_id'] as int?);
      final String saleType = (minRow['sale_type'] as String?) ?? (_currentItem.saleType ?? '');
      setState(() {
        _lowestRecentPrice = minPrice;
        final String d = dateStr.isNotEmpty ? dateStr : '';
        final String idText = invoiceId != null ? 'فاتورة #${minRow['invoice_number'] ?? invoiceId}' : '';
        _lowestRecentInfo = [idText, d, saleType].where((s) => s.toString().trim().isNotEmpty).join(' — ');
      });
    } catch (_) {
      // ignore أخطاء الاستعلام البسيطة
    }
  }

  Future<void> _applyProductSelection(Product prod) async {
    final saleType = (prod.unit == 'piece') ? 'قطعة' : ((prod.unit == 'meter') ? 'متر' : prod.unit);
    
    // 🧠 السعر المقترح حسب «نمط التسعير» في الإعدادات (أنماط debt_book كلها):
    //   0 مطفأ (سعر المادة) • 1/3/5 آخر سعر ومتوسطات • 11–13 متوسط شهر/شهرين/3 أشهر
    //   21–23 الأكثر تكراراً • 99 ذكي • 101/102/103 شخصي (تكلفة/نسبة/هايبرد)
    // بلا نتيجة ⇒ سعر المادة نفسه.
    final double defaultPrice = prod.unitPrice > 0 ? prod.unitPrice : prod.price1;
    double suggestedPrice = defaultPrice;
    try {
      final db = widget.databaseService ?? DatabaseService();
      int mode = 99;
      try {
        mode = (await SettingsManager.getAppSettings()).pricingMode;
      } catch (_) {}
      int? custId;
      final custName = widget.currentCustomerName.trim();
      if (custName.isNotEmpty && mode != 0) {
        final c = await db.findCustomerByNormalizedName(custName);
        if (c != null) custId = c.id;
      }
      double? picked;
      if (mode == 0) {
        picked = null;
      } else if (mode == 101 || mode == 102 || mode == 103) {
        picked = await PersonalPricingService().getPersonalizedPriceForProduct(
          prod.name,
          saleType,
          custId,
          mode: mode,
          paymentType: widget.paymentType,
          preloadedProduct: prod,
        );
      } else if (mode == 99) {
        if (prod.id != null) {
          final smartResult = await SmartPricingService().getSmartPriceEnhanced(
            productId: prod.id!,
            customerId: custId,
            saleType: saleType,
          );
          picked = smartResult?.price;
        }
      } else {
        picked = await db.getHistoricalPriceForProduct(prod.name, saleType, mode);
      }
      if (picked != null && picked > 0) suggestedPrice = picked;
    } catch (_) {}

    final quantity = _currentItem.quantityIndividual ?? _currentItem.quantityLargeUnit ?? 1.0;
    if (!mounted) return;

    setState(() {
      _idController.text = prod.id?.toString() ?? '';
      _currentItem = _currentItem.copyWith(
        productId: prod.id, // ✅ Critical: Update ID
        productName: prod.name,
        unit: prod.unit,
        unitPrice: prod.unitPrice,
        saleType: saleType,
        appliedPrice: suggestedPrice,
        itemTotal: quantity * suggestedPrice,
        quantityIndividual: (saleType == 'قطعة' || saleType == 'متر') ? quantity : null,
        quantityLargeUnit: (saleType != 'قطعة' && saleType != 'متر') ? quantity : null,
        // السعر رجع للسعر المقترح ⇒ خصم السطر السابق لم يعد صالحاً
        priceBeforeDiscount: null,
        discountType: null,
        discountValue: null,
      );
      // مزامنة خانة التفاصيل والسعر فوراً
      _detailsController?.text = prod.name;
      _priceController.text = suggestedPrice > 0 ? _formatNumber(suggestedPrice) : '';
      // الكمية الفعلية تظهر في خانتها (1 إن لم تُكتب) — مهم إذا تخطاها Enter
      if (_quantityController.text.trim().isEmpty) _quantityController.text = _qtyText(quantity);
      _discountController.text = '';
    });
    widget.onItemUpdated(_currentItem);
    // (الانتقال للخانة التالية يتولاه _pickProduct حسب ترتيب Enter)
    // بعد اختيار المنتج، حدّث أقل سعر تاريخي لعرض الأيقونة إن لزم
    _fetchLowestRecentPrice();
  }

  /// 🏷️ خصم هذا السطر: نسبة/مبلغ/هدية/بلا خصم — يغيّر السعر الصافي والإجمالي
  Future<void> _editLineDiscount() async {
    final it = _currentItem;
    final r = await showLineDiscountDialog(
      context,
      listPrice: it.priceBeforeDiscount ?? it.appliedPrice,
      type: it.discountType,
      value: it.discountValue,
    );
    if (r == null || !mounted) return;
    final qty = it.soldQuantity;
    setState(() {
      _currentItem = _currentItem.copyWith(
        appliedPrice: r.net,
        itemTotal: qty * r.net,
        priceBeforeDiscount: r.type == null ? null : r.listPrice,
        discountType: r.type,
        discountValue: r.value,
      );
      _priceController.text = NumberFormat('#,##0.##', 'en_US').format(r.net);
      _discountController.text = _currentItem.discountLabel;
    });
    widget.onItemUpdated(_currentItem);
  }

  String formatCurrency(num value) {
    final formatter = NumberFormat('#,##0.##', 'en_US');
    return formatter.format(value);
  }
  @override
  Widget build(BuildContext context) {
    // 🧩 شبكة الجدول: لونها وسماكتها من الإعدادات ← تخطيط شاشة إنشاء فاتورة
    final Color gridBorderColor = InvoiceEntryLayout.current.gridColor;
    final double gridW = InvoiceEntryLayout.current.gridLineWidth;
    return Container(
      decoration: BoxDecoration(
        color: widget.index.isOdd ? const Color(0xFFF8FAFC) : Colors.white,
        border: Border(
          bottom: BorderSide(color: gridBorderColor, width: gridW),
          left: BorderSide(color: gridBorderColor, width: gridW),
          right: BorderSide(color: gridBorderColor, width: gridW),
        ),
      ),
      child: SizedBox(
        height: widget.rowHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // رقم الصف
            _cell('index', Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border(right: BorderSide(color: gridBorderColor, width: gridW)),
                ),
                child: Text((widget.index + 1).toString(),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium),
              )),

            // 🔢 المعرّف الداخلي (ID) — للعرض فقط
            _cell('code', Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border(right: BorderSide(color: gridBorderColor, width: gridW)),
              ),
              child: Text(
                '${_currentItem.productId ?? _rowProduct?.id ?? ''}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
            )),

            // 🏷️ رمز المادة (من بطاقة المادة) — يُكتب فيه للبحث بالرمز
            _cell('itemCode', Container(
              decoration: BoxDecoration(
                border: Border(right: BorderSide(color: gridBorderColor, width: gridW)),
              ),
              child: _CodeLookupField(
                barcodeMode: false,
                productId: _currentItem.productId ?? _rowProduct?.id,
                displayValue: ProductCodes.codeOf(_currentItem.productId ?? _rowProduct?.id) ?? '',
                readOnly: widget.isViewOnly,
                vPad: _vPad,
                getCurrentInvoiceProductNames: widget.getCurrentInvoiceProductNames,
                onPicked: _onProductChosen,
              ),
            )),

            // ▥ الباركود — يُكتب فيه أو يُمسح بالماسح للبحث بالباركود
            _cell('barcode', Container(
              decoration: BoxDecoration(
                border: Border(right: BorderSide(color: gridBorderColor, width: gridW)),
              ),
              child: _CodeLookupField(
                barcodeMode: true,
                productId: _currentItem.productId ?? _rowProduct?.id,
                displayValue: (_rowProduct?.barcode ?? '').trim(),
                readOnly: widget.isViewOnly,
                vPad: _vPad,
                getCurrentInvoiceProductNames: widget.getCurrentInvoiceProductNames,
                onPicked: _onProductChosen,
              ),
            )),

            // التفاصيل (اسم المنتج)
            _cell('details', Container(
                decoration: BoxDecoration(
                  border: Border(right: BorderSide(color: gridBorderColor, width: gridW)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: widget.isViewOnly
                    ? Text(widget.item.productName,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium)
                    : RawAutocomplete<Product>(
                        displayStringForOption: (Product p) => p.name,
                        textEditingController: _getOrCreateDetailsController(),
                        focusNode: _detailsFocusNode, // استخدام FocusNode الممرر من الخارج مباشرة
                        optionsBuilder: (TextEditingValue textEditingValue) async {
                          if (textEditingValue.text.isEmpty) {
                            return const Iterable<Product>.empty();
                          }
                          try {
                            // 🧠 استخدام البحث الذكي مع تمرير قائمة المنتجات الحالية لخفض أولويتها
                            final currentNames = widget.getCurrentInvoiceProductNames?.call();
                            return await SmartSearchService.instance.smartSearch(
                              textEditingValue.text,
                              currentInvoiceProductNames: currentNames,
                            );
                          } catch (e) {
                            debugPrint('Error in smart search: $e');
                            return widget.allProducts
                                .where((p) => p.name.contains(textEditingValue.text));
                          }
                        },
                        fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                          _detailsController = controller;
                          return TextField(
                            controller: controller,
                            focusNode: focusNode,
                            enabled: !widget.isViewOnly,
                            decoration: InputDecoration(
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                                borderSide: const BorderSide(color: Colors.transparent, width: 1),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                                borderSide: const BorderSide(color: Colors.transparent, width: 1),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                                borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
                              ),
                              contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: _vPad),
                              isDense: true,
                              filled: false,
                            ),
                            style: Theme.of(context).textTheme.bodyMedium,
                            onChanged: (val) {
                              _currentItem = _currentItem.copyWith(productName: val);
                              _validateStockByManualName(val); // 🔍 تحقق عند كل تغييرة
                            },
                            onSubmitted: (val) {
                              final seqBefore = _pickSeq;
                              onFieldSubmitted(); // قد يختار المادة المظللة في القائمة
                              _validateStockByManualName(val); // 🔍 تحقق نهائي عند الضغط على Enter
                              final sanitizedInput = val.trim().replaceAll(' ', '');
                              if (sanitizedInput.isNotEmpty) {
                                for (final p in widget.allProducts) {
                                  if (p.name.trim().replaceAll(' ', '') == sanitizedInput) {
                                    // نفس مادة السطر (المرور عليه بـ Enter): لا يُعاد تسعيرها
                                    if (p.id != null && p.id == _currentItem.productId) break;
                                    _pickProduct(p); // يطبّق المادة ثم ينقل المؤشر
                                    return;
                                  }
                                }
                              }
                              widget.onItemUpdated(_currentItem);
                              // اختيار من القائمة ينقل المؤشر بنفسه؛ والسطر الفارغ يبقى مكانه
                              if (_pickSeq != seqBefore || sanitizedInput.isEmpty) return;
                              _goNext('details');
                            },
                          );
                        },
                        optionsViewBuilder: (context, onSelected, options) {
                          return Align(
                            alignment: Alignment.topLeft,
                            child: Material(
                              elevation: 4.0,
                              borderRadius: BorderRadius.circular(8),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxHeight: 250, maxWidth: 350),
                                child: _ProductAutoScrollListView(
                                  options: options.toList(),
                                  onSelected: onSelected,
                                ),
                              ),
                            ),
                          );
                        },
                        onSelected: _onProductChosen,
                      ),
              )),
            // العدد
            _cell('qty', Container(
                decoration: BoxDecoration(
                  border: Border(right: BorderSide(color: gridBorderColor, width: gridW)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                alignment: Alignment.center,
                child: widget.isViewOnly
                    ? Text(
                        ((widget.item.quantityIndividual ??
                                    widget.item.quantityLargeUnit) ??
                                '')
                            .toString(),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      )
                    : TextFormField(
                        controller: _quantityController,
                        textAlign: TextAlign.center,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [ThousandSeparatorDecimalInputFormatter()],
                        enabled: !widget.isViewOnly && !_isRowLocked, // 🔒 قفل الحقل
                        onChanged: _updateQuantity, // الآن أصبح آمناً
                        focusNode: _quantityFocusNode,
                        onFieldSubmitted: (val) {
                          widget.onItemUpdated(_currentItem);
                          // 🧭 الخانة التالية حسب ترتيب Enter (الافتراضي: قائمة الوحدة)
                          _goNext('qty');
                        },
                        style: Theme.of(context).textTheme.bodyMedium,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: const BorderSide(color: Colors.transparent, width: 1),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: const BorderSide(color: Colors.transparent, width: 1),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
                          ),
                          contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: _vPad),
                          isDense: true,
                          filled: false,
                        ),
                      ),
              )),
            // نوع البيع
            _cell('saleType', Container(
                key: _saleTypeKey, // مفتاح لتحديد موقع القائمة المنبثقة
                decoration: BoxDecoration(
                  border: Border(right: BorderSide(color: gridBorderColor, width: gridW)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: widget.isViewOnly
                    ? Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                        ),
                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: _vPad),
                        child: Text(
                          widget.item.saleType ?? '',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      )
                    : Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _currentItem.saleType,
                            items: _getUnitOptions(),
                            onChanged: (widget.isViewOnly || _isRowLocked)
                                ? null
                                : (value) async {
                                    if (value == null || value == _currentItem.saleType) return;
                                    await _updateSaleType(value);
                                    // بالفأرة: إلى الخانة التالية داخل السطر فقط
                                    if (mounted) _goNext('saleType', finishRow: false);
                                  },
                            isExpanded: true,
                            isDense: widget.rowHeight < 40, // 🧩 سطر مضغوط
                            alignment: AlignmentDirectional.center,
                            style: Theme.of(context).textTheme.bodyMedium,
                            itemHeight: 48,
                            autofocus: _openSaleTypeDropdown,
                            focusNode: _saleTypeFocusNode,
                            onTap: () {
                              setState(() {
                                _openSaleTypeDropdown = false;
                              });
                            },
                          ),
                        ),
                      ),
              )),
            // السعر
            _cell('price', Container(
                decoration: BoxDecoration(
                  border: Border(right: BorderSide(color: gridBorderColor, width: gridW)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: widget.isViewOnly
                    ? Text(
                        formatCurrency(widget.item.appliedPrice),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      )
                    : TextFormField(
                        controller: _priceController,
                        textAlign: TextAlign.center,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        enabled: !widget.isViewOnly && !_isRowLocked, // 🔒 قفل الحقل
                        inputFormatters: [
                          ThousandSeparatorDecimalInputFormatter(),
                        ],
                        onChanged: _updatePrice, // الآن أصبح آمناً
                        focusNode: _priceFocusNode,
                        onFieldSubmitted: (val) {
                          widget.onItemUpdated(_currentItem);
                          // 🧭 الخانة التالية حسب الترتيب، أو اسم المادة في السطر التالي إن كان السعر آخرها
                          _goNext('price');
                        },
                        style: Theme.of(context).textTheme.bodyMedium,
                        decoration: InputDecoration(
                          // 🔧 إضافة مؤشر بصري للبيع بخسارة
                          // 🔧 تم إزالة أيقونة التحذير من داخل الحقل بناءً على طلب المستخدم
                          // والاكتفاء بالأيقونة الموجودة بجانب زر الحذف
                          suffixIcon: null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: const BorderSide(color: Colors.transparent, width: 1),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: const BorderSide(color: Colors.transparent, width: 1),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
                          ),
                          contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: _vPad),
                          isDense: true,
                          filled: false,
                        ),
                      ),
              )),
            // السعر قبل الخصم (للسطر المخصوم أو الهدية)
            _cell('listPrice', Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border(right: BorderSide(color: gridBorderColor, width: gridW)),
              ),
              child: Text(
                _currentItem.hasLineDiscount
                    ? formatCurrency(_currentItem.priceBeforeDiscount ?? _currentItem.appliedPrice)
                    : '',
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
              ),
            )),
            // 🏷️ الخصم / الهدية — ضمن مسار Enter: خانة يُكتب فيها (10% أو 500 أو «هدية»)؛
            //    وإلا: اضغط لتعديل خصم هذا السطر
            _cell('discount', _discountIsStop ? _discountField() : InkWell(
                onTap: (widget.isViewOnly || widget.isPlaceholder || _isRowLocked) ? null : _editLineDiscount,
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border(right: BorderSide(color: gridBorderColor, width: gridW)),
                  ),
                  child: Tooltip(
                    message: _currentItem.hasLineDiscount
                        ? 'قبل الخصم: ${formatCurrency(_currentItem.priceBeforeDiscount ?? _currentItem.appliedPrice)}'
                        : 'اضغط لإضافة خصم أو جعلها هدية',
                    child: _currentItem.hasLineDiscount
                        ? Text(
                            _currentItem.discountLabel,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _currentItem.isGift ? Colors.purple : Colors.green.shade800,
                            ),
                          )
                        : (widget.isViewOnly || widget.isPlaceholder
                            ? const SizedBox.shrink()
                            : Icon(Icons.local_offer_outlined, size: 16, color: Colors.grey.shade400)),
                  ),
                ),
              )),
            _cell('units', Container(
                alignment: Alignment.center,
                child: widget.isViewOnly
                  ? ((widget.item.saleType == 'قطعة' ||
                          widget.item.saleType == 'متر')
                      ? const SizedBox.shrink()
                      : Text(
                          widget.item.unitsInLargeUnit?.toStringAsFixed(0) ??
                              '',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium))
                  : (_currentItem.saleType == 'قطعة' ||
                          _currentItem.saleType == 'متر')
                      ? const SizedBox.shrink()
                      : Text(
                          _currentItem.unitsInLargeUnit?.toStringAsFixed(0) ??
                              '',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium),
              )),
            // المبلغ (Total) - Moved to end
            _cell('total', Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border(right: BorderSide(color: gridBorderColor, width: gridW)),
                ),
                child: widget.isViewOnly
                    ? Text(
                        formatCurrency(widget.item.itemTotal),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary),
                      )
                    : Text(
                        formatCurrency(_currentItem.itemTotal),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary),
                      ),
              )),
            // 📦 الرصيد في المخزن (بالوحدة الأساسية)
            _cell('stock', Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border(right: BorderSide(color: gridBorderColor, width: gridW)),
              ),
              child: Builder(builder: (context) {
                final p = _rowProduct;
                if (p == null) return const SizedBox.shrink();
                final q = p.stockQuantity;
                return Text(
                  NumberFormat('#,##0.##', 'en_US').format(q),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: q <= 0 ? Colors.red.shade700 : Colors.teal.shade700,
                  ),
                );
              }),
            )),
            // 💰 كلفة الوحدة المباعة
            _cell('cost', Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border(right: BorderSide(color: gridBorderColor, width: gridW)),
              ),
              child: Builder(builder: (context) {
                if (_currentItem.productName.isEmpty) return const SizedBox.shrink();
                final c = _effectiveCostPerUnit();
                final costText = Text(c == null ? '—' : formatCurrency(c),
                    style: TextStyle(fontSize: 12.5, color: Colors.grey.shade800));
                final dates = widget.costDates;
                if (dates == null) return costText;
                // 👑 Ctrl+D: الكلفة بلون بارز وتحتها تاريخ آخر تحديث لها
                final pid = _rowProduct?.id;
                final d = pid == null ? null : dates[pid];
                return FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(c == null ? '—' : formatCurrency(c),
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF15803D))),
                    Text(d == null ? 'لا تاريخ' : DateFormat('yyyy-MM-dd').format(d),
                        style: TextStyle(fontSize: 9.5, color: d == null ? Colors.grey : Colors.red.shade700)),
                  ]),
                );
              }),
            )),
            // 📈 ربح السطر = الإجمالي − الكلفة × الكمية
            _cell('profit', Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border(right: BorderSide(color: gridBorderColor, width: gridW)),
              ),
              child: Builder(builder: (context) {
                if (_currentItem.productName.isEmpty) return const SizedBox.shrink();
                final c = _effectiveCostPerUnit();
                if (c == null) return const Text('—');
                final profit = _currentItem.itemTotal - c * _currentItem.soldQuantity;
                return Text(formatCurrency(profit),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: profit < 0 ? Colors.red.shade700 : Colors.green.shade700,
                    ));
              }),
            )),
            // أيقونات التنبيه في أقصى اليمين
            SizedBox(
              width: 80, // زيادة العرض لاستيعاب أيقونتين
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // أيقونة تحذير حمراء: سعر البيع أقل من التكلفة
                  Builder(builder: (context) {
                    final bool showCostWarning = !widget.isViewOnly && 
                        !widget.isPlaceholder &&
                        _isPriceBelowCost();
                    if (!showCostWarning) return const SizedBox.shrink();
                    return const Tooltip(
                      message: '⚠️ تحذير: سعر البيع أقل من سعر التكلفة!',
                      preferBelow: false,
                      child: Icon(Icons.warning,
                          color: Colors.red, size: 22),
                    );
                  }),
                  // أيقونة تنبيه برتقالية: سعر أعلى من سعر سابق
                  Builder(builder: (context) {
                    final bool showIcon = _lowestRecentPrice != null &&
                        !widget.isViewOnly &&
                        _currentItem.appliedPrice > (_lowestRecentPrice ?? 0);
                    if (!showIcon) return const SizedBox.shrink();
                    return Tooltip(
                      message:
                          'سعر أقل سابقاً: ${formatCurrency(_lowestRecentPrice!)}\n${_lowestRecentInfo ?? ''}',
                      preferBelow: false,
                      child: Icon(Icons.error_outline,
                          color: Colors.orange.shade700, size: 22),
                    );
                  }),
                ],
              ),
            ),
            if (!widget.isViewOnly && !widget.isPlaceholder)
              SizedBox(
                width: 40,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.delete_outline,
                      color: Colors.red, size: widget.rowHeight < 40 ? 19 : 24),
                  onPressed: () =>
                      widget.onItemRemovedByUid(widget.item.uniqueId),
                  tooltip: 'حذف الصنف',
                ),
              )
            else
              const SizedBox(width: 40),
          ],
        ),
      ),
    );
  }
}

// أضف دالة مساعدة للتحقق من اكتمال الصف
bool _isInvoiceItemComplete(InvoiceItem item) {
  // التحقق من أن الكمية موجودة وأكبر من صفر
  final hasValidQuantity = (item.quantityIndividual != null && item.quantityIndividual! > 0) ||
                           (item.quantityLargeUnit != null && item.quantityLargeUnit! > 0);
  return (item.productName.isNotEmpty &&
      hasValidQuantity &&
      (item.appliedPrice > 0 || item.isGift) && // 🎁 الهدية سعرها صفر
      (item.itemTotal > 0 || item.isGift) &&
      (item.saleType != null && item.saleType!.isNotEmpty));
}

// إدارة FocusNode لكل صف
class LineItemFocusNodes {
  FocusNode details = FocusNode();
  FocusNode quantity = FocusNode();
  FocusNode price = FocusNode();
  void dispose() {
    details.dispose();
    quantity.dispose();
    price.dispose();
  }
}

// Widget مساعد للتمرير التلقائي في قائمة الاقتراحات - للمنتجات
/// 🏷️ خانة «رمز المادة» أو «الباركود» في سطر الفاتورة: تعرض قيمة مادة السطر،
/// ويُكتب فيها للبحث. الاقتراحات تُعرض «الرمز — الاسم» ويرتّبها البحث الذكي
/// (العلاقة مع مواد الفاتورة) كما في البحث بالاسم. Enter على رمز مطابق تماماً
/// (أو مسح الباركود بالماسح) يختار المادة مباشرة.
class _CodeLookupField extends StatefulWidget {
  const _CodeLookupField({
    required this.barcodeMode,
    required this.productId,
    required this.displayValue,
    required this.readOnly,
    required this.vPad,
    required this.onPicked,
    this.getCurrentInvoiceProductNames,
  });

  final bool barcodeMode;
  final int? productId;
  final String displayValue;
  final bool readOnly;
  final double vPad;
  /// يُرجع false إن رُفضت المادة (نافذة من المخزون مثلاً)
  final bool Function(Product) onPicked;
  final List<String> Function()? getCurrentInvoiceProductNames;

  @override
  State<_CodeLookupField> createState() => _CodeLookupFieldState();
}

class _CodeLookupFieldState extends State<_CodeLookupField> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  List<ProductCodeHit> _lastOptions = const [];
  int _searchSeq = 0;
  bool _picked = false;
  bool _suppressNextSearch = false; // نص كتبناه نحن بعد الاختيار — لا يفتح الاقتراحات
  // الباركود الذي اختيرت به المادة (قد يكون باركوداً إضافياً غير الأساسي)
  int? _pickedForId;
  String? _pickedCode;
  // ⌨️ لغة لوحة المفاتيح قبل دخول الخانة (تُرجع عند الخروج)
  int? _prevLayout;
  bool _layoutSwitched = false;

  void _enterKeyboard() {
    if (widget.barcodeMode || !ItemCodeKeyboard.forceEnglish || _layoutSwitched) return;
    _prevLayout = KeyboardLayoutSwitcher.switchToEnglish();
    _layoutSwitched = true;
  }

  void _leaveKeyboard() {
    if (!_layoutSwitched) return;
    _layoutSwitched = false;
    KeyboardLayoutSwitcher.restore(_prevLayout); // null = كانت إنجليزية أصلاً ⇒ لا شيء
    _prevLayout = null;
  }

  String get _shown =>
      (_pickedForId != null && _pickedForId == widget.productId && _pickedCode != null)
          ? _pickedCode!
          : widget.displayValue;

  @override
  void initState() {
    super.initState();
    _controller.text = _shown;
    _focus.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(covariant _CodeLookupField old) {
    super.didUpdateWidget(old);
    // لا نغيّر النص أثناء الكتابة
    if (!_focus.hasFocus && _controller.text != _shown) _controller.text = _shown;
  }

  void _onFocus() {
    if (_focus.hasFocus) {
      _suppressNextSearch = false;
      _enterKeyboard();
      // تظليل القيمة: ما يُكتب يحلّ محلها
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _focus.hasFocus) {
          _controller.selection = TextSelection(baseOffset: 0, extentOffset: _controller.text.length);
        }
      });
    } else {
      _leaveKeyboard();
      if (_controller.text != _shown) {
        // خرج دون اختيار ⇒ تعود قيمة مادة السطر
        _controller.text = _shown;
      }
    }
  }

  @override
  void dispose() {
    _leaveKeyboard();
    _focus.removeListener(_onFocus);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<List<ProductCodeHit>> _search(String q) {
    final names = widget.getCurrentInvoiceProductNames?.call();
    return widget.barcodeMode
        ? ProductCodes.searchByBarcode(q, currentInvoiceProductNames: names)
        : ProductCodes.searchByCode(q, currentInvoiceProductNames: names);
  }

  void _choose(ProductCodeHit hit) {
    _picked = true;
    if (!widget.onPicked(hit.product)) {
      _controller.text = _shown;
      return;
    }
    _pickedForId = hit.product.id;
    _pickedCode = hit.code.isEmpty ? null : hit.code;
    if (_controller.text != hit.code) {
      _suppressNextSearch = true;
      _controller.text = hit.code;
    }
  }

  Future<void> _submit(String value, VoidCallback onFieldSubmitted) async {
    final q = value.trim();
    if (q.isEmpty || q == _shown) {
      // لا تغيير ⇒ Enter يكمل إلى «اسم المادة»
      FocusScope.of(context).nextFocus();
      return;
    }
    // الماسح الضوئي يكتب بسرعة ثم Enter قبل وصول الاقتراحات ⇒ نبحث الآن
    final hits = await _search(q);
    if (!mounted) return;
    final ex = ProductCodes.exact(hits, q);
    if (ex != null) {
      _choose(ex);
      return;
    }
    _picked = false;
    if (_lastOptions.isNotEmpty) {
      onFieldSubmitted(); // المادة المظللة في القائمة
      if (_picked) return;
    }
    if (hits.length == 1) {
      _choose(hits.first);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(hits.isEmpty
          ? (widget.barcodeMode ? 'لا توجد مادة بهذا الباركود' : 'لا توجد مادة بهذا الرمز')
          : 'أكثر من مادة تطابق «$q» — اختر من القائمة'),
      backgroundColor: hits.isEmpty ? Colors.red.shade700 : Colors.orange.shade800,
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 12.5,
      color: Colors.grey.shade800,
    );
    if (widget.readOnly) {
      return Center(
        child: Text(_shown, style: style, maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr),
      );
    }
    return RawAutocomplete<ProductCodeHit>(
      textEditingController: _controller,
      focusNode: _focus,
      displayStringForOption: (h) => h.code,
      optionsBuilder: (v) async {
        final q = v.text.trim();
        if (_suppressNextSearch) {
          _suppressNextSearch = false;
          _lastOptions = const [];
          return const Iterable<ProductCodeHit>.empty();
        }
        if (q.isEmpty || !_focus.hasFocus || q == _shown) {
          _lastOptions = const [];
          return const Iterable<ProductCodeHit>.empty();
        }
        final seq = ++_searchSeq;
        final hits = await _search(q);
        if (seq != _searchSeq) return _lastOptions; // نتيجة قديمة
        _lastOptions = hits;
        return hits;
      },
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) => TextField(
        controller: controller,
        focusNode: focusNode,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        style: style,
        decoration: InputDecoration(
          isDense: true,
          filled: false,
          hintText: widget.barcodeMode ? '▥' : '#',
          hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
          contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: widget.vPad),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: Colors.transparent),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: Colors.transparent),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
          ),
        ),
        // يبقى المؤشر هنا حتى يُختار شيء (اختيار المادة ينقله بنفسه للخانة التالية)
        onEditingComplete: () {},
        onSubmitted: (v) => _submit(v, onFieldSubmitted),
      ),
      optionsViewBuilder: (context, onSelected, options) {
        final list = options.toList();
        return Align(
          alignment: AlignmentDirectional.topStart,
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(10),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280, maxWidth: 440, minWidth: 300),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                shrinkWrap: true,
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final h = list[i];
                  final highlighted = AutocompleteHighlightedOption.of(context) == i;
                  if (highlighted) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (context.mounted) Scrollable.ensureVisible(context, alignment: 0.5);
                    });
                  }
                  final stock = h.product.stockQuantity;
                  return InkWell(
                    onTap: () => onSelected(h),
                    child: Container(
                      color: highlighted ? const Color(0xFFEFF6FF) : null,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Text(h.code,
                              textDirection: TextDirection.ltr,
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF1E3A8A))),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(h.product.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          NumberFormat('#,##0.##', 'en_US').format(stock),
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: stock > 0 ? Colors.green.shade700 : Colors.red.shade600),
                        ),
                      ]),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
      onSelected: _choose,
    );
  }
}

class _ProductAutoScrollListView extends StatefulWidget {
  final List<Product> options;
  final void Function(Product) onSelected;

  const _ProductAutoScrollListView({
    required this.options,
    required this.onSelected,
  });

  @override
  State<_ProductAutoScrollListView> createState() => _ProductAutoScrollListViewState();
}

class _ProductAutoScrollListViewState extends State<_ProductAutoScrollListView> {
  final ScrollController _scrollController = ScrollController();
  // السعر + المخزون يحتاج مساحة أكبر قليلاً
  static const double _itemHeight = 60.0; 

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToHighlighted(int highlightedIndex) {
    if (!_scrollController.hasClients) return;
    
    final double targetOffset = highlightedIndex * _itemHeight;
    final double viewportHeight = _scrollController.position.viewportDimension;
    final double currentOffset = _scrollController.offset;
    
    if (targetOffset < currentOffset) {
      _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
    } else if (targetOffset + _itemHeight > currentOffset + viewportHeight) {
      _scrollController.animateTo(
        targetOffset + _itemHeight - viewportHeight,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      itemCount: widget.options.length,
      itemExtent: _itemHeight,
      itemBuilder: (context, index) {
        final product = widget.options[index];
        final int highlightedIndex = AutocompleteHighlightedOption.of(context);
        final bool isHighlighted = highlightedIndex == index;
        
        if (isHighlighted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToHighlighted(highlightedIndex);
          });
        }
        
        return Container(
          decoration: BoxDecoration(
            // 🔧 اللون انتقل إلى tileColor — DecoratedBox الملون فوق ListTile
            // كان يخفي رشّ الحبر (assertion)
            border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
          ),
          child: Material(type: MaterialType.transparency, child: ListTile(
            dense: true,
            tileColor: isHighlighted ? Colors.blue.shade50 : null,
            visualDensity: VisualDensity.compact,
            title: Text(
              product.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isHighlighted ? Colors.blue.shade900 : Colors.black87,
                fontWeight: isHighlighted ? FontWeight.bold : FontWeight.w500,
                fontSize: 13,
              ),
            ),
            subtitle: Row(
              children: [
                Text(
                  'المخزون: ${NumberFormat('#,##0.###', 'en_US').format(product.stockQuantity)}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                if (product.stockQuantity <= 0) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.info_outline, color: Colors.red, size: 12),
                  const SizedBox(width: 2),
                  const Text('نفذت الكمية', style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
                ],
              ],
            ),
            trailing: Text(
              '${NumberFormatter.format(product.price1)} ',
              style: TextStyle(
                fontSize: 12, 
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade700
              ),
            ),
            onTap: () => widget.onSelected(product),
          )),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 🔧 Widget مخصص لقائمة نوع البيع مع دعم التنقل بالكيبورد
// ═══════════════════════════════════════════════════════════════════════════
class _SaleTypeDropdownDialog extends StatefulWidget {
  final List<String> options;
  final String initialValue;
  final Offset position;
  final Size size;

  const _SaleTypeDropdownDialog({
    required this.options,
    required this.initialValue,
    required this.position,
    required this.size,
  });

  @override
  State<_SaleTypeDropdownDialog> createState() => _SaleTypeDropdownDialogState();
}

class _SaleTypeDropdownDialogState extends State<_SaleTypeDropdownDialog> {
  late int _selectedIndex;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    // البدء من أول خيار (أصغر وحدة)
    _selectedIndex = 0;
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _selectAndClose() {
    Navigator.of(context).pop(widget.options[_selectedIndex]);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // خلفية شفافة للإغلاق عند النقر خارج القائمة
        Positioned.fill(
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(null),
            child: Container(color: Colors.transparent),
          ),
        ),
        // القائمة المنسدلة
        Positioned(
          left: widget.position.dx,
          top: widget.position.dy + widget.size.height,
          width: widget.size.width,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(4),
            child: Focus(
              focusNode: _focusNode,
              autofocus: true,
              onKeyEvent: (node, event) {
                if (event is! KeyDownEvent) return KeyEventResult.ignored;

                if (event.logicalKey.keyLabel == 'Arrow Down') {
                  setState(() {
                    _selectedIndex = (_selectedIndex + 1) % widget.options.length;
                  });
                  return KeyEventResult.handled;
                } else if (event.logicalKey.keyLabel == 'Arrow Up') {
                  setState(() {
                    _selectedIndex = (_selectedIndex - 1 + widget.options.length) % widget.options.length;
                  });
                  return KeyEventResult.handled;
                } else if (event.logicalKey.keyLabel == 'Enter') {
                  _selectAndClose();
                  return KeyEventResult.handled;
                } else if (event.logicalKey.keyLabel == 'Escape') {
                  Navigator.of(context).pop(null);
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Container(
                constraints: const BoxConstraints(maxHeight: 200),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: widget.options.length,
                  itemBuilder: (context, index) {
                    final isSelected = index == _selectedIndex;
                    return InkWell(
                      onTap: () {
                        setState(() {
                          _selectedIndex = index;
                        });
                        _selectAndClose();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.red.shade50 : Colors.white,
                          border: isSelected
                              ? Border.all(color: Colors.red, width: 2)
                              : null,
                        ),
                        child: Text(
                          widget.options[index],
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: isSelected ? Colors.red : Colors.black87,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// Helper for parsing doubles with Arabic numerals support
double? safeParseDouble(String value) {
  if (value.trim().isEmpty) return null;
  String normalized = value
      .replaceAll('٠', '0')
      .replaceAll('١', '1')
      .replaceAll('٢', '2')
      .replaceAll('٣', '3')
      .replaceAll('٤', '4')
      .replaceAll('٥', '5')
      .replaceAll('٦', '6')
      .replaceAll('٧', '7')
      .replaceAll('٨', '8')
      .replaceAll('٩', '9')
      .replaceAll(',', ''); // Remove thousands separator
  try {
     return double.tryParse(normalized);
  } catch (e) {
     return null;
  }
}