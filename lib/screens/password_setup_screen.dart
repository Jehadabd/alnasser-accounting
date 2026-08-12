import 'package:flutter/material.dart';
import '../services/password_service.dart';

class PasswordSetupScreen extends StatefulWidget {
  const PasswordSetupScreen({super.key});

  @override
  State<PasswordSetupScreen> createState() => _PasswordSetupScreenState();
}

class _PasswordSetupScreenState extends State<PasswordSetupScreen> {
  final TextEditingController _password1Controller = TextEditingController();
  final TextEditingController _password2Controller = TextEditingController();
  final TextEditingController _password3Controller = TextEditingController();
  final PasswordService _passwordService = PasswordService();
  final _formKey = GlobalKey<FormState>();

  Future<void> _savePasswords() async {
    if (_formKey.currentState!.validate()) {
      final String p1 = _password1Controller.text;
      final String p2 = _password2Controller.text;
      final String p3 = _password3Controller.text;

      if (p1 == p2 || p1 == p3 || p2 == p3) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('الرجاء إدخال ثلاث كلمات سر مختلفة.')),
        );
        return;
      }

      try {
        await _passwordService.savePasswords([p1, p2, p3]);
        await _passwordService.setFirstLaunchCompleted();
        // Navigate to the main screen after successful setup
        Navigator.of(context).pushReplacementNamed('/');
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل حفظ كلمات السر: ${e.toString()}')),
        );
      }
    }
  }

  @override
  void dispose() {
    _password1Controller.dispose();
    _password2Controller.dispose();
    _password3Controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إعداد كلمات السر'),
        automaticallyImplyLeading: false, // Prevent going back
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const Text(
                  'الرجاء إدخال ثلاث كلمات سر مختلفة لحماية التطبيق.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _password1Controller,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'كلمة السر 1',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'الرجاء إدخال كلمة السر';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _password2Controller,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'كلمة السر 2',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'الرجاء إدخال كلمة السر';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _password3Controller,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'كلمة السر 3',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'الرجاء إدخال كلمة السر';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _savePasswords,
                  child: const Text('حفظ كلمات السر'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
} 