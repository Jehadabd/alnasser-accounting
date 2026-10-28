// lib/screens/pos/pos_screen.dart
//
// 🧾 نقطة البيع (الكاشير) — تخطيط مرن حسب عرض الشاشة:
//  • عريضة (≥ 1150): أقسام عمودية | المواد | السلة
//  • متوسطة (≥ 760): المواد مع شريط أقسام أفقي | السلة
//  • صغيرة (تابلت عمودي/هاتف): المواد، وشريط سفلي يفتح السلة
// اختصارات: F2 البحث، F9 الدفع. قارئ الباركود يكتب في حقل البحث، و Enter يضيف المادة.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/app_settings.dart';
import '../../models/product.dart';
import '../../providers/pos_provider.dart';
import '../../services/settings_manager.dart';
import '../../widgets/app_side_nav.dart';
import '../../widgets/camera_barcode_scanner_dialog.dart';
import '../../widgets/continuous_barcode_scanner.dart';
import 'pos_receipts_screen.dart';
import 'widgets/cart_panel.dart';
import 'widgets/categories_sidebar.dart';
import 'widgets/pos_style.dart';
import 'widgets/products_grid.dart';

class POSScreen extends StatefulWidget {
  const POSScreen({super.key});

  @override
  State<POSScreen> createState() => _POSScreenState();
}

class _POSScreenState extends State<POSScreen> {
  final _focusNode = FocusNode(debugLabel: 'pos-root');
  final _searchFocus = FocusNode(debugLabel: 'pos-search');
  final _searchController = TextEditingController();
  final _cartKey = GlobalKey<CartPanelState>();
  final _sheetCartKey = GlobalKey<CartPanelState>(); // السلة المنبثقة (شاشة صغيرة)

  String _barcodeBuffer = '';
  DateTime? _lastKeyTime;

  /// الفاصل الزمني الأقصى بين ضغطات المفاتيح من قارئ الباركود
  static const _barcodeTimeout = Duration(milliseconds: 100);

  AppSettings? _appSettings;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<POSProvider>().loadInitialData();
      _searchFocus.requestFocus(); // قارئ الباركود يكتب في حقل البحث مباشرة
    });
  }

  Future<void> _loadSettings() async {
    final settings = await SettingsManager.getAppSettings();
    if (mounted) setState(() => _appSettings = settings);
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _searchFocus.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// هل التركيز الآن داخل حقل كتابة؟ (الحقل يستقبل الحروف بنفسه)
  bool get _typingInField {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    return ctx.widget is EditableText || ctx.findAncestorStateOfType<EditableTextState>() != null;
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    // ⌨️ الاختصارات
    if (event.logicalKey == LogicalKeyboardKey.f2) {
      _focusSearch();
      return;
    }
    if (event.logicalKey == LogicalKeyboardKey.f9) {
      (_cartKey.currentState ?? _sheetCartKey.currentState)?.checkout();
      return;
    }

    // داخل حقل كتابة: لا نجمع الحروف (كانت تختلط بكتابة اسم العميل أو الخصم)
    if (_typingInField) {
      _barcodeBuffer = '';
      return;
    }

    // قارئ الباركود والتركيز خارج الحقول
    final now = DateTime.now();
    if (_lastKeyTime != null && now.difference(_lastKeyTime!) > _barcodeTimeout) {
      _barcodeBuffer = '';
    }
    _lastKeyTime = now;

    if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (_barcodeBuffer.isNotEmpty) {
        _processBarcode(_barcodeBuffer);
        _barcodeBuffer = '';
      }
      return;
    }

    final char = event.character;
    if (char != null && char.isNotEmpty && !char.contains('\n')) {
      _barcodeBuffer += char;
    }
  }

  void _focusSearch() {
    _searchFocus.requestFocus();
    _searchController.selection = TextSelection(baseOffset: 0, extentOffset: _searchController.text.length);
  }

  void _clearSearch() {
    _searchController.clear();
    context.read<POSProvider>().setSearchQuery('');
    _searchFocus.requestFocus();
  }

  void _toast(String msg, Color color, {int ms = 1200}) {
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      duration: Duration(milliseconds: ms),
    ));
  }

  Future<void> _processBarcode(String barcode) async {
    final code = barcode.trim();
    if (code.isEmpty) return;
    final pos = context.read<POSProvider>();
    final product = await pos.addProductByBarcode(code);
    if (!mounted) return;
    if (product != null) {
      _toast('✓ أُضيفت: ${product.name}', PosColors.cash);
    } else {
      _toast(pos.lastErrorMessage ?? 'لم يُعثر على مادة بالباركود: $code', PosColors.credit, ms: 2200);
    }
  }

  /// للمسح المستمر بالكاميرا: يضيف للسلة ويعيد الاسم أو سبب الفشل (بلا رسائل منبثقة)
  Future<({String? name, String? error})> _scanToCart(String code) async {
    final pos = context.read<POSProvider>();
    final product = await pos.addProductByBarcode(code);
    if (product != null) return (name: product.name, error: null);
    return (name: null, error: pos.lastErrorMessage ?? 'لا توجد مادة بهذا الباركود');
  }

  /// Enter في حقل البحث: باركود ⇒ يُضاف مباشرة، أو نتيجة واحدة ⇒ تُضاف
  Future<void> _submitSearch(String text) async {
    final q = text.trim();
    if (q.isEmpty) return;
    final pos = context.read<POSProvider>();
    final byCode = await pos.addProductByBarcode(q);
    if (!mounted) return;
    if (byCode != null) {
      _clearSearch();
      _toast('✓ أُضيفت: ${byCode.name}', PosColors.cash);
      return;
    }
    final list = pos.displayedProducts;
    if (list.length == 1) {
      if (_addProduct(list.first)) _clearSearch();
      return;
    }
    _toast(
      list.isEmpty ? (pos.lastErrorMessage ?? 'لا توجد مادة بهذا الاسم أو الباركود') : 'اختر المادة من النتائج (${list.length})',
      PosColors.credit,
      ms: 1800,
    );
  }

  /// إضافة مادة للسلة (مع منع المادة النافدة إن كان البيع بالسالب ممنوعاً)
  bool _addProduct(Product p) {
    final pos = context.read<POSProvider>();
    if (p.stockQuantity <= 0 && !pos.allowNegativeStock) {
      _toast('نفذت كمية «${p.name}»', PosColors.danger, ms: 1800);
      return false;
    }
    pos.addToCart(p);
    if (pos.basePriceOf(p) <= 0) {
      _toast('«${p.name}» بلا سعر — اكتب السعر في السلة', PosColors.warn, ms: 2200);
    }
    return true;
  }

  void _onProductTap(Product p) {
    _addProduct(p);
    _searchFocus.requestFocus();
  }

  Future<void> _openCartSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.94,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          child: Material(
            color: PosColors.surface,
            child: Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(color: PosColors.border, borderRadius: BorderRadius.circular(4)),
                ),
                Expanded(
                  child: CartPanel(key: _sheetCartKey, onCheckedOut: () => Navigator.of(ctx).maybePop()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (mounted) _searchFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final showNav = _appSettings != null && AppSideNav.shouldShow(context, _appSettings!);
    final compactBar = MediaQuery.sizeOf(context).width < 640;

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: PosColors.bg,
        appBar: AppBar(
          backgroundColor: PosColors.surface,
          surfaceTintColor: Colors.transparent,
          foregroundColor: PosColors.text,
          elevation: 0,
          scrolledUnderElevation: 0,
          titleSpacing: 16,
          shape: const Border(bottom: BorderSide(color: PosColors.border)),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: PosColors.primary, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.point_of_sale_rounded, color: Colors.white, size: 19),
              ),
              const SizedBox(width: 10),
              const Flexible(
                child: Text(
                  'نقطة البيع',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          actions: [
            _PriceLevelPicker(onChanged: () => _searchFocus.requestFocus()),
            const SizedBox(width: 4),
            if (compactBar)
              IconButton(
                tooltip: 'الإيصالات',
                icon: const Icon(Icons.receipt_long_rounded, color: PosColors.primary),
                onPressed: _openReceipts,
              )
            else
              TextButton.icon(
                onPressed: _openReceipts,
                icon: const Icon(Icons.receipt_long_rounded, color: PosColors.primary, size: 20),
                label: const Text('الإيصالات', style: TextStyle(color: PosColors.primary, fontWeight: FontWeight.w700)),
              ),
            IconButton(
              tooltip: 'مسح باركود بالكاميرا',
              icon: const Icon(Icons.qr_code_scanner_rounded, color: PosColors.primary),
              onPressed: () async {
                // الهاتف: كاميرا تبقى مفتوحة (أو تُغلق بعد كل مادة حسب الإعداد). الحاسبة: إدخال يدوي/قارئ USB
                if (ContinuousScanPrefs.cameraAvailable) {
                  await ContinuousBarcodeScanner.open(context, _scanToCart);
                  _searchFocus.requestFocus();
                  return;
                }
                final scanned = await CameraBarcodeScannerDialog.scan(context);
                if (scanned != null && scanned.isNotEmpty) _processBarcode(scanned);
              },
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Row(
          children: [
            if (showNav) const AppSideNav(currentRoute: '/pos'),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) {
                  final w = box.maxWidth;
                  if (w >= PosBreakpoints.wide) {
                    final cartW = (w * 0.33).clamp(380.0, 470.0);
                    return Row(
                      children: [
                        const SizedBox(width: 176, child: CategoriesSidebar()),
                        Expanded(child: _products(showChips: false)),
                        SizedBox(width: cartW, child: CartPanel(key: _cartKey)),
                      ],
                    );
                  }
                  if (w >= PosBreakpoints.medium) {
                    final cartW = (w * 0.42).clamp(330.0, 400.0);
                    return Row(
                      children: [
                        Expanded(child: _products(showChips: true)),
                        SizedBox(width: cartW, child: CartPanel(key: _cartKey)),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      Expanded(child: _products(showChips: true)),
                      _MiniCartBar(onOpen: _openCartSheet),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _products({required bool showChips}) => ProductsGrid(
        searchController: _searchController,
        searchFocus: _searchFocus,
        onSubmitSearch: _submitSearch,
        onProductTap: _onProductTap,
        showCategoryChips: showChips,
      );

  void _openReceipts() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const PosReceiptsScreen()))
        .then((_) => _searchFocus.requestFocus());
  }
}

/// 💰 مستوى السعر (مفرد، جملة…) — يُحفظ على هذا الجهاز
class _PriceLevelPicker extends StatelessWidget {
  const _PriceLevelPicker({required this.onChanged});

  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Consumer<POSProvider>(
      builder: (context, pos, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Container(
          padding: const EdgeInsetsDirectional.fromSTEB(10, 0, 6, 0),
          decoration: BoxDecoration(
            color: PosColors.accentSoft,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFC7D2FE)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: pos.priceLevel,
              isDense: true,
              borderRadius: BorderRadius.circular(12),
              icon: const Icon(Icons.expand_more_rounded, color: PosColors.accent, size: 20),
              style: const TextStyle(color: PosColors.primary, fontWeight: FontWeight.w700, fontSize: 13),
              selectedItemBuilder: (_) => [
                for (final l in POSProvider.priceLevels)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.sell_outlined, size: 16, color: PosColors.accent),
                      const SizedBox(width: 6),
                      Text('السعر: $l'),
                    ],
                  ),
              ],
              items: [
                for (final l in POSProvider.priceLevels) DropdownMenuItem(value: l, child: Text(l)),
              ],
              onChanged: (v) {
                if (v != null) pos.setPriceLevel(v);
                onChanged();
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// شريط السلة السفلي على الشاشات الصغيرة
class _MiniCartBar extends StatelessWidget {
  const _MiniCartBar({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Consumer<POSProvider>(
      builder: (context, pos, _) {
        final n = pos.cartItems.length;
        final cash = pos.paymentType == PaymentType.cash;
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: const BoxDecoration(
            color: PosColors.surface,
            border: Border(top: BorderSide(color: PosColors.border)),
            boxShadow: [BoxShadow(color: Color(0x140F172A), blurRadius: 14, offset: Offset(0, -4))],
          ),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        n == 0 ? 'السلة فارغة' : '$n مادة في السلة',
                        style: const TextStyle(fontSize: 12.5, color: PosColors.muted),
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          posMoney(pos.total),
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: cash ? PosColors.cash : PosColors.credit,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: onOpen,
                    style: FilledButton.styleFrom(
                      backgroundColor: PosColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                    ),
                    icon: const Icon(Icons.shopping_basket_outlined, size: 20),
                    label: const Text('السلة والدفع', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
