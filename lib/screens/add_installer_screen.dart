import 'package:flutter/material.dart';
import '../models/installer.dart';
import '../services/database_service.dart';

class AddInstallerScreen extends StatefulWidget {
  const AddInstallerScreen({super.key});

  @override
  State<AddInstallerScreen> createState() => _AddInstallerScreenState();
}

class _AddInstallerScreenState extends State<AddInstallerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final DatabaseService _db = DatabaseService();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveInstaller() async {
    if (_formKey.currentState!.validate()) {
      final newInstaller = Installer(
        id: null,
        name: _nameController.text.trim(),
        totalBilledAmount: 0.0, // New installers start with 0
      );
      try {
        await _db.insertInstaller(newInstaller);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم إضافة المؤسس بنجاح!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context); // Go back to the installers list
        }
      } catch (e) {
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('فشل إضافة المؤسس: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إضافة مؤسس جديد'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'اسم المؤسس'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'الرجاء إدخال اسم المؤسس';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24.0),
              ElevatedButton(
                onPressed: _saveInstaller,
                child: const Text('حفظ المؤسس'),
              ),
            ],
          ),
        ),
      ),
    );
  }
} 