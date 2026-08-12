// screens/invoice_design_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:alnaser/models/app_settings.dart';
import 'package:alnaser/models/invoice_design_settings.dart';
import 'package:alnaser/services/settings_manager.dart';

class InvoiceDesignScreen extends StatefulWidget {
  const InvoiceDesignScreen({super.key});

  @override
  State<InvoiceDesignScreen> createState() => _InvoiceDesignScreenState();
}

class _InvoiceDesignScreenState extends State<InvoiceDesignScreen> {
  static const Color primaryColor = Color(0xFF3F51B5);
  
  late AppSettings _appSettings;
  late InvoiceDesignSettings _invoiceDesign;
  bool _isLoading = true;
  
  // Controllers
  final TextEditingController _companyNameController = TextEditingController();
  final TextEditingController _companyAddressController = TextEditingController();
  final TextEditingController _phone1Controller = TextEditingController();
  final TextEditingController _phone2Controller = TextEditingController();
  final TextEditingController _companyDescriptionController = TextEditingController();
  
  File? _logoFile;
  
  // ألوان عناصر الفاتورة
  Color _companyNameColor = Colors.green;
  Color _companyDescriptionColor = Colors.black;
  Color _remainingAmountColor = Colors.black;
  Color _discountColor = Colors.black;
  Color _loadingFeesColor = Colors.black;
  Color _totalBeforeDiscountColor = Colors.black;
  Color _totalAfterDiscountColor = Colors.black;
  Color _previousDebtColor = Colors.black;
  Color _currentDebtColor = Colors.black;
  Color _paidAmountColor = Colors.black;
  Color _phoneColor = Colors.black;
  Color _itemSerialColor = Colors.black;
  Color _itemDetailsColor = Colors.black;
  Color _itemQuantityColor = Colors.black;
  Color _itemPriceColor = Colors.black;
  Color _itemTotalColor = Colors.black;
  Color _noticeColor = Colors.red;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _appSettings = await SettingsManager.getAppSettings();
    _invoiceDesign = _appSettings.invoiceDesign;
    
    _companyNameController.text = _invoiceDesign.companyName;
    _companyAddressController.text = _invoiceDesign.companyAddress;
    _companyDescriptionController.text = _appSettings.companyDescription;
    
    if (_invoiceDesign.phoneNumbers.isNotEmpty) {
      _phone1Controller.text = _invoiceDesign.phoneNumbers[0];
    }
    if (_invoiceDesign.phoneNumbers.length > 1) {
      _phone2Controller.text = _invoiceDesign.phoneNumbers[1];
    }
    
    if (_invoiceDesign.logoPath != null) {
      final file = File(_invoiceDesign.logoPath!);
      if (await file.exists()) {
        _logoFile = file;
      }
    }
    
    // تحميل الألوان من الإعدادات
    _companyNameColor = Color(_appSettings.companyNameColor);
    _companyDescriptionColor = Color(_appSettings.companyDescriptionColor);
    _remainingAmountColor = Color(_appSettings.remainingAmountColor);
    _discountColor = Color(_appSettings.discountColor);
    _loadingFeesColor = Color(_appSettings.loadingFeesColor);
    _totalBeforeDiscountColor = Color(_appSettings.totalBeforeDiscountColor);
    _totalAfterDiscountColor = Color(_appSettings.totalAfterDiscountColor);
    _previousDebtColor = Color(_appSettings.previousDebtColor);
    _currentDebtColor = Color(_appSettings.currentDebtColor);
    _paidAmountColor = Color(_appSettings.paidAmountColor);
    _phoneColor = Color(_appSettings.electricPhoneColor);
    _itemSerialColor = Color(_appSettings.itemSerialColor);
    _itemDetailsColor = Color(_appSettings.itemDetailsColor);
    _itemQuantityColor = Color(_appSettings.itemQuantityColor);
    _itemPriceColor = Color(_appSettings.itemPriceColor);
    _itemTotalColor = Color(_appSettings.itemTotalColor);
    _noticeColor = Color(_appSettings.noticeColor);
    
    setState(() => _isLoading = false);
  }

  Future<void> _saveSettings() async {
    // جمع أرقام الهواتف
    final phones = <String>[];
    if (_phone1Controller.text.trim().isNotEmpty) {
      phones.add(_phone1Controller.text.trim());
    }
    if (_phone2Controller.text.trim().isNotEmpty) {
      phones.add(_phone2Controller.text.trim());
    }

    final updatedDesign = _invoiceDesign.copyWith(
      companyName: _companyNameController.text.trim(),
      companyAddress: _companyAddressController.text.trim(),
      phoneNumbers: phones,
      logoPath: _logoFile?.path,
    );

    final updatedSettings = _appSettings.copyWith(
      invoiceDesign: updatedDesign,
      companyDescription: _companyDescriptionController.text.trim(),
      // حفظ الألوان
      companyNameColor: _companyNameColor.value,
      companyDescriptionColor: _companyDescriptionColor.value,
      remainingAmountColor: _remainingAmountColor.value,
      discountColor: _discountColor.value,
      loadingFeesColor: _loadingFeesColor.value,
      totalBeforeDiscountColor: _totalBeforeDiscountColor.value,
      totalAfterDiscountColor: _totalAfterDiscountColor.value,
      previousDebtColor: _previousDebtColor.value,
      currentDebtColor: _currentDebtColor.value,
      paidAmountColor: _paidAmountColor.value,
      electricPhoneColor: _phoneColor.value,
      healthPhoneColor: _phoneColor.value,
      itemSerialColor: _itemSerialColor.value,
      itemDetailsColor: _itemDetailsColor.value,
      itemQuantityColor: _itemQuantityColor.value,
      itemPriceColor: _itemPriceColor.value,
      itemTotalColor: _itemTotalColor.value,
      noticeColor: _noticeColor.value,
    );

    await SettingsManager.saveAppSettings(updatedSettings);
    _appSettings = updatedSettings;
    _invoiceDesign = updatedDesign;
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم حفظ إعدادات تصميم الفاتورة بنجاح'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _pickColor(String colorType) {
    Color currentColor;
    switch (colorType) {
      case 'companyName': currentColor = _companyNameColor; break;
      case 'companyDescription': currentColor = _companyDescriptionColor; break;
      case 'remainingAmount': currentColor = _remainingAmountColor; break;
      case 'discount': currentColor = _discountColor; break;
      case 'loadingFees': currentColor = _loadingFeesColor; break;
      case 'totalBeforeDiscount': currentColor = _totalBeforeDiscountColor; break;
      case 'totalAfterDiscount': currentColor = _totalAfterDiscountColor; break;
      case 'previousDebt': currentColor = _previousDebtColor; break;
      case 'currentDebt': currentColor = _currentDebtColor; break;
      case 'paidAmount': currentColor = _paidAmountColor; break;
      case 'phone': currentColor = _phoneColor; break;
      case 'itemSerial': currentColor = _itemSerialColor; break;
      case 'itemDetails': currentColor = _itemDetailsColor; break;
      case 'itemQuantity': currentColor = _itemQuantityColor; break;
      case 'itemPrice': currentColor = _itemPriceColor; break;
      case 'itemTotal': currentColor = _itemTotalColor; break;
      case 'notice': currentColor = _noticeColor; break;
      default: currentColor = Colors.black;
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        Color tempColor = currentColor;
        return AlertDialog(
          title: const Text('اختر اللون'),
          content: SingleChildScrollView(
            child: BlockPicker(
              pickerColor: currentColor,
              onColorChanged: (color) => tempColor = color,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
              onPressed: () {
                setState(() {
                  switch (colorType) {
                    case 'companyName': _companyNameColor = tempColor; break;
                    case 'companyDescription': _companyDescriptionColor = tempColor; break;
                    case 'remainingAmount': _remainingAmountColor = tempColor; break;
                    case 'discount': _discountColor = tempColor; break;
                    case 'loadingFees': _loadingFeesColor = tempColor; break;
                    case 'totalBeforeDiscount': _totalBeforeDiscountColor = tempColor; break;
                    case 'totalAfterDiscount': _totalAfterDiscountColor = tempColor; break;
                    case 'previousDebt': _previousDebtColor = tempColor; break;
                    case 'currentDebt': _currentDebtColor = tempColor; break;
                    case 'paidAmount': _paidAmountColor = tempColor; break;
                    case 'phone': _phoneColor = tempColor; break;
                    case 'itemSerial': _itemSerialColor = tempColor; break;
                    case 'itemDetails': _itemDetailsColor = tempColor; break;
                    case 'itemQuantity': _itemQuantityColor = tempColor; break;
                    case 'itemPrice': _itemPriceColor = tempColor; break;
                    case 'itemTotal': _itemTotalColor = tempColor; break;
                    case 'notice': _noticeColor = tempColor; break;
                  }
                });
                Navigator.pop(context);
              },
              child: const Text('حفظ'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildColorTile(String title, Color color, VoidCallback onTap) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      trailing: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.grey.shade300, width: 2),
          boxShadow: [
            BoxShadow(color: color.withOpacity(0.4), blurRadius: 4, offset: const Offset(0, 2)),
          ],
        ),
      ),
      onTap: onTap,
    );
  }

  Future<void> _pickLogo() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    
    if (pickedFile != null) {
      // حفظ الصورة في مجلد التطبيق
      final appDir = await getApplicationDocumentsDirectory();
      final logoDir = Directory('${appDir.path}/logo');
      if (!await logoDir.exists()) {
        await logoDir.create(recursive: true);
      }
      
      final savedFile = await File(pickedFile.path).copy('${logoDir.path}/company_logo.png');
      
      setState(() {
        _logoFile = savedFile;
      });
    }
  }

  void _removeLogo() {
    setState(() {
      _logoFile = null;
    });
  }

  void _toggleColumn(String columnId, bool visible) {
    setState(() {
      final columns = _invoiceDesign.columns.map((c) {
        if (c.id == columnId) {
          return c.copyWith(visible: visible);
        }
        return c;
      }).toList();
      _invoiceDesign = _invoiceDesign.copyWith(columns: columns);
    });
  }

  void _updateColumnWidth(String columnId, double width) {
    setState(() {
      final columns = _invoiceDesign.columns.map((c) {
        if (c.id == columnId) {
          return c.copyWith(widthFlex: width);
        }
        return c;
      }).toList();
      _invoiceDesign = _invoiceDesign.copyWith(columns: columns);
    });
  }

  void _reorderColumns(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    setState(() {
      final visibleColumns = _invoiceDesign.visibleColumns;
      final movedColumn = visibleColumns.removeAt(oldIndex);
      visibleColumns.insert(newIndex, movedColumn);
      
      // تحديث الترتيب
      final allColumns = _invoiceDesign.columns.map((c) {
        final visibleIndex = visibleColumns.indexWhere((vc) => vc.id == c.id);
        if (visibleIndex >= 0) {
          return c.copyWith(order: visibleIndex);
        }
        return c;
      }).toList();
      
      _invoiceDesign = _invoiceDesign.copyWith(columns: allColumns);
    });
  }

  @override
  void dispose() {
    _companyNameController.dispose();
    _companyAddressController.dispose();
    _phone1Controller.dispose();
    _phone2Controller.dispose();
    _companyDescriptionController.dispose();
    super.dispose();
  }

  Widget _buildSettingsCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required Widget child,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: iconColor, size: 24),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildInvoicePreview() {
    final visibleColumns = _invoiceDesign.visibleColumns;
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.3),
            spreadRadius: 2,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header Preview
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            _companyNameController.text.isEmpty 
                              ? 'اسم الشركة' 
                              : _companyNameController.text,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _companyDescriptionController.text.isEmpty
                              ? 'وصف الشركة'
                              : _companyDescriptionController.text,
                            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _companyAddressController.text.isEmpty
                              ? 'العنوان'
                              : _companyAddressController.text,
                            style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            [_phone1Controller.text, _phone2Controller.text]
                              .where((p) => p.isNotEmpty)
                              .join('  |  '),
                            style: TextStyle(fontSize: 10, color: Colors.grey[700]),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: _logoFile != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(_logoFile!, fit: BoxFit.contain),
                          )
                        : Icon(Icons.image, color: Colors.grey[400]),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Table Preview
          Container(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                // Table Header
                Container(
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: visibleColumns.map((col) {
                      return Expanded(
                        flex: (col.widthFlex * 10).toInt(),
                        child: Text(
                          col.label,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                // Sample Rows
                ...List.generate(3, (index) => Container(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Colors.grey[200]!),
                    ),
                  ),
                  child: Row(
                    children: visibleColumns.map((col) {
                      String sampleData = '';
                      switch (col.id) {
                        case 'serial': sampleData = '${index + 1}'; break;
                        case 'productId': sampleData = '${100 + index}'; break;
                        case 'details': sampleData = 'منتج ${index + 1}'; break;
                        case 'quantity': sampleData = '${(index + 1) * 5}'; break;
                        case 'unitsCount': sampleData = '${index + 1}×12'; break;
                        case 'price': sampleData = '${(index + 1) * 1000}'; break;
                        case 'amount': sampleData = '${(index + 1) * 5000}'; break;
                        case 'weight': sampleData = '${(index + 1) * 0.5} كغ'; break;
                        case 'expiry': sampleData = '2026/06'; break;
                      }
                      return Expanded(
                        flex: (col.widthFlex * 10).toInt(),
                        child: Text(
                          sampleData,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 9, color: Colors.grey[700]),
                        ),
                      );
                    }).toList(),
                  ),
                )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('تصميم الفاتورة'),
        centerTitle: true,
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: 'حفظ الإعدادات',
            onPressed: _saveSettings,
          ),
        ],
      ),
      body: Row(
        children: [
          // Left Panel - Preview
          Expanded(
            flex: 2,
            child: Container(
              color: Colors.grey[100],
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'معاينة الفاتورة',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 400),
                        child: _buildInvoicePreview(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Right Panel - Settings
          Expanded(
            flex: 3,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                // Company Logo
                _buildSettingsCard(
                  icon: Icons.image,
                  iconColor: Colors.purple,
                  title: 'شعار الشركة (اللوجو)',
                  child: Row(
                    children: [
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: _logoFile != null
                          ? Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.file(_logoFile!, fit: BoxFit.contain, width: 100, height: 100),
                                ),
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: GestureDetector(
                                    onTap: _removeLogo,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(
                                        color: Colors.red,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.close, color: Colors.white, size: 16),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : Icon(Icons.add_photo_alternate, size: 40, color: Colors.grey[400]),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ElevatedButton.icon(
                              onPressed: _pickLogo,
                              icon: const Icon(Icons.upload),
                              label: const Text('اختيار صورة'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primaryColor,
                                foregroundColor: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'يفضل استخدام صورة مربعة بدقة عالية',
                              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Company Info
                _buildSettingsCard(
                  icon: Icons.business,
                  iconColor: Colors.indigo,
                  title: 'معلومات الشركة',
                  child: Column(
                    children: [
                      TextField(
                        controller: _companyNameController,
                        decoration: InputDecoration(
                          labelText: 'اسم الشركة',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          prefixIcon: const Icon(Icons.store),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _companyDescriptionController,
                        decoration: InputDecoration(
                          labelText: 'وصف الشركة',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          prefixIcon: const Icon(Icons.description),
                        ),
                        maxLines: 2,
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _companyAddressController,
                        decoration: InputDecoration(
                          labelText: 'عنوان الشركة',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          prefixIcon: const Icon(Icons.location_on),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                  ),
                ),

                // Phone Numbers
                _buildSettingsCard(
                  icon: Icons.phone,
                  iconColor: Colors.green,
                  title: 'أرقام الهاتف (حد أقصى 2)',
                  child: Column(
                    children: [
                      TextField(
                        controller: _phone1Controller,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          labelText: 'رقم الهاتف الأول',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          prefixIcon: const Icon(Icons.phone),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _phone2Controller,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          labelText: 'رقم الهاتف الثاني',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          prefixIcon: const Icon(Icons.phone),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                  ),
                ),

                // Columns Configuration
                _buildSettingsCard(
                  icon: Icons.view_column,
                  iconColor: Colors.orange,
                  title: 'أعمدة جدول الفاتورة',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'اختر الأعمدة التي تريد إظهارها في الفاتورة وحدد عرض كل عمود',
                        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 16),
                      ..._invoiceDesign.columns.map((column) => _buildColumnItem(column)),
                    ],
                  ),
                ),

                // Reorder Columns
                _buildSettingsCard(
                  icon: Icons.reorder,
                  iconColor: Colors.teal,
                  title: 'ترتيب الأعمدة',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'اسحب لتغيير ترتيب الأعمدة في الفاتورة',
                        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 16),
                      ReorderableListView(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        onReorder: _reorderColumns,
                        children: _invoiceDesign.visibleColumns.asMap().entries.map((entry) {
                          final col = entry.value;
                          return ListTile(
                            key: ValueKey(col.id),
                            leading: const Icon(Icons.drag_handle),
                            title: Text(col.label),
                            trailing: Text(
                              'العرض: ${(col.widthFlex * 100 / 2).toStringAsFixed(0)}%',
                              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),

                // ألوان معلومات الشركة
                _buildSettingsCard(
                  icon: Icons.palette,
                  iconColor: Colors.green,
                  title: 'ألوان معلومات الشركة',
                  child: Column(
                    children: [
                      _buildColorTile('لون اسم الشركة', _companyNameColor, () => _pickColor('companyName')),
                      _buildColorTile('لون وصف الشركة', _companyDescriptionColor, () => _pickColor('companyDescription')),
                      _buildColorTile('لون أرقام الهواتف', _phoneColor, () => _pickColor('phone')),
                    ],
                  ),
                ),

                // ألوان عناصر الفاتورة (الملخص)
                _buildSettingsCard(
                  icon: Icons.receipt_long,
                  iconColor: Colors.blue,
                  title: 'ألوان ملخص الفاتورة',
                  child: Column(
                    children: [
                      _buildColorTile('المبلغ المتبقي', _remainingAmountColor, () => _pickColor('remainingAmount')),
                      _buildColorTile('الخصم', _discountColor, () => _pickColor('discount')),
                      _buildColorTile('أجور التحميل', _loadingFeesColor, () => _pickColor('loadingFees')),
                      _buildColorTile('الإجمالي قبل الخصم', _totalBeforeDiscountColor, () => _pickColor('totalBeforeDiscount')),
                      _buildColorTile('الإجمالي بعد الخصم', _totalAfterDiscountColor, () => _pickColor('totalAfterDiscount')),
                      _buildColorTile('الدين السابق', _previousDebtColor, () => _pickColor('previousDebt')),
                      _buildColorTile('الدين الحالي', _currentDebtColor, () => _pickColor('currentDebt')),
                      _buildColorTile('المبلغ المدفوع', _paidAmountColor, () => _pickColor('paidAmount')),
                    ],
                  ),
                ),

                // ألوان عناصر الجدول
                _buildSettingsCard(
                  icon: Icons.table_chart,
                  iconColor: Colors.purple,
                  title: 'ألوان عناصر الجدول',
                  child: Column(
                    children: [
                      _buildColorTile('التسلسل', _itemSerialColor, () => _pickColor('itemSerial')),
                      _buildColorTile('التفاصيل (أسماء المواد)', _itemDetailsColor, () => _pickColor('itemDetails')),
                      _buildColorTile('العدد', _itemQuantityColor, () => _pickColor('itemQuantity')),
                      _buildColorTile('السعر', _itemPriceColor, () => _pickColor('itemPrice')),
                      _buildColorTile('المبلغ', _itemTotalColor, () => _pickColor('itemTotal')),
                    ],
                  ),
                ),

                // ألوان أخرى
                _buildSettingsCard(
                  icon: Icons.color_lens,
                  iconColor: Colors.red,
                  title: 'ألوان أخرى',
                  child: Column(
                    children: [
                      _buildColorTile('التنويه', _noticeColor, () => _pickColor('notice')),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColumnItem(InvoiceColumnConfig column) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Checkbox(
            value: column.visible,
            activeColor: primaryColor,
            onChanged: (value) => _toggleColumn(column.id, value ?? false),
          ),
          Expanded(
            flex: 2,
            child: Text(
              column.label,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: column.visible ? Colors.black : Colors.grey,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Row(
              children: [
                const Text('العرض:', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 8),
                Expanded(
                  child: Slider(
                    value: column.widthFlex,
                    min: 0.3,
                    max: 3.0,
                    divisions: 27,
                    activeColor: primaryColor,
                    label: '${(column.widthFlex * 100 / 2).toStringAsFixed(0)}%',
                    onChanged: column.visible 
                      ? (value) => _updateColumnWidth(column.id, value)
                      : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
