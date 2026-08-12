// screens/person_details_screen.dart
import 'package:flutter/material.dart';
import '../models/customer.dart';
import '../models/person_data.dart'; // Correct import
import '../services/database_service.dart';
import 'person_year_details_screen.dart';
import 'package:intl/intl.dart';

class PersonDetailsScreen extends StatefulWidget {
  final Customer customer;

  const PersonDetailsScreen({
    super.key,
    required this.customer,
  });

  @override
  State<PersonDetailsScreen> createState() => _PersonDetailsScreenState();
}

class _PersonDetailsScreenState extends State<PersonDetailsScreen> {
  final DatabaseService _databaseService = DatabaseService();
  Map<int, PersonYearData> _yearlyData = {};
  bool _isLoading = true;
   late final NumberFormat _nf = NumberFormat('#,##0', 'en_US');
  String _fmt(num v) => _nf.format(v);

  @override
  void initState() {
    super.initState();
    _loadYearlyData();
  }

  Future<void> _loadYearlyData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final yearlyData =
          await _databaseService.getCustomerYearlyData(widget.customer.id!);
      setState(() {
        _yearlyData = yearlyData;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ في تحميل البيانات: $e'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: Text(
          'تفاصيل ${widget.customer.name}',
          style: const TextStyle(fontSize: 20),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF2196F3),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadYearlyData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF2196F3),
              ),
            )
          : Column(
              children: [
                _buildPersonHeader(),
                Expanded(
                  child: _yearlyData.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.timeline,
                                size: 80,
                                color: Color(0xFFCCCCCC),
                              ),
                              SizedBox(height: 16),
                              Text(
                                'لا توجد تعاملات لهذا العميل',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Color(0xFF666666),
                                ),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadYearlyData,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _yearlyData.length,
                            itemBuilder: (context, index) {
                              final year = _yearlyData.keys.elementAt(index);
                              final yearData = _yearlyData[year]!;
                              return _buildYearCard(year, yearData);
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildPersonHeader() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.customer.name,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2C3E50),
                  ),
                ),
              ),
              if (widget.customer.phone != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2196F3).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    widget.customer.phone!,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF2196F3),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          if (widget.customer.address != null) ...[
            const SizedBox(height: 8),
            Text(
              'العنوان: ${widget.customer.address}',
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF666666),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildHeaderInfo(
                  icon: Icons.trending_up,
                  title: 'الربح',
                  value:
                      '${_calculateTotalProfit() >= 0 ? _fmt(_calculateTotalProfit()) : _fmt(-_calculateTotalProfit())} د.ع',
                  color: const Color(0xFF4CAF50),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildHeaderInfo(
                  icon: Icons.shopping_cart,
                  title: 'المبيعات',
                  value: '${_fmt(_calculateTotalSales())} د.ع',
                  color: const Color(0xFF2196F3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildHeaderInfo(
                  icon: Icons.receipt_long,
                  title: 'الفواتير',
                  value: '${_calculateTotalInvoices()}',
                  color: const Color(0xFFFF9800),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildHeaderInfo(
                  icon: Icons.account_balance_wallet,
                  title: 'المعاملات',
                  value: '${_calculateTotalTransactions()}',
                  color: const Color(0xFF9C27B0),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  double _calculateTotalProfit() {
    return _yearlyData.values
        .fold(0.0, (sum, yearData) => sum + yearData.totalProfit);
  }

  double _calculateTotalSales() {
    return _yearlyData.values
        .fold(0.0, (sum, yearData) => sum + yearData.totalSales);
  }

  int _calculateTotalInvoices() {
    return _yearlyData.values
        .fold(0, (sum, yearData) => sum + yearData.totalInvoices);
  }

  int _calculateTotalTransactions() {
    return _yearlyData.values
        .fold(0, (sum, yearData) => sum + yearData.totalTransactions);
  }

  Widget _buildHeaderInfo({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF666666),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildYearCard(int year, PersonYearData yearData) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.green.withOpacity(0.3), width: 1),
      ),
      child: InkWell(
        onTap: () => _navigateToYearDetails(year),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.green.withOpacity(0.1),
                Colors.green.withOpacity(0.05),
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.calendar_today,
                      color: Colors.green,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'سنة $year',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'عدد الفواتير: ${yearData.totalInvoices}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildInfoItem(
                      icon: Icons.trending_up,
                      title: 'الربح',
                      value:
                          '${yearData.totalProfit >= 0 ? _fmt(yearData.totalProfit) : _fmt(-yearData.totalProfit)} د.ع',
                      color: const Color(0xFF4CAF50),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildInfoItem(
                      icon: Icons.shopping_cart,
                      title: 'المبيعات',
                      value: '${_fmt(yearData.totalSales)} د.ع',
                      color: const Color(0xFF2196F3),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoItem({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToYearDetails(int year) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PersonYearDetailsScreen(
          customer: widget.customer,
          year: year,
        ),
      ),
    );
  }
}
