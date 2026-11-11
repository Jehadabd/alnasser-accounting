// lib/utils/iqd.dart
//
// 💵 الدينار العراقي بلا كسور.
//
// كل مبلغ بالدينار يُحفظ رقماً صحيحاً. التقريب لأقرب دينار، وعند النصف بالضبط
// يُحسم لصالح المحل:
//   • [up]   — النصف إلى الأعلى (نحو +∞): ما يزيد دين العميل أو ما يأخذه المحل
//              (سطر بيع، أجور نقل، معاملة على حساب العميل — موجبة أو سالبة:
//              تسديد −52.5 ← −52، أي يبقى دين العميل أعلى بنصف دينار).
//   • [down] — النصف إلى الأسفل (نحو −∞): ما يعطيه المحل أو ما يُنقص حقّه
//              (خصم، مسدد على الفاتورة، مرتجع، وفي حساب المورد: ما علينا له).
// أمثلة (up): 20.83 ← 21، 52.5 ← 53، 52.4 ← 52، 20.49 ← 20.
//
// التقريب يُحسب على أجزاء من عشرة آلاف من الدينار أولاً، فضجيج الكسور العشرية
// (52.49999999 بدل 52.5) لا يغيّر النتيجة، و52.495 تبقى أقل من النصف.
//
// لا يعتمد على أي نموذج أو قاعدة: الاختبارات تستعمله كما هو.

class Iqd {
  Iqd._();

  static const int _scale = 10000;
  static const int _half = 5000;

  /// سماحية «رقم صحيح»: أقل من عُشر فلس (ضجيج الحساب العشري لا يُعدّ كسراً)
  static const double wholeTolerance = 0.0001;

  static int _floorDiv(int a, int b) {
    final q = a ~/ b;
    return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q;
  }

  static double _toWhole(num v, bool halfUp) {
    final d = v.toDouble();
    if (!d.isFinite) return d;
    final u = (d * _scale).round();
    final f = _floorDiv(u, _scale);
    final r = u - f * _scale; // 0 .. 9999
    final whole = (r > _half || (r == _half && halfUp)) ? f + 1 : f;
    return whole == 0 ? 0.0 : whole.toDouble(); // لا «-0.0»
  }

  /// لأقرب دينار، والنصف إلى الأعلى (نحو +∞).
  static double up(num v) => _toWhole(v, true);

  /// لأقرب دينار، والنصف إلى الأسفل (نحو −∞).
  static double down(num v) => _toWhole(v, false);

  /// هل المبلغ رقم صحيح من الدنانير؟ (null يُعدّ صحيحاً)
  static bool isWhole(num? v) {
    if (v == null) return true;
    final d = v.toDouble();
    if (!d.isFinite) return false;
    return (d - d.roundToDouble()).abs() <= wholeTolerance;
  }

  /// مبلغ بالفلس (1/100 دينار) ← أقرب دينار بالفلس (مضاعف 100)، النصف إلى الأعلى.
  static int centsUp(int cents) {
    final f = _floorDiv(cents, 100);
    final r = cents - f * 100;
    return (r >= 50 ? f + 1 : f) * 100;
  }

  /// مبلغ معاملة على حساب العميل وهو مفتوح على كسر قديم.
  ///
  /// العميل الذي رصيده رقم صحيح: المبلغ يُقرَّب ([up]).
  /// العميل الذي في رصيده كسر (بيانات قديمة، أو جهاز لم يُحدَّث): يُقبل المبلغ
  /// بكسره كما كُتب **فقط** إن جعل الرصيد رقماً صحيحاً — هكذا يُصفّى الكسر
  /// العالق بتسديد واحد. وإلا يُقرَّب كالعادة.
  static double ledgerAmount(double amount, double balanceBefore) {
    if (isWhole(amount)) return up(amount);
    if (!isWhole(balanceBefore) && isWhole(balanceBefore + amount)) {
      return _cents(amount);
    }
    return up(amount);
  }

  static double _cents(double v) => (v * 100).roundToDouble() / 100;

  /// مبالغ رأس فاتورة البيع بعد التقريب.
  ///
  /// [itemsTotal] مجموع أسطر صحيحة (كل سطر قُرّب في InvoiceItem).
  /// الخصم [down]، أجور النقل [up]، والإجمالي = الأسطر + الأجور − الخصم.
  /// المسدد: إن كان يساوي الإجمالي المعروض (بفرق فلس) ⇒ الإجمالي الجديد نفسه؛
  /// وإلا [down]، ولا يتجاوز الإجمالي ما دام المكتوب لم يتجاوزه.
  static IqdInvoiceTotals invoiceTotals({
    required double itemsTotal,
    required double discount,
    required double loadingFee,
    required double paid,
  }) {
    final items = up(itemsTotal);
    final disc = down(discount);
    final fee = up(loadingFee);
    final total = items + fee - disc;
    final rawTotal = itemsTotal + loadingFee - discount;
    double p;
    if ((paid - rawTotal).abs() <= 0.01) {
      p = total;
    } else {
      p = down(paid);
      if (paid <= rawTotal + 0.01 && p > total) p = total;
    }
    return IqdInvoiceTotals(
        itemsTotal: items, discount: disc, loadingFee: fee, paid: p, total: total);
  }
}

class IqdInvoiceTotals {
  const IqdInvoiceTotals({
    required this.itemsTotal,
    required this.discount,
    required this.loadingFee,
    required this.paid,
    required this.total,
  });
  final double itemsTotal;
  final double discount;
  final double loadingFee;
  final double paid;
  final double total;
}
