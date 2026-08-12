// lib/screens/dropbox_backup_screen.dart
// 🔥 واجهة النسخ الاحتياطي إلى Dropbox

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/dropbox_backup_service.dart';

class DropboxBackupScreen extends StatefulWidget {
  const DropboxBackupScreen({super.key});

  @override
  State<DropboxBackupScreen> createState() => _DropboxBackupScreenState();
}

class _DropboxBackupScreenState extends State<DropboxBackupScreen> {
  final DropboxBackupService _backupService = DropboxBackupService();
  
  DropboxAuthStatus _authStatus = DropboxAuthStatus.notConfigured;
  List<BackupInfo> _backups = [];
  bool _isLoading = false;
  String _statusMessage = '';
  int _progress = 0;
  int _maxBackups = 20;
  
  // Controller للـ OAuth code
  final _codeController = TextEditingController();
  bool _showCodeInput = false;

  @override
  void initState() {
    super.initState();
    _checkAuthAndLoadBackups();
  }

  Future<void> _checkAuthAndLoadBackups() async {
    setState(() => _isLoading = true);
    
    _authStatus = await _backupService.checkAuthStatus();
    
    if (_authStatus == DropboxAuthStatus.authenticated) {
      _backups = await _backupService.listBackups();
      _backups.sort((a, b) => b.modifiedTime.compareTo(a.modifiedTime));
    }
    
    setState(() => _isLoading = false);
  }

  Future<void> _startOAuthFlow() async {
    const redirectUri = 'http://localhost';
    final authUrl = _backupService.getAuthorizationUrl(redirectUri);
    
    setState(() {
      _showCodeInput = true;
      _statusMessage = 'سيتم فتح صفحة Dropbox للمصادقة...\nبعد الموافقة، انسخ الكود وألصقه هنا';
    });
    
    final uri = Uri.parse(authUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      setState(() {
        _statusMessage = '❌ لا يمكن فتح الرابط';
      });
    }
  }

  Future<void> _submitAuthCode(String code) async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'جاري التحقق من الكود...';
    });

    const redirectUri = 'http://localhost';
    final success = await _backupService.exchangeCodeForToken(code, redirectUri);
    
    if (success) {
      setState(() {
        _authStatus = DropboxAuthStatus.authenticated;
        _showCodeInput = false;
        _statusMessage = '✅ تم الاتصال بنجاح!';
      });
      await _checkAuthAndLoadBackups();
    } else {
      setState(() {
        _statusMessage = '❌ فشل في التحقق من الكود. حاول مرة أخرى.';
      });
    }
    
    setState(() => _isLoading = false);
  }

  Future<void> _createBackup() async {
    setState(() {
      _isLoading = true;
      _progress = 0;
      _statusMessage = '';
    });

    final result = await _backupService.createAndUploadBackup(
      maxBackups: _maxBackups,
      onProgress: (progress, status) {
        setState(() {
          _progress = progress;
          _statusMessage = status;
        });
      },
    );

    setState(() {
      _isLoading = false;
      if (result.success) {
        _statusMessage = '✅ تم إنشاء النسخة: ${result.backupName}\n'
            'حجم الملف: ${(result.backupSize! / 1024).toStringAsFixed(1)} KB\n'
            'تم حذف ${result.deletedCount} نسخة قديمة';
      } else {
        _statusMessage = '❌ ${result.error}';
      }
    });

    await _checkAuthAndLoadBackups();
  }

  Future<void> _restoreBackup(BackupInfo backup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الاستعادة'),
        content: Text('هل تريد استعادة النسخة:\n${backup.name}?\n\n'
            '⚠️ سيتم استبدال قاعدة البيانات الحالية.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('استعادة'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isLoading = true;
      _statusMessage = 'جاري الاستعادة...';
    });

    final success = await _backupService.restoreBackup(backup);
    
    setState(() {
      _isLoading = false;
      _statusMessage = success 
          ? '✅ تم استعادة النسخة بنجاح!\nيرجى إعادة تشغيل التطبيق.'
          : '❌ فشل في الاستعادة';
    });

    if (success && mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('تمت الاستعادة'),
          content: const Text('تم استعادة النسخة الاحتياطية بنجاح.\n'
              'يرجى إعادة تشغيل التطبيق لتطبيق التغييرات.'),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
              },
              child: const Text('حسناً'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _deleteBackup(BackupInfo backup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل تريد حذف النسخة:\n${backup.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final success = await _backupService.deleteBackup(backup);
    if (success) {
      await _checkAuthAndLoadBackups();
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تسجيل الخروج'),
        content: const Text('هل تريد قطع الاتصال بـ Dropbox؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('تسجيل الخروج'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _backupService.logout();
      setState(() {
        _authStatus = DropboxAuthStatus.notConfigured;
        _backups = [];
        _statusMessage = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('النسخ الاحتياطي السحابي'),
        centerTitle: true,
        actions: [
          if (_authStatus == DropboxAuthStatus.authenticated)
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: _logout,
              tooltip: 'تسجيل الخروج',
            ),
        ],
      ),
      body: _isLoading 
          ? _buildLoadingView()
          : _buildContent(),
    );
  }

  Widget _buildLoadingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          if (_progress > 0) ...[
            SizedBox(
              width: 200,
              child: LinearProgressIndicator(value: _progress / 100),
            ),
            const SizedBox(height: 10),
          ],
          if (_statusMessage.isNotEmpty)
            Text(_statusMessage, textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // حالة الاتصال
          _buildAuthStatus(),
          const SizedBox(height: 20),
          
          // رسالة الحالة
          if (_statusMessage.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _statusMessage.startsWith('✅') 
                    ? Colors.green.withOpacity(0.1)
                    : _statusMessage.startsWith('❌')
                        ? Colors.red.withOpacity(0.1)
                        : Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14),
              ),
            ),
            const SizedBox(height: 20),
          ],
          
          // واجهة المصادقة
          if (_authStatus != DropboxAuthStatus.authenticated)
            _buildAuthSection()
          else ...[
            // إعدادات النسخ
            _buildSettingsSection(),
            const SizedBox(height: 20),
            
            // زر النسخ الاحتياطي
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _createBackup,
              icon: const Icon(Icons.cloud_upload),
              label: const Text('إنشاء نسخة احتياطية جديدة'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 20),
            
            // قائمة النسخ
            _buildBackupsList(),
          ],
        ],
      ),
    );
  }

  Widget _buildAuthStatus() {
    IconData icon;
    Color color;
    String text;

    switch (_authStatus) {
      case DropboxAuthStatus.authenticated:
        icon = Icons.check_circle;
        color = Colors.green;
        text = 'متصل بـ Dropbox';
        break;
      case DropboxAuthStatus.needsAuth:
        icon = Icons.warning;
        color = Colors.orange;
        text = 'يجب إعادة المصادقة';
        break;
      case DropboxAuthStatus.error:
        icon = Icons.error;
        color = Colors.red;
        text = 'خطأ في الاتصال';
        break;
      default:
        icon = Icons.cloud_off;
        color = Colors.grey;
        text = 'غير متصل';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(width: 12),
          Text(
            text,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Icon(Icons.cloud, size: 64, color: Colors.blue),
            const SizedBox(height: 16),
            const Text(
              'النسخ الاحتياطي السحابي',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'احفظ نسخة احتياطية من بياناتك في Dropbox\nمع حماية تلقائية ضد فقدان البيانات',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),
            
            if (_showCodeInput) ...[
              TextField(
                controller: _codeController,
                decoration: const InputDecoration(
                  labelText: 'أدخل كود المصادقة',
                  hintText: 'الصق الكود من Dropbox',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _submitAuthCode(_codeController.text.trim()),
                      child: const Text('تأكيد'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() => _showCodeInput = false),
                      child: const Text('إلغاء'),
                    ),
                  ),
                ],
              ),
            ] else ...[
              ElevatedButton.icon(
                onPressed: _startOAuthFlow,
                icon: const Icon(Icons.login),
                label: const Text('تسجيل الدخول إلى Dropbox'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'إعدادات النسخ الاحتياطي',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('الاحتفاظ بـ '),
                DropdownButton<int>(
                  value: _maxBackups,
                  items: [10, 15, 20, 30, 50].map((n) {
                    return DropdownMenuItem(
                      value: n,
                      child: Text('$n نسخة'),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => _maxBackups = v ?? 20),
                ),
                const Text(' احتياطية'),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'سيتم حذف النسخ الأقدم تلقائياً عند تجاوز العدد',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackupsList() {
    if (_backups.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            children: [
              Icon(Icons.inbox, size: 48, color: Colors.grey),
              SizedBox(height: 12),
              Text(
                'لا توجد نسخ احتياطية',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'النسخ الاحتياطية (${_backups.length})',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        ...(_backups.map((backup) => _buildBackupItem(backup))),
      ],
    );
  }

  Widget _buildBackupItem(BackupInfo backup) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.backup, color: Colors.blue),
        title: Text(
          backup.name,
          style: const TextStyle(fontSize: 13),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_formatDate(backup.modifiedTime)} • ${(backup.size / 1024).toStringAsFixed(1)} KB',
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (value) {
            if (value == 'restore') _restoreBackup(backup);
            if (value == 'delete') _deleteBackup(backup);
          },
          itemBuilder: (ctx) => [
            const PopupMenuItem(
              value: 'restore',
              child: Row(
                children: [
                  Icon(Icons.restore, color: Colors.blue),
                  SizedBox(width: 8),
                  Text('استعادة'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, color: Colors.red),
                  SizedBox(width: 8),
                  Text('حذف'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
           '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }
}
