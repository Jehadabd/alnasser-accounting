// lib/screens/invoice_history/invoice_ledger_moves.dart
//
// 📒 حركات سجل الديون المرتبطة بفاتورة واحدة — للعرض فقط (لا يكتب شيئاً).
//
// لماذا؟ تاريخ الفاتورة يقارن نسخها (المبالغ والأصناف والاسم)، لكن أثرها في
// سجل الديون يُكتب في جدول المعاملات: دين الفاتورة، تعديلاتها، تسويات الحارس
// المحاسبي، ونقل الدين بين العملاء. حادثة فاتورة غسان (1202610191) في تطبيق
// المتجر القديم نقلت الدين بين عميلين ولم يظهر في تاريخها أي شيء، لأن الاسم
// والمبلغ لم يتغيرا. هذا القسم يعرض كل حركة كما هي في السجل، وصافي أثر الفاتورة
// على كل عميل، وينبّه إن بقي أثر على عميل غير عميل الفاتورة الحالي.

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../services/database/business/invoice_debt_reconciler.dart';
import 'invoice_history_model.dart' show HistFmt;

/// حركة واحدة من سجل الديون مرتبطة بالفاتورة.
class InvoiceLedgerMove {
  final int id;
  final int customerId;
  final String customerName;
  final double amount;
  final String type;
  final DateTime? at;
  final String? note;
  final String? user;

  /// هل تدخل في «دين الفاتورة»؟ (التسديدات والتصحيحات لها كيانها المستقل)
  final bool contributes;

  const InvoiceLedgerMove({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.amount,
    required this.type,
    required this.contributes,
    this.at,
    this.note,
    this.user,
  });
}

/// صافي أثر الفاتورة على عميل واحد (من الحركات التي تدخل في دين الفاتورة).
class InvoiceLedgerNet {
  final int customerId;
  final String customerName;
  final double net;
  final bool isCurrent;
  const InvoiceLedgerNet(this.customerId, this.customerName, this.net, this.isCurrent);
}

class InvoiceLedgerSummary {
  final List<InvoiceLedgerMove> moves; // بترتيب كتابتها في السجل
  final List<InvoiceLedgerNet> nets; // عميل الفاتورة الحالي أولاً
  /// عملاء غير عميل الفاتورة الحالي بقي عليهم أثر من هذه الفاتورة
  final List<InvoiceLedgerNet> stray;

  const InvoiceLedgerSummary(this.moves, this.nets, this.stray);

  static const empty = InvoiceLedgerSummary(<InvoiceLedgerMove>[], <InvoiceLedgerNet>[], <InvoiceLedgerNet>[]);

  bool get isEmpty => moves.isEmpty;

  /// أكثر من عميل ظهر في حركات الفاتورة (نُقلت بين حسابات)
  bool get touchedSeveralCustomers => nets.length > 1;
}

class InvoiceLedgerMoves {
  InvoiceLedgerMoves._();

  // 🪙 نصف فلس — نفس حد الحارس المحاسبي
  static const double tolerance = 0.005;

  /// قراءة حركات الفاتورة (قراءة فقط). أي خطأ ⇒ ملخص فارغ ولا تفشل الشاشة.
  static Future<InvoiceLedgerSummary> load(DatabaseExecutor db, int invoiceId,
      {required int? currentCustomerId}) async {
    try {
      final rows = await db.rawQuery('''
        SELECT t.*, c.name AS cust_name
        FROM transactions t
        LEFT JOIN customers c ON c.id = t.customer_id
        WHERE t.invoice_id = ? AND COALESCE(t.is_deleted, 0) = 0
        ORDER BY t.id ASC
      ''', [invoiceId]);
      return summarize(rows, currentCustomerId: currentCustomerId);
    } catch (e) {
      debugPrint('⚠️ حركات سجل الديون للفاتورة $invoiceId: $e');
      return InvoiceLedgerSummary.empty;
    }
  }

  /// منطق صافٍ (قابل للاختبار): يحوّل صفوف المعاملات إلى حركات وصافي لكل عميل.
  static InvoiceLedgerSummary summarize(List<Map<String, Object?>> rows,
      {required int? currentCustomerId}) {
    final int current = currentCustomerId ?? 0;
    final moves = <InvoiceLedgerMove>[];
    final netBy = <int, double>{};
    final nameBy = <int, String>{};

    for (final r in rows) {
      final int cid = _int(r['customer_id']);
      final String type = (r['transaction_type'] as String?)?.trim() ?? '';
      final double amount = _num(r['amount_changed']);
      final bool contributes = !InvoiceDebtReconciler.nonContributionTypes.contains(type);
      final String name = ((r['cust_name'] as String?) ?? '').trim();
      nameBy[cid] = name.isEmpty ? 'عميل محذوف أو غير موجود (#$cid)' : name;
      if (contributes) netBy[cid] = (netBy[cid] ?? 0) + amount;
      moves.add(InvoiceLedgerMove(
        id: _int(r['id']),
        customerId: cid,
        customerName: nameBy[cid]!,
        amount: amount,
        type: type,
        contributes: contributes,
        at: _date(r['transaction_date']) ?? _date(r['created_at']),
        note: _nonEmpty(r['transaction_note']),
        user: _nonEmpty(r['created_by_username']),
      ));
    }

    // عميلان مختلفان بالاسم نفسه ⇒ نُظهر رقم الحساب حتى لا يلتبسا
    final byName = <String, Set<int>>{};
    nameBy.forEach((id, n) => byName.putIfAbsent(n, () => <int>{}).add(id));
    String label(int id) {
      final n = nameBy[id] ?? '#$id';
      return (byName[n]?.length ?? 1) > 1 ? '$n (حساب #$id)' : n;
    }

    final ids = <int>{...nameBy.keys}.toList()
      ..sort((a, b) {
        if (a == b) return 0;
        if (a == current) return -1;
        if (b == current) return 1;
        return a.compareTo(b);
      });
    final nets = <InvoiceLedgerNet>[
      for (final id in ids) InvoiceLedgerNet(id, label(id), netBy[id] ?? 0, id == current),
    ];
    final stray = nets.where((n) => !n.isCurrent && n.net.abs() > tolerance).toList();
    final shownMoves = [
      for (final m in moves)
        InvoiceLedgerMove(
          id: m.id,
          customerId: m.customerId,
          customerName: label(m.customerId),
          amount: m.amount,
          type: m.type,
          contributes: m.contributes,
          at: m.at,
          note: m.note,
          user: m.user,
        ),
    ];
    return InvoiceLedgerSummary(shownMoves, nets, stray);
  }

  /// اسم نوع الحركة كما يفهمه صاحب المحل
  static String typeLabel(String t) => switch (t) {
        'invoice_debt' => 'دين الفاتورة',
        'invoice_edit' || 'invoice_live_update' || 'Invoice_Debt_Adjustment' => 'تعديل الفاتورة',
        'invoice_payment_type_change' => 'تغيير نقد/دين',
        'invoice_customer_change' => 'نقل الدين بين العملاء',
        'invoice_debt_sync' => 'تسوية الحارس المحاسبي',
        'Invoice_Debt_Reversal' => 'إلغاء دين الفاتورة',
        'SETTLEMENT' => 'تسوية قديمة',
        'manual_payment' => 'تسديد مرتبط بالفاتورة',
        'return_payment' => 'تسديد مرتجع',
        'correction' => 'تصحيح',
        'opening_balance' => 'رصيد افتتاحي',
        '' => 'حركة بلا نوع',
        _ => t,
      };

  static int _int(Object? v) => v is num ? v.toInt() : (v is String ? int.tryParse(v) ?? 0 : 0);
  static double _num(Object? v) => v is num ? v.toDouble() : (v is String ? double.tryParse(v) ?? 0 : 0);
  static DateTime? _date(Object? v) => v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;
  static String? _nonEmpty(Object? v) {
    final s = v?.toString().trim() ?? '';
    return s.isEmpty ? null : s;
  }
}

/// بطاقة «حركات سجل الديون» في شاشة تاريخ الفاتورة.
class InvoiceLedgerMovesCard extends StatefulWidget {
  final InvoiceLedgerSummary summary;
  const InvoiceLedgerMovesCard({super.key, required this.summary});

  @override
  State<InvoiceLedgerMovesCard> createState() => _InvoiceLedgerMovesCardState();
}

class _InvoiceLedgerMovesCardState extends State<InvoiceLedgerMovesCard> {
  static const Color _textDark = Color(0xFF263238);
  static const Color _border = Color(0xFFE3E7EE);
  late bool _open;

  @override
  void initState() {
    super.initState();
    // يُفتح تلقائياً حين يكون هناك ما يستحق الانتباه
    _open = widget.summary.stray.isNotEmpty || widget.summary.touchedSeveralCustomers;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.summary;
    final bool warn = s.stray.isNotEmpty;
    final Color accent = warn ? Colors.red.shade700 : const Color(0xFF00796B);
    final bool open = _open;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: warn ? Colors.red.shade200 : _border),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => _open = !open),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(
                children: [
                  Icon(Icons.account_balance_wallet_outlined, color: accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'حركات سجل الديون لهذه الفاتورة (${s.moves.length})',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _textDark),
                    ),
                  ),
                  Icon(open ? Icons.expand_less : Icons.expand_more, color: Colors.grey.shade600),
                ],
              ),
            ),
          ),
          if (warn) _warning(s),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final n in s.nets) _netChip(n)],
            ),
          ),
          if (open) ...[
            const Divider(height: 1),
            for (final m in s.moves) _moveRow(m),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }

  Widget _warning(InvoiceLedgerSummary s) => Container(
        margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red.shade700),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'بقي أثر من هذه الفاتورة على عميل ليس عميلها الآن: '
                '${s.stray.map((n) => '${n.customerName} ${HistFmt.signed(n.net)}').join('، ')}. '
                'افحصها من «الفحص العميق» قبل أي تصحيح.',
                style: TextStyle(fontSize: 12.5, color: Colors.red.shade900, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );

  Widget _netChip(InvoiceLedgerNet n) {
    final bool bad = !n.isCurrent && n.net.abs() > InvoiceLedgerMoves.tolerance;
    final Color c = bad ? Colors.red.shade700 : (n.isCurrent ? const Color(0xFF3F51B5) : Colors.blueGrey.shade600);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.withAlpha(16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withAlpha(70)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: n.isCurrent ? 'عميل الفاتورة: ' : 'عميل آخر: '),
                TextSpan(text: n.customerName, style: const TextStyle(fontWeight: FontWeight.bold)),
                const TextSpan(text: ' — صافي الأثر '),
              ]),
              style: TextStyle(fontSize: 12.5, color: c),
            ),
          ),
          const SizedBox(width: 4),
          _amountText(n.net, c),
        ],
      ),
    );
  }

  Widget _amountText(double v, Color c) => Directionality(
        textDirection: TextDirection.ltr,
        child: Text(HistFmt.signed(v), style: TextStyle(fontSize: 12.5, color: c, fontWeight: FontWeight.bold)),
      );

  Widget _moveRow(InvoiceLedgerMove m) {
    final Color amountColor = m.amount > 0 ? Colors.red.shade700 : Colors.green.shade700;
    final String when = m.at == null ? '' : HistFmt.dateTime(m.at!);
    final List<String> meta = [
      if (when.isNotEmpty) when,
      if (m.user != null) m.user!,
      if (!m.contributes) 'لا يدخل في دين الفاتورة',
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${InvoiceLedgerMoves.typeLabel(m.type)} — ${m.customerName}',
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: _textDark)),
                if (meta.isNotEmpty)
                  Text(meta.join(' · '), style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
                if (m.note != null)
                  Text(m.note!, style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(HistFmt.signed(m.amount),
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: amountColor)),
          ),
        ],
      ),
    );
  }
}
