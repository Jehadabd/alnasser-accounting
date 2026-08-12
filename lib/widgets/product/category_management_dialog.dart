import 'package:flutter/material.dart';
import '../../models/category.dart';
import '../../services/database_service.dart';

const Color kPrimaryColor = Color(0xFF5D5FEF); // Purple/Indigo
const Color kBackgroundColor = Color(0xFFF5F7FA);
const Color kInputFillColor = Color(0xFFF8F9FA);

class CategoryManagementDialog extends StatefulWidget {
  const CategoryManagementDialog({super.key});

  @override
  State<CategoryManagementDialog> createState() => _CategoryManagementDialogState();
}

class _CategoryManagementDialogState extends State<CategoryManagementDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final DatabaseService _db = DatabaseService();
  bool _isLoading = false;

  Future<void> _saveCategory() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      try {
        final newCategory = Category(
          name: _nameController.text.trim(),
          description: '', // Removed from UI, default empty
        );
        await _db.insertCategory(newCategory);

        if (mounted) {
          Navigator.of(context).pop(true); // Return true on success
        }
      } catch (e) {
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('فشل حفظ القسم: $e'), backgroundColor: Colors.red),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
       child: Container(
         padding: const EdgeInsets.all(24),
         width: 400,
         decoration: BoxDecoration(
           color: Colors.white,
           borderRadius: BorderRadius.circular(20),
         ),
         child: Form(
           key: _formKey,
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
                     child: const Icon(Icons.category, color: kPrimaryColor),
                   ),
                   const SizedBox(width: 12),
                   const Text(
                     'إضافة تصنيف جديد',
                     style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                   ),
                 ],
               ),
               const SizedBox(height: 24),
               
               // Input
               const Text('اسم التصنيف', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: kPrimaryColor)),
               const SizedBox(height: 8),
               Container(
                 decoration: BoxDecoration(color: kInputFillColor, borderRadius: BorderRadius.circular(12)),
                 child: TextFormField(
                   controller: _nameController,
                   decoration: InputDecoration(
                     border: InputBorder.none,
                     contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                     hintText: 'مثال: مواد غذائية، منظفات...',
                     hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
                   ),
                   validator: (val) => val == null || val.isEmpty ? 'مطلوب' : null,
                 ),
               ),
               
               const SizedBox(height: 32),
               
               // Actions
               Row(
                 children: [
                   Expanded(
                     child: OutlinedButton(
                       onPressed: () => Navigator.pop(context, false),
                       style: OutlinedButton.styleFrom(
                         padding: const EdgeInsets.symmetric(vertical: 16),
                         side: BorderSide(color: Colors.grey[300]!),
                         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                         foregroundColor: Colors.grey[700],
                       ),
                       child: const Text('إلغاء'),
                     ),
                   ),
                   const SizedBox(width: 12),
                   Expanded(
                     child: ElevatedButton(
                       onPressed: _isLoading ? null : _saveCategory,
                       style: ElevatedButton.styleFrom(
                         backgroundColor: kPrimaryColor,
                         padding: const EdgeInsets.symmetric(vertical: 16),
                         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                         elevation: 0,
                       ),
                       child: _isLoading 
                           ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                           : const Text('حفظ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                     ),
                   ),
                 ],
               )
             ],
           ),
         ),
       ),
    );
  }
}
