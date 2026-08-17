// screens/people_reports_screen.dart
import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../models/customer.dart';
import '../models/person_data.dart'; // Added import for PersonReportData
import 'person_details_screen.dart';
import 'package:intl/intl.dart';

class PeopleReportsScreen extends StatefulWidget {
  const PeopleReportsScreen({super.key});

  @override
  State<PeopleReportsScreen> createState() => _PeopleReportsScreenState();
}

class _PeopleReportsScreenState extends State<PeopleReportsScreen> {
  final DatabaseService _databaseService = DatabaseService();
  List<PersonReportData> _people = [];
  List<PersonReportData> _filteredPeople = [];
  bool _isLoading = true;
  // reportSource: 'all' = الكل, 'this_device' = هذا الجهاز فقط, 'sync' = المزامنة فقط
  String _reportSource = 'all';
  final TextEditingController _searchController = TextEditingController();
  late final NumberFormat _nf = NumberFormat('#,##0', 'en_US');
  String _fmt(num v) => _nf.format(v);

  final ScrollController _scrollController = ScrollController();
  int _offset = 0;
  final int _limit = 20;
  bool _hasMore = true;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _loadPeopleReports();
    _searchController.addListener(_onSearchChanged);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _scrollController.removeListener(_onScroll);
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
  
  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingMore && _hasMore) {
        _loadPeopleReports(isLoadMore: true);
      }
    }
  }

  void _onSearchChanged() {
    // إمكانية إضافة Debouncer هنا لتأخير البحث
    _loadPeopleReports();
  }

  void _filterPeople() {
    // تم إلغاء فلترة الذاكرة العشوائية واستبدالها بالبحث المباشر في قاعدة البيانات
  }

  Future<void> _loadPeopleReports({bool isLoadMore = false}) async {
    if (isLoadMore) {
      setState(() { _isLoadingMore = true; });
    } else {
      setState(() { 
        _isLoading = true; 
        _offset = 0;
        _hasMore = true;
      });
    }

    try {
      if (!isLoadMore) {
        // تحديث الفواتير القديمة فقط عند التحميل الأول
        try { await _databaseService.updateOldInvoicesWithCustomerIds(); } catch (_) {}
      }
      
      _databaseService.reportsService.reportSourceFilter = _reportSource;
      final customers = await _databaseService.getPaginatedCustomersForReports(
        limit: _limit,
        offset: _offset,
        searchQuery: _searchController.text.trim(),
        reportSource: _reportSource,
      );
      
      if (customers.length < _limit) {
        _hasMore = false;
      }
      
      final List<PersonReportData> newReports = [];

      for (final customer in customers) {
        final profitData = await _databaseService.getCustomerProfitData(customer.id!);

        newReports.add(PersonReportData(
          customer: customer,
          totalProfit: (profitData['totalProfit'] as num?)?.toDouble() ?? 0.0,
          totalSales: (profitData['totalSales'] as num?)?.toDouble() ?? 0.0,
          totalInvoices: (profitData['totalInvoices'] as num?)?.toInt() ?? 0,
          totalInvoicesGlobal: (profitData['totalInvoicesGlobal'] as num?)?.toInt() ?? 0,
          totalTransactions: (profitData['totalTransactions'] as num?)?.toInt() ?? 0,
        ));
      }

      // نعرض الجميع بناءً على طلب المستخدم، حتى لو كانت إحصائياتهم 0 في المصدر الحالي
      setState(() {
        if (isLoadMore) {
          _people.addAll(newReports);
        } else {
          _people = newReports;
        }
        _filteredPeople = _people; // لأن البحث يتم الآن في الداتابيز
        _offset += _limit;
        _isLoading = false;
        _isLoadingMore = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ في تحميل البيانات: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text('تقرير الأشخاص', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: const Color(0xFF673AB7),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          // زر اختيار نوع التقرير
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list, color: Colors.white),
            onSelected: (value) {
              setState(() {
                _reportSource = value;
                _loadPeopleReports();
              });
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'all',
                child: Row(
                  children: [
                    Icon(Icons.all_inclusive, color: _reportSource == 'all' ? const Color(0xFF673AB7) : Colors.grey),
                    const SizedBox(width: 8),
                    const Text('تقارير شاملة'),
                    if (_reportSource == 'all') const Icon(Icons.check, color: Color(0xFF673AB7), size: 18),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'this_device',
                child: Row(
                  children: [
                    Icon(Icons.phone_android, color: _reportSource == 'this_device' ? const Color(0xFF673AB7) : Colors.grey),
                    const SizedBox(width: 8),
                    const Text('هذا الجهاز فقط'),
                    if (_reportSource == 'this_device') const Icon(Icons.check, color: Color(0xFF673AB7), size: 18),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'sync',
                child: Row(
                  children: [
                    Icon(Icons.sync, color: _reportSource == 'sync' ? const Color(0xFF673AB7) : Colors.grey),
                    const SizedBox(width: 8),
                    const Text('المزامنة فقط'),
                    if (_reportSource == 'sync') const Icon(Icons.check, color: Color(0xFF673AB7), size: 18),
                  ],
                ),
              ),
            ],
          ),
          // عرض النص التوضيحي
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: Text(
                _reportSource == 'all' ? 'شامل' : (_reportSource == 'this_device' ? 'الجهاز' : 'المزامنة'),
                style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPeopleReports,
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
                // حقل البحث
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
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
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: 'البحث في الأشخاص...',
                      border: InputBorder.none,
                      icon: Icon(Icons.search, color: Color(0xFF2196F3)),
                      suffixIcon: Icon(Icons.filter_list, color: Color(0xFF2196F3)),
                    ),
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
                // قائمة الأشخاص
                Expanded(
                  child: _filteredPeople.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.people,
                                size: 80,
                                color: Color(0xFFCCCCCC),
                              ),
                              SizedBox(height: 16),
                              Text(
                                'لا توجد أشخاص',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Color(0xFF666666),
                                ),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadPeopleReports,
                          child: ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            itemCount: _filteredPeople.length + (_isLoadingMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == _filteredPeople.length) {
                                return const Padding(
                                  padding: EdgeInsets.all(16.0),
                                  child: Center(
                                    child: CircularProgressIndicator(color: Color(0xFF673AB7)),
                                  ),
                                );
                              }
                              final person = _filteredPeople[index];
                              return _buildPersonCard(person);
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildPersonCard(PersonReportData person) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.green.withOpacity(0.3), width: 1),
      ),
      child: InkWell(
        onTap: () => _navigateToPersonDetails(person),
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
                      Icons.person,
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
                          person.customer.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'عدد الفواتير: ${person.totalInvoices}',
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
                          '${person.totalProfit >= 0 ? _fmt(person.totalProfit) : _fmt(-person.totalProfit)} د.ع',
                      color: const Color(0xFF4CAF50),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildInfoItem(
                      icon: Icons.shopping_cart,
                      title: 'المبيعات',
                      value: '${_fmt(person.totalSales)} د.ع',
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

  Future<void> _navigateToPersonDetails(PersonReportData person) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PersonDetailsScreen(
          customer: person.customer,
        ),
      ),
    );
    if (!mounted) return;
    // بعد الرجوع: امسح البحث وأعد القائمة كاملة كأنها أول مرة
    _searchController.text = '';
    FocusScope.of(context).unfocus();
    setState(() {
      _filteredPeople = _people;
    });
  }
}


