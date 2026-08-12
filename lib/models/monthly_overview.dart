class MonthlyOverview {
  final String monthYear; // yyyy-MM
  final double totalSales;
  final double netProfit;
  final double totalCost; // إجمالي التكلفة
  final double cashSales;
  final double creditSales;
  final double totalReturns;
  final double totalDebtPayments;
  final double totalManualDebt; // إضافة دين يدوية
  final double manualDebtProfit; // ربح المعاملات اليدوية (15%)
  final double settlementAdditions;
  final double settlementReturns;
  final int invoiceCount; // عدد الفواتير
  final int manualDebtCount; // عدد معاملات إضافة الدين
  final int manualPaymentCount; // عدد معاملات تسديد الدين

  const MonthlyOverview({
    required this.monthYear,
    required this.totalSales,
    required this.netProfit,
    this.totalCost = 0.0,
    required this.cashSales,
    required this.creditSales,
    required this.totalReturns,
    required this.totalDebtPayments,
    this.totalManualDebt = 0.0,
    this.manualDebtProfit = 0.0,
    required this.settlementAdditions,
    required this.settlementReturns,
    this.invoiceCount = 0,
    this.manualDebtCount = 0,
    this.manualPaymentCount = 0,
  });
}


