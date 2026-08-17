// screens/returns_report_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/reports_service.dart';
import 'invoice_history_screen.dart';

class ReturnsReportScreen extends StatefulWidget {
  const ReturnsReportScreen({super.key});

  @override
  State<ReturnsReportScreen> createState() => _ReturnsReportScreenState();
}

class _ReturnsReportScreenState extends State<ReturnsReportScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ReportsService _reportsService = ReportsService();
  bool _isLoading = false;
  List<Map<String, dynamic>> _returns = [];
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
  String _currentPeriodLabel = '';
  bool _onlyThisDevice = false;

  // لتعريف الفترة الحالية بناءً على التبويب
  int _selectedTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_handleTabSelection);
    _updateDateRangeForTab(0); // Default to Daily (Today)
    _loadData();
  }

  void _handleTabSelection() {
    if (_tabController.indexIsChanging || _tabController.index != _selectedTabIndex) {
      setState(() {
        _selectedTabIndex = _tabController.index;
      });
      _updateDateRangeForTab(_selectedTabIndex);
      _loadData();
    }
  }

  void _updateDateRangeForTab(int index) {
    final now = DateTime.now();
    switch (index) {
      case 0: // Daily
        _startDate = DateTime(now.year, now.month, now.day);
        _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
        _currentPeriodLabel = DateFormat('yyyy/MM/dd', 'en_US').format(now);
        break;
      case 1: // Weekly
        // Start of week (Saturday as per custom, or Monday?) Let's assume Saturday start
        // Finding previous Saturday
        int daysToSaturday = (now.weekday + 1) % 7; 
        _startDate = DateTime(now.year, now.month, now.day).subtract(Duration(days: daysToSaturday));
        _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59); // To now
        _currentPeriodLabel = 'الأسبوع الحالي';
        break;
      case 2: // Monthly
        _startDate = DateTime(now.year, now.month, 1);
        _endDate = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
        _currentPeriodLabel = DateFormat('MMMM yyyy', 'en_US').format(now);
        break;
      case 3: // Yearly
        _startDate = DateTime(now.year, 1, 1);
        _endDate = DateTime(now.year, 12, 31, 23, 59, 59);
        _currentPeriodLabel = '${now.year}';
        break;
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      _reportsService.filterOnlyThisDevice = _onlyThisDevice;
      final data = await _reportsService.getCashReturnsInPeriod(
        startDate: _startDate,
        endDate: _endDate,
      );
      setState(() {
        _returns = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحميل التقرير: $e')),
        );
      }
    }
  }

  String _formatCurrency(dynamic value) {
    if (value == null) return '0';
    final number = (value is num) ? value : double.tryParse(value.toString()) ?? 0;
    return NumberFormat('#,##0', 'en_US').format(number);
  }

  @override
  Widget build(BuildContext context) {
    // حساب الإجمالي
    double totalReturns = _returns.fold(0, (sum, item) => sum + (item['amount_returned'] as num).toDouble());

    return Scaffold(
      appBar: AppBar(
        title: const Text('تقرير المرتجعات', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: const Color(0xFF673AB7),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          tabs: const [
            Tab(text: 'يومي'),
            Tab(text: 'أسبوعي'),
            Tab(text: 'شهري'),
            Tab(text: 'سنوي'),
          ],
        ),
        actions: [
          Row(
            children: [
              Text(_onlyThisDevice ? 'فقط هذا الجهاز' : 'تقارير شاملة', style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold)),
              Switch(
                value: _onlyThisDevice,
                onChanged: (val) {
                  setState(() {
                    _onlyThisDevice = val;
                    _loadData();
                  });
                },
                activeColor: Colors.white,
                inactiveTrackColor: Colors.white30,
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: Column(
        children: [
          // ملخص
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.red[50],
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('الفترة: $_currentPeriodLabel', style: TextStyle(color: Colors.grey[700])),
                      const SizedBox(height: 4),
                      Text(
                        'إجمالي المرتجعات: ${_formatCurrency(totalReturns)} د.ع',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.red[800],
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadData,
                ),
              ],
            ),
          ),
          
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _returns.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle_outline, size: 64, color: Colors.grey),
                            SizedBox(height: 16),
                            Text('لا توجد مرتجعات في هذه الفترة'),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: _returns.length,
                        itemBuilder: (context, index) {
                          final item = _returns[index];
                          return Card(
                            elevation: 2,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => InvoiceHistoryScreen(
                                      invoiceId: item['invoice_id'],
                                      customerName: item['customer_name'],
                                    ),
                                  ),
                                );
                              },
                              leading: CircleAvatar(
                                backgroundColor: Colors.red[100],
                                child: Icon(Icons.undo, color: Colors.red[800]),
                              ),
                              title: Text('فاتورة #${item['invoice_number'] ?? item['invoice_id']} - ${item['customer_name'] ?? 'بدون اسم'}'),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('التاريخ: ${DateFormat('yyyy/MM/dd HH:mm').format(DateTime.parse(item['date']))}'),
                                  Text('المحاسب: ${item['created_by']}'),
                                  if (item['notes'] != null && item['notes'].isNotEmpty)
                                    Text('ملاحظات: ${item['notes']}'),
                                ],
                              ),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '- ${_formatCurrency(item['amount_returned'])}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    '${_formatCurrency(item['before_total'])} ⬅ ${_formatCurrency(item['after_total'])}',
                                    style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                                  ),
                                ],
                              ),
                              isThreeLine: true,
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
