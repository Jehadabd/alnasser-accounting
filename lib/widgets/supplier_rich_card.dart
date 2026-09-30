import 'package:flutter/material.dart';
import '../models/supplier.dart';
import 'package:intl/intl.dart' as intl;

/// بطاقة مورد في لوحة الموردين.
///
/// الرصيد يُعرض بالعملتين (الدينار والدولار) لأن دين المورد يُحسب لكل عملة على
/// حدة؛ كانت تعرض عملته المفضلة فقط، فمورد عليه دين بالدولار وحده يظهر «0 د.ع».
class SupplierRichCard extends StatelessWidget {
  final Supplier supplier;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const SupplierRichCard({
    super.key,
    required this.supplier,
    required this.onTap,
    required this.onDelete,
    required this.onEdit,
  });

  /// الارتفاع الذي تحتاجه البطاقة (يُمرَّر لـ mainAxisExtent في الشبكة).
  static const double preferredHeight = 300;

  /// أقل عرض مريح للبطاقة (لحساب عدد الأعمدة).
  static const double minWidth = 260;

  static final intl.NumberFormat _money = intl.NumberFormat('#,##0.##', 'en_US');

  @override
  Widget build(BuildContext context) {
    final iqd = supplier.totalDebtIqd;
    final usd = supplier.totalDebtUsd;
    final preferUsd = supplier.currency == 'USD';
    final showIqd = iqd.abs() > 0.01 || (usd.abs() <= 0.01 && !preferUsd);
    final showUsd = usd.abs() > 0.01 || (iqd.abs() <= 0.01 && preferUsd);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
          border: Border.all(color: Colors.grey.withOpacity(0.1)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // HEADER
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Avatar
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF455A64), Color(0xFF607D8B)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF455A64).withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        supplier.name.trim().isNotEmpty ? supplier.name.trim()[0].toUpperCase() : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          supplier.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            _chip(supplier.paymentTerms == 'credit' ? 'آجل' : 'نقدي', Colors.blue),
                            _chip(preferUsd ? 'دولار' : 'دينار', Colors.blueGrey),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const Spacer(),

              // STATS ROW
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildMiniStat('الفواتير المؤكدة', '${supplier.totalInvoices}'),
                    _buildMiniStat('الدفعات', '${supplier.totalPayments}'),
                  ],
                ),
              ),

              // FINANCIALS
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'الرصيد',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (showIqd) _balanceLine(iqd, 'د.ع'),
                        if (showUsd) _balanceLine(usd, '\$'),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // ACTIONS: التفاصيل + تعديل + حذف
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: onTap,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF334155),
                        elevation: 0,
                        side: BorderSide(color: Colors.grey[200]!),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text(
                        'عرض التفاصيل',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: Icon(Icons.edit_outlined, color: Colors.blueGrey[400], size: 20),
                    onPressed: onEdit,
                    tooltip: 'تعديل بيانات المورد',
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_outline, color: Colors.red[300], size: 20),
                    onPressed: onDelete,
                    tooltip: 'حذف المورد',
                    hoverColor: Colors.red.withOpacity(0.1),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// موجب = دين علينا للمورد (أحمر)، سالب = رصيد لنا عنده (أخضر).
  Widget _balanceLine(double amount, String symbol) {
    final Color color;
    final String suffix;
    if (amount > 0.01) {
      color = const Color(0xFFEF4444);
      suffix = '';
    } else if (amount < -0.01) {
      color = const Color(0xFF10B981);
      suffix = ' (لنا)';
    } else {
      color = const Color(0xFF10B981);
      suffix = '';
    }
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerEnd,
      child: Text(
        '${_money.format(amount.abs())} $symbol$suffix',
        maxLines: 1,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Widget _chip(String text, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color[50],
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: color[700],
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildMiniStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF334155)),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: Colors.grey[500]),
        ),
      ],
    );
  }
}
