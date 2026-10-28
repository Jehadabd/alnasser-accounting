// lib/erp/control/approval_gate.dart
//
// ✅ موافقة المدير قبل العمليات الحساسة (لا بعدها):
//   • فاتورة بتاريخ يوم سابق: تعديل فاتورة يوم مضى، أو فاتورة جديدة بتاريخ رجعي.
//   • بيع تحت الكلفة (ومنه الهدية المجانية).
//   • خصم أعلى من نسبة يحددها المدير (خصم الفاتورة + خصومات الأسطر).
//
// المدير المسجّل دخوله لا يُسأل. غيره: تظهر أسباب المنع، ويُدخل المدير كلمة سرّه
// على الجهاز نفسه فيستمر الحفظ — أو يُلغى. كل طلب يُسجَّل في «سجل الموافقات»
// (من طلب، من وافق أو رفض، ولماذا). لا يغيّر هذا الملف رقماً: يقرر هل يستمر الحفظ.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;

import '../../models/app_user.dart';
import '../../models/invoice_item.dart';
import '../../services/auth_service.dart';
import '../activity/activity_log.dart';
import '../erp_common.dart';
import 'control_common.dart';

class ApprovalRule {
  ApprovalRule._();
  static const pastDate = 'past_date';
  static const belowCost = 'below_cost';
  static const discount = 'discount';

  static String label(String r) => switch (r) {
        pastDate => 'فاتورة بتاريخ سابق',
        belowCost => 'بيع تحت الكلفة',
        discount => 'خصم أعلى من المسموح',
        _ => r,
      };

  /// مفاتيح الإعدادات
  static const kPastDate = 'approve_past_date';
  static const kBelowCost = 'approve_below_cost';
  static const kDiscountPct = 'approve_discount_pct';
}

class ApprovalSettings {
  ApprovalSettings({required this.pastDate, required this.belowCost, required this.discountPct});
  final bool pastDate;
  final bool belowCost;

  /// 0 = بلا قيد على الخصم.
  final double discountPct;

  static Future<ApprovalSettings> load() async => ApprovalSettings(
        pastDate: await ControlSettings.getBool(ApprovalRule.kPastDate, true),
        belowCost: await ControlSettings.getBool(ApprovalRule.kBelowCost, true),
        discountPct: await ControlSettings.getNum(ApprovalRule.kDiscountPct, 10),
      );

  static Future<void> save(ApprovalSettings s) async {
    if (!await currentIsAdmin()) throw ErpException('إعدادات الموافقات للمدير فقط');
    await ControlSettings.setBool(ApprovalRule.kPastDate, s.pastDate);
    await ControlSettings.setBool(ApprovalRule.kBelowCost, s.belowCost);
    await ControlSettings.setNum(ApprovalRule.kDiscountPct, s.discountPct < 0 ? 0 : s.discountPct);
    ActivityLog.log('تعديل', 'إعدادات الموافقات',
            'تاريخ سابق: ${s.pastDate ? 'نعم' : 'لا'}، تحت الكلفة: ${s.belowCost ? 'نعم' : 'لا'}، الخصم: ${s.discountPct}%')
        .catchError((_) {});
  }
}

class ApprovalViolation {
  ApprovalViolation(this.rule, this.text);
  final String rule;
  final String text;
}

final NumberFormat _nf = NumberFormat('#,##0', 'en_US');
String _m(num v) => _nf.format(v.round());

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// ما يحتاج موافقة في فاتورة — دالة صافية (تُختبر وحدها).
List<ApprovalViolation> invoiceViolations({
  required ApprovalSettings settings,
  required List<InvoiceItem> items,
  required double invoiceDiscount,
  required DateTime selectedDate,
  DateTime? originalDate,
  DateTime? today,
}) {
  final now = _day(today ?? DateTime.now());
  final out = <ApprovalViolation>[];

  if (settings.pastDate) {
    if (originalDate != null && _day(originalDate).isBefore(now)) {
      out.add(ApprovalViolation(ApprovalRule.pastDate,
          'تعديل فاتورة من يوم سابق (${_day(originalDate).toIso8601String().substring(0, 10)})'));
    } else if (_day(selectedDate).isBefore(now)) {
      out.add(ApprovalViolation(ApprovalRule.pastDate,
          'تاريخ الفاتورة قبل اليوم (${_day(selectedDate).toIso8601String().substring(0, 10)})'));
    }
  }

  final real = items.where((it) => it.productName.trim().isNotEmpty && it.soldQuantity > 0).toList();

  if (settings.belowCost) {
    final lines = <String>[];
    var loss = 0.0;
    for (final it in real) {
      final unitCost = (it.actualCostPrice ?? 0) > 0 ? it.actualCostPrice! : (it.costPrice ?? 0);
      if (unitCost <= 0) continue; // كلفة غير معروفة: لا حكم
      final cost = unitCost * it.soldQuantity;
      if (it.itemTotal < cost - 0.5) {
        loss += cost - it.itemTotal;
        if (lines.length < 5) {
          lines.add(it.isGift ? '«${it.productName}» هدية (كلفتها ${_m(cost)})' : '«${it.productName}» بخسارة ${_m(cost - it.itemTotal)}');
        }
      }
    }
    if (lines.isNotEmpty) {
      out.add(ApprovalViolation(ApprovalRule.belowCost, 'بيع تحت الكلفة بخسارة ${_m(loss)}: ${lines.join('، ')}'));
    }
  }

  if (settings.discountPct > 0) {
    final net = real.fold<double>(0, (s, it) => s + it.itemTotal);
    final lineDisc = real.fold<double>(0, (s, it) => s + (it.isGift ? 0 : it.lineDiscountTotal));
    final gross = net + lineDisc;
    final disc = invoiceDiscount + lineDisc;
    if (gross > 0 && disc > 0.5) {
      final pct = disc / gross * 100;
      if (pct > settings.discountPct + 0.001) {
        out.add(ApprovalViolation(ApprovalRule.discount,
            'خصم ${_m(disc)} = ${pct.toStringAsFixed(1)}% من ${_m(gross)} (المسموح ${settings.discountPct.toStringAsFixed(settings.discountPct % 1 == 0 ? 0 : 1)}%)'));
      }
    }
  }
  return out;
}

class ApprovalGate {
  ApprovalGate._();

  static Future<void> _log({
    required List<ApprovalViolation> v,
    required String refLabel,
    int? refId,
    required String decision,
    String? decidedBy,
  }) async {
    try {
      final db = await controlDb();
      final now = DateTime.now().toIso8601String();
      await db.transaction((txn) async {
        for (final x in v) {
          await txn.insert('approval_log', {
            'rule': x.rule,
            'ref_type': 'invoice',
            'ref_id': refId,
            'ref_label': refLabel,
            'details': x.text,
            'requested_by': currentUserName(),
            'decided_by': decidedBy,
            'decision': decision,
            'created_at': now,
          });
        }
      });
    } catch (e) {
      debugPrint('⚠️ سجل الموافقات: $e');
    }
  }

  /// يقرر هل يستمر حفظ الفاتورة. true = استمر.
  static Future<bool> checkInvoice(
    BuildContext context, {
    required List<InvoiceItem> items,
    required double discount,
    required DateTime selectedDate,
    DateTime? originalDate,
    int? invoiceId,
    required String customerName,
  }) async {
    if (await currentIsAdmin()) return true;
    final ApprovalSettings settings;
    try {
      settings = await ApprovalSettings.load();
    } catch (_) {
      return true; // لا إعدادات بعد (قاعدة قديمة): السلوك القديم
    }
    final v = invoiceViolations(
      settings: settings,
      items: items,
      invoiceDiscount: discount,
      selectedDate: selectedDate,
      originalDate: originalDate,
    );
    if (v.isEmpty) return true;
    if (!context.mounted) return false;
    final label = '${invoiceId == null ? 'فاتورة جديدة' : 'فاتورة #$invoiceId'} — ${customerName.trim()}';
    final admin = await _askAdmin(context, v, label);
    await _log(
      v: v,
      refLabel: label,
      refId: invoiceId,
      decision: admin == null ? 'denied' : 'approved',
      decidedBy: admin?.username,
    );
    if (admin != null) {
      ActivityLog.log('موافقة المدير', label, '${admin.username}: ${v.map((x) => ApprovalRule.label(x.rule)).join('، ')}')
          .catchError((_) {});
    }
    return admin != null;
  }

  /// يعيد المدير الذي وافق، أو null إن أُلغي.
  static Future<AppUser?> _askAdmin(BuildContext context, List<ApprovalViolation> v, String label) async {
    final auth = AuthService();
    final admins = (await auth.getAllUsers()).where((u) => u.isAdmin && u.id != null).toList();
    if (!context.mounted) return null;
    final pw = TextEditingController();
    String? error;
    var busy = false;

    Future<AppUser?> check() async {
      if (pw.text.isEmpty) return null;
      for (final u in admins) {
        if (await auth.checkPassword(u.id!, pw.text)) return u;
      }
      return null;
    }

    final r = await showDialog<AppUser>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        Future<void> submit() async {
          if (busy) return;
          setD(() => busy = true);
          final u = await check();
          if (!ctx.mounted) return;
          if (u != null) {
            Navigator.pop(ctx, u);
          } else {
            setD(() {
              busy = false;
              error = 'كلمة سر المدير غير صحيحة';
            });
          }
        }

        return AlertDialog(
          title: const Row(children: [
            Icon(Icons.admin_panel_settings_rounded, color: Colors.deepOrange),
            SizedBox(width: 8),
            Expanded(child: Text('تحتاج موافقة المدير', style: TextStyle(fontSize: 17))),
          ]),
          content: SizedBox(
            width: 460,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              for (final x in v)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.error_outline_rounded, size: 18, color: Colors.deepOrange),
                    const SizedBox(width: 6),
                    Expanded(child: Text(x.text, style: const TextStyle(height: 1.5))),
                  ]),
                ),
              const SizedBox(height: 12),
              if (admins.isEmpty)
                const Text('لا يوجد مستخدم مدير في البرنامج — لا يمكن الاعتماد. أضف مديراً من إدارة المستخدمين.',
                    style: TextStyle(color: Colors.red))
              else
                TextField(
                  controller: pw,
                  obscureText: true,
                  autofocus: true,
                  enabled: !busy,
                  decoration: InputDecoration(
                    labelText: 'كلمة سر المدير',
                    errorText: error,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    prefixIcon: const Icon(Icons.lock_rounded),
                  ),
                  onSubmitted: (_) => submit(),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: busy ? null : () => Navigator.pop(ctx), child: const Text('إلغاء الحفظ')),
            if (admins.isNotEmpty)
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.deepOrange),
                onPressed: busy ? null : submit,
                icon: const Icon(Icons.verified_user_rounded, size: 18),
                label: const Text('موافقة المدير'),
              ),
          ],
        );
      }),
    );
    pw.dispose();
    return r;
  }

  /// سجل الموافقات.
  static Future<List<Map<String, Object?>>> log({DateTime? from, DateTime? to}) async {
    final db = await controlDb();
    final where = <String>[];
    final args = <Object?>[];
    if (from != null) {
      where.add('created_at >= ?');
      args.add(isoDay(from));
    }
    if (to != null) {
      where.add('created_at < ?');
      args.add(isoDayAfter(to));
    }
    return db.rawQuery(
        'SELECT * FROM approval_log ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'} ORDER BY id DESC LIMIT 1000',
        args);
  }
}
