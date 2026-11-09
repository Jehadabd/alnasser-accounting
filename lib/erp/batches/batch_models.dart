// lib/erp/batches/batch_models.dart
//
// 🧪 دفعات المادة بتاريخ صلاحية (دوال صافية مختبَرة).
//
// الكمية الحالية للمادة تبقى من دفتر المخزون كما هي (لا يتغيّر البيع ولا الجرد). المتبقي من
// كل دفعة يُقدَّر على قاعدة «الأقرب انتهاءً يخرج أولاً» (FEFO): الكمية الحالية تُوزَّع على
// الدفعات من الأبعد انتهاءً إلى الأقرب، وما لا تغطيه الكمية يُعد قد خرج.

class StockLot {
  StockLot({this.id, required this.productId, required this.lotNo, required this.expiry, required this.qty, required this.receivedAt, this.note = ''});
  final int? id;
  final int productId;
  final String lotNo, note;
  final DateTime expiry;

  /// الكمية المستلمة بالوحدة الأساسية.
  final double qty;
  final DateTime receivedAt;

  Map<String, Object?> toMap() => {
        'product_id': productId,
        'lot_no': lotNo.trim(),
        'expiry': expiry.toIso8601String().substring(0, 10),
        'qty': qty,
        'received_at': receivedAt.toIso8601String(),
        'note': note.trim(),
      };

  factory StockLot.fromMap(Map<String, Object?> m) => StockLot(
        id: m['id'] as int?,
        productId: m['product_id'] as int,
        lotNo: '${m['lot_no'] ?? ''}',
        expiry: DateTime.tryParse('${m['expiry']}') ?? DateTime(2100),
        qty: (m['qty'] as num?)?.toDouble() ?? 0,
        receivedAt: DateTime.tryParse('${m['received_at']}') ?? DateTime(2000),
        note: '${m['note'] ?? ''}',
      );
}

class LotRemaining {
  LotRemaining(this.lot, this.remaining);
  final StockLot lot;
  final double remaining;
  int daysLeft(DateTime now) => DateTime(lot.expiry.year, lot.expiry.month, lot.expiry.day)
      .difference(DateTime(now.year, now.month, now.day))
      .inDays;
}

class Lots {
  Lots._();

  /// يوزّع [stock] على [lots] (FEFO): الأبعد انتهاءً يحتفظ بالكمية أولاً.
  static List<LotRemaining> allocate(double stock, List<StockLot> lots) {
    final sorted = [...lots]..sort((a, b) {
        final c = b.expiry.compareTo(a.expiry);
        return c != 0 ? c : b.receivedAt.compareTo(a.receivedAt);
      });
    var left = stock < 0 ? 0.0 : stock;
    final out = <LotRemaining>[];
    for (final l in sorted) {
      final take = l.qty <= 0 ? 0.0 : (left < l.qty ? left : l.qty);
      out.add(LotRemaining(l, take));
      left -= take;
    }
    out.sort((a, b) => a.lot.expiry.compareTo(b.lot.expiry));
    return out;
  }
}
