// screens/add_transaction_screen.dart
// screens/add_transaction_screen.dart
import '../services/save_lock.dart'; // 🔒 قفل الحفظ
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import '../providers/app_provider.dart';
import '../models/customer.dart';
import '../models/transaction.dart';
import 'package:intl/intl.dart' hide TextDirection; // For currency formatting (TextDirection من Flutter)
import '../widgets/formatters.dart';
import 'dart:io';
import 'dart:async';

import '../services/receipt_voucher_pdf_service.dart';
import '../models/customer_receipt_voucher.dart';
import '../services/database_service.dart';
import '../services/credit_limit_guard.dart'; // 🚫 سقف الدين
// import '../services/drive_service.dart'; // Removed
import 'package:uuid/uuid.dart';
import 'package:pdf/widgets.dart' as pw;
import '../utils/money_calculator.dart'; // 🔒 إضافة MoneyCalculator للأمان المالي
import '../services/logo_service.dart'; // 🖼️ Custom logo loading
import '../accounting/vouchers_service.dart' show VouchersService;
import '../erp/device_defaults.dart';
import '../erp/debts/receipts_service.dart';
import '../erp/debts/receipt_pdf.dart';
import '../services/voucher_print.dart'; // 🧾 إعداد طباعة سند القبض
import '../erp/report_export.dart';
import '../accounting/screens/acc_ui.dart' show accAppBar;
import 'dart:math' as math;
import '../erp/debts/customer_money.dart';
import '../owner/founder_service.dart';
import '../services/debt_return_service.dart';

class AddTransactionScreen extends StatefulWidget {
  final Customer customer;

  /// true = «إضافة دين»، false = «تسديد». زرّا صفحة العميل يفتحان الشاشة على النوع المطلوب.
  final bool initialIsDebt;

  const AddTransactionScreen({
    super.key,
    required this.customer,
    this.initialIsDebt = true,
  });

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  bool _isDebt = true; // true for adding debt, false for paying debt
  bool _isSaving = false; // 🔒 منع الضغط المزدوج على زر الحفظ

  // ↩️ تسديد دين راجع (كما في سجل الديون): يُنقص الدين بلا نقد، ويخصم نقاط المؤسس
  bool _isReturn = false;
  bool _loadingInv = false;
  List<ReturnableInvoice> _invoices = [];
  final List<int> _picked = []; // بترتيب الاختيار: المبلغ يُوزَّع عليها بهذا الترتيب
  final _invSearch = TextEditingController();


  // 🔒 لا يضيف جهازان (أو شاشتان على نفس الحاسبة) معاملة لنفس العميل في اللحظة
  //    نفسها: الشاشة تحجز العميل ما دامت مفتوحة، وتحرره عند الإغلاق.
  static const _lockType = 'debt_entry';
  bool _holdsLock = false;
  Timer? _lockBeat;

  @override
  void initState() {
    super.initState();
    _isDebt = widget.initialIsDebt;
    WidgetsBinding.instance.addPostFrameCallback((_) => _lockCustomer());
  }

  Future<void> _lockCustomer() async {
    final id = widget.customer.id;
    if (id == null) return;
    final locks = DatabaseService().lockingService;
    final r = await locks.acquireLock(resourceType: _lockType, resourceId: id);
    if (!mounted) {
      if (r.success) await locks.releaseLock(resourceType: _lockType, resourceId: id);
      return;
    }
    if (r.success) {
      _holdsLock = true;
      _lockBeat = Timer.periodic(const Duration(minutes: 2), (_) {
        locks.keepAlive(resourceType: _lockType, resourceId: id);
      });
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('العميل مشغول الآن'),
        content: Text(
          'يُضاف الآن دين أو تسديد للعميل «${widget.customer.name}»'
          '${r.lockedBy != null && r.lockedBy!.isNotEmpty ? ' عند ${r.lockedBy}' : ' على جهاز أو شاشة أخرى'}.\n'
          'انتظر حتى تُحفظ تلك المعاملة أو تُغلق شاشتها، ثم أعد المحاولة.',
          style: const TextStyle(height: 1.6),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('حسناً'))],
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _lockBeat?.cancel();
    final id = widget.customer.id;
    if (_holdsLock && id != null) {
      DatabaseService().lockingService.releaseLock(resourceType: _lockType, resourceId: id);
    }
    _amountController.dispose();
    _noteController.dispose();
    _invSearch.dispose();
    super.dispose();
  }

  // Helper to format currency with thousand separators (no decimals)
  String formatCurrency(num value) {
    return NumberFormat('#,##0', 'en_US').format(value);
  }

  // 🔒 لا يُنفَّذ مرتين مهما كانت سرعة الضغط (القفل قبل أي انتظار)
  Future<void> _saveTransaction() async {
    await SaveLock.run(() => _saveTransactionUnlocked(), message: 'جارٍ حفظ المعاملة…');
  }
  Future<void> _saveTransactionUnlocked() async {
    // 🔒 منع الضغط المزدوج - إذا كانت العملية جارية، لا تفعل شيئاً
    if (_isSaving) return;
    
    if (_formKey.currentState!.validate()) {
      // 🔒 تفعيل حالة الحفظ فوراً قبل أي عملية async
      setState(() => _isSaving = true);
      
      try {
      final amount = double.parse(_amountController.text.replaceAll(',', ''));
      final amountChanged = _isDebt ? amount : -amount;
      
      // ═══════════════════════════════════════════════════════════════════════════
      // 🔒 تحسين الأمان: استخدام MoneyCalculator لضمان دقة الحسابات
      // ═══════════════════════════════════════════════════════════════════════════
      final balanceBefore = widget.customer.currentTotalDebt;
      final newBalance = MoneyCalculator.add(balanceBefore, amountChanged);
      
      // 🔒 التحقق المزدوج من صحة الحساب
      final verification = MoneyCalculator.verifyTransaction(
        balanceBefore: balanceBefore,
        amountChanged: amountChanged,
        expectedBalanceAfter: newBalance,
      );
      
      if (!verification.isValid) {
        debugPrint('⚠️ تحذير أمني في المعاملة: ${verification.errorMessage}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في الحساب: ${verification.errorMessage}'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      
      // 🔒 التحقق من أن التسديد لا يجعل الرصيد سالباً بشكل غير منطقي
      if (!_isDebt && newBalance < -0.01) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ: التسديد سيجعل الرصيد سالباً (${NumberFormat('#,##0.##', 'en_US').format(newBalance)})'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      
      // 🚫 سقف الدين: إضافة دين يدوي تخضع له (الاستثناء للمدير)
      if (_isDebt) {
        final go = await CreditLimitGuard.enforce(
          context,
          customerId: widget.customer.id,
          increase: amount,
          what: 'إضافة دين يدوي — ${widget.customer.name}',
        );
        if (!go) return;
      }

      // ↩️ تسديد دين راجع: بلا صندوق، مع خصم نقاط المؤسس
      if (!_isDebt && _isReturn) {
        await _saveReturnPayment(amount);
        return;
      }
      // 🧾 التسديد = وصل قبض (سجل وصولات واحد، بالصندوق)، مع نفس سؤال الطباعة.
      if (!_isDebt) {
        await _savePaymentAsReceipt(amount);
        return;
      }

      final uuid = const Uuid().v4();
      final transaction = DebtTransaction(
        customerId: widget.customer.id!,
        amountChanged: amountChanged,
        balanceBeforeTransaction: balanceBefore, // تعيين الرصيد قبل المعاملة
        newBalanceAfterTransaction: newBalance,
        transactionNote:
            _noteController.text.isEmpty ? null : _noteController.text,
        transactionType:
            _isDebt ? 'manual_debt' : 'manual_payment', // Use specific types
        createdAt: DateTime.now(), // Add createdAt for consistency
        transactionDate: DateTime.now(), // Add transactionDate for consistency

        transactionUuid: uuid,
      );
      
      await context.read<AppProvider>().addTransaction(transaction);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'تم ${_isDebt ? 'إضافة' : 'تسديد'} مبلغ ${formatCurrency(amount)} دينار بنجاح!'),
            backgroundColor: Theme.of(context).colorScheme.tertiary,
          ),
        );
        // --- هنا منطق سند القبض ---
        if (!_isDebt) {
          final shouldPrint = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('طباعة سند قبض'),
              content: const Text('هل تريد طباعة سند القبض لهذا التسديد؟'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('لا'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('نعم'),
                ),
              ],
            ),
          );
          if (shouldPrint == true) {
            // الحصول على رقم سند القبض التالي
            final db = DatabaseService();
            final receiptNumber = await db.getNextCustomerReceiptNumber();
            
            final font = pw.Font.ttf(
                await rootBundle.load('assets/fonts/Amiri-Regular.ttf'));
            // استخدام نفس خط الفاتورة لكلمة الناصر
            final alnaserFont = pw.Font.ttf(await rootBundle
                .load('assets/fonts/PTBLDHAD.TTF'));
            // تحميل اللوجو باستخدام خدمة اللوجو
            final logoImage = await LogoService.getLogoImage();
            final pdf =
                await ReceiptVoucherPdfService.generateReceiptVoucherPdf(
              customerName: widget.customer.name,
              beforePayment: balanceBefore,
              paidAmount: amount,
              afterPayment: newBalance,
              dateTime: DateTime.now(),
              font: font,
              alnaserFont: alnaserFont,
              logoImage: logoImage,
              receiptNumber: receiptNumber,
            );
            
            // حفظ سند القبض في قاعدة البيانات
            final receipt = CustomerReceiptVoucher(
              receiptNumber: receiptNumber,
              customerId: widget.customer.id!,
              customerName: widget.customer.name,
              beforePayment: balanceBefore,
              paidAmount: amount,
              afterPayment: newBalance,
              createdAt: DateTime.now(),
            );
            await db.insertCustomerReceiptVoucher(receipt);
            
            // حفظ PDF في ملف مؤقت وفتحه في Microsoft Edge
            final tempDir = Directory.systemTemp;
            final filePath =
                '${tempDir.path}/receipt_voucher_${DateTime.now().millisecondsSinceEpoch}.pdf';
            final file = File(filePath);
            await file.writeAsBytes(await pdf.save());
            await Process.start('cmd', ['/c', 'start', 'msedge', filePath]);
          }
        }
        if (mounted) Navigator.pop(context);
      }
      } catch (e) {
        // 🔒 في حالة حدوث خطأ، نعيد تفعيل الزر
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('حدث خطأ أثناء الحفظ: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        // 🔒 إعادة تفعيل الزر في جميع الحالات
        if (mounted) {
          setState(() => _isSaving = false);
        }
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('الرجاء تصحيح الأخطاء في النموذج قبل الحفظ.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }



  // ═══════════════════ ↩️ تسديد دين راجع ═══════════════════

  Future<void> _toggleReturn(bool v) async {
    setState(() => _isReturn = v);
    if (v && _invoices.isEmpty && !_loadingInv) await _loadInvoices();
  }

  Future<void> _loadInvoices() async {
    final id = widget.customer.id;
    if (id == null) return;
    setState(() => _loadingInv = true);
    try {
      final list = await DebtReturnService.customerInvoices(id, widget.customer.name);
      if (mounted) setState(() => _invoices = list);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('تعذّر تحميل فواتير العميل: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _loadingInv = false);
    }
  }

  ReturnableInvoice? _inv(int id) {
    for (final i in _invoices) {
      if (i.id == id) return i;
    }
    return null;
  }

  Future<void> _pick(ReturnableInvoice inv) async {
    if (_picked.contains(inv.id)) {
      setState(() => _picked.remove(inv.id));
      return;
    }
    setState(() => _picked.add(inv.id));
    if (inv.hasFounder && inv.points == null) {
      try {
        final fi = await FounderService.invoiceWithPoints(inv.id);
        final (_, donePts) = await FounderService.returnedOn(inv.id);
        if (mounted) {
          setState(() {
            inv.points = fi?.points ?? 0;
            inv.pointsDeductedBefore = donePts;
          });
        }
      } catch (_) {
        if (mounted) setState(() => inv.points = 0);
      }
    }
  }

  /// يوزّع المبلغ على الفواتير المختارة بترتيب اختيارها، بحدّ صافي كل فاتورة ناقص ما رجع منها سابقاً
  Map<int, double> _allocation(double amount) {
    final out = <int, double>{};
    var left = amount;
    for (final id in _picked) {
      final inv = _inv(id);
      if (inv == null) continue;
      final a = math.max(0.0, math.min(left, inv.room));
      out[id] = a;
      left -= a;
    }
    return out;
  }

  /// نفس حساب FounderService.previewReturnDeduction (للعرض قبل الحفظ)
  double _previewPts(ReturnableInvoice inv, double alloc) {
    final p = inv.points;
    if (!inv.hasFounder || p == null || p <= 0 || inv.net <= 0 || alloc <= 0) return 0;
    final want = FounderService.round2(p * math.min(1.0, alloc / inv.net));
    return FounderService.round2(math.max(0, math.min(want, p - inv.pointsDeductedBefore)));
  }

  // 🔒 لا يُنفَّذ مرتين مهما كانت سرعة الضغط (القفل قبل أي انتظار)
  Future<void> _saveReturnPayment(double amount) async {
    await SaveLock.run(() => _saveReturnPaymentUnlocked(amount), message: 'جارٍ الحفظ…');
  }
  Future<void> _saveReturnPaymentUnlocked(double amount) async {
    final note = _noteController.text.trim();
    final alloc = _allocation(amount);
    final nums = [
      for (final id in _picked)
        if ((alloc[id] ?? 0) > 0) _inv(id)!.number
    ];
    // 1) المعاملة: تسديد على الحساب بوصف «مرتجع مبيعات» (لا يدخل الصندوق)
    final uuid = await CustomerMoney.post(
      context,
      customerId: widget.customer.id!,
      amount: -amount,
      kind: CustomerTxKind.salesReturn,
      note: 'تسديد دين راجع${nums.isEmpty ? '' : ' — فاتورة ${nums.join('، ')}'}${note.isEmpty ? '' : ' — $note'}',
    );
    // 2) من هنا الدين نقص فعلاً؛ تسجيله كراجع وخصم النقاط بعده، وفشلهما لا يلغيه
    final problems = <String>[];
    int? txId;
    try {
      txId = await DebtReturnService.recordReturn(
          transactionUuid: uuid, customerId: widget.customer.id!, amount: amount, note: note.isEmpty ? null : note);
    } catch (e) {
      problems.add('تسجيله في تقارير الراجع: $e');
    }
    var pts = 0.0;
    for (final e in alloc.entries) {
      if (e.value <= 0) continue;
      try {
        pts += await FounderService.deductForReturnedPayment(
          invoiceId: e.key,
          amount: e.value,
          customer: widget.customer.name,
          transactionId: txId,
          note: note.isEmpty ? null : note,
        );
      } catch (err) {
        problems.add('نقاط فاتورة ${_inv(e.key)?.number ?? e.key}: $err');
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: Duration(seconds: problems.isEmpty ? 4 : 10),
      content: Text('سُجّل تسديد دين راجع بمبلغ ${formatCurrency(amount)} دينار'
          '${pts > 0 ? ' — خُصم ${FounderService.round2(pts)} نقطة من المؤسس' : ''}'
          '${problems.isEmpty ? '' : '\n⚠️ لم يكتمل: ${problems.join(' — ')}'}'),
      backgroundColor: problems.isEmpty ? Colors.green[600] : Colors.orange[800],
    ));
    Navigator.pop(context, true);
  }

  Widget _returnSection(double entered) {
    const pink = Color(0xFFE91E63);
    final alloc = _allocation(entered);
    final allocated = alloc.values.fold(0.0, (s, v) => s + v);
    var pts = 0.0;
    for (final e in alloc.entries) {
      final inv = _inv(e.key);
      if (inv != null) pts += _previewPts(inv, e.value);
    }
    final q = _invSearch.text.trim();
    final shown = [
      for (final i in _invoices)
        if (q.isEmpty || i.number.contains(q) || i.founder.contains(q) || _picked.contains(i.id)) i
    ];
    final df = DateFormat('yyyy/MM/dd', 'en');
    // Material لا Container: الـ ListTile يرسم خلفيته على أقرب Material، وخلفية
    // Container ملوّنة تجعل Flutter يرمي خطأ فيختفي القسم كله.
    return Material(
      color: _isReturn ? const Color(0xFFFFF1F5) : const Color(0xFFFBFCFE),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: _isReturn ? pink.withValues(alpha: 0.35) : _line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SwitchListTile(
          value: _isReturn,
          onChanged: _toggleReturn,
          activeThumbColor: pink,
          secondary: const Icon(Icons.assignment_return_rounded, color: pink),
          title: const Text('تسديد دين راجع', style: TextStyle(fontWeight: FontWeight.w800, color: _ink)),
          subtitle: const Text('بضاعة رجعت بدل النقد: لا يدخل الصندوق، ويظهر في التقارير «تسديد دين راجع»، ويُخصم من المؤسس نقاط المبلغ',
              style: TextStyle(fontSize: 12, color: _muted, height: 1.5)),
        ),
        if (_isReturn) ...[
          const Divider(height: 1, color: _line),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: Row(children: [
              const Expanded(
                  child: Text('اختر الفاتورة التي رجع منها (لخصم نقاط مؤسسها)',
                      style: TextStyle(fontWeight: FontWeight.w700, color: _ink))),
              SizedBox(
                width: 180,
                height: 38,
                child: TextField(
                  controller: _invSearch,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'رقم الفاتورة…',
                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ]),
          ),
          if (_loadingInv)
            const Padding(padding: EdgeInsets.all(18), child: Center(child: CircularProgressIndicator()))
          else if (_invoices.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('لا فواتير محفوظة لهذا العميل — يُسجَّل الراجع بلا خصم نقاط.',
                  textAlign: TextAlign.center, style: TextStyle(color: _muted)),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: shown.length,
                itemBuilder: (_, k) {
                  final inv = shown[k];
                  final on = _picked.contains(inv.id);
                  final a = alloc[inv.id] ?? 0;
                  final p = on ? _previewPts(inv, a) : 0.0;
                  return CheckboxListTile(
                    dense: true,
                    value: on,
                    activeColor: pink,
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: inv.room <= 0 && !on ? null : (_) => _pick(inv),
                    title: Row(children: [
                      Text('فاتورة ${inv.number}', style: const TextStyle(fontWeight: FontWeight.w800, color: _ink)),
                      const SizedBox(width: 8),
                      Text(df.format(inv.date), style: const TextStyle(fontSize: 12, color: _muted)),
                      const Spacer(),
                      Text(formatCurrency(inv.net),
                          textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w800, color: _ink)),
                    ]),
                    subtitle: Text(
                      [
                        inv.hasFounder ? 'المؤسس: ${inv.founder}' : 'بلا مؤسس',
                        if (inv.paymentType.isNotEmpty) inv.paymentType,
                        if (inv.returnedBefore > 0) 'رجع منها سابقاً ${formatCurrency(inv.returnedBefore)}',
                        if (inv.room <= 0) 'لا متبقٍ للراجع',
                        if (on) 'يُحتسب منها ${formatCurrency(a)}',
                        if (on && inv.hasFounder) inv.points == null ? 'تحميل النقاط…' : 'يُخصم ${FounderService.round2(p)} نقطة',
                      ].join(' • '),
                      style: TextStyle(fontSize: 12, color: on ? pink : _muted, fontWeight: on ? FontWeight.w700 : null),
                    ),
                  );
                },
              ),
            ),
          Container(
            margin: const EdgeInsets.fromLTRB(12, 6, 12, 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
            child: Text(
              _picked.isEmpty
                  ? 'لم تُختر فاتورة: يُسجَّل المبلغ راجعاً بلا خصم نقاط.'
                  : 'على ${_picked.length} فاتورة: ${formatCurrency(allocated)} دينار — يُخصم ${FounderService.round2(pts)} نقطة'
                      '${entered - allocated > 0.5 ? '\nالباقي ${formatCurrency(entered - allocated)} أكبر مما بقي في الفواتير المختارة: يُسجَّل راجعاً بلا نقاط.' : ''}',
              style: const TextStyle(fontSize: 12.5, color: _ink, height: 1.6, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ]),
    );
  }

  /// التسديد يُحفظ كوصل قبض عبر ReceiptsService ⇒ CustomerMoney ⇒ AppProvider.addTransaction
  /// (نفس دالة الرصيد)، فيظهر في «سجل الوصولات» ويُرحَّل على الصندوق.
  Future<void> _savePaymentAsReceipt(double amount) async {
    final boxes = await VouchersService().cashBoxes();
    if (!mounted) return;
    if (boxes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('لا يوجد صندوق مفعّل — أضف صندوقاً من المحاسبة ← الصناديق والبنوك'),
        backgroundColor: Colors.red,
      ));
      return;
    }
    final preferred = await DeviceDefaults.cashBoxId();
    final box = boxes.firstWhere((b) => b.id == preferred,
        orElse: () => boxes.firstWhere((b) => b.isDefault, orElse: () => boxes.first));
    if (!mounted) return;
    final note = _noteController.text.trim();
    final res = await ReceiptsService().createCustomerReceipt(
      context,
      date: DateTime.now(),
      cashBoxId: box.id,
      currency: 'IQD',
      fxRate: 1,
      lines: [
        ReceiptLineInput(
          customerId: widget.customer.id!,
          customerName: widget.customer.name,
          amountFc: amount,
          note: note.isEmpty ? null : note,
        ),
      ],
    );
    if (!mounted) return;
    if (res.errors.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('لم يُحفظ التسديد: ${res.errors.join(' — ')}'),
        backgroundColor: Colors.red,
      ));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('تم تسديد ${formatCurrency(amount)} دينار — وصل قبض رقم ${res.receiptNo}'),
      backgroundColor: Colors.green[600],
    ));
    // 🧾 اسألني / اطبع دائماً / لا تُظهر — من «مصمم السندات» (سند قبض)
    final pmode = await VoucherPrint.modeFor(VoucherKinds.receipt);
    if (!mounted) return;
    final shouldPrint = pmode == 'always'
        ? true
        : pmode == 'never'
            ? false
            : await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('طباعة سند قبض'),
        content: const Text('هل تريد طباعة سند القبض لهذا التسديد؟'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('لا')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('نعم')),
        ],
      ),
    );
    if (shouldPrint == true && mounted) {
      // الطباعة بعد الحفظ: فشلها لا يعني أن التسديد لم يُحفظ
      try {
        final lines = await ReceiptsService().receiptLines(res.receiptId);
        final bytes = await ReceiptPdf.build(
          title: 'وصل قبض',
          number: res.receiptNo,
          date: DateTime.now(),
          boxName: box.name,
          currency: 'IQD',
          fxRate: 1,
          lines: lines,
          notes: note.isEmpty ? null : note,
        );
        if (mounted) await ReportExport.openPdf(context, bytes, 'وصل_قبض_${res.receiptNo}');
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('حُفظ التسديد، لكن تعذّرت الطباعة: $e — أعد الطباعة من سجل الوصولات'),
            backgroundColor: Colors.orange,
          ));
        }
      }
    }
    if (mounted) Navigator.pop(context, true);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 🎨 الواجهة فقط — الحقول والتحقق والحفظ (_saveTransaction) كما كانت تماماً.
  // ═══════════════════════════════════════════════════════════════════════
  static const _navy = Color(0xFF0F3460);
  static const _ink = Color(0xFF1B2433);
  static const _muted = Color(0xFF667085);
  static const _line = Color(0xFFE4E9F1);
  static const _bg = Color(0xFFF3F6FB);
  static const _debtC = Color(0xFFB42318);
  static const _payC = Color(0xFF067647);

  @override
  Widget build(BuildContext context) {
    final current = widget.customer.currentTotalDebt;
    final accent = _isDebt ? _debtC : _payC;
    final soft = _isDebt ? const Color(0xFFFDECEA) : const Color(0xFFE7F6EE);
    final entered = double.tryParse(_amountController.text.replaceAll(',', '')) ?? 0.0;
    final signed = _isDebt ? entered : -entered;
    // 🔒 استخدام MoneyCalculator للمعاينة أيضاً (كما كان)
    final newBalance = MoneyCalculator.add(current, signed);
    final overPay = !_isDebt && entered > current;

    final name = widget.customer.name.trim();
    final initial = name.isEmpty ? '؟' : name.substring(0, 1);
    final owes = current > 0.5;
    final balColor = owes ? _debtC : _payC;

    Widget customerPanel() => Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _line),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: balColor.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(16)),
                child: Text(initial, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: balColor)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.customer.name,
                      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: _ink)),
                  if ((widget.customer.phone ?? '').trim().isNotEmpty)
                    Text(widget.customer.phone!.trim(),
                        textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 13, color: _muted)),
                ]),
              ),
            ]),
            const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider(height: 1, color: _line)),
            const Text('الدين الحالي', style: TextStyle(fontSize: 13, color: _muted)),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(formatCurrency(current),
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                      fontSize: 38,
                      fontWeight: FontWeight.w900,
                      color: balColor,
                      height: 1.15,
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ),
            Text(owes ? 'دينار — عليه' : (current < -0.5 ? 'دينار — له' : 'دينار — مسدَّد'),
                style: const TextStyle(fontSize: 12, color: _muted)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: const Color(0xFFF7F9FC), borderRadius: BorderRadius.circular(12)),
              child: const Text(
                'العميل محجوز على هذه الشاشة ما دامت مفتوحة: لا يضيف له جهاز آخر معاملة في اللحظة نفسها.',
                style: TextStyle(fontSize: 12.5, color: _muted, height: 1.7),
              ),
            ),
          ]),
        );

    Widget modeTab(bool debtTab) {
      final on = _isDebt == debtTab;
      final c = debtTab ? _debtC : _payC;
      return Expanded(
        child: Material(
          color: on ? c : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _isDebt = debtTab),
            child: SizedBox(
              height: 54,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(debtTab ? Icons.north_east_rounded : Icons.south_west_rounded,
                    size: 20, color: on ? Colors.white : _muted),
                const SizedBox(width: 8),
                Text(debtTab ? 'إضافة دين' : 'تسديد',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: on ? Colors.white : _muted)),
              ]),
            ),
          ),
        ),
      );
    }

    Widget part(String label, String value, TextStyle style) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(fontSize: 12.5, color: _muted)),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(value, textDirection: TextDirection.ltr, style: style),
            ),
          ],
        );
    Widget op(String s, Color c) => SizedBox(
          width: 40,
          child: Text(s, textAlign: TextAlign.center, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w300, color: c)),
        );
    const tab = [FontFeature.tabularFigures()];

    final form = Container(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // نوع المعاملة
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(16)),
          child: Row(children: [modeTab(true), const SizedBox(width: 10), modeTab(false)]),
        ),
        const SizedBox(height: 20),
        const Text('المبلغ', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _ink)),
        const SizedBox(height: 8),
        // ⚠️ الحقل نفسه: نفس المُنسّقات والتحقق حرفياً
        TextFormField(
          controller: _amountController,
          autofocus: true,
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.left,
          style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: _ink, fontFeatures: tab),
          decoration: InputDecoration(
            hintText: '0',
            hintStyle: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: _muted.withValues(alpha: 0.4)),
            suffixText: 'دينار',
            suffixStyle: const TextStyle(fontSize: 16, color: _muted, fontWeight: FontWeight.w700),
            filled: true,
            fillColor: soft,
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: accent, width: 2)),
            enabledBorder:
                OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: accent, width: 2)),
            focusedBorder:
                OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: accent, width: 2.4)),
            errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _debtC, width: 2)),
            focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _debtC, width: 2.4)),
            errorStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            ThousandSeparatorInputFormatter(),
            LengthLimitingTextInputFormatter(15),
          ],
          onChanged: (_) => setState(() {}),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'الرجاء إدخال المبلغ';
            }
            final number = double.tryParse(value.replaceAll(',', ''));
            if (number == null) {
              return 'الرجاء إدخال رقم صحيح';
            }
            if (number <= 0) {
              return 'يجب أن يكون المبلغ أكبر من صفر';
            }
            if (number > 1000000000) {
              return 'المبلغ أكبر من الحد المسموح به';
            }
            if (!_isDebt && number > widget.customer.currentTotalDebt) {
              return 'المبلغ المدخل أكبر من الدين الحالي';
            }
            return null;
          },
        ),
        if (overPay)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('المبلغ المدخل أكبر من الدين الحالي',
                style: TextStyle(fontSize: 13, color: _debtC, fontWeight: FontWeight.w700)),
          ),
        const SizedBox(height: 16),
        // المعاينة: الرصيد الحالي ± المبلغ = الرصيد بعد الحفظ
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFCBD5E1)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
                child: part('الرصيد الحالي', formatCurrency(current),
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _ink, fontFeatures: tab))),
            op(_isDebt ? '+' : '−', accent),
            Expanded(
                child: part(_isDebt ? 'دين جديد' : 'تسديد', formatCurrency(signed.abs()),
                    TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: accent, fontFeatures: tab))),
            op('=', _navy),
            Expanded(
                child: part(
                    'الرصيد بعد الحفظ',
                    formatCurrency(newBalance),
                    TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: newBalance > 0.5 ? _debtC : _payC,
                        fontFeatures: tab))),
          ]),
        ),
        if (!_isDebt) ...[
          const SizedBox(height: 16),
          _returnSection(entered),
        ],
        const SizedBox(height: 20),
        const Text.rich(TextSpan(children: [
          TextSpan(text: 'ملاحظات ', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _ink)),
          TextSpan(text: '(اختياري)', style: TextStyle(fontSize: 13, color: _muted)),
        ])),
        const SizedBox(height: 8),
        TextFormField(
          controller: _noteController,
          maxLines: 2,
          style: const TextStyle(fontSize: 15, color: _ink),
          decoration: InputDecoration(
            hintText: 'مثلاً: بضاعة يوم الخميس، أو دفعة عن طريق المندوب',
            hintStyle: const TextStyle(color: _muted, fontSize: 14),
            filled: true,
            fillColor: const Color(0xFFFBFCFE),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _line)),
            enabledBorder:
                OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _line)),
            focusedBorder:
                OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _navy, width: 1.6)),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 58,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              disabledBackgroundColor: const Color(0xFF98A2B3),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            // 🔒 تعطيل الزر أثناء عملية الحفظ (كما كان)
            onPressed: _isSaving ? null : _saveTransaction,
            icon: _isSaving
                ? const SizedBox(
                    width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Icon(_isDebt ? Icons.add_task_rounded : Icons.check_circle_outline_rounded),
            label: Text(_isSaving ? 'جاري الحفظ...' : (_isDebt ? 'حفظ الدين' : (_isReturn ? 'حفظ تسديد الدين الراجع' : 'حفظ التسديد')),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ),
        ),
      ]),
    );

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(primary: _navy, error: _debtC),
        ),
        child: Scaffold(
          backgroundColor: _bg,
          appBar: accAppBar(
            _isDebt ? 'إضافة دين' : 'تسديد',
            icon: _isDebt ? Icons.north_east_rounded : Icons.south_west_rounded,
            subtitle: widget.customer.name,
          ),
          body: Form(
            key: _formKey,
            child: LayoutBuilder(builder: (context, c) {
              final wide = c.maxWidth >= 900;
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1180),
                    child: wide
                        ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            SizedBox(width: 360, child: customerPanel()),
                            const SizedBox(width: 20),
                            Expanded(child: form),
                          ])
                        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            customerPanel(),
                            const SizedBox(height: 16),
                            form,
                          ]),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

}
