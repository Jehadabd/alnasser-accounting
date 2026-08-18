// screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../providers/app_provider.dart';
import '../models/customer.dart';

import '../services/settings_manager.dart';
import 'customer_details_screen.dart';
import 'add_customer_screen.dart';
import 'saved_invoices_screen.dart';
import 'ai_chat_screen.dart';
import 'overdue_debts_screen.dart'; // ✅ Added
import '../services/debt_report_service.dart'; // ✅ Added
import '../services/alert_service.dart'; // ✅ Added
import 'package:intl/intl.dart';
import '../models/app_settings.dart';
import '../widgets/app_side_nav.dart';

// أسماء أنواع الترتيب بالعربية
String getSortTypeName(CustomerSortType type) {
  switch (type) {
    case CustomerSortType.alphabetical:
      return 'أبجدي';
    case CustomerSortType.lastDebtAdded:
      return 'آخر إضافة دين';
    case CustomerSortType.lastPayment:
      return 'آخر تسديد';
    case CustomerSortType.lastTransaction:
      return 'آخر معاملة';
    case CustomerSortType.highestDebt:
      return 'الأكبر مبلغاً';
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _showScrollToTop = false; // 🔼 للتحكم بظهور زر العودة للأعلى
  AppSettings? _appSettings;

  
  @override
  void initState() {
    super.initState();
    // مراقبة موضع التمرير لإظهار/إخفاء زر العودة للأعلى
    _scrollController.addListener(_onScroll);
    _loadSettings();
    // Use Future.microtask or addPostFrameCallback to ensure context is available
    // and to avoid issues with calling methods on providers too early.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final app = context.read<AppProvider>();
      // تأكد من تصفية البحث الفارغة عند الدخول للشاشة لتجنب بقاء فلتر قديم
      app.setSearchQuery('');
      app.initialize();

      // ملاحظة: تم نقل فحص التنبيهات إلى MainScreen لضمان ظهوره مرة واحدة فقط عند التشغيل
    });
  }

  Future<void> _loadSettings() async {
    final settings = await SettingsManager.getAppSettings();
    if (mounted) setState(() => _appSettings = settings);
  }

  void _onScroll() {
    // إظهار زر العودة للأعلى عند التمرير أكثر من 300 بكسل
    final shouldShow = _scrollController.offset > 300;
    if (shouldShow != _showScrollToTop) {
      setState(() => _showScrollToTop = shouldShow);
    }
    // 📄 Lazy loading: عند الاقتراب من نهاية القائمة نحمّل الصفحة التالية
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      final app = context.read<AppProvider>();
      if (app.hasMoreData && !app.isLoadingMore) {
        app.loadMoreCustomers();
      }
    }
    
    // تحميل المزيد من العملاء عند الوصول للنهاية
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      context.read<AppProvider>().loadMoreCustomers();
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }
  


  // Helper to format currency consistently
  String formatCurrency(num value) {
    return NumberFormat('0.00', 'en_US')
        .format(value); // Always two decimal places
  }

  @override
  Widget build(BuildContext context) {
    // Define the consistent theme colors for the screen
    final Color primaryColor = const Color(0xFF3F51B5); // Indigo 700
    final Color accentColor =
        const Color(0xFF8C9EFF); // Light Indigo Accent (Indigo A200)
    final Color textColor =
        const Color(0xFF212121); // Dark grey for general text
    final Color lightBackgroundColor =
        const Color(0xFFF8F8F8); // Very light grey for text field fill
    final Color successColor =
        Colors.green[600]!; // Green for success messages/positive debt
    final Color errorColor =
        Colors.red[700]!; // Red for error messages/negative debt
    
    // Access the provider
    final provider = Provider.of<AppProvider>(context);

    return Theme(
      data: ThemeData(
        // Define color scheme for light theme
        colorScheme: ColorScheme.light(
          primary: primaryColor,
          onPrimary: Colors.white, // Text/icons on primary color
          secondary: accentColor,
          onSecondary: Colors.black, // Text/icons on secondary color
          surface: Colors.white, // Card/sheet background
          onSurface: textColor, // Text/icons on surface
          background: Colors.white, // Scaffold background
          onBackground: textColor, // Text/icons on background
          error: errorColor,
          onError: Colors.white, // Text/icons on error color
          tertiary: successColor, // Custom color for success, used in SnackBars
        ),
        // Define typography (font family and text styles)
        fontFamily: 'Roboto', // Modern, clean font
        textTheme: TextTheme(
          titleLarge: TextStyle(
              fontSize: 22.0,
              fontWeight: FontWeight.bold,
              color: Colors.white), // AppBar title
          titleMedium: TextStyle(
              fontSize: 18.0,
              fontWeight: FontWeight.w600,
              color: textColor), // Section titles
          bodyLarge:
              TextStyle(fontSize: 16.0, color: textColor), // General body text
          bodyMedium:
              TextStyle(fontSize: 14.0, color: textColor), // Smaller body text
          labelLarge: TextStyle(
              fontSize: 16.0,
              color: Colors.white,
              fontWeight: FontWeight.w600), // Button text
          labelMedium: TextStyle(
              fontSize: 14.0, color: Colors.grey[600]), // Input field labels
          bodySmall: TextStyle(
              fontSize: 12.0, color: Colors.grey[700]), // Hint text / captions
        ),
        // Define input field decoration theme
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            // Default border style
            borderRadius: BorderRadius.circular(10.0), // Rounded corners
            borderSide:
                BorderSide(color: Colors.grey[400]!), // Light grey border
          ),
          enabledBorder: OutlineInputBorder(
            // Border when enabled and not focused
            borderRadius: BorderRadius.circular(10.0),
            borderSide: BorderSide(color: Colors.grey[400]!),
          ),
          focusedBorder: OutlineInputBorder(
            // Border when focused
            borderRadius: BorderRadius.circular(10.0),
            borderSide: BorderSide(
                color: primaryColor, width: 2.0), // Primary color, thicker
          ),
          errorBorder: OutlineInputBorder(
            // Border when in error state
            borderRadius: BorderRadius.circular(10.0),
            borderSide: BorderSide(
                color: errorColor, width: 2.0), // Error color, thicker
          ),
          focusedErrorBorder: OutlineInputBorder(
            // Border when focused and in error state
            borderRadius: BorderRadius.circular(10.0),
            borderSide: BorderSide(color: errorColor, width: 2.0),
          ),
          labelStyle: TextStyle(
              color: Colors.grey[700], fontSize: 15.0), // Label text style
          hintStyle: TextStyle(
              color: Colors.grey[500], fontSize: 14.0), // Hint text style
          contentPadding: const EdgeInsets.symmetric(
              vertical: 16.0, horizontal: 16.0), // Inner padding
          filled: true, // Enable fill color
          fillColor: lightBackgroundColor, // Light background for fields
        ),
        // Define AppBar theme
        appBarTheme: AppBarTheme(
          backgroundColor: primaryColor, // AppBar background color
          foregroundColor: Colors.white, // AppBar text/icon color
          centerTitle: true, // Center title
          elevation: 4, // Shadow elevation
          titleTextStyle: TextStyle(
            // Title text style (inherits from TextTheme.titleLarge)
            fontSize: 24.0,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        // Define Card theme
        cardTheme: CardThemeData(
          elevation: 3, // Consistent shadow for cards
          shape: RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(12.0), // Rounded corners for cards
          ),
          margin: EdgeInsets
              .zero, // Reset default card margin to manage it manually
        ),
        // Define ListTile theme
        listTileTheme: ListTileThemeData(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          tileColor: Colors.transparent, // Default transparent
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
        ),
        // Define ElevatedButton theme (for Google Drive sign in)
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor, // Default button color
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.0)), // Slightly rounded
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            elevation: 2,
            textStyle: TextStyle(fontSize: 15.0, fontWeight: FontWeight.w500),
          ),
        ),
        // Define TextButton theme (for dialogs)
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: primaryColor,
            textStyle: TextStyle(fontSize: 16.0, fontWeight: FontWeight.w600),
          ),
        ),
        // Define IconButton theme
        iconTheme: IconThemeData(color: Colors.grey[700], size: 24.0),
        // Define FloatingActionButton theme
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.circular(12.0)), // Consistent rounded shape
          elevation: 6, // Slightly higher elevation for FABs
        ),
      ),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الناصر'),
          actions: [
            IconButton(
              icon: const Icon(Icons.receipt_long,
                  color: Colors.white), // Themed icon
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SavedInvoicesScreen(),
                  ),
                );
              },
              tooltip: 'الفواتير المحفوظة',
            ),
            IconButton(
              icon: const Icon(Icons.chat_bubble_outline,
                  color: Colors.white), // AI Chat icon
              onPressed: () {
                Navigator.pushNamed(context, '/ai_chat');
              },
              tooltip: 'الدردشة مع الذكاء الاصطناعي',
            ),
            // 🆕 زر المتأخرين عن السداد
            IconButton(
              icon: const Icon(Icons.warning_amber_rounded, color: Colors.white),
              tooltip: 'المتأخرون عن السداد',
              onPressed: () async {
                 final TextEditingController _monthsController = TextEditingController();
                 int? selectedMonths;
                 await showDialog<int>(
                   context: context,
                   builder: (context) {
                     return AlertDialog(
                       title: const Text('أدخل عدد الأشهر', style: TextStyle(fontSize: 20)),
                       content: TextField(
                         controller: _monthsController,
                         keyboardType: TextInputType.number,
                         autofocus: true,
                         decoration: const InputDecoration(
                           hintText: 'مثلاً: 12',
                           suffixText: 'شهر',
                         ),
                       ),
                       actions: [
                         TextButton(
                           onPressed: () => Navigator.of(context).pop(),
                           child: const Text('إلغاء', style: TextStyle(fontSize: 18)),
                         ),
                         ElevatedButton(
                           style: ElevatedButton.styleFrom(
                             backgroundColor: Theme.of(context).colorScheme.primary,
                           ),
                           onPressed: () {
                             final input = int.tryParse(_monthsController.text);
                             if (input != null && input > 0) {
                               Navigator.of(context).pop(input);
                             }
                           },
                           child: const Text('بحث', style: TextStyle(fontSize: 18)),
                         ),
                       ],
                     );
                   },
                 ).then((value) {
                   selectedMonths = value;
                 });

                 if (selectedMonths != null) {
                    Navigator.push(
                     context,
                     MaterialPageRoute(
                       builder: (context) => OverdueDebtsScreen(initialMonths: selectedMonths!),
                     ),
                   );
                 }
              },
            ),
            // 🆕 زر مشاركة الديون PDF
            IconButton(
              icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
              tooltip: 'مشاركة الديون PDF',
              onPressed: () async {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('جاري إعداد تقرير الديون...')),
                );
                try {
                  await DebtReportService.generateAndShareReport();
                } catch (e) {
                   ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('خطأ في إنشاء التقرير: $e')),
                  );
                }
              },
            ),
                    // زر ترتيب العملاء
                    PopupMenuButton<CustomerSortType>(
                      icon: const Icon(Icons.sort, color: Colors.white),
                      tooltip: 'ترتيب العملاء',
                      onSelected: (CustomerSortType sortType) async {
                        await provider.setSortType(sortType);
                      },
                      itemBuilder: (BuildContext context) => [
                        PopupMenuItem<CustomerSortType>(
                          value: CustomerSortType.alphabetical,
                          child: Row(
                            children: [
                              Icon(
                                provider.currentSortType == CustomerSortType.alphabetical
                                    ? Icons.check_circle
                                    : Icons.sort_by_alpha,
                                color: provider.currentSortType == CustomerSortType.alphabetical
                                    ? Colors.green
                                    : Colors.grey,
                              ),
                              const SizedBox(width: 8),
                              const Text('أبجدي (الافتراضي)'),
                            ],
                          ),
                        ),
                        PopupMenuItem<CustomerSortType>(
                          value: CustomerSortType.lastDebtAdded,
                          child: Row(
                            children: [
                              Icon(
                                provider.currentSortType == CustomerSortType.lastDebtAdded
                                    ? Icons.check_circle
                                    : Icons.add_circle_outline,
                                color: provider.currentSortType == CustomerSortType.lastDebtAdded
                                    ? Colors.green
                                    : Colors.red,
                              ),
                              const SizedBox(width: 8),
                              const Text('آخر إضافة دين'),
                            ],
                          ),
                        ),
                        PopupMenuItem<CustomerSortType>(
                          value: CustomerSortType.lastPayment,
                          child: Row(
                            children: [
                              Icon(
                                provider.currentSortType == CustomerSortType.lastPayment
                                    ? Icons.check_circle
                                    : Icons.payment,
                                color: provider.currentSortType == CustomerSortType.lastPayment
                                    ? Colors.green
                                    : Colors.blue,
                              ),
                              const SizedBox(width: 8),
                              const Text('آخر تسديد'),
                            ],
                          ),
                        ),
                        PopupMenuItem<CustomerSortType>(
                          value: CustomerSortType.lastTransaction,
                          child: Row(
                            children: [
                              Icon(
                                provider.currentSortType == CustomerSortType.lastTransaction
                                    ? Icons.check_circle
                                    : Icons.history,
                                color: provider.currentSortType == CustomerSortType.lastTransaction
                                    ? Colors.green
                                    : Colors.orange,
                              ),
                              const SizedBox(width: 8),
                              const Text('آخر معاملة'),
                            ],
                          ),
                        ),
                        PopupMenuItem<CustomerSortType>(
                          value: CustomerSortType.highestDebt,
                          child: Row(
                            children: [
                              Icon(
                                provider.currentSortType == CustomerSortType.highestDebt
                                    ? Icons.check_circle
                                    : Icons.trending_up,
                                color: provider.currentSortType == CustomerSortType.highestDebt
                                    ? Colors.green
                                    : Colors.purple,
                              ),
                              const SizedBox(width: 8),
                              const Text('الأكبر مبلغاً'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
        body: Row(
          children: [
            if (_appSettings != null && AppSideNav.shouldShow(context, _appSettings!))
              const AppSideNav(currentRoute: '/debt_register'),
            Expanded(
              child: Consumer<AppProvider>(
          builder: (context, provider, child) {
            if (provider.isLoading) {
              return const Center(
                  child: CircularProgressIndicator(
                color: Color(0xFF3F51B5), // Explicitly set color
              ));
            }

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(24.0), // Consistent padding
                  child: TextFormField(
                    // Changed to TextFormField for consistent styling
                    decoration: InputDecoration(
                      hintText: 'ابحث عن عميل...',
                      prefixIcon: Icon(Icons.search,
                          color: Theme.of(context)
                              .colorScheme
                              .primary), // Themed icon
                      // Inherits other styles from inputDecorationTheme
                    ),
                    onChanged: provider.setSearchQuery,
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge, // Themed text style
                  ),
                ),
                Expanded(
                  child: provider.customers.isEmpty
                      ? Center(
                          child: Text(
                            'لا يوجد عملاء',
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(
                                    color:
                                        Colors.grey[600]), // Themed text style
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController, // 🔼 حفظ موضع التمرير
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24.0,
                              vertical: 12.0), // Padding for the list itself
                          itemCount: provider.customers.length + (provider.isLoadingMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == provider.customers.length) {
                              return const Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Center(child: CircularProgressIndicator()),
                              );
                            }
                            final customer = provider.customers[index];
                            return CustomerListTile(
                              customer: customer,
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
            ),
          ],
        ),
        floatingActionButton: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // 🔼 زر العودة للأعلى - يظهر فقط عند التمرير للأسفل
            if (_showScrollToTop)
              Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: FloatingActionButton.small(
                  heroTag: 'scroll_to_top',
                  onPressed: () {
                    _scrollController.animateTo(
                      0,
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeOutCubic,
                    );
                  },
                  tooltip: 'العودة للأعلى',
                  backgroundColor: const Color(0xFF3F51B5).withOpacity(0.9),
                  child: const Icon(Icons.keyboard_arrow_up, size: 28),
                ),
              ),
            FloatingActionButton(
              heroTag: 'add_customer',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AddCustomerScreen(),
                  ),
                );
              },
              tooltip: 'إضافة عميل جديد',
              child: const Icon(Icons.person_add_alt_1), // Modern icon
            ),
          ],
        ),
      ),
    );
  }
}

class CustomerListTile extends StatelessWidget {
  final Customer customer;

  const CustomerListTile({
    super.key,
    required this.customer,
  });

  // Helper to format currency consistently
  String _formatCurrency(num value) {
    return NumberFormat('#,##0', 'en_US').format(value);
  }

  @override
  Widget build(BuildContext context) {
    // Determine color based on debt status
    final debtColor = (customer.currentTotalDebt ?? 0.0) > 0
        ? Theme.of(context).colorScheme.error // Red for debt
        : Theme.of(context)
            .colorScheme
            .tertiary; // Green for no debt/positive balance

    return Card(
      margin: const EdgeInsets.only(bottom: 12.0), // Spacing between cards
      elevation: 2, // Consistent card elevation
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 20.0, vertical: 12.0), // Increased internal padding
        leading: CircleAvatar(
          backgroundColor:
              debtColor.withOpacity(0.1), // Lighter background for avatar
          child: Icon(
            (customer.currentTotalDebt ?? 0.0) > 0
                ? Icons.arrow_downward
                : Icons.check_circle_outline, // Dynamic icon based on debt
            color: debtColor, // Themed icon color
            size: 28, // Larger icon
          ),
        ),
        title: Text(
          customer.name,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
        ),
        subtitle: Text(
          customer.phone ?? 'لا يوجد رقم هاتف',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: Colors.grey[700]), // Themed text style
        ),
        trailing: Text(
          '${_formatCurrency(customer.currentTotalDebt ?? 0.0)} دينار', // Formatted currency
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: debtColor,
                fontWeight: FontWeight.bold,
              ),
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CustomerDetailsScreen(customer: customer),
            ),
          ).then((_) {
            // 🔼 بعد العودة: تحديث البيانات بصمت (بدون إظهار مؤشر التحميل)
            // هذا يحافظ على موضع التمرير لأن ListView لا يُدمَّر
            final app = Provider.of<AppProvider>(context, listen: false);
            app.refreshCustomers();
          });
        },
      ),
    );
  }
}
