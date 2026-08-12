import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../models/font_settings.dart';
import '../models/app_settings.dart';
import '../services/font_manager.dart';
import '../services/settings_manager.dart';

class FontSettingsScreen extends StatefulWidget {
  const FontSettingsScreen({Key? key}) : super(key: key);

  @override
  State<FontSettingsScreen> createState() => _FontSettingsScreenState();
}

class _FontSettingsScreenState extends State<FontSettingsScreen> {
  late AppSettings _appSettings;
  late FontSettings _fontSettings;
  List<FontInfo> _availableFonts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      // تحميل إعدادات التطبيق
      _appSettings = await SettingsManager.loadSettings();
      _fontSettings = _appSettings.fontSettings;
      
      // تحميل الخطوط المتاحة
      await FontManager.loadArabicFonts();
      _availableFonts = await FontManager.getAvailableFonts();
      _ensureValidFontSelections();
      
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      print('خطأ في تحميل الإعدادات: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _ensureValidFontSelections() {
    // إذا كان الخط المحفوظ غير موجود ضمن القائمة، قم بضبطه على أول خيار متاح
    String fallback() => _availableFonts.isNotEmpty ? _availableFonts.first.name : 'Amiri-Regular';

    String coerce(String name) {
      if (_availableFonts.any((f) => f.name == name)) return name;
      return fallback();
    }

    _fontSettings = _fontSettings.copyWith(
      serialNumber: _fontSettings.serialNumber.copyWith(fontFamily: coerce(_fontSettings.serialNumber.fontFamily)),
      productId: _fontSettings.productId.copyWith(fontFamily: coerce(_fontSettings.productId.fontFamily)),
      productDetails: _fontSettings.productDetails.copyWith(fontFamily: coerce(_fontSettings.productDetails.fontFamily)),
      quantity: _fontSettings.quantity.copyWith(fontFamily: coerce(_fontSettings.quantity.fontFamily)),
      unitsCount: _fontSettings.unitsCount.copyWith(fontFamily: coerce(_fontSettings.unitsCount.fontFamily)),
      price: _fontSettings.price.copyWith(fontFamily: coerce(_fontSettings.price.fontFamily)),
      amount: _fontSettings.amount.copyWith(fontFamily: coerce(_fontSettings.amount.fontFamily)),
      remainingAmount: _fontSettings.remainingAmount.copyWith(fontFamily: coerce(_fontSettings.remainingAmount.fontFamily)),
      paidAmount: _fontSettings.paidAmount.copyWith(fontFamily: coerce(_fontSettings.paidAmount.fontFamily)),
      totalBeforeDiscount: _fontSettings.totalBeforeDiscount.copyWith(fontFamily: coerce(_fontSettings.totalBeforeDiscount.fontFamily)),
      discount: _fontSettings.discount.copyWith(fontFamily: coerce(_fontSettings.discount.fontFamily)),
      totalAfterDiscount: _fontSettings.totalAfterDiscount.copyWith(fontFamily: coerce(_fontSettings.totalAfterDiscount.fontFamily)),
      previousDebt: _fontSettings.previousDebt.copyWith(fontFamily: coerce(_fontSettings.previousDebt.fontFamily)),
      previousRequiredAmount: _fontSettings.previousRequiredAmount.copyWith(fontFamily: coerce(_fontSettings.previousRequiredAmount.fontFamily)),
      currentRequiredAmount: _fontSettings.currentRequiredAmount.copyWith(fontFamily: coerce(_fontSettings.currentRequiredAmount.fontFamily)),
      shippingFees: _fontSettings.shippingFees.copyWith(fontFamily: coerce(_fontSettings.shippingFees.fontFamily)),
    );
  }

  Future<void> _addCustomFont() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['ttf', 'otf', 'ttc'],
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (file.path != null) {
          // إضافة الخط إلى النظام
          final success = await FontManager.addCustomFont(file.path!);
          
          if (success) {
            // تحديث قائمة الخطوط
            _availableFonts = await FontManager.refreshFonts();
            
            setState(() {});
            
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('تم إضافة الخط "${file.name}" بنجاح'),
                backgroundColor: Colors.green,
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('فشل في إضافة الخط'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في إضافة الخط: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _refreshFonts() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      _availableFonts = await FontManager.refreshFonts();
      _ensureValidFontSelections();
      setState(() {
        _isLoading = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تحديث قائمة الخطوط'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في تحديث الخطوط: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _saveSettings() async {
    try {
      final updatedSettings = _appSettings.copyWith(fontSettings: _fontSettings);
      await SettingsManager.saveSettings(updatedSettings);
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم حفظ إعدادات الخط بنجاح'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في حفظ الإعدادات: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildFontElementCard(String title, FontElementSettings settings, Function(FontElementSettings) onChanged) {
    return Card(
      margin: const EdgeInsets.all(8.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('نوع الخط:', style: TextStyle(fontWeight: FontWeight.w500)),
                      const SizedBox(height: 8),
                      DropdownButton<String>(
                        value: settings.fontFamily,
                        isExpanded: true,
                        selectedItemBuilder: (context) {
                          return _availableFonts.map((font) {
                            return Tooltip(
                              message: font.name,
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  font.name,
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                            );
                          }).toList();
                        },
                        items: _availableFonts.map((font) {
                          return DropdownMenuItem<String>(
                            value: font.name,
                            child: Tooltip(
                              message: font.name,
                              child: Text(
                                font.name,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: (String? newValue) {
                          if (newValue != null) {
                            onChanged(settings.copyWith(fontFamily: newValue));
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('وزن الخط:', style: TextStyle(fontWeight: FontWeight.w500)),
                      const SizedBox(height: 8),
                      DropdownButton<String>(
                        value: settings.fontWeight,
                        isExpanded: true,
                        items: FontElementSettings.availableWeights.map((weight) {
                          return DropdownMenuItem<String>(
                            value: weight,
                            child: Text(weight),
                          );
                        }).toList(),
                        onChanged: (String? newValue) {
                          if (newValue != null) {
                            onChanged(settings.copyWith(fontWeight: newValue));
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // معاينة الخط
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'معاينة: $title',
                    style: FontManager.getFlutterFont(settings.fontFamily, settings.fontWeight).copyWith(
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'الخط المحدد: ${settings.fontFamily}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('إعدادات الخطوط'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _addCustomFont,
            tooltip: 'إضافة خط جديد',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshFonts,
            tooltip: 'تحديث قائمة الخطوط',
          ),
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveSettings,
            tooltip: 'حفظ الإعدادات',
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'تخصيص خطوط عناصر الفاتورة',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(
                'يمكنك تخصيص نوع الخط ووزنه لكل عنصر من عناصر الفاتورة. التغييرات ستظهر فقط عند طباعة الفاتورة.\n\nيمكنك إضافة خطوط جديدة من الإنترنت باستخدام زر "+" في شريط الأدوات.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            
            // معلومات الخطوط المتاحة
            Card(
              margin: const EdgeInsets.all(16.0),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.info_outline, color: Colors.blue),
                        const SizedBox(width: 8),
                        Text(
                          'الخطوط المتاحة: ${_availableFonts.length}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '• الخطوط المدعومة: TTF, OTF, TTC\n• المسار الافتراضي: C:\\Windows\\Fonts\\\n• يمكن إضافة خطوط جديدة من الإنترنت\n• راجع ملف FONT_ADDITION_GUIDE.md للتعليمات التفصيلية',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
            
            // عناصر الفاتورة
            _buildFontElementCard(
              'التسلسل',
              _fontSettings.serialNumber,
              (settings) => setState(() {
                _fontSettings = _fontSettings.copyWith(serialNumber: settings);
              }),
            ),
            
            _buildFontElementCard(
              'الـ ID',
              _fontSettings.productId,
              (settings) => setState(() {
                _fontSettings = _fontSettings.copyWith(productId: settings);
              }),
            ),
            
            _buildFontElementCard(
              'التفاصيل',
              _fontSettings.productDetails,
              (settings) => setState(() {
                _fontSettings = _fontSettings.copyWith(productDetails: settings);
              }),
            ),
            
            _buildFontElementCard(
              'العدد',
              _fontSettings.quantity,
              (settings) => setState(() {
                _fontSettings = _fontSettings.copyWith(quantity: settings);
              }),
            ),
            
            _buildFontElementCard(
              'عدد الوحدات',
              _fontSettings.unitsCount,
              (settings) => setState(() {
                _fontSettings = _fontSettings.copyWith(unitsCount: settings);
              }),
            ),
            
            _buildFontElementCard(
              'السعر',
              _fontSettings.price,
              (settings) => setState(() {
                _fontSettings = _fontSettings.copyWith(price: settings);
              }),
            ),
            
            _buildFontElementCard(
              'المبلغ',
              _fontSettings.amount,
              (settings) => setState(() {
                _fontSettings = _fontSettings.copyWith(amount: settings);
              }),
            ),
            
            _buildFontElementCard(
              'المبلغ المتبقي',
              _fontSettings.remainingAmount,
              (settings) => setState(() {
                _fontSettings = _fontSettings.copyWith(remainingAmount: settings);
              }),
            ),
            
            _buildFontElementCard(
              'المبلغ المدفوع',
              _fontSettings.paidAmount,
              (settings) => setState(() {
                _fontSettings = _fontSettings.copyWith(paidAmount: settings);
              }),
            ),
            
            _buildFontElementCard(
              'الإجمالي قبل الخصم',
              _fontSettings.totalBeforeDiscount,
              (settings) => setState(() {
                _fontSettings = _fontSettings.copyWith(totalBeforeDiscount: settings);
              }),
            ),
            
            _buildFontElementCard(
              'الخصم',
              _fontSettings.discount,
              (settings) => setState(() {
                _fontSettings = _fontSettings.copyWith(discount: settings);
              }),
            ),
            
            _buildFontElementCard(
              'الإجمالي بعد الخصم',
              _fontSettings.totalAfterDiscount,
              (settings) => setState(() {
                _fontSettings = _fontSettings.copyWith(totalAfterDiscount: settings);
              }),
            ),
            
            _buildFontElementCard(
              'الدين السابق',
              _fontSettings.previousDebt,
              (settings) => setState(() {
                _fontSettings = _fontSettings.copyWith(previousDebt: settings);
              }),
            ),
            
            _buildFontElementCard(
              'المبلغ المطلوب السابق',
              _fontSettings.previousRequiredAmount,
              (settings) => setState(() {
                _fontSettings = _fontSettings.copyWith(previousRequiredAmount: settings);
              }),
            ),
            
            _buildFontElementCard(
              'المبلغ المطلوب الحالي',
              _fontSettings.currentRequiredAmount,
              (settings) => setState(() {
                _fontSettings = _fontSettings.copyWith(currentRequiredAmount: settings);
              }),
            ),
            
            _buildFontElementCard(
              'أجور التحميل',
              _fontSettings.shippingFees,
              (settings) => setState(() {
                _fontSettings = _fontSettings.copyWith(shippingFees: settings);
              }),
            ),
            
            const SizedBox(height: 32),
            
            // أزرار التحكم
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _addCustomFont,
                          icon: const Icon(Icons.add),
                          label: const Text('إضافة خط جديد'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _refreshFonts,
                          icon: const Icon(Icons.refresh),
                          label: const Text('تحديث الخطوط'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _saveSettings,
                          icon: const Icon(Icons.save),
                          label: const Text('حفظ الإعدادات'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            setState(() {
                              _fontSettings = FontSettings();
                            });
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('إعادة تعيين'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
