// lib/widgets/currency_impact_card.dart
//
// 💱 بطاقة «أثر سعر الدولار» للتقرير الشهري والسنوي.
// تجيب صاحب المحل عن: كم خسرت ديوني على الناس من قيمتها؟ كم زادت ديوني
// بالدولار عليّ؟ أي مواد صار سعر بيعها لا يغطي كلفتها الجديدة؟

import 'package:flutter/material.dart';

import '../services/reports_service.dart' show CurrencyImpact, UsdProductImpact;
import 'report_kit.dart';

class CurrencyImpactCard extends StatefulWidget {
  const CurrencyImpactCard({super.key, required this.impact, required this.showProfit, this.onProductTap});
  final CurrencyImpact impact;
  final bool showProfit;
  final void Function(int productId, String name)? onProductTap;

  @override
  State<CurrencyImpactCard> createState() => _CurrencyImpactCardState();
}

String _usd(double v) => '\$${repMoney(v)}';

class _CurrencyImpactCardState extends State<CurrencyImpactCard> {
  int _tab = 0; // 0 تحت الكلفة، 1 هامش ضعيف، 2 كلفة قديمة، 3 كلفة مشكوك فيها

  @override
  Widget build(BuildContext context) {
    final im = widget.impact;
    final up = im.rateAfter > im.rateBefore;
    final changed = im.rateChanged;
    final headColor = !changed ? kSetNavy : (up ? kSetRed : kSetGreen);
    final nothing = im.usdReceivables <= 0 && im.payablesUsd <= 0 && im.products.isEmpty;
    return SetCard(
      title: 'أثر سعر الدولار',
      subtitle: 'تشتري بالدولار، وتبيع وتُدين الناس بالدينار',
      icon: Icons.currency_exchange_rounded,
      color: kRepAmber,
      trailing: _RatePill(im),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 10),
        _headline(im, headColor, up),
        if (im.rateChanged) ...[
          const SizedBox(height: 8),
          _summary(im),
        ],
        if (!im.hasRateHistory)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: SetBanner(
              'لا يوجد سجل أسعار للدولار بتواريخ. سجّل كل تغيير في «العملات وأسعار الصرف» '
              '(المحاسبة) ليُحسب الأثر بين بداية الفترة ونهايتها — تغيير السعر بلا تاريخ لا يظهر هنا.',
              kind: SetBannerKind.warn,
            ),
          ),
        if (nothing)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: SetBanner('لا ديون ولا مواد مشتراة بالدولار — لا أثر للسعر على المحل حالياً.', kind: SetBannerKind.ok),
          )
        else ...[
          const SizedBox(height: 12),
          KpiGrid(minTileWidth: 220, children: [
            KpiTile(
              label: 'ديون من بضاعة الدولار',
              value: im.usdReceivables,
              icon: Icons.groups_rounded,
              color: kSetBlue,
              hint: changed
                  ? 'كانت ≈ ${_usd(im.receivablesUsdBefore)} وصارت ≈ ${_usd(im.receivablesUsdAfter)}'
                  : '≈ ${_usd(im.receivablesUsdAfter)} • ${im.usdDebtorCount} عميل',
            ),
            if (changed && im.usdReceivables > 0)
              KpiTile(
                label: up ? 'ما فقدته هذه الديون (\$)' : 'ما كسبته هذه الديون (\$)',
                value: im.receivablesLossUsd.abs(),
                icon: up ? Icons.trending_down_rounded : Icons.trending_up_rounded,
                color: up ? kSetRed : kSetGreen,
                hint: '${im.receivablesLossPct.abs().toStringAsFixed(1)}% • ≈ ${repMoney(im.receivablesLossIqd.abs())} دينار لإعادة الشراء',
              ),
            KpiTile(
              label: 'ديون بضاعة الدينار واليدوي',
              value: im.iqdReceivables,
              icon: Icons.verified_user_outlined,
              color: kSetMuted,
              hint: 'لا تتأثر بالدولار — من أصل ${repMoney(im.receivables)}',
            ),
            KpiTile(
              label: 'ديونك للموردين بالدولار (\$)',
              value: im.payablesUsd,
              icon: Icons.local_shipping_rounded,
              color: kRepPurple,
              hint: im.payablesUsd > 0 ? '≈ ${repMoney(im.payablesUsdIqdAfter)} دينار بسعر اليوم' : 'لا ديون بالدولار',
            ),
            if (changed && im.payablesUsd > 0)
              KpiTile(
                label: up ? 'زادت كلفتها عليك (دينار)' : 'نقصت كلفتها عليك (دينار)',
                value: im.payablesIncrease.abs(),
                icon: up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                color: up ? kSetRed : kSetGreen,
                hint: 'كانت ${repMoney(im.payablesUsdIqdBefore)}',
              ),
            if (widget.showProfit && im.healthy.isNotEmpty)
              KpiTile(
                label: 'تغيّر قيمة مخزون الدولار',
                value: im.stockEffect,
                icon: Icons.inventory_rounded,
                color: kRepTeal,
                hint: changed
                    ? 'كلفة استبدال ${im.healthy.length} مادة بين السعرين'
                    : 'قيمته اليوم ${repMoney(im.usdStockValueNow)}',
              ),
            if (im.periodUsdPurchases > 0)
              KpiTile(
                label: 'مشتريات الفترة بالدولار (\$)',
                value: im.periodUsdPurchases,
                icon: Icons.shopping_bag_rounded,
                color: kRepAmber,
                hint: '≈ ${repMoney(im.periodUsdPurchasesIqd)} دينار بأسعار أيامها',
              ),
          ]),
          if (im.payablesUsd > 0) ...[
            const SizedBox(height: 10),
            _coverage(im),
            const SizedBox(height: 8),
            _whatIf(im),
          ],
          if (im.usdSuppliers.isNotEmpty) ...[
            const SizedBox(height: 12),
            _suppliers(im),
          ],
          if (im.products.isNotEmpty) ...[
            const SizedBox(height: 14),
            _productsSection(im),
          ],
          if (im.rates.length > 1) ...[
            const SizedBox(height: 12),
            _rateHistory(im),
          ],
        ],
      ]),
    );
  }

  Widget _headline(CurrencyImpact im, Color c, bool up) {
    final text = !im.rateChanged
        ? 'سعر الدولار ثابت في هذه الفترة: ${repMoney(im.rateAfter)} دينار'
        : 'الدولار ${up ? 'ارتفع' : 'انخفض'} من ${repMoney(im.rateBefore)} إلى ${repMoney(im.rateAfter)} دينار '
            '(${up ? '+' : '−'}${im.changePct.abs().toStringAsFixed(1)}%)';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        Icon(!im.rateChanged ? Icons.horizontal_rule_rounded : (up ? Icons.north_east_rounded : Icons.south_east_rounded),
            color: c),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(fontWeight: FontWeight.w800, color: c, fontSize: 14.5))),
      ]),
    );
  }

  /// الأثر بجملة عامة: ما خسرته ديون بضاعة الدولار، ما زادته ديون الدولار، وما
  /// ربحه المخزون، والصافي.
  Widget _summary(CurrencyImpact im) {
    final up = im.rateUp;
    final parts = <String>[
      if (im.usdReceivables > 0)
        'ديونك من بضاعة الدولار (${repMoney(im.usdReceivables)} د.ع) ${up ? 'فقدت' : 'كسبت'} ≈ ${_usd(im.receivablesLossUsd.abs())} '
            'من قيمتها — تحتاج ${repMoney(im.receivablesLossIqd.abs())} د.ع ${up ? 'إضافية' : 'أقل'} لتعيد شراء بضاعتها',
      if (im.payablesUsd > 0)
        'ديونك للموردين (${_usd(im.payablesUsd)}) صارت ${up ? 'تكلّفك' : 'توفّر عليك'} ${repMoney(im.payablesIncrease.abs())} د.ع ${up ? 'أكثر' : ''}',
      if (widget.showProfit && im.stockEffect.abs() >= 1)
        'مخزون مواد الدولار ${im.stockEffect >= 0 ? 'ارتفعت' : 'انخفضت'} قيمته ${repMoney(im.stockEffect.abs())} د.ع',
    ];
    if (parts.isEmpty) {
      return const SetBanner('لا ديون ولا مخزون مرتبط بالدولار — تغيّر السعر لم يؤثر على المحل.', kind: SetBannerKind.ok);
    }
    final net = widget.showProfit ? im.netEffect : -(im.receivablesLossIqd + im.payablesIncrease);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kSetBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final p in parts)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(padding: EdgeInsets.only(top: 6), child: Icon(Icons.circle, size: 6, color: kSetMuted)),
              const SizedBox(width: 8),
              Expanded(child: Text(p, style: const TextStyle(height: 1.6, color: kSetText))),
            ]),
          ),
        const Divider(height: 14),
        Row(children: [
          Text(net < 0 ? 'صافي الأثر عليك: ' : 'صافي الأثر لصالحك: ',
              style: const TextStyle(fontWeight: FontWeight.w800, color: kSetText)),
          MoneyLabel(net, size: 16),
          const Text(' د.ع', style: TextStyle(color: kSetMuted)),
        ]),
        if (im.iqdReceivables > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'ديون بضاعة الدينار والديون اليدوية (${repMoney(im.iqdReceivables)} د.ع) لم تُحسب خسارة: '
              'تشتري تلك البضاعة بالدينار.',
              style: const TextStyle(fontSize: 12, color: kSetMuted),
            ),
          ),
      ]),
    );
  }

  Widget _coverage(CurrencyImpact im) {
    final cov = im.coverage;
    if (cov < 1) {
      return SetBanner(
        'كل ديونك على الناس (≈ ${_usd(im.rateAfter > 0 ? im.receivables / im.rateAfter : 0)}) لا تغطي ديون الدولار عليك (${_usd(im.payablesUsd)}) — '
        'كل ارتفاع للدولار يوسّع الفجوة. التحصيل السريع أو تسديد جزء بالدولار يقلّل الخطر.',
        kind: SetBannerKind.warn,
        icon: Icons.warning_amber_rounded,
      );
    }
    return SetBanner(
      'كل ديونك على الناس تغطي ديون الدولار ${cov.toStringAsFixed(1)} مرة بسعر اليوم — '
      'التحصيل قبل ارتفاع آخر للدولار يحفظ هذه التغطية.',
      icon: Icons.shield_outlined,
    );
  }

  Widget _whatIf(CurrencyImpact im) {
    final a = im.whatIf(5), b = im.whatIf(10);
    Widget chip(String p, ({double payablesIqd, double receivablesUsd, double stockIqd}) w) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kSetBorder),
          ),
          child: Text(
            'لو ارتفع $p أخرى: ديون الدولار +${repMoney(w.payablesIqd)} دينار، وديون بضاعة الدولار تفقد ${_usd(w.receivablesUsd)}'
            '${widget.showProfit && w.stockIqd > 0 ? '، والمخزون +${repMoney(w.stockIqd)}' : ''}',
            style: const TextStyle(fontSize: 12.5, color: kSetText),
          ),
        );
    return Wrap(spacing: 8, runSpacing: 8, children: [chip('5%', a), chip('10%', b)]);
  }

  Widget _suppliers(CurrencyImpact im) {
    final maxV = im.usdSuppliers.fold<double>(0, (m, s) => s.usd > m ? s.usd : m);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const _SubTitle('الموردون الذين تدين لهم بالدولار'),
      for (var i = 0; i < im.usdSuppliers.length; i++)
        RankRow(
          rank: i + 1,
          title: im.usdSuppliers[i].name,
          subtitle: '≈ ${repMoney(im.usdSuppliers[i].usd * im.rateAfter)} دينار اليوم',
          value: im.usdSuppliers[i].usd,
          fraction: maxV > 0 ? im.usdSuppliers[i].usd / maxV : 0,
          color: kRepPurple,
          trailing: Text(_usd(im.usdSuppliers[i].usd),
              textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w800, color: kSetText)),
        ),
    ]);
  }

  Widget _productsSection(CurrencyImpact im) {
    final r = im.rateAfter;
    final below = im.belowCost;
    final low = im.lowMargin(10);
    final outdated = im.costOutdated;
    final sus = im.suspicious;
    final lists = <(String, List<UsdProductImpact>, Color)>[
      ('تحت الكلفة', below, kSetRed),
      ('هامش أقل من 10%', low, kSetOrange),
      ('كلفتها المسجّلة قديمة', outdated, kRepAmber),
      ('كلفة مشكوك فيها', sus, kRepPurple),
    ];
    final tab = _tab.clamp(0, lists.length - 1).toInt();
    final cur = lists[tab];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _SubTitle('مواد آخر شراء لها بالدولار (${im.products.length})'),
      if (sus.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SetBanner(
            '${sus.length} مادة كلفتها مسجّلة بالرقم الدولاري كأنه دينار (خطأ قديم في تأكيد فواتير الشراء بالدولار، أُصلح الآن). '
            'ربح هذه المواد في التقارير مضخّم حتى تصحّح كلفتها من بطاقة المادة.',
            kind: SetBannerKind.error,
          ),
        ),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (var i = 0; i < lists.length; i++)
          ChoiceChip(
            label: Text('${lists[i].$1} (${lists[i].$2.length})'),
            selected: tab == i,
            onSelected: (_) => setState(() => _tab = i),
            selectedColor: lists[i].$3.withValues(alpha: 0.15),
            labelStyle: TextStyle(fontWeight: FontWeight.w700, color: tab == i ? lists[i].$3 : kSetText),
          ),
      ]),
      const SizedBox(height: 8),
      if (cur.$2.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            switch (tab) {
              0 => 'لا مادة سعر بيعها أقل من كلفتها بسعر الدولار اليوم.',
              1 => 'لا مادة هامشها أقل من 10% بكلفة اليوم.',
              2 => 'كلفة مواد الدولار مسجّلة بسعر اليوم (المواد التي كلفتها بالدولار تتبعه تلقائياً).',
              _ => 'لا كلفة مشكوك فيها.',
            },
            style: const TextStyle(color: kSetMuted),
          ),
        )
      else ...[
        _UsdHeader(suspicious: tab == 3),
        for (final p in cur.$2.take(15))
          _UsdRow(
            p: p,
            rate: r,
            suspicious: tab == 3,
            onTap: widget.onProductTap == null ? null : () => widget.onProductTap!(p.productId, p.name),
          ),
        if (cur.$2.length > 15)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('و${cur.$2.length - 15} مادة أخرى', style: const TextStyle(color: kSetMuted)),
          ),
      ],
    ]);
  }

  Widget _rateHistory(CurrencyImpact im) {
    final list = im.rates.length > 10 ? im.rates.sublist(im.rates.length - 10) : im.rates;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const _SubTitle('أسعار الدولار المسجّلة في الفترة'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final r in list)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(10), border: Border.all(color: kSetBorder)),
            child: Text('${repDate(r.$1)}: ${repMoney(r.$2)}', style: const TextStyle(fontSize: 12.5)),
          ),
      ]),
    ]);
  }
}

class _RatePill extends StatelessWidget {
  const _RatePill(this.im);
  final CurrencyImpact im;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: kRepAmber.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(20)),
        child: Text('\$1 = ${repMoney(im.rateAfter)}',
            textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w800, color: kRepAmber, fontSize: 12.5)),
      );
}

class _SubTitle extends StatelessWidget {
  const _SubTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w800, color: kSetText, fontSize: 14)),
      );
}

Widget _c(Widget child, {int flex = 2, bool numeric = true}) => Expanded(
      flex: flex,
      child: Align(alignment: numeric ? Alignment.center : AlignmentDirectional.centerStart, child: child),
    );

class _UsdHeader extends StatelessWidget {
  const _UsdHeader({required this.suspicious});
  final bool suspicious;
  @override
  Widget build(BuildContext context) {
    const st = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: kSetMuted);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: kSetBorder))),
      child: Row(children: [
        _c(const Text('المادة', style: st), flex: 4, numeric: false),
        _c(const Text('الكلفة \$', style: st)),
        _c(Text(suspicious ? 'المسجّلة' : 'المسجّلة (د)', style: st)),
        _c(Text(suspicious ? 'الصحيحة تقريباً' : 'بسعر اليوم (د)', style: st)),
        _c(const Text('سعر البيع', style: st)),
        _c(const Text('الهامش', style: st)),
      ]),
    );
  }
}

class _UsdRow extends StatelessWidget {
  const _UsdRow({required this.p, required this.rate, required this.suspicious, this.onTap});
  final UsdProductImpact p;
  final double rate;
  final bool suspicious;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final m = p.marginAt(rate);
    final mc = p.belowCost(rate) ? kSetRed : (m < 10 ? kSetOrange : kSetGreen);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9)))),
        child: Row(children: [
          _c(
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, color: kSetText)),
              Text(
                  [
                    if (p.autoTracked) 'تتبع الدولار',
                    if (p.supplierName.isNotEmpty) p.supplierName,
                    if (p.lastPurchase != null) repDate(p.lastPurchase!),
                    'مخزون ${repQty(p.stock)}',
                  ].join(' • '),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: kSetMuted)),
            ]),
            flex: 4,
            numeric: false,
          ),
          _c(Text(p.usdUnitCost.toStringAsFixed(2), textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 13))),
          _c(MoneyLabel(p.costPrice, size: 13, bold: false)),
          _c(MoneyLabel(suspicious ? p.usdUnitCost * p.rateAtPurchase : p.newCost(rate), size: 13)),
          _c(MoneyLabel(p.sellingPrice, size: 13, bold: false)),
          _c(Text(p.sellingPrice > 0 ? repPercent(m) : '—',
              textDirection: TextDirection.ltr, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: mc))),
        ]),
      ),
    );
  }
}
