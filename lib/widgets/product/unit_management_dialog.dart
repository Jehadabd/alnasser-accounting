import 'package:flutter/material.dart';
import '../../services/database_service.dart';

const Color kPrimaryColor = Color(0xFF5D5FEF);
const Color kBackgroundColor = Color(0xFFF5F7FA);
const Color kInputFillColor = Color(0xFFF8F9FA);

/// الوحدات الافتراضية المتاحة في النظام
const List<String> kDefaultUnits = [
  // العد
  'قطعة', 'حبة', 'عدد', 'دستة', 'درزن',
  // الوزن
  'كيلو', 'غرام', 'طن', 'أوقية', 'رطل',
  // الطول
  'متر', 'سنتيمتر', 'ياردة', 'قدم',
  // التعبئة
  'كيس', 'باكيت', 'كرتون', 'صندوق', 'علبة', 'عبوة', 'لفة', 'ربطة', 'بال', 'شيكارة',
  // الأوراق/القماش
  'شيت', 'ورقة', 'رزمة', 'متر طولي', 'يارد',
  // السوائل
  'لتر', 'جالون', 'مل',
  // أخرى
  'سيت', 'طقم', 'سلة',
];

class UnitManagementDialog extends StatefulWidget {
  const UnitManagementDialog({super.key});

  @override
  State<UnitManagementDialog> createState() => _UnitManagementDialogState();
}

class _UnitManagementDialogState extends State<UnitManagementDialog> {
  final _formKey = GlobalKey<FormState>();
  final _newUnitController = TextEditingController();
  final DatabaseService _db = DatabaseService();
  
  List<Map<String, dynamic>> _customUnits = [];
  bool _isLoading = false;
  String? _editingUnitName;
  final _editController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCustomUnits();
  }

  Future<void> _loadCustomUnits() async {
    setState(() => _isLoading = true);
    try {
      final units = await _db.getCustomUnits();
      if (mounted) setState(() => _customUnits = units);
    } catch (e) {
      // تجاهل الخطأ
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addUnit() async {
    if (!_formKey.currentState!.validate()) return;
    
    final name = _newUnitController.text.trim();
    if (name.isEmpty) return;
    
    // تحقق إذا كانت موجودة
    if (kDefaultUnits.contains(name) || 
        _customUnits.any((u) => u['name'] == name)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('هذه الوحدة موجودة بالفعل!'), backgroundColor: Colors.orange),
      );
      return;
    }
    
    setState(() => _isLoading = true);
    try {
      await _db.addCustomUnit(name);
      _newUnitController.clear();
      await _loadCustomUnits();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تمت إضافة "$name" بنجاح'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateUnit(String oldName, String newName) async {
    if (newName.isEmpty || oldName == newName) {
      setState(() => _editingUnitName = null);
      return;
    }
    
    setState(() => _isLoading = true);
    try {
      await _db.updateCustomUnit(oldName, newName);
      await _loadCustomUnits();
      setState(() => _editingUnitName = null);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في التحديث: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteUnit(String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف الوحدة'),
        content: Text('هل تريد حذف "$name"؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    
    if (confirm != true) return;
    
    setState(() => _isLoading = true);
    try {
      await _db.deleteCustomUnit(name);
      await _loadCustomUnits();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم حذف "$name"'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _newUnitController.dispose();
    _editController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(24),
        width: 500,
        constraints: const BoxConstraints(maxHeight: 600),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: kPrimaryColor.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.straighten, color: kPrimaryColor),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'إدارة الوحدات',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: () => Navigator.pop(context, _customUnits.isNotEmpty),
                ),
              ],
            ),
            const SizedBox(height: 20),
            
            // Add new unit form
            Form(
              key: _formKey,
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(color: kInputFillColor, borderRadius: BorderRadius.circular(12)),
                      child: TextFormField(
                        controller: _newUnitController,
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          hintText: 'أدخل اسم وحدة جديدة...',
                          hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
                        ),
                        validator: (val) => val == null || val.trim().isEmpty ? 'أدخل اسم الوحدة' : null,
                        onFieldSubmitted: (_) => _addUnit(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _addUnit,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('إضافة'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),
            
            // Custom units section
            const Text(
              'الوحدات المخصصة (قابلة للتعديل والحذف)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
            ),
            const SizedBox(height: 8),
            
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_customUnits.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Text('لا توجد وحدات مخصصة', style: TextStyle(color: Colors.grey)),
                ),
              )
            else
              Container(
                constraints: const BoxConstraints(maxHeight: 150),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _customUnits.length,
                  itemBuilder: (context, index) {
                    final unit = _customUnits[index];
                    final name = unit['name'] as String;
                    final isEditing = _editingUnitName == name;
                    
                    if (isEditing) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        margin: const EdgeInsets.only(bottom: 4),
                        decoration: BoxDecoration(
                          color: kPrimaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _editController..text = name,
                                autofocus: true,
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  isDense: true,
                                ),
                                onSubmitted: (val) => _updateUnit(name, val.trim()),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.check, color: Colors.green, size: 20),
                              onPressed: () => _updateUnit(name, _editController.text.trim()),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.grey, size: 20),
                              onPressed: () => setState(() => _editingUnitName = null),
                            ),
                          ],
                        ),
                      );
                    }
                    
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      margin: const EdgeInsets.only(bottom: 4),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.label_outline, size: 18, color: kPrimaryColor),
                          const SizedBox(width: 8),
                          Expanded(child: Text(name, style: const TextStyle(fontSize: 14))),
                          IconButton(
                            icon: const Icon(Icons.edit, size: 18, color: Colors.blue),
                            onPressed: () => setState(() => _editingUnitName = name),
                            tooltip: 'تعديل',
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                            onPressed: () => _deleteUnit(name),
                            tooltip: 'حذف',
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            
            // Default units section
            Row(
              children: [
                const Text(
                  'الوحدات الافتراضية',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${kDefaultUnits.length} وحدة',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            
            Flexible(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 150),
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: kDefaultUnits.map((unit) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: kInputFillColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Text(unit, style: const TextStyle(fontSize: 12)),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
