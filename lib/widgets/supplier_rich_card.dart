import 'package:flutter/material.dart';
import '../models/supplier.dart';
import 'package:intl/intl.dart' as intl;

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

  @override
  Widget build(BuildContext context) {
    final hasDebt = supplier.hasDebt;
    final totalBalance = supplier.totalDebt;
    final totalPaid = supplier.totalPayments.toDouble(); // Assuming we track this
    final totalVolume = totalBalance + totalPaid;
    final progress = totalVolume > 0 ? (totalPaid / totalVolume) : 0.0;
    
    // Determine currency logic safely
    final currencySymbol = supplier.currency == 'USD' ? '\$' : 'د.ع';

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
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            children: [
              // DELETE BUTTON HOVER EFFECT (Simulated by simple position)
              Positioned(
                top: 12,
                left: 12,
                child: IconButton(
                  icon: Icon(Icons.delete_outline, color: Colors.grey[400], size: 20),
                  onPressed: onDelete,
                  tooltip: 'حذف المورد',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.grey[50],
                    hoverColor: Colors.red.withOpacity(0.1),
                    focusColor: Colors.red.withOpacity(0.1),
                  ),
                ),
              ),

              Padding(
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
                              supplier.name.isNotEmpty ? supplier.name[0].toUpperCase() : '?',
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
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blue[50],
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  supplier.paymentTerms == 'credit' ? 'آجل' : 'نقدي', // Simplified category logic
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.blue[700],
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    
                    const Spacer(),

                    // STATS ROW
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildMiniStat('الفواتير', '${supplier.totalInvoices}'),
                          // Note: totalPayments might need updates in Supplier model to be accurate
                          _buildMiniStat('المدفوعات', '${supplier.totalPayments}'), 
                        ],
                      ),
                    ),

                    // FINANCIALS
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'الرصيد المتبقي',
                          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                        ),
                        Text(
                          '${_formatCurrency(supplier.totalDebt)} $currencySymbol',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: hasDebt ? const Color(0xFFEF4444) : const Color(0xFF10B981), // Red if debt, Green if clean
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    // PROGRESS BAR
                    Stack(
                      children: [
                        Container(
                          height: 6,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        FractionallySizedBox(
                          widthFactor: progress.clamp(0.0, 1.0),
                          child: Container(
                            height: 6,
                            decoration: BoxDecoration(
                              color: const Color(0xFF3B82F6), // Blue 500
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    // ACTION BUTTON
                    SizedBox(
                      width: double.infinity,
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
                  ],
                ),
              ),
            ],
          ),
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

  String _formatCurrency(double amount) {
    return intl.NumberFormat("#,##0", "en_US").format(amount);
  }
}
