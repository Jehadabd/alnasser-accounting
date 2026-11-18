// lib/services/manual_debt_notes.dart
//
// 🧾 إشعار مدين — دين يدوي (بضاعة بلا فاتورة).
//
// حين يأخذ العميل بضاعة ويُسجَّل مبلغها فقط (إضافة دين يدوية)، فالمستند المحاسبي لها
// «إشعار مدين»: يزيد دين العميل ولا يخرج نقد من الصندوق.
//
// • كل دين يدوي يُحفظ يأخذ رقم إشعار متسلسلاً لحظة الحفظ — طُبع أم لا (هذا الملف).
// • القيد المحاسبي لا يُكتب هنا: محرك الترحيل يشتقّه من سجل الديون كما كان
//   (مدين ذمم العملاء / دائن «ديون يدوية — مبيعات خارج القوائم»).
// • الطباعة حسب إعداد النوع في «مصمم السندات»: اسألني / اطبع دائماً / لا تُظهر
//   (VoucherPrint.offerManualDebt)، وكل ورقة تُسجَّل في سجل السندات المطبوعة.
//
// لا يغيّر رصيداً ولا قيداً ولا حركة دين: يقرأ الحركة ويُرقّمها فقط.

import 'package:sqflite/sqflite.dart';

import '../erp/control/control_common.dart';
import '../erp/erp_common.dart';

/// ما يلزم لطباعة إشعار دين يدوي.
class ManualDebtNote {
  ManualDebtNote({
    required this.noteNo,
    required this.txId,
    required this.txUuid,
    required this.customerId,
    required this.customerName,
    required this.phone,
    required this.address,
    required this.amount,
    required this.before,
    required this.after,
    required this.date,
    required this.note,
    required this.recordedBy,
  });

  final int noteNo;
  final int txId;
  final String txUuid;
  final int? customerId;
  final String customerName;
  final String phone;
  final String address;
  final double amount;
  final double? before;
  final double? after;
  final DateTime date;
  final String note;
  final String recordedBy;
}

class ManualDebtNotes {
  ManualDebtNotes._();

  static const table = 'manual_debt_notes';

  /// رقم الإشعار لحركة الدين [uuid]: الموجود إن رُقّمت سابقاً، وإلا الرقم التالي.
  /// آمن عند التكرار (حركة واحدة ⇒ رقم واحد دائماً).
  static Future<int> assignIn(DatabaseExecutor db,
      {required String uuid, int? customerId, required double amount, String? createdBy}) async {
    final u = uuid.trim();
    if (u.isEmpty) throw ErpException('حركة دين بلا معرّف — لا يُرقَّم إشعارها');
    Future<int?> existing() async {
      final r = await db.query(table, columns: ['note_no'], where: 'transaction_uuid = ?', whereArgs: [u], limit: 1);
      return r.isEmpty ? null : (r.first['note_no'] as num).toInt();
    }

    final got = await existing();
    if (got != null) return got;
    for (var attempt = 0; attempt < 3; attempt++) {
      final n = await db.rawQuery('SELECT COALESCE(MAX(note_no), 0) + 1 AS n FROM $table');
      final no = (n.first['n'] as num).toInt();
      try {
        await db.insert(table, {
          'note_no': no,
          'transaction_uuid': u,
          'customer_id': customerId,
          'amount': round2(amount),
          'created_by': createdBy,
          'created_at': DateTime.now().toIso8601String(),
        });
        return no;
      } on DatabaseException {
        // سبقنا جهاز آخر (الرقم أو الحركة نفسها): نعيد القراءة ثم المحاولة
        final again = await existing();
        if (again != null) return again;
      }
    }
    throw ErpException('تعذّر ترقيم الإشعار — أعد المحاولة');
  }

  /// يرقّم حركة الدين اليدوي (يُستدعى بعد حفظها).
  static Future<int> assign({required String uuid, int? customerId, required double amount}) async {
    final db = await controlDb();
    return assignIn(db, uuid: uuid, customerId: customerId, amount: amount, createdBy: currentUserName());
  }

  /// الإشعار كاملاً لحركة الدين [uuid] (ويرقّمها إن لم تُرقَّم). null إن لم توجد الحركة
  /// أو حُذفت أو لم تكن ديناً يدوياً.
  static Future<ManualDebtNote?> load(String uuid) async {
    final db = await controlDb();
    return loadIn(db, uuid, createdBy: currentUserName());
  }

  static Future<ManualDebtNote?> loadIn(DatabaseExecutor db, String uuid, {String? createdBy}) async {
    final rows = await db.rawQuery('''
      SELECT t.*, c.name AS c_name, c.phone AS c_phone, c.address AS c_address
      FROM transactions t LEFT JOIN customers c ON c.id = t.customer_id
      WHERE t.transaction_uuid = ? LIMIT 1''', [uuid]);
    if (rows.isEmpty) return null;
    final t = rows.first;
    if (((t['is_deleted'] as num?) ?? 0) == 1) return null;
    if (t['transaction_type'] != 'manual_debt') return null;
    final amount = d0(t['amount_changed']);
    if (amount <= 0) return null;
    final customerId = (t['customer_id'] as num?)?.toInt();
    final no = await assignIn(db, uuid: uuid, customerId: customerId, amount: amount, createdBy: createdBy);
    final by = '${t['created_by_username'] ?? ''}'.trim();
    return ManualDebtNote(
      noteNo: no,
      txId: (t['id'] as num).toInt(),
      txUuid: uuid,
      customerId: customerId,
      customerName: '${t['c_name'] ?? ''}'.trim(),
      phone: '${t['c_phone'] ?? ''}'.trim(),
      address: '${t['c_address'] ?? ''}'.trim(),
      amount: amount,
      before: (t['balance_before_transaction'] as num?)?.toDouble(),
      after: (t['new_balance_after_transaction'] as num?)?.toDouble(),
      date: DateTime.tryParse('${t['transaction_date']}') ?? DateTime.now(),
      note: '${t['transaction_note'] ?? ''}'.trim(),
      recordedBy: by.isNotEmpty ? by : (createdBy ?? ''),
    );
  }
}
