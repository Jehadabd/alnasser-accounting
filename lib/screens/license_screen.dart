// license_screen.dart
// شاشة تفعيل الترخيص

import 'package:flutter/material.dart';
import '../services/license_service.dart';

class LicenseScreen extends StatefulWidget {
  const LicenseScreen({super.key});

  @override
  State<LicenseScreen> createState() => _LicenseScreenState();
}

class _LicenseScreenState extends State<LicenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _licenseService = LicenseService();
  
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _activateLicense() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await _licenseService.activateLicense(
        _usernameController.text.trim(),
        _passwordController.text,
      );

      if (!mounted) return;

      if (result.success) {
        // عرض تحذير إذا كان قريب من الانتهاء
        if (result.warning != null) {
          await _showWarningDialog(result.warning!);
        }
        
        // الانتقال للتطبيق
        Navigator.of(context).pushReplacementNamed('/');
      } else {
        setState(() {
          _errorMessage = _getErrorMessage(result.error, result.message);
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'حدث خطأ غير متوقع: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _getErrorMessage(String? error, String? message) {
    if (message != null && message.isNotEmpty) return message;
    
    switch (error) {
      case 'USER_NOT_FOUND':
        return 'اسم المستخدم غير موجود';
      case 'WRONG_PASSWORD':
        return 'كلمة المرور خاطئة';
      case 'DEVICE_MISMATCH':
        return 'هذا الحساب مُفعّل على جهاز آخر\n\nتواصل مع المطور (واتساب / اتصال: 07705252905)';
      case 'SUSPENDED':
        return 'الحساب معلّق\n\nتواصل مع المطور (واتساب / اتصال: 07705252905)';
      case 'EXPIRED':
        return 'انتهت صلاحية الاشتراك\n\nتواصل مع المطور (واتساب / اتصال: 07705252905)';
      case 'NETWORK_ERROR':
        return 'فشل الاتصال بالسيرفر\n\nتأكد من اتصالك بالإنترنت';
      default:
        return 'حدث خطأ غير معروف';
    }
  }

  Future<void> _showWarningDialog(String message) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.orange, size: 28),
            SizedBox(width: 8),
            Text('تنبيه'),
          ],
        ),
        content: Text(message, textAlign: TextAlign.center),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('فهمت'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.blue.shade800,
              Colors.blue.shade600,
              Colors.blue.shade400,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Card(
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // الشعار
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.verified_user,
                            size: 64,
                            color: Colors.blue.shade700,
                          ),
                        ),
                        const SizedBox(height: 24),
                        
                        // العنوان
                        Text(
                          'تفعيل الترخيص',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'أدخل بيانات الترخيص للمتابعة',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 32),
                        
                        // رسالة الخطأ
                        if (_errorMessage != null) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.error_outline, color: Colors.red.shade700),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: TextStyle(color: Colors.red.shade700),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        
                        // حقل اسم المستخدم
                        TextFormField(
                          controller: _usernameController,
                          textDirection: TextDirection.ltr,
                          decoration: InputDecoration(
                            labelText: 'اسم المستخدم',
                            prefixIcon: const Icon(Icons.person),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'أدخل اسم المستخدم';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        
                        // حقل كلمة المرور
                        TextFormField(
                          controller: _passwordController,
                          textDirection: TextDirection.ltr,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            labelText: 'كلمة المرور',
                            prefixIcon: const Icon(Icons.lock),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'أدخل كلمة المرور';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),
                        
                        // زر التفعيل
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _activateLicense,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade700,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : const Text(
                                    'تفعيل',
                                    style: TextStyle(fontSize: 18),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        // معلومات التواصل
                        Text(
                          'للحصول على ترخيص، تواصل مع المطور (واتساب / اتصال: 07705252905)',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// شاشة انتظار فحص الترخيص
class LicenseCheckScreen extends StatefulWidget {
  const LicenseCheckScreen({super.key});

  @override
  State<LicenseCheckScreen> createState() => _LicenseCheckScreenState();
}

class _LicenseCheckScreenState extends State<LicenseCheckScreen> {
  final _licenseService = LicenseService();
  String _status = 'جارٍ التحقق من الترخيص...';
  bool _hasError = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _performCheck();
  }

  Future<void> _performCheck() async {
    try {
      final result = await _licenseService.performStartupCheck();
      
      if (!mounted) return;

      if (result.canProceed) {
        // عرض تحذير إذا وجد
        if (result.showWarning && result.warningMessage != null) {
          await _showWarningDialog(result.warningMessage!);
        }
        
        // الانتقال للتطبيق
        Navigator.of(context).pushReplacementNamed('/main');
      } else {
        // التعامل مع سبب الحظر
        switch (result.reason) {
          case StartupBlockReason.notActivated:
            Navigator.of(context).pushReplacementNamed('/license');
            break;
          case StartupBlockReason.expired:
          case StartupBlockReason.clockTampering:
          case StartupBlockReason.serverRejected:
          case StartupBlockReason.noInternetInGrace:
            setState(() {
              _hasError = true;
              _errorMessage = result.message ?? 'خطأ في الترخيص';
            });
            break;
          default:
            Navigator.of(context).pushReplacementNamed('/license');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = 'حدث خطأ: $e';
        });
      }
    }
  }

  Future<void> _showWarningDialog(String message) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.orange, size: 28),
            SizedBox(width: 8),
            Text('تنبيه'),
          ],
        ),
        content: Text(message, textAlign: TextAlign.center),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('فهمت'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.blue.shade800,
              Colors.blue.shade600,
            ],
          ),
        ),
        child: Center(
          child: _hasError
              ? _buildErrorView()
              : _buildLoadingView(),
        ),
      ),
    );
  }

  Widget _buildLoadingView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
        ),
        const SizedBox(height: 24),
        Text(
          _status,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
          ),
        ),
      ],
    );
  }

  Widget _buildErrorView() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 64,
                color: Colors.red,
              ),
              const SizedBox(height: 16),
              const Text(
                'خطأ في الترخيص',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _errorMessage ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _hasError = false;
                        _errorMessage = null;
                      });
                      _performCheck();
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('إعادة المحاولة'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await _licenseService.clearLicense();
                      if (mounted) {
                        Navigator.of(context).pushReplacementNamed('/license');
                      }
                    },
                    icon: const Icon(Icons.logout),
                    label: const Text('إعادة التفعيل'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
