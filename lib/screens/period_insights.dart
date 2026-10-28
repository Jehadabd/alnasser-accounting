// lib/screens/period_insights.dart
//
// 💡 «ماذا حدث؟» — جمل قصيرة تشرح أرقام الفترة: هل المبيعات أعلى أو أقل من
// المعتاد ولماذا، الديون والمقبوض، الربح والفواتير الخاسرة، الآجل، الراجع،
// الخصومات، العملاء المعتادون الغائبون، أفضل يوم ومادة.
// قواعد ثابتة على بياناتك (لا ذكاء اصطناعي)، فالجملة نفسها تعطي الرقم نفسه دائماً.

import 'package:flutter/material.dart';

import '../services/reports_service.dart';
import '../widgets/report_kit.dart';
import 'report_parts.dart' show repWeekday;

class PeriodInsight {
  const PeriodInsight(this.icon, this.color, this.title, this.text);
  final IconData icon;
  final Color color;
  final String title;
  final String text;
}

/// عميل اشترى في معظم الفترات السابقة ولم يشترِ في هذه.
class AbsentCustomer {
  AbsentCustomer(this.id, this.name);
  final int id;
  final String name;
  double sales = 0;
  int invoices = 0;
  final Set<int> periods = {};
}

double _n(Map<String, dynamic> m, String k) => (m[k] as num?)?.toDouble() ?? 0.0;
String _pct(double v) => '${v.abs().toStringAsFixed(v.abs() < 10 ? 1 : 0)}%';

List<PeriodInsight> buildPeriodInsights({
  required Map<String, dynamic> s,
  required Map<String, dynamic> prev,
  required String prevLabel,
  required double baseNet,
  required String baseLabel,
  required SalesFacts facts,
  required SalesFacts prevFacts,
  required Map<int, String> catNames,
  required Map<int, int?> catParents,
  required CashFlow cash,
  required bool canProfit,
  required bool inProgress,
  required bool dayMode,
  required bool yearMode,
  List<AbsentCustomer> absent = const [],
}) {
  final out = <PeriodInsight>[];
  final net = _n(s, 'netSales');
  final sales = _n(s, 'totalSales');
  final hasSales = facts.invoices.isNotEmpty || facts.returns.isNotEmpty;

  // 0) فترة لم تنتهِ
  if (inProgress) {
    out.add(PeriodInsight(
      Icons.timelapse_rounded,
      kSetMuted,
      dayMode ? 'اليوم لم ينتهِ بعد' : 'الفترة لم تنتهِ بعد',
      dayMode
          ? 'الأرقام حتى الآن — قارن بحذر.'
          : 'المقارنة مع نفس عدد الأيام من $prevLabel، لا مع الفترة كاملة.',
    ));
  }

  // 1) المبيعات مقابل المعتاد
  if (net.abs() >= 1 || baseNet.abs() >= 1) {
    if (baseNet <= 0) {
      out.add(PeriodInsight(Icons.point_of_sale_rounded, kSetNavy, 'صافي المبيعات ${repMoney(net)}',
          'لا مبيعات في $baseLabel للمقارنة.'));
    } else {
      final p = (net - baseNet) / baseNet * 100;
      final same = p.abs() < 3;
      out.add(PeriodInsight(
        p >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
        same ? kSetMuted : (p > 0 ? kSetGreen : kSetRed),
        same
            ? 'المبيعات في مستواها المعتاد'
            : (p > 0 ? 'المبيعات أعلى من المعتاد بـ ${_pct(p)}' : 'المبيعات أقل من المعتاد بـ ${_pct(p)}'),
        'صافي المبيعات ${repMoney(net)} مقابل ${repMoney(baseNet)} ($baseLabel).',
      ));
    }
  }

  // 2) أكبر سبب للتغيّر: القسم الذي تغيّرت مبيعاته أكثر باتجاه التغيّر
  if (hasSales || prevFacts.invoices.isNotEmpty) {
    Map<String, (String, double)> byCat(SalesFacts f) => {
          for (final c in f.byCategory(catNames, parents: catParents, rollupToRoot: true))
            '${c.categoryId}': (c.categoryId == null ? 'عام / غير مصنّف' : c.name, c.netRevenue),
        };
    final cur = byCat(facts), old = byCat(prevFacts);
    final keys = {...cur.keys, ...old.keys};
    var total = 0.0;
    String? bestKey;
    var best = 0.0;
    for (final k in keys) {
      total += (cur[k]?.$2 ?? 0) - (old[k]?.$2 ?? 0);
    }
    for (final k in keys) {
      final diff = (cur[k]?.$2 ?? 0) - (old[k]?.$2 ?? 0);
      if ((total >= 0 && diff > best) || (total < 0 && diff < best)) {
        best = diff;
        bestKey = k;
      }
    }
    if (bestKey != null && best.abs() >= 1 && total.abs() >= 1) {
      final name = cur[bestKey]?.$1 ?? old[bestKey]?.$1 ?? '';
      out.add(PeriodInsight(
        Icons.category_rounded,
        best > 0 ? kSetGreen : kSetRed,
        'أكبر سبب للتغيّر: $name',
        'مبيعات القسم ${repMoney(cur[bestKey]?.$2 ?? 0)} مقابل ${repMoney(old[bestKey]?.$2 ?? 0)} في $prevLabel '
            '(${best > 0 ? '+' : '−'}${repMoney(best.abs())}).',
      ));
    }
  }

  // 3) الديون والمقبوض
  {
    final change = cash.debtChange;
    final cashSales = _n(s, 'cashSales');
    final credit = _n(s, 'creditSales');
    final down = (_n(s, 'paidAmount') - cashSales).clamp(0, double.infinity).toDouble();
    final unpaid = (credit - down).clamp(0, double.infinity).toDouble();
    final manual = _n(s, 'totalManualDebt');
    if (change.abs() >= 1 || cash.netCollected.abs() >= 1) {
      final end = cash.debtEnd;
      out.add(PeriodInsight(
        Icons.account_balance_wallet_rounded,
        change > 0.5 ? kSetOrange : kSetGreen,
        change > 0.5
            ? 'الديون زادت ${repMoney(change)}'
            : (change < -0.5 ? 'الديون نقصت ${repMoney(-change)}' : 'الديون لم تتغيّر'),
        'قبضت ${repMoney(cash.netCollected)} (نقد الفواتير وتسديد الديون)، وبعت آجلاً ${repMoney(unpaid)}'
            '${manual > 0 ? ' وأُضيف دين يدوي ${repMoney(manual)}' : ''}.'
            '${end != null ? ' مجموع الديون في نهاية الفترة ${repMoney(end)}.' : ''}',
      ));
    }
  }

  // 4) الربح: فواتير خاسرة وهامش الربح
  if (canProfit && hasSales) {
    final losses = facts.invoices.where((i) => i.profit < -0.5).toList()..sort((a, b) => a.profit.compareTo(b.profit));
    if (losses.isNotEmpty) {
      final sum = losses.fold<double>(0, (a, i) => a + i.profit);
      out.add(PeriodInsight(
        Icons.warning_amber_rounded,
        kSetRed,
        '${losses.length} فاتورة بيعت بأقل من الكلفة',
        'مجموع الخسارة ${repMoney(-sum)} — أكبرها فاتورة ${losses.first.displayNumber} (${losses.first.customerName}). '
            'اضغط «الربح المؤكد» لقائمتها.',
      ));
    }
    final m = _n(s, 'profitMargin'), pm = _n(prev, 'profitMargin');
    if (_n(prev, 'invoiceCount') > 0 && (m - pm).abs() >= 2) {
      out.add(PeriodInsight(
        m < pm ? Icons.south_east_rounded : Icons.north_east_rounded,
        m < pm ? kSetRed : kSetGreen,
        'هامش الربح ${repPercent(m)} (كان ${repPercent(pm)})',
        m < pm
            ? 'الربح من كل 100 دينار مبيعات نزل — راجع الخصومات والمواد التي ارتفعت كلفتها.'
            : 'الربح من كل 100 دينار مبيعات ارتفع عن $prevLabel.',
      ));
    }
  }

  // 5) البيع الآجل
  if (sales > 0) {
    final share = _n(s, 'creditSales') / sales * 100;
    final ps = _n(prev, 'totalSales');
    final prevShare = ps > 0 ? _n(prev, 'creditSales') / ps * 100 : null;
    if (prevShare != null && share - prevShare >= 10) {
      out.add(PeriodInsight(Icons.schedule_rounded, kSetOrange, 'البيع الآجل ارتفع إلى ${share.toStringAsFixed(0)}% من المبيعات',
          'كان ${prevShare.toStringAsFixed(0)}% في $prevLabel. الآجل يرفع الديون ولا يدخل الصندوق.'));
    } else if (share >= 60) {
      out.add(PeriodInsight(Icons.schedule_rounded, kSetOrange, 'الآجل ${share.toStringAsFixed(0)}% من المبيعات',
          'أكثر من نصف البيع دين: تابع التحصيل.'));
    }
  }

  // 6) الراجع
  final ret = _n(s, 'totalReturns');
  if (sales > 0 && ret / sales >= 0.03) {
    final edits = _n(s, 'editReturns');
    out.add(PeriodInsight(
      Icons.keyboard_return_rounded,
      kRepPurple,
      'الراجع ${_pct(ret / sales * 100)} من المبيعات',
      '${repMoney(ret)} — ${_n(s, 'salesReturnsCount').toInt()} مستند مرتجع'
          '${edits > 0 ? '، و${repMoney(edits)} أُرجعت بتعديل الفواتير' : ''}.',
    ));
  }

  // 7) الخصومات
  final gross = _n(s, 'grossSales'), disc = _n(s, 'totalDiscount');
  if (gross > 0 && disc / gross >= 0.03) {
    out.add(PeriodInsight(Icons.discount_rounded, kSetOrange, 'الخصومات ${_pct(disc / gross * 100)} من قيمة البضاعة',
        'خصم ${repMoney(disc)} على الفواتير.'));
  }

  // 8) متوسط الفاتورة
  final cnt = _n(s, 'invoiceCount'), pcnt = _n(prev, 'invoiceCount');
  if (cnt >= 3 && pcnt >= 3) {
    final avg = _n(s, 'averageInvoice'), pavg = _n(prev, 'averageInvoice');
    if (pavg > 0) {
      final ch = (avg - pavg) / pavg * 100;
      if (ch.abs() >= 15) {
        out.add(PeriodInsight(
          Icons.receipt_rounded,
          ch > 0 ? kSetGreen : kSetOrange,
          'متوسط الفاتورة ${repMoney(avg)} (${ch > 0 ? '+' : '−'}${_pct(ch)})',
          'كان ${repMoney(pavg)} في $prevLabel. ${ch > 0 ? 'الزبون يشتري أكثر في الفاتورة الواحدة.' : 'فواتير أصغر من المعتاد.'}',
        ));
      }
    }
  }

  // 9) عملاء معتادون غائبون
  if (absent.isNotEmpty) {
    out.add(PeriodInsight(
      Icons.person_search_rounded,
      kSetBlue,
      '${absent.length} من العملاء المعتادين لم يشتروا',
      'اشتروا في معظم الفترات الثلاث السابقة ولم يشتروا في هذه: ${absent.map((a) => a.name).join('، ')}.',
    ));
  }

  // 10) أفضل وقت
  if (facts.invoices.isNotEmpty) {
    if (dayMode) {
      final h = List<double>.filled(24, 0);
      for (final i in facts.invoices) {
        h[i.date.hour] += i.total;
      }
      var peak = 0;
      for (var k = 1; k < 24; k++) {
        if (h[k] > h[peak]) peak = k;
      }
      if (facts.invoices.length >= 3) {
        out.add(PeriodInsight(Icons.local_fire_department_rounded, kRepAmber, 'ذروة البيع الساعة $peak',
            '${repMoney(h[peak])} من فواتير الساعة ${peak.toString().padLeft(2, '0')}:00.'));
      }
    } else if (yearMode || facts.byMonth().length >= 3) {
      // أفضل وأضعف شهر، وأشهر الربح السالب
      final months = facts.byMonth().entries.where((e) => e.value.netSales > 0).toList()
        ..sort((a, b) => b.value.netSales.compareTo(a.value.netSales));
      String label(String key) {
        final ym = key.split('-');
        return ym.length == 2 ? repMonth(int.parse(ym[0]), int.parse(ym[1])) : key;
      }

      if (months.length >= 2) {
        final best = months.first, worst = months.last;
        out.add(PeriodInsight(
          Icons.emoji_events_rounded,
          kRepAmber,
          'أفضل شهر: ${label(best.key)} — أضعف شهر: ${label(worst.key)}',
          'الفرق بينهما ${repMoney(best.value.netSales - worst.value.netSales)} '
              '(${(worst.value.netSales / best.value.netSales * 100).toStringAsFixed(0)}% من أفضل شهر). '
              'خطّط المخزون والعروض على هذا الموسم.',
        ));
      }
      if (canProfit) {
        final loss = facts.byMonth().entries.where((e) => e.value.profit < -0.5).map((e) => label(e.key)).toList();
        if (loss.isNotEmpty) {
          out.add(PeriodInsight(Icons.warning_amber_rounded, kSetRed, 'أشهر بربح سالب: ${loss.length}',
              '${loss.join('، ')} — افتح الشهر وتحقق من الكلفة والخصومات والراجع.'));
        }
      }
    } else {
      final days = facts.byDay();
      if (days.length >= 2) {
        final best = days.entries.reduce((a, b) => a.value.netSales >= b.value.netSales ? a : b);
        final d = DateTime.parse(best.key);
        out.add(PeriodInsight(Icons.emoji_events_rounded, kRepAmber, 'أفضل يوم: ${repWeekday(d)} ${repDate(d)}',
            'صافي مبيعاته ${repMoney(best.value.netSales)} في ${best.value.invoiceCount} فاتورة.'));
      }
    }
  }

  // 11) المادة الأكثر مبيعاً
  final products = facts.byProduct()..sort((a, b) => b.netRevenue.compareTo(a.netRevenue));
  if (products.isNotEmpty && products.first.netRevenue > 0) {
    final p = products.first;
    out.add(PeriodInsight(
      Icons.inventory_2_rounded,
      kSetNavy,
      'الأكثر مبيعاً: ${p.name}',
      '${repQty(p.netQty)} ${p.baseUnit} بـ ${repMoney(p.netRevenue)}${canProfit ? ' • ربح ${repMoney(p.profit)}' : ''}.',
    ));
  }

  // 12) تركّز المبيعات في عملاء ومواد قليلة (فترة أطول من أسبوع)
  final spanDays = facts.byDay().length;
  if (!dayMode && net > 0 && spanDays >= 7) {
    final customers = facts.byCustomer()..sort((a, b) => b.totals.netSales.compareTo(a.totals.netSales));
    if (customers.length >= 10) {
      final top = customers.take(10).fold<double>(0, (a, c) => a + c.totals.netSales);
      final share = top / net * 100;
      out.add(PeriodInsight(
        Icons.groups_rounded,
        share > 50 ? kSetOrange : kSetBlue,
        'أكبر 10 عملاء = ${share.toStringAsFixed(0)}% من المبيعات',
        share > 50
            ? 'اعتماد كبير على عملاء قليلين: خسارة أحدهم تهزّ الفترة. أكبرهم: ${customers.first.name}.'
            : 'المبيعات موزعة على عملاء كثيرين — وضع صحي. أكبرهم: ${customers.first.name}.',
      ));
    }
    if (products.length >= 10) {
      final top = products.take(10).fold<double>(0, (a, p) => a + p.netRevenue);
      out.add(PeriodInsight(
        Icons.inventory_rounded,
        kRepAmber,
        'أعلى 10 مواد = ${(top / net * 100).toStringAsFixed(0)}% من المبيعات',
        'أولها ${products.first.name}. هذه المواد لا يجب أن تنقطع من المخزن.',
      ));
    }
  }

  // 13) أيام بلا فواتير (من الأيام المنقضية فقط)
  if (!dayMode && facts.from != null && facts.to != null) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final f0 = facts.from!, t0 = facts.to!;
    final start = DateTime(f0.year, f0.month, f0.day);
    var end = DateTime(t0.year, t0.month, t0.day);
    if (end.isAfter(today)) end = today;
    final n = end.difference(start).inDays + 1;
    if (n >= 7) {
      final withSales = facts.invoices.map((i) => SalesFacts.day(i.date)).toSet().length;
      final zero = n - withSales;
      if (zero > 0) {
        out.add(PeriodInsight(Icons.event_busy_rounded, kSetMuted, '$zero يوم بلا فواتير من $n',
            'متوسط مبيعات اليوم ${repMoney(net / n)} (على الأيام المنقضية فقط).'));
      }
    }
  }
  return out;
}

/// بطاقة «ماذا حدث؟».
class PeriodInsightsCard extends StatelessWidget {
  const PeriodInsightsCard({super.key, required this.items});
  final List<PeriodInsight> items;

  @override
  Widget build(BuildContext context) {
    return SetCard(
      title: 'ماذا حدث؟',
      subtitle: 'قراءة سريعة للأرقام — بقواعد ثابتة من بياناتك',
      icon: Icons.auto_awesome_rounded,
      color: const Color(0xFF7C3AED),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      child: items.isEmpty
          ? const EmptyReport(title: 'لا شيء يستحق الذكر', icon: Icons.auto_awesome_outlined)
          : LayoutBuilder(builder: (context, c) {
              final cols = c.maxWidth >= 820 ? 2 : 1;
              final w = cols == 1 ? c.maxWidth : (c.maxWidth - 10) / 2;
              return Wrap(spacing: 10, runSpacing: 10, children: [
                for (final i in items) SizedBox(width: w, child: _InsightTile(i)),
              ]);
            }),
    );
  }
}

class _InsightTile extends StatelessWidget {
  const _InsightTile(this.i);
  final PeriodInsight i;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: i.color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: i.color.withValues(alpha: 0.18)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: i.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
          child: Icon(i.icon, size: 19, color: i.color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(i.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: kSetText)),
            const SizedBox(height: 3),
            Text(i.text, style: const TextStyle(fontSize: 12.5, color: kSetMuted, height: 1.55)),
          ]),
        ),
      ]),
    );
  }
}
