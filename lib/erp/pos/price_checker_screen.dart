// lib/erp/pos/price_checker_screen.dart
//
// 🔎 قارئ الأسعار للزبائن (مثل سهل): شاشة كاملة على جهاز أو شاشة ثانية؛ الزبون
// يمرّر الباركود أمام الماسح فيظهر اسم المادة وسعرها (وأسعار وحداتها الكبرى).
// قراءة فقط — لا يغيّر شيئاً، ولا يُظهر الكلفة أبداً.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../accounting/screens/acc_ui.dart';
import '../../models/product.dart';
import '../../services/database_service.dart';
import 'scale_barcode.dart';

class PriceCheckerScreen extends StatefulWidget {
  const PriceCheckerScreen({super.key});
  @override
  State<PriceCheckerScreen> createState() => _PriceCheckerScreenState();
}

class _PriceCheckerScreenState extends State<PriceCheckerScreen> {
  final _ctl = TextEditingController();
  final _focus = FocusNode();
  Product? _product;
  double? _price;
  List<Map<String, Object?>> _units = const [];
  String? _error;
  double? _scaleQty;
  Timer? _reset;
  bool _full = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _reset?.cancel();
    _ctl.dispose();
    _focus.dispose();
    if (_full) SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _lookup(String code) async {
    final c = code.trim();
    _ctl.clear();
    _focus.requestFocus();
    if (c.isEmpty) return;
    final dbs = DatabaseService();
    Product? p;
    double? price;
    double? scaleQty;
    try {
      p = await dbs.findProductByBarcode(c);
      if (p != null) price = (await dbs.getBarcodePrice(c))['sell_price'];
      if (p == null) {
        final hit = await ScaleBarcode.parse(c);
        if (hit != null) {
          p = await dbs.getProductById(hit.productId);
          scaleQty = hit.quantityKg;
        }
      }
    } catch (_) {}
    final units = <Map<String, Object?>>[];
    if (p != null) {
      for (final u in p.getUnitHierarchyList()) {
        final name = '${u['unit_name'] ?? ''}';
        final q = (u['quantity'] as num?)?.toDouble() ?? 1;
        final pr = (u['price'] as num?)?.toDouble() ?? p.unitPrice * q;
        if (name.isNotEmpty) units.add({'name': name, 'qty': q, 'price': pr});
      }
    }
    if (!mounted) return;
    setState(() {
      _product = p;
      _price = price ?? p?.unitPrice;
      _units = units;
      _scaleQty = scaleQty;
      _error = p == null ? 'المادة غير معرّفة — راجع الكاشير' : null;
    });
    _reset?.cancel();
    _reset = Timer(const Duration(seconds: 10), () {
      if (mounted) {
        setState(() {
          _product = null;
          _error = null;
        });
      }
    });
  }

  void _toggleFull() {
    _full = !_full;
    SystemChrome.setEnabledSystemUIMode(_full ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
    setState(() {});
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final p = _product;
    return Scaffold(
      body: GestureDetector(
        onTap: () => _focus.requestFocus(),
        child: Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0B1F3A), Color(0xFF0F3460), Color(0xFF1B6CA8)],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
          ),
          child: SafeArea(
            child: Stack(children: [
              Positioned(
                top: 8,
                left: 8,
                child: Row(children: [
                  IconButton(
                    tooltip: 'ملء الشاشة',
                    icon: Icon(_full ? Icons.fullscreen_exit : Icons.fullscreen, color: Colors.white70),
                    onPressed: _toggleFull,
                  ),
                  IconButton(
                    tooltip: 'خروج',
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.pop(context),
                  ),
                ]),
              ),
              // حقل الماسح (شبه مخفي)
              Positioned(
                bottom: 0,
                left: 0,
                width: 1,
                height: 1,
                child: Opacity(
                  opacity: 0,
                  child: TextField(controller: _ctl, focusNode: _focus, autofocus: true, onSubmitted: _lookup),
                ),
              ),
              Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: p == null ? _idle() : _card(p),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _idle() => Column(key: const ValueKey('idle'), mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.qr_code_scanner_rounded, size: 120, color: Colors.white),
        const SizedBox(height: 20),
        const Text('قارئ الأسعار', style: TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        const Text('يرجى تمرير الباركود أمام الماسح الضوئي', style: TextStyle(color: Colors.white70, fontSize: 22)),
        if (_error != null) ...[
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            decoration: BoxDecoration(color: Colors.red.withOpacity(.25), borderRadius: BorderRadius.circular(30)),
            child: Text(_error!, style: const TextStyle(color: Colors.white, fontSize: 20)),
          ),
        ],
      ]);

  Widget _card(Product p) {
    final price = _price ?? p.unitPrice;
    final base = p.unit == 'piece' ? 'قطعة' : (p.unit == 'meter' ? 'متر' : p.unit);
    return Container(
      key: ValueKey('p${p.id}${DateTime.now().millisecondsSinceEpoch}'),
      constraints: const BoxConstraints(maxWidth: 720),
      margin: const EdgeInsets.all(24),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(.3), blurRadius: 40, offset: const Offset(0, 16))],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(p.name,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold, color: Color(0xFF0F3460))),
        if ((p.barcode ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(p.barcode!, style: const TextStyle(color: Colors.grey, fontSize: 16)),
          ),
        const SizedBox(height: 20),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text('${fmtMoney(price)} د.ع',
              style: const TextStyle(fontSize: 72, fontWeight: FontWeight.w900, color: Color(0xFF0E7C61))),
        ),
        Text('لكل $base', style: const TextStyle(fontSize: 20, color: Colors.grey)),
        if (_scaleQty != null) ...[
          const SizedBox(height: 12),
          Text('الوزن ${_scaleQty!.toStringAsFixed(3)} • المبلغ ${fmtMoney(price * _scaleQty!)} د.ع',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        ],
        if (_units.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Divider(),
          Wrap(spacing: 14, runSpacing: 14, alignment: WrapAlignment.center, children: [
            for (final u in _units)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(color: const Color(0xFFF1F5FB), borderRadius: BorderRadius.circular(16)),
                child: Column(children: [
                  Text('${u['name']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  Text('${fmtMoney((u['price'] as double))} د.ع',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1B6CA8))),
                ]),
              ),
          ]),
        ],
      ]),
    );
  }
}
