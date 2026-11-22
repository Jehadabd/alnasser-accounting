// lib/erp/reports/voucher_details_sheet.dart
//
// 🧾 تفاصيل سند واحد — كل ما يخصه: النوع والرقم والتاريخ، المبلغ (وبالعملة الأجنبية
// وسعر الصرف)، من أي صندوق وإلى أين، الحساب بمساره الكامل، البيان والمرجع، من
// أنشأه ومتى، وقيده في الدفتر (رقمه وسطوره). مع طباعة السند.
// للقراءة فقط.

import 'package:flutter/material.dart';

import '../../accounting/screens/acc_ui.dart';
import '../../accounting/vouchers_service.dart' show VoucherType, voucherTypeLabels;
import '../accounting_plus/voucher_pdf.dart';
import '../erp_common.dart';
import '../erp_ui.dart';

String _dt(DateTime d) => '${fmtDate(d)}  ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

Future<void> showVoucherDetails(BuildContext context, int voucherId) => showDialog<void>(
      context: context,
      builder: (_) => _VoucherDetails(voucherId),
    );

class _VoucherDetails extends StatefulWidget {
  const _VoucherDetails(this.id);
  final int id;
  @override
  State<_VoucherDetails> createState() => _VoucherDetailsState();
}

class _VoucherDetailsState extends State<_VoucherDetails> {
  Map<String, Object?>? _v;
  List<Map<String, Object?>> _lines = const [];
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<String?> _userName(int? id) async {
    if (id == null) return null;
    try {
      final db = await erpDb();
      final r = await db.query('users', where: 'id = ?', whereArgs: [id], limit: 1);
      if (r.isEmpty) return '#$id';
      final dn = '${r.first['display_name'] ?? ''}'.trim();
      final un = '${r.first['username'] ?? ''}';
      return dn.isEmpty ? un : '$dn ($un)';
    } catch (_) {
      return '#$id';
    }
  }

  /// المسار الكامل للحساب: المصاريف ← مصاريف تشغيلية ← الكهرباء
  Future<String> _path(int? accountId) async {
    if (accountId == null) return '—';
    final db = await erpDb();
    final parts = <String>[];
    int? cur = accountId;
    var guard = 0;
    while (cur != null && guard++ < 8) {
      final r = await db.query('accounts', columns: ['code', 'name', 'parent_id'], where: 'id = ?', whereArgs: [cur], limit: 1);
      if (r.isEmpty) break;
      parts.insert(0, guard == 1 ? '${r.first['name']} (${r.first['code']})' : '${r.first['name']}');
      cur = r.first['parent_id'] as int?;
    }
    return parts.isEmpty ? '—' : parts.join(' ← ');
  }

  Future<void> _load() async {
    try {
      final db = await erpDb();
      final r = await db.rawQuery('''
        SELECT v.*, b.name AS box_name, tb.name AS to_box_name
        FROM vouchers v
        LEFT JOIN cash_boxes b ON b.id = v.cash_box_id
        LEFT JOIN cash_boxes tb ON tb.id = v.to_cash_box_id
        WHERE v.id = ?''', [widget.id]);
      if (r.isEmpty) throw 'السند غير موجود';
      final v = Map<String, Object?>.of(r.first);
      v['_account'] = await _path(v['account_id'] as int?);
      v['_by'] = await _userName(v['created_by_user_id'] as int?);
      v['_deleted_by'] = await _userName(v['deleted_by_user_id'] as int?);
      final je = await db.query('journal_entries',
          where: 'source_type = ? AND source_id = ?', whereArgs: ['voucher', widget.id], limit: 1);
      var lines = const <Map<String, Object?>>[];
      if (je.isNotEmpty) {
        v['_entry_no'] = je.first['entry_number'];
        lines = await db.rawQuery('''
          SELECT l.debit, l.credit, l.memo, a.code, a.name FROM journal_lines l
          JOIN accounts a ON a.id = l.account_id WHERE l.entry_id = ? ORDER BY l.id''', [je.first['id']]);
      }
      if (!mounted) return;
      setState(() {
        _v = v;
        _lines = lines;
      });
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = _v;
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 760),
        child: _err != null
            ? Padding(padding: const EdgeInsets.all(30), child: Text('تعذّر التحميل: $_err', style: const TextStyle(color: ErpColors.red)))
            : v == null
                ? const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
                : _body(v),
      ),
    );
  }

  Widget _body(Map<String, Object?> v) {
    final type = VoucherType.values.asNameMap()['${v['voucher_type']}'];
    final out = type == VoucherType.expense || type == VoucherType.payment;
    final c = out ? ErpColors.red : (type == VoucherType.transfer ? ErpColors.navy : ErpColors.green);
    final cur = '${v['currency'] ?? 'IQD'}';
    final fc = d0(v['fc_amount']);
    final deleted = (v['is_deleted'] as int? ?? 0) == 1;
    String? s(Object? o) => o == null || '$o'.trim().isEmpty ? null : '$o'.trim();
    final rows = <(IconData, String, String?)>[
      (Icons.event_rounded, 'التاريخ', fmtDate(parseDate(v['voucher_date']))),
      (Icons.account_balance_wallet_rounded, type == VoucherType.transfer ? 'من صندوق' : 'الصندوق', s(v['box_name'])),
      if (type == VoucherType.transfer) (Icons.call_received_rounded, 'إلى صندوق', s(v['to_box_name'])),
      if (type != VoucherType.transfer) (Icons.account_tree_rounded, 'الحساب', s(v['_account'])),
      if (cur != 'IQD' && fc != 0) (Icons.currency_exchange_rounded, 'بالعملة', '$cur ${fmtMoney(fc)} × ${fmtMoney(d0(v['fx_rate']))}'),
      (Icons.notes_rounded, 'البيان', s(v['description'])),
      (Icons.tag_rounded, 'المرجع', s(v['reference']) ?? s(v['doc_no'])),
      (Icons.person_rounded, 'أنشأه', s(v['_by'])),
      (Icons.schedule_rounded, 'وقت الإنشاء', v['created_at'] == null ? null : _dt(parseDate(v['created_at']))),
      (Icons.menu_book_rounded, 'القيد', v['_entry_no'] == null ? 'لم يُرحَّل بعد' : 'قيد رقم ${v['_entry_no']}'),
      if (deleted)
        (Icons.delete_outline_rounded, 'محذوف',
            '${v['deleted_at'] == null ? '' : _dt(parseDate(v['deleted_at']))}${v['_deleted_by'] == null ? '' : ' — ${v['_deleted_by']}'}'),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
        decoration: BoxDecoration(gradient: LinearGradient(colors: [c, Color.lerp(c, Colors.black, 0.3)!])),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)),
            child: Icon(out ? Icons.north_east_rounded : Icons.south_west_rounded, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${voucherTypeLabels[type] ?? 'سند'} رقم ${v['voucher_number']}',
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(fmtMoney(d0(v['amount'])),
                  style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
            ]),
          ),
          IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: Colors.white)),
        ]),
      ),
      if (deleted)
        Container(
          color: ErpColors.red.withValues(alpha: 0.1),
          padding: const EdgeInsets.all(10),
          child: const Text('هذا السند محذوف — لا يدخل في المجاميع', textAlign: TextAlign.center,
              style: TextStyle(color: ErpColors.red, fontWeight: FontWeight.w800)),
        ),
      Flexible(
        child: ListView(padding: const EdgeInsets.fromLTRB(18, 12, 18, 8), shrinkWrap: true, children: [
          for (final r in rows)
            if (r.$3 != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(r.$1, size: 19, color: ErpColors.muted),
                  const SizedBox(width: 10),
                  SizedBox(width: 96, child: Text(r.$2, style: const TextStyle(color: ErpColors.muted, fontWeight: FontWeight.w600))),
                  Expanded(child: Text(r.$3!, style: const TextStyle(fontWeight: FontWeight.w700, height: 1.4))),
                ]),
              ),
          if (_lines.isNotEmpty) ...[
            const Divider(height: 24),
            const Text('سطور القيد', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            for (final l in _lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Expanded(child: Text('${l['name']} (${l['code']})', style: const TextStyle(fontSize: 13))),
                  SizedBox(
                    width: 100,
                    child: Text(d0(l['debit']) > 0 ? 'مدين ${fmtMoney(d0(l['debit']))}' : '',
                        textAlign: TextAlign.end, style: const TextStyle(fontSize: 12.5, color: ErpColors.navy)),
                  ),
                  SizedBox(
                    width: 100,
                    child: Text(d0(l['credit']) > 0 ? 'دائن ${fmtMoney(d0(l['credit']))}' : '',
                        textAlign: TextAlign.end, style: const TextStyle(fontSize: 12.5, color: ErpColors.orange)),
                  ),
                ]),
              ),
          ],
        ]),
      ),
      Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: ErpColors.border))),
        child: Row(children: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
          const Spacer(),
          FilledButton.icon(
            onPressed: () => VoucherPdf.printVoucher(context, widget.id),
            icon: const Icon(Icons.print_rounded),
            label: const Text('طباعة السند'),
          ),
        ]),
      ),
    ]);
  }
}
