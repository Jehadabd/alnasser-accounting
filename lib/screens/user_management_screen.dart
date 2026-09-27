// screens/user_management_screen.dart
import 'package:flutter/material.dart';
import '../models/app_user.dart';
import '../services/auth_service.dart';
import '../services/password_service.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  final AuthService _authService = AuthService();
  final PasswordService _passwordService = PasswordService();
  List<AppUser> _accountants = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAccountants();
  }

  Future<void> _loadAccountants() async {
    setState(() => _isLoading = true);
    _accountants = await _authService.getAllAccountants();
    setState(() => _isLoading = false);
  }

  Future<void> _showAddUserDialog({bool isAdmin = false}) async {
    // طلب التحقق من كلمة السر أولاً
    final passwordController = TextEditingController();
    
    final verified = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.security, color: Colors.deepPurple),
            SizedBox(width: 8),
            Text('التحقق من الهوية'),
          ],
        ),
        content: TextField(
          controller: passwordController,
          obscureText: true,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'أدخل كلمة سر الجوكر أو كلمة سر الاسترداد',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onSubmitted: (val) async {
            final isValid = await _passwordService.verifyPassword(val);
            Navigator.pop(context, isValid);
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              final isValid = await _passwordService.verifyPassword(passwordController.text);
              Navigator.pop(context, isValid);
            },
            child: const Text('تحقق'),
          ),
        ],
      ),
    );
    
    if (verified != true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('كلمة السر غير صحيحة'), backgroundColor: Colors.red),
        );
      }
      return;
    }
    
    // عرض نموذج إضافة المستخدم
    final usernameController = TextEditingController();
    final displayNameController = TextEditingController(); // 🆕 اسم المحاسب
    final newPasswordController = TextEditingController();
    List<String> selectedPermissions = isAdmin ? AppPermissions.allKeys : [];
    
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(isAdmin ? Icons.admin_panel_settings : Icons.person_add, color: Colors.deepPurple),
              const SizedBox(width: 8),
              Text(isAdmin ? 'إضافة Admin' : 'إضافة محاسب'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 🆕 اسم المحاسب (للعرض)
                if (!isAdmin) ...[
                  TextField(
                    controller: displayNameController,
                    decoration: InputDecoration(
                      labelText: 'اسم المحاسب',
                      hintText: 'مثال: محمد أحمد',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      prefixIcon: const Icon(Icons.badge),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                TextField(
                  controller: usernameController,
                  decoration: InputDecoration(
                    labelText: 'اسم المستخدم',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    prefixIcon: const Icon(Icons.person),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: newPasswordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'كلمة السر',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    prefixIcon: const Icon(Icons.lock),
                  ),
                ),
                if (!isAdmin) ...[
                  const SizedBox(height: 24),
                  const Text('الصلاحيات:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  // 🧩 قوالب جاهزة: تملأ الصلاحيات ثم يمكن تعديلها
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final t in AppPermissions.roleTemplates.entries)
                        ActionChip(
                          avatar: const Icon(Icons.badge, size: 16),
                          label: Text(t.key),
                          onPressed: () => setDialogState(() {
                            selectedPermissions
                              ..clear()
                              ..addAll(t.value);
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...AppPermissions.allPermissions.entries.map((entry) => CheckboxListTile(
                    title: Text(entry.value),
                    value: selectedPermissions.contains(entry.key),
                    onChanged: (val) {
                      setDialogState(() {
                        if (val == true) {
                          selectedPermissions.add(entry.key);
                        } else {
                          selectedPermissions.remove(entry.key);
                        }
                      });
                    },
                    activeColor: Colors.deepPurple,
                    dense: true,
                  )),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
              onPressed: () {
                if (usernameController.text.isEmpty || newPasswordController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('يرجى ملء جميع الحقول'), backgroundColor: Colors.red),
                  );
                  return;
                }
                Navigator.pop(context, {
                  'username': usernameController.text.trim(),
                  'password': newPasswordController.text,
                  'permissions': selectedPermissions,
                });
              },
              child: const Text('إضافة', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
    
    if (result != null) {
      AppUser? user;
      if (isAdmin) {
        user = await _authService.createAdmin(result['username'], result['password']);
      } else {
        user = await _authService.createAccountant(result['username'], result['password'], result['permissions']);
      }
      
      if (user != null) {
        // تحذير بحفظ البيانات
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.orange, size: 32),
                SizedBox(width: 8),
                Text('تأكيد مهم!'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('تم إنشاء المستخدم بنجاح. يرجى حفظ هذه البيانات:', style: TextStyle(fontSize: 16)),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Row(children: [const Text('اسم المستخدم: ', style: TextStyle(fontWeight: FontWeight.bold)), Text(result['username'])]),
                      const SizedBox(height: 8),
                      Row(children: [const Text('كلمة السر: ', style: TextStyle(fontWeight: FontWeight.bold)), Text(result['password'])]),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text('هل أخذت صورة أو حفظت هذه البيانات؟', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              ],
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                onPressed: () => Navigator.pop(context),
                child: const Text('نعم، حفظتها', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
        
        // إذا كان Admin، تسجيل الخروج
        if (isAdmin && mounted) {
          await _authService.logout();
          Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
        } else {
          _loadAccountants();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('اسم المستخدم موجود مسبقاً'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _deleteUser(AppUser user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل أنت متأكد من حذف المحاسب "${user.username}"؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    
    if (confirmed == true && user.id != null) {
      await _authService.deleteUser(user.id!);
      _loadAccountants();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة المستخدمين'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.add),
            onSelected: (value) {
              if (value == 'admin') {
                _showAddUserDialog(isAdmin: true);
              } else {
                _showAddUserDialog(isAdmin: false);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'admin', child: Row(children: [Icon(Icons.admin_panel_settings, color: Colors.deepPurple), SizedBox(width: 8), Text('إضافة Admin')])),
              const PopupMenuItem(value: 'accountant', child: Row(children: [Icon(Icons.person_add, color: Colors.blue), SizedBox(width: 8), Text('إضافة محاسب')])),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _accountants.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text('لا يوجد محاسبين', style: TextStyle(fontSize: 18, color: Colors.grey[600])),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: () => _showAddUserDialog(isAdmin: false),
                        icon: const Icon(Icons.person_add),
                        label: const Text('إضافة محاسب'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _accountants.length,
                  itemBuilder: (context, index) {
                    final user = _accountants[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.blue[100],
                          child: const Icon(Icons.person, color: Colors.blue),
                        ),
                        title: Text(user.username, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('${user.permissions.length} صلاحيات'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              onPressed: () {
                                // TODO: Edit permissions dialog
                              },
                              tooltip: 'تعديل الصلاحيات',
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _deleteUser(user),
                              tooltip: 'حذف',
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
