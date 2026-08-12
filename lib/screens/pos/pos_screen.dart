import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/pos_provider.dart';
import 'widgets/categories_sidebar.dart';
import 'widgets/products_grid.dart';
import 'widgets/cart_panel.dart';

class POSScreen extends StatefulWidget {
  const POSScreen({super.key});

  @override
  State<POSScreen> createState() => _POSScreenState();
}

class _POSScreenState extends State<POSScreen> {
  final _focusNode = FocusNode();
  String _barcodeBuffer = '';
  DateTime? _lastKeyTime;
  
  // الفاصل الزمني الأقصى بين ضغطات المفاتيح من قارئ الباركود
  static const _barcodeTimeout = Duration(milliseconds: 100);
  
  @override
  void initState() {
    super.initState();
    // Load data after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<POSProvider>().loadInitialData();
      // طلب التركيز لاستقبال مدخلات الباركود
      _focusNode.requestFocus();
    });
  }
  
  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }
  
  void _handleKeyEvent(KeyEvent event) {
    // نتعامل فقط مع الضغطات (وليس الرفع)
    if (event is! KeyDownEvent) return;
    
    final now = DateTime.now();
    
    // إذا مرّ وقت طويل، نعيد تعيين البافر (مدخلات يدوية وليس من القارئ)
    if (_lastKeyTime != null && 
        now.difference(_lastKeyTime!) > _barcodeTimeout) {
      _barcodeBuffer = '';
    }
    _lastKeyTime = now;
    
    // Enter = نهاية الباركود
    if (event.logicalKey == LogicalKeyboardKey.enter || 
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (_barcodeBuffer.isNotEmpty) {
        _processBarcode(_barcodeBuffer);
        _barcodeBuffer = '';
      }
      return;
    }
    
    // تجميع الحرف
    final char = event.character;
    if (char != null && char.isNotEmpty && !char.contains('\n')) {
      _barcodeBuffer += char;
    }
  }
  
  void _processBarcode(String barcode) {
    final product = context.read<POSProvider>().addProductByBarcode(barcode);
    if (product != null) {
      // تم إضافة المنتج بنجاح
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ تم إضافة: ${product.name}'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 1),
        ),
      );
    } else {
      // لم يتم العثور على المنتج
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠ لم يتم العثور على منتج بالباركود: $barcode'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('نقطة البيع (الكاشير)'),
          backgroundColor: Colors.white,
          elevation: 0,
          foregroundColor: Colors.black,
        ),
        body: Row(
          children: [
            // Categories - Right (RTL) or Left
            const Expanded(
              flex: 2, 
              child: CategoriesSidebar(),
            ),
            
            // Products - Center
            const Expanded(
              flex: 4,
              child: ProductsGrid(),
            ),
            
            // Cart - Left (RTL) or Right - Larger for better visibility
            const Expanded(
              flex: 4,
              child: CartPanel(),
            ),
          ],
        ),
      ),
    );
  }
}
