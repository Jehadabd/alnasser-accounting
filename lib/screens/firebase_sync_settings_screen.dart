// lib/screens/firebase_sync_settings_screen.dart
// شاشة إعدادات المزامنة عبر Firebase مع حماية صارمة

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/firebase_sync/firebase_sync_config.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/firebase_sync/firebase_sync_service.dart';
import 'package:sqflite/sqflite.dart';
import '../services/firebase_sync/firebase_custom_config.dart';
import '../services/firebase_sync/invoice_sync_service.dart';
import '../services/firebase_sync/smart_pipe_cleanup_service.dart';
import '../services/database_service.dart';
import 'firebase_custom_setup_screen.dart';
import 'reconciliation_screen.dart';

class FirebaseSyncSettingsScreen extends StatefulWidget {
  const FirebaseSyncSettingsScreen({super.key});

  @override
  State<FirebaseSyncSettingsScreen> createState() => _FirebaseSyncSettingsScreenState();
}

class _FirebaseSyncSettingsScreenState extends State<FirebaseSyncSettingsScreen> {
  bool _isLoading = false; // 🔧 تغيير: لا نبدأ بالتحميل
  bool _isLoadingStats = false; // 🆕 تحميل الإحصائيات منفصل
  bool _isEnabled = false;
  String? _projectId; // 🆕 معرف المشروع
  Map<String, dynamic>? _syncStats;
  String _loadingMessage = ''; // 🆕 رسالة التحميل
  double _loadingProgress = 0.0; // 🆕 نسبة التقدم (0.0 - 1.0)
  
  // 🔒 إعدادات الأمان
  bool _rejectOldTransactions = false;
  int _maxTransactionAgeDays = 30;
  int _autoDeleteDays = 90;
  bool _postSyncVerification = true;
  CustomerConflictPolicy _customerConflictPolicy = CustomerConflictPolicy.smartReactivate;
  
  // 🔄 حالة تحميل كل زر
  bool _isSyncing = false;
  bool _isCleaning = false;
  bool _isRepairing = false;
  bool _isLoadingDevices = false;
  bool _isLoadingTrackingStats = false;
  bool _isSyncingInvoices = false;
  bool _isMarkingOldInvoices = false;
  
  final _firebaseSync = FirebaseSyncService();

  // 📊 اشتراكات الـ Streams اللحظية
  StreamSubscription<FirebaseSyncStatus>? _statusSubscription;
  StreamSubscription<Map<String, dynamic>>? _statsSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _devicesSubscription;

  @override
  void initState() {
    super.initState();
    _loadSettingsQuick(); // 🔧 تحميل سريع أولاً
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    _statsSubscription?.cancel();
    _devicesSubscription?.cancel();
    super.dispose();
  }

  /// 🔧 تحميل سريع للإعدادات الأساسية + بدء الاستماع للـ Streams
  Future<void> _loadSettingsQuick() async {
    _isEnabled = await FirebaseSyncConfig.isEnabled();
    
    // 🔒 تحميل إعدادات الأمان
    _rejectOldTransactions = await FirebaseSyncSecuritySettings.isRejectOldTransactionsEnabled();
    _maxTransactionAgeDays = await FirebaseSyncSecuritySettings.getMaxTransactionAgeDays();
    _autoDeleteDays = await FirebaseSyncSecuritySettings.getAutoDeleteDays();
    _postSyncVerification = await FirebaseSyncSecuritySettings.isPostSyncVerificationEnabled();
    _customerConflictPolicy = await FirebaseSyncSecuritySettings.getCustomerConflictPolicy();
    
    // 🆕 تحميل Project ID
    _projectId = await FirebaseCustomConfig.getProjectId();
    
    if (mounted) {
      setState(() {});
    }
    
    // 📊 بدء الاستماع للـ Streams اللحظية
    if (_isEnabled) {
      _startStreamListeners();
      _loadStatsInBackground(); // تحميل أولي
    }
  }
  
  /// 📊 بدء الاستماع للتحديثات اللحظية
  void _startStreamListeners() {
    // 1. الاستماع لتغيرات حالة المزامنة
    _statusSubscription?.cancel();
    _statusSubscription = _firebaseSync.statusStream.listen((status) {
      if (mounted) {
        setState(() {}); // تحديث الواجهة عند تغير الحالة
      }
    });
    
    // 2. الاستماع لتحديثات الإحصائيات اللحظية
    _statsSubscription?.cancel();
    _statsSubscription = _firebaseSync.liveStatsStream.listen((stats) {
      if (mounted) {
        setState(() {
          _syncStats ??= {};
          _syncStats!['customersInCloud'] = stats['customersInCloud'];
          _syncStats!['transactionsInCloud'] = stats['transactionsInCloud'];
          _syncStats!['invoicesInCloud'] = stats['invoicesInCloud'];
          _isLoadingStats = false;
        });
      }
    });
  }

  /// 🆕 تحميل الإحصائيات (مع دعم Fallback للبيانات اللحظية)
  Future<void> _loadStatsInBackground() async {
    if (!mounted) return;
    setState(() {
      _isLoadingStats = true;
    });
    
    try {
      // 🔄 محاولة إعادة التهيئة إذا لم تكن مكتملة
      if (_firebaseSync.status == FirebaseSyncStatus.notConfigured ||
          _firebaseSync.status == FirebaseSyncStatus.idle ||
          _firebaseSync.status == FirebaseSyncStatus.error) {
        await _firebaseSync.initialize(
          onProgress: (progress, message) {
            if (mounted) {
              setState(() {
                _loadingProgress = progress * 0.2; 
                _loadingMessage = message;
              });
            }
          }
        );
      }
      
      _syncStats = await _firebaseSync.getSyncStats(
        onProgress: (progress, message) {
          if (mounted) {
            setState(() {
              _loadingProgress = 0.2 + (progress * 0.6);
              _loadingMessage = message;
            });
          }
        },
      );
      
    } catch (e) {
      _syncStats = {'error': e.toString()};
    }
    
    if (mounted) {
      setState(() {
        _isLoadingStats = false;
        _loadingProgress = 0.0;
        _loadingMessage = '';
      });
    }
  }

  Future<void> _loadSettings() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _loadingProgress = 0.0;
      _loadingMessage = 'جاري تحميل الإعدادات...';
    });
    
    _isEnabled = await FirebaseSyncConfig.isEnabled();
    if (_isEnabled) {
      if (mounted) {
        setState(() {
          _loadingProgress = 0.2;
          _loadingMessage = 'جاري تحميل الإحصائيات...';
        });
      }
      
      try {
        _syncStats = await _firebaseSync.getSyncStats(
          onProgress: (progress, message) {
            if (mounted) {
              setState(() {
                _loadingProgress = 0.2 + (progress * 0.8);
                _loadingMessage = message;
              });
            }
          },
        );
      } catch (e) {
        _syncStats = {'error': e.toString()};
      }
    }
    
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _loadingProgress = 0.0;
      _loadingMessage = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('مزامنة Firebase'),
          backgroundColor: Colors.deepOrange,
          foregroundColor: Colors.white,
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // بطاقة الحالة
                    _buildStatusCard(),
                    const SizedBox(height: 16),
                    
                    // بطاقة الإعدادات
                    _buildSettingsCard(),
                    const SizedBox(height: 16),
                    
                    // بطاقة الإحصائيات
                    if (_isEnabled)
                      _buildStatsCard(),
                    
                    const SizedBox(height: 16),
                    
                    // 🔒 بطاقة إعدادات الأمان
                    if (_isEnabled)
                      _buildSecuritySettingsCard(),
                    
                    const SizedBox(height: 16),

                    // 🔀 بطاقة سياسة تعارض حذف العملاء
                    if (_isEnabled)
                      _buildConflictPolicyCard(),
                    
                    const SizedBox(height: 16),
                    
                    // ملاحظات
                    _buildNotesCard(),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildStatusCard() {
    final status = _firebaseSync.status;
    Color statusColor;
    String statusText;
    IconData statusIcon;
    
    switch (status) {
      case FirebaseSyncStatus.online:
        statusColor = Colors.green;
        statusText = 'متصل ويستمع للتغييرات اللحظية';
        statusIcon = Icons.cloud_done_rounded;
        break;
      case FirebaseSyncStatus.syncing:
        statusColor = Colors.blue;
        statusText = 'جاري المزامنة مع السحابة...';
        statusIcon = Icons.sync_rounded;
        break;
      case FirebaseSyncStatus.offline:
        statusColor = Colors.orange;
        statusText = 'غير متصل - يعمل محلياً فقط';
        statusIcon = Icons.cloud_off_rounded;
        break;
      case FirebaseSyncStatus.error:
        statusColor = Colors.red;
        statusText = 'خطأ في الاتصال بالمزامنة';
        statusIcon = Icons.error_rounded;
        break;
      case FirebaseSyncStatus.disabled:
        statusColor = Colors.grey;
        statusText = 'المزامنة السحابية معطلة';
        statusIcon = Icons.pause_circle_rounded;
        break;
      default:
        statusColor = Colors.blueGrey;
        statusText = 'غير مُعد بعد';
        statusIcon = Icons.settings_rounded;
    }
    
    return Container(
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withOpacity(0.2)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(statusIcon, color: statusColor, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'حالة المزامنة السحابية',
                  style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  statusText,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: statusColor),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _isEnabled ? 'نشط' : 'معطل',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: statusColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsCard() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.withOpacity(0.15)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.deepOrange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.sync_rounded, color: Colors.deepOrange, size: 20),
                ),
                const SizedBox(width: 10),
                const Text(
                  'إعدادات المزامنة الفورية',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'تفعيل المزامنة التلقائية الحية',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              subtitle: Text(
                _isEnabled 
                    ? 'المزامنة الفورية مفعلة - تتزامن الديون والفواتير تلقائياً عبر الأجهزة'
                    : 'المزامنة معطلة - يعمل التطبيق في الوضع المحلي فقط',
                style: const TextStyle(fontSize: 12),
              ),
              value: _isEnabled,
              onChanged: (value) => _toggleSync(value),
              activeColor: Colors.deepOrange,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsCard() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.withOpacity(0.15)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.analytics_rounded, color: Colors.blue, size: 20),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'إحصائيات المزامنة السحابية',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                // 🔧 مؤشر تحميل الإحصائيات مع النسبة
                if (_isLoadingStats)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${(_loadingProgress * 100).toInt()}%',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.deepOrange,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          value: _loadingProgress > 0 ? _loadingProgress : null,
                          backgroundColor: Colors.grey.shade200,
                          valueColor: const AlwaysStoppedAnimation<Color>(Colors.deepOrange),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const Divider(height: 24),
            
            // 🔧 عرض حالة التحميل أو الإحصائيات
            if (_isLoadingStats && _syncStats == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  children: [
                    // شريط التقدم الخطي
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: _loadingProgress > 0 ? _loadingProgress : null,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.deepOrange),
                        minHeight: 8,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // النسبة المئوية
                    Text(
                      '${(_loadingProgress * 100).toInt()}%',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.deepOrange,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // رسالة التحميل
                    Text(
                      _loadingMessage,
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            else if (_syncStats?['error'] != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _syncStats!['timeout'] == true 
                            ? 'انتهت مهلة التحميل - اضغط مزامنة الآن'
                            : 'خطأ: ${_syncStats!['error']}',
                        style: const TextStyle(color: Colors.orange, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              _buildStatRow('معرف المشروع', _projectId ?? 'غير متصل'),
              _buildStatRow('معرف المصادقة', FirebaseAuth.instance.currentUser?.uid ?? 'غير مصادق'),
              _buildStatRow('العملاء في السحابة', '${_syncStats?['customersInCloud'] ?? 0}'),
              _buildStatRow('المعاملات في السحابة', '${_syncStats?['transactionsInCloud'] ?? 0}'),
              _buildStatRow('الفواتير في السحابة', '${_syncStats?['invoicesInCloud'] ?? 0}'),
              _buildStatRow('آخر مزامنة', _formatLastSync(_syncStats?['lastSync'])),
            ],
            
            const SizedBox(height: 16),
            
            // 1. مزامنة الآن
            _buildActionButton(
              icon: Icons.sync,
              label: 'مزامنة الآن',
              isLoading: _isSyncing,
              progress: _isSyncing ? _loadingProgress : null,
              message: _isSyncing ? _loadingMessage : null,
              color: Colors.deepOrange,
              onPressed: _isSyncing ? null : _performManualSync,
              isPrimary: true,
            ),
            
            const SizedBox(height: 8),
            
            // 2. الرفع الشامل
            _buildActionButton(
              icon: Icons.cloud_upload,
              label: 'الرفع الشامل',
              isLoading: _isRepairing,
              progress: _isRepairing ? _loadingProgress : null,
              message: _isRepairing ? _loadingMessage : null,
              color: Colors.blue,
              onPressed: _isRepairing ? null : _repairAndSyncAll,
            ),
            
            const SizedBox(height: 8),

            // 3. رفع الفواتير المعلقة
            _buildActionButton(
              icon: Icons.receipt_long,
              label: 'رفع الفواتير المعلقة',
              isLoading: _isSyncingInvoices,
              color: Colors.indigo,
              onPressed: _isSyncingInvoices ? null : _syncInvoices,
            ),

            const SizedBox(height: 8),

            // 4. اعتبار الفواتير القديمة مرفوعة
            _buildActionButton(
              icon: Icons.done_all,
              label: 'اعتبار الفواتير القديمة مرفوعة',
              isLoading: _isMarkingOldInvoices,
              color: Colors.blueGrey,
              onPressed: _isMarkingOldInvoices ? null : _markOldInvoicesAsSynced,
            ),

            const SizedBox(height: 8),

            // 5. المطابقة بين الأجهزة
            _buildActionButton(
              icon: Icons.rule,
              label: 'المطابقة بين الأجهزة',
              isLoading: false,
              color: Colors.deepPurple,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const ReconciliationScreen()),
                );
              },
            ),

            const SizedBox(height: 8),

            // 6. إعدادات فايربيس
            _buildActionButton(
              icon: Icons.settings,
              label: 'إعدادات فايربيس',
              isLoading: false,
              color: Colors.teal,
              onPressed: () {
                // فتح شاشة إعدادات فايربيس المخصصة
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const FirebaseCustomSetupScreen()),
                );
              },
            ),
            
            const SizedBox(height: 8),
            
            // 4. الأجهزة المتصلة
            _buildActionButton(
              icon: Icons.devices,
              label: 'الأجهزة المتصلة',
              isLoading: _isLoadingDevices,
              color: Colors.purple,
              onPressed: _isLoadingDevices ? null : _showConnectedDevices,
            ),
            
            const SizedBox(height: 8),
            
            // 4. المعاملات الفاشلة
            _buildActionButton(
              icon: Icons.error_outline,
              label: 'المعاملات الفاشلة',
              isLoading: _isLoadingTrackingStats,
              color: Colors.red,
              onPressed: _isLoadingTrackingStats ? null : _showFailedOperations,
            ),
            
            const SizedBox(height: 8),
            
            // 5. مسح قاعدة البيانات السحابية بالكامل
            _buildActionButton(
              icon: Icons.delete_forever,
              label: 'حذف قاعدة البيانات السحابية بالكامل',
              isLoading: _isCleaning,
              progress: _isCleaning ? _loadingProgress : null,
              message: _isCleaning ? _loadingMessage : null,
              color: Colors.red.shade900,
              onPressed: _isCleaning ? null : _deleteCloudDatabase,
            ),
          ],
        ),
      ),
    );
  }
  
  /// 🆕 Widget لبناء زر مع مؤشر تقدم
  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required bool isLoading,
    double? progress,
    String? message,
    required Color color,
    required VoidCallback? onPressed,
    bool isPrimary = false,
  }) {
    return SizedBox(
      width: double.infinity,
      child: Column(
        children: [
          SizedBox(
            height: 48,
            width: double.infinity,
            child: isPrimary
                ? ElevatedButton.icon(
                    onPressed: onPressed,
                    icon: isLoading 
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              value: progress,
                              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Icon(icon, size: 20),
                    label: Text(
                      isLoading && progress != null 
                          ? '$label (${(progress * 100).toInt()}%)'
                          : label,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.white,
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  )
                : OutlinedButton.icon(
                    onPressed: onPressed,
                    icon: isLoading 
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              value: progress,
                              valueColor: AlwaysStoppedAnimation<Color>(color),
                            ),
                          )
                        : Icon(icon, size: 20),
                    label: Text(
                      isLoading && progress != null 
                          ? '$label (${(progress * 100).toInt()}%)'
                          : label,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: color,
                      side: BorderSide(color: color.withOpacity(0.4), width: 1.2),
                      backgroundColor: color.withOpacity(0.04),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
          ),
          // عرض رسالة التقدم إذا كانت موجودة
          if (isLoading && message != null && message.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                message,
                style: TextStyle(fontSize: 11, color: color.withOpacity(0.9), fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 13, fontWeight: FontWeight.w500)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  String _formatLastSync(String? isoString) {
    if (isoString == null) return 'لم تتم بعد';
    try {
      final date = DateTime.parse(isoString);
      final now = DateTime.now();
      final diff = now.difference(date);
      
      if (diff.inMinutes < 1) return 'الآن';
      if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} دقيقة';
      if (diff.inHours < 24) return 'منذ ${diff.inHours} ساعة';
      return 'منذ ${diff.inDays} يوم';
    } catch (e) {
      return isoString;
    }
  }

  /// 🔒 بطاقة إعدادات الأمان
  Widget _buildSecuritySettingsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.security, color: Colors.green),
                SizedBox(width: 8),
                Text(
                  'إعدادات الأمان',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(),
            
            // 🔒 رفض المعاملات القديمة
            SwitchListTile(
              title: const Text('رفض المعاملات القديمة'),
              subtitle: Text(
                _rejectOldTransactions 
                    ? 'سيتم رفض المعاملات الأقدم من $_maxTransactionAgeDays يوم'
                    : 'قبول جميع المعاملات بغض النظر عن تاريخها',
              ),
              value: _rejectOldTransactions,
              onChanged: (value) async {
                await FirebaseSyncSecuritySettings.setRejectOldTransactionsEnabled(value);
                setState(() => _rejectOldTransactions = value);
              },
              activeColor: Colors.green,
              secondary: const Icon(Icons.history, color: Colors.orange),
            ),
            
            // عدد الأيام (يظهر فقط إذا كان الرفض مفعلاً)
            if (_rejectOldTransactions)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Text('الحد الأقصى للعمر: '),
                    const SizedBox(width: 8),
                    DropdownButton<int>(
                      value: _maxTransactionAgeDays,
                      items: [7, 14, 30, 60, 90].map((days) {
                        return DropdownMenuItem(
                          value: days,
                          child: Text('$days يوم'),
                        );
                      }).toList(),
                      onChanged: (value) async {
                        if (value != null) {
                          await FirebaseSyncSecuritySettings.setMaxTransactionAgeDays(value);
                          setState(() => _maxTransactionAgeDays = value);
                        }
                      },
                    ),
                  ],
                ),
              ),
            
            const Divider(),
            
            // 🗑️ الحذف التلقائي للبيانات
            ListTile(
              title: const Text('الحذف التلقائي للبيانات القديمة (TTL)'),
              subtitle: Text('سيتم حذف البيانات الأقدم من $_autoDeleteDays يوم نهائياً من السحابة لتوفير المساحة.'),
              trailing: DropdownButton<int>(
                value: [30, 60, 90, 180, 365, 730].contains(_autoDeleteDays) ? _autoDeleteDays : 90,
                items: [30, 60, 90, 180, 365, 730].map((days) {
                  return DropdownMenuItem(
                    value: days,
                    child: Text('$days يوم'),
                  );
                }).toList(),
                onChanged: (value) async {
                  if (value != null) {
                    await FirebaseSyncSecuritySettings.setAutoDeleteDays(value);
                    setState(() => _autoDeleteDays = value);
                  }
                },
              ),
            ),
            
            const Divider(),
            
            // 🔍 التحقق من الأرصدة بعد المزامنة
            SwitchListTile(
              title: const Text('التحقق من الأرصدة بعد المزامنة'),
              subtitle: Text(
                _postSyncVerification 
                    ? 'سيتم التحقق من صحة الأرصدة بعد كل مزامنة'
                    : 'لن يتم التحقق من الأرصدة تلقائياً',
              ),
              value: _postSyncVerification,
              onChanged: (value) async {
                await FirebaseSyncSecuritySettings.setPostSyncVerificationEnabled(value);
                setState(() => _postSyncVerification = value);
              },
              activeColor: Colors.green,
              secondary: const Icon(Icons.account_balance_wallet, color: Colors.blue),
            ),
          ],
        ),
      ),
    );
  }

  /// 🔀 بطاقة سياسة معالجة تعارض حذف العملاء
  Widget _buildConflictPolicyCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.alt_route_rounded, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'سياسة تعارض حذف العملاء عند المزامنة',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'تحدد ماذا يحدث إذا حُذف عميل من جهاز، بينما قام جهاز آخر (أثناء انقطاع الإنترنت) بإضافة فاتورة أو دين له:',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
            const Divider(height: 24),
            
            // 🌟 الخيار الأول: التنشيط الذكي
            RadioListTile<CustomerConflictPolicy>(
              title: const Text(
                'إعادة التنشيط الذكي بالمعاملات الجديدة فقط (موصى به)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              subtitle: const Text(
                'يُعاد تنشيط العميل تلقائياً ويُسجل عليه فقط مبلغ المعاملة الجديدة التي أُنشئت أوفلاين، مع إبقاء ديونه القديمة المحذوفة ملغاة ومصفرة.',
                style: TextStyle(fontSize: 12),
              ),
              value: CustomerConflictPolicy.smartReactivate,
              groupValue: _customerConflictPolicy,
              activeColor: Colors.teal,
              contentPadding: EdgeInsets.zero,
              secondary: const CircleAvatar(
                radius: 16,
                backgroundColor: Color(0xFFE0F2F1),
                child: Icon(Icons.auto_awesome, color: Colors.teal, size: 18),
              ),
              onChanged: (value) async {
                if (value != null) {
                  await FirebaseSyncSecuritySettings.setCustomerConflictPolicy(value);
                  setState(() => _customerConflictPolicy = value);
                }
              },
            ),
            
            const SizedBox(height: 8),
            
            // 🔒 الخيار الثاني: الحذف الصارم
            RadioListTile<CustomerConflictPolicy>(
              title: const Text(
                'الحذف الصارم (الحذف يلغي أي معاملة أوفلاين)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              subtitle: const Text(
                'يعتبر قرار الحذف نهائياً وتُلغى أي فاتورة أو حركة أُضيفت للعميل أثناء انقطاع الإنترنت لمنع أي حركة غير مصرح بها.',
                style: TextStyle(fontSize: 12),
              ),
              value: CustomerConflictPolicy.strictDelete,
              groupValue: _customerConflictPolicy,
              activeColor: Colors.red.shade700,
              contentPadding: EdgeInsets.zero,
              secondary: CircleAvatar(
                radius: 16,
                backgroundColor: Colors.red.shade50,
                child: Icon(Icons.delete_forever, color: Colors.red.shade700, size: 18),
              ),
              onChanged: (value) async {
                if (value != null) {
                  await FirebaseSyncSecuritySettings.setCustomerConflictPolicy(value);
                  setState(() => _customerConflictPolicy = value);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotesCard() {
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Row(
              children: [
                Icon(Icons.info, color: Colors.blue),
                SizedBox(width: 8),
                Text(
                  'ملاحظات مهمة',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            Text('• المزامنة تتم تلقائياً في الخلفية'),
            Text('• يعمل التطبيق بدون إنترنت ويزامن عند العودة'),
            Text('• كل مجموعة مستقلة تماماً عن الأخرى'),
            Text('• تغيير المجموعة يتطلب تأكيد صارم'),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // الإجراءات
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _toggleSync(bool enable) async {
    await FirebaseSyncConfig.setEnabled(enable);
    if (enable) {
      await _firebaseSync.initialize();
    }
    await _loadSettings();
  }

  Future<void> _performManualSync() async {
    if (_isSyncing) return;
    
    final _sw = Stopwatch()..start();
    print('⏱️ [_performManualSync/UI] ▶️ ═══════════════════════════════════════');
    print('⏱️ [_performManualSync/UI] ▶️ المستخدم ضغط على زر مزامنة الآن...');
    
    setState(() {
      _isSyncing = true;
      _loadingProgress = 0.0;
      _loadingMessage = 'جاري بدء المزامنة...';
    });
    
    try {
      // 🔄 محاولة التهيئة إذا لم تكن مكتملة
      if (_firebaseSync.status == FirebaseSyncStatus.notConfigured ||
          _firebaseSync.status == FirebaseSyncStatus.idle ||
          _firebaseSync.status == FirebaseSyncStatus.error) {
        var _swStep = Stopwatch()..start();
        print('⏱️ [_performManualSync/UI] 🔧 بدء التهيئة...');
        setState(() {
          _loadingProgress = 0.05;
          _loadingMessage = 'جاري تهيئة المزامنة...';
        });
        final initSuccess = await _firebaseSync.initialize(
          onProgress: (progress, message) {
            if (mounted) {
              setState(() {
                _loadingProgress = 0.05 + (progress * 0.05); // 5% -> 10%
                _loadingMessage = message;
              });
            }
          }
        ).timeout(
          const Duration(minutes: 2),
          onTimeout: () => false,
        );
        print('⏱️ [_performManualSync/UI] 🔧 انتهت التهيئة في ${_swStep.elapsedMilliseconds}ms | النتيجة: ${initSuccess ? "نجاح" : "فشل"}');
        if (!initSuccess) {
          throw Exception('فشلت تهيئة المزامنة - تأكد من الاتصال بالإنترنت');
        }
      }
      
      // استخدام callback للتقدم
      var _swSync = Stopwatch()..start();
      print('⏱️ [_performManualSync/UI] 🔄 بدء performFullSync...');
      final syncSucceeded = await _firebaseSync.performFullSync(
        onProgress: (progress, message) {
          if (mounted) {
            setState(() {
              _loadingProgress = 0.1 + (progress * 0.75); // 10-85% للمزامنة
              _loadingMessage = message;
            });
          }
        },
      );
      print('⏱️ [_performManualSync/UI] 🔄 انتهت performFullSync في ${_swSync.elapsedMilliseconds}ms (${(_swSync.elapsedMilliseconds / 1000).toStringAsFixed(1)}s)');
      
      // ⚠️ إذا فشلت المزامنة (بدون اتصال أو خطأ)، لا نكمل تدفق النجاح
      if (!syncSucceeded) {
        throw Exception('فشلت المزامنة - تحقق من الاتصال بالإنترنت وأعد المحاولة');
      }
      
      // التحقق من الأرصدة (85-95%)
      if (_postSyncVerification) {
        setState(() {
          _loadingProgress = 0.88;
          _loadingMessage = 'جاري التحقق من الأرصدة...';
        });
        
        final verificationResult = await _firebaseSync.verifyBalancesAfterSync();
        
        setState(() {
          _loadingProgress = 0.95;
          _loadingMessage = 'اكتمل التحقق من الأرصدة';
        });
        
        if (verificationResult['hasIssues'] == true) {
          final issues = verificationResult['issues'] as List? ?? [];
          if (mounted && issues.isNotEmpty) {
            _showBalanceVerificationResult(verificationResult);
          }
        }
      }
      
      // الانتهاء (100%)
      setState(() {
        _loadingProgress = 1.0;
        _loadingMessage = 'تمت المزامنة بنجاح!';
      });
      
      _sw.stop();
      print('⏱️ [_performManualSync/UI] ⏹️ ═══════════════════════════════════════');
      print('⏱️ [_performManualSync/UI] ⏹️ إجمالي وقت العملية: ${_sw.elapsedMilliseconds}ms (${(_sw.elapsedMilliseconds / 1000).toStringAsFixed(1)}s)');
      print('⏱️ [_performManualSync/UI] ⏹️ ═══════════════════════════════════════');
      
      await Future.delayed(const Duration(milliseconds: 500));
      await _loadSettingsQuick();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تمت المزامنة بنجاح ✅'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشلت المزامنة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
    
    if (mounted) {
      setState(() {
        _isSyncing = false;
        _loadingProgress = 0.0;
        _loadingMessage = '';
      });
    }
  }
  
  /// 🔍 عرض نتيجة التحقق من الأرصدة
  void _showBalanceVerificationResult(Map<String, dynamic> result) {
    final issues = result['issues'] as List? ?? [];
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.warning, color: Colors.orange),
            SizedBox(width: 8),
            Text('تحذير: فروقات في الأرصدة'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'تم اكتشاف ${issues.length} فرق في الأرصدة:',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ...issues.take(5).map((issue) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        issue['customerName'] ?? 'عميل غير معروف',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'الرصيد المسجل: ${issue['recordedBalance']?.toStringAsFixed(2) ?? 0}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text(
                        'الرصيد المحسوب: ${issue['calculatedBalance']?.toStringAsFixed(2) ?? 0}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text(
                        'الفرق: ${issue['difference']?.toStringAsFixed(2) ?? 0}',
                        style: const TextStyle(fontSize: 12, color: Colors.red),
                      ),
                    ],
                  ),
                ),
              )),
              if (issues.length > 5)
                Text(
                  '... و ${issues.length - 5} فروقات أخرى',
                  style: const TextStyle(color: Colors.grey),
                ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('حسناً'),
          ),
        ],
      ),
    );
  }
  
  /// 🗑️ مسح قاعدة البيانات السحابية بالكامل
  Future<void> _deleteCloudDatabase() async {
    // تأكيد صارم قبل المسح
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 8),
            Text('تحذير خطير جداً', style: TextStyle(color: Colors.red)),
          ],
        ),
        content: const Text(
          'سيتم مسح جميع البيانات من Firebase بالكامل!\n'
          '(العملاء، المعاملات، الأجهزة، وكل شيء)\n\n'
          'هذا الإجراء لا يمكن التراجع عنه.\n'
          'هل أنت متأكد بنسبة 1000%؟',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade900,
              foregroundColor: Colors.white,
            ),
            child: const Text('نعم، امسح كل شيء في السحابة'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    setState(() {
      _isCleaning = true;
      _loadingProgress = 0.0;
      _loadingMessage = 'جاري حذف قاعدة البيانات بالكامل...';
    });
    
    try {
      if (_firebaseSync.status == FirebaseSyncStatus.notConfigured ||
          _firebaseSync.status == FirebaseSyncStatus.idle ||
          _firebaseSync.status == FirebaseSyncStatus.error) {
        await _firebaseSync.initialize().timeout(
          const Duration(minutes: 2),
          onTimeout: () => false,
        );
      }
      
      final result = await _firebaseSync.clearCloudDatabase();
      
      setState(() {
        _loadingProgress = 1.0;
        _loadingMessage = 'تم مسح قاعدة البيانات بالكامل!';
      });
      
      await Future.delayed(const Duration(milliseconds: 300));
      
      if (mounted) {
        if (result['error'] != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('فشل المسح: ${result['error']}'),
              backgroundColor: Colors.red,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تم مسح قاعدة البيانات السحابية بنجاح (${result['deletedCount']} مستند) ✅'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
      
      await _loadSettingsQuick();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل المسح: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
    
    setState(() {
      _isCleaning = false;
      _loadingProgress = 0.0;
      _loadingMessage = '';
    });
  }

  Widget _buildIntegrityRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
  
  /// 🧾 رفع الفواتير التي لم تصل بعد إلى الأجهزة الأخرى
  Future<void> _syncInvoices() async {
    setState(() => _isSyncingInvoices = true);
    try {
      final uploaded = await InvoiceSyncService().syncPendingInvoices();
      if (!mounted) return;

      final db = await DatabaseService().database;
      final remaining = Sqflite.firstIntValue(await db.rawQuery(
        "SELECT COUNT(*) FROM invoices WHERE is_synced = 0 AND invoice_uuid IS NOT NULL",
      )) ?? 0;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(remaining == 0
              ? 'تم رفع $uploaded فاتورة — لا توجد فواتير معلقة'
              : 'تم رفع $uploaded فاتورة، وبقيت $remaining فاتورة معلقة'),
          backgroundColor: remaining == 0 ? Colors.green : Colors.orange,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل رفع الفواتير: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncingInvoices = false);
    }
  }

  /// 🧾 اعتبار الفواتير القديمة مرفوعة (تخطي أرشيف ما قبل تفعيل المزامنة)
  Future<void> _markOldInvoicesAsSynced() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('اعتبار الفواتير القديمة مرفوعة'),
        content: const Text(
          'سيتم تعليم كل الفواتير الحالية على أنها مرفوعة، فلا تُرسل إلى الأجهزة '
          'الأخرى. استخدم هذا الخيار مرة واحدة عند بدء المزامنة لتجنب رفع الأرشيف '
          'كاملاً. الفواتير الجديدة بعد ذلك سترتفع تلقائياً.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isMarkingOldInvoices = true);
    try {
      final db = await DatabaseService().database;
      final count = await db.rawUpdate(
        'UPDATE invoices SET is_synced = 1 WHERE is_synced = 0',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم اعتبار $count فاتورة مرفوعة'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشلت العملية: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isMarkingOldInvoices = false);
    }
  }

  /// 🔧 إصلاح ورفع جميع البيانات
  Future<void> _repairAndSyncAll() async {
    // تأكيد قبل الإصلاح
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.build_circle, color: Colors.purple),
            SizedBox(width: 8),
            Text('إصلاح ورفع البيانات'),
          ],
        ),
        content: const Text(
          'سيتم:\n'
          '• إصلاح المعاملات التي ليس لها معرف مزامنة\n'
          '• رفع جميع العملاء والمعاملات إلى Firebase\n\n'
          'هذه العملية قد تستغرق بعض الوقت حسب حجم البيانات.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple,
              foregroundColor: Colors.white,
            ),
            child: const Text('بدء الإصلاح'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    setState(() {
      _isRepairing = true;
      _loadingProgress = 0.0;
      _loadingMessage = 'جاري بدء الإصلاح...';
    });
    
    try {
      // 🔄 محاولة التهيئة إذا لم تكن مكتملة
      if (_firebaseSync.status == FirebaseSyncStatus.notConfigured ||
          _firebaseSync.status == FirebaseSyncStatus.idle ||
          _firebaseSync.status == FirebaseSyncStatus.error) {
        if (mounted) {
          setState(() {
            _loadingProgress = 0.05;
            _loadingMessage = 'جاري تهيئة المزامنة...';
          });
        }
        final initSuccess = await _firebaseSync.initialize(
          onProgress: (progress, message) {
            if (mounted) {
              setState(() {
                _loadingProgress = 0.05 + (progress * 0.05); // 5% -> 10%
                _loadingMessage = message;
              });
            }
          }
        ).timeout(
          const Duration(minutes: 2),
          onTimeout: () => false,
        );
        if (!initSuccess) {
          throw Exception('فشلت تهيئة المزامنة - تأكد من الاتصال بالإنترنت');
        }
      }
      
      // المرحلة 1: البحث عن المعاملات بدون UUID (0-20%)
      if (mounted) {
        setState(() {
          _loadingProgress = 0.1;
          _loadingMessage = 'جاري تحضير البيانات...';
        });
      }
      await Future.delayed(const Duration(milliseconds: 200));
      
      final result = await _firebaseSync.repairAndSyncAllTransactions(
        onProgress: (current, total, message) {
          if (mounted) {
            setState(() {
              // تقسيم التقدم بين 0.1 و 0.9 بناءً على النسبة
              _loadingProgress = 0.1 + (0.8 * (current / (total > 0 ? total : 1)));
              _loadingMessage = message;
            });
          }
        },
      );
      
      // المرحلة 5: الانتهاء (95-100%)
      if (mounted) {
        setState(() {
          _loadingProgress = 1.0;
          _loadingMessage = 'اكتمل الإصلاح!';
        });
      }
      
      await Future.delayed(const Duration(milliseconds: 300));
      
      if (mounted) {
        if (result.containsKey('error')) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('فشل الرفع الشامل: ${result['error']}'),
              backgroundColor: Colors.red,
            ),
          );
        } else {
          final complete = result['success'] == true;

          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Row(
                children: [
                  Icon(complete ? Icons.check_circle : Icons.error,
                      color: complete ? Colors.green : Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(complete
                        ? 'اكتمل الرفع الشامل'
                        : 'الرفع الشامل غير مكتمل'),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildIntegrityRow('عملاء تم رفعهم',
                        '${result['uploadedCustomers'] ?? 0} / ${result['totalCustomers'] ?? 0}'),
                    _buildIntegrityRow('معاملات تم رفعها',
                        '${result['uploadedTransactions'] ?? 0} / ${result['expectedTransactions'] ?? 0}'),
                    _buildIntegrityRow('معرّفات تم إصلاحها', '${result['fixed'] ?? 0}'),
                    _buildIntegrityRow('أخطاء', '${result['errors'] ?? 0}'),
                    if ((result['txCountBefore'] ?? result['txCountAfter']) !=
                        null)
                      _buildIntegrityRow(
                        'عدد المعاملات قبل/بعد',
                        '${result['txCountBefore'] ?? '-'} → ${result['txCountAfter'] ?? '-'}',
                      ),
                    if (!complete) ...[
                      const Divider(),
                      const Text(
                        'أعد الضغط على «الرفع الشامل» بعد التأكد من الاتصال.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('حسناً'),
                ),
              ],
            ),
          );
        }
      }
      
      await _loadSettingsQuick();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل الإصلاح: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
    
    if (mounted) {
      setState(() {
        _isRepairing = false;
        _loadingProgress = 0.0;
        _loadingMessage = '';
      });
    }
  }
  
  /// 📱 عرض الأجهزة المتصلة
  Future<void> _showConnectedDevices() async {
    setState(() {
      _isLoadingDevices = true;
      _loadingProgress = 0.0;
      _loadingMessage = 'جاري جلب قائمة الأجهزة...';
    });
    
    try {
      // 📊 محاولة استخدام البيانات اللحظية أولاً
      List<Map<String, dynamic>> devices;
      
      if (_firebaseSync.statsListenersActive && _firebaseSync.liveDevices.isNotEmpty) {
        // ✅ البيانات متوفرة لحظياً — لا حاجة للانتظار
        devices = _firebaseSync.liveDevices;
        print('📊 تم جلب الأجهزة من الكاش اللحظي (${devices.length} جهاز)');
      } else {
        // 🔄 Fallback: جلب من Firebase مباشرة
        if (_firebaseSync.status == FirebaseSyncStatus.notConfigured ||
            _firebaseSync.status == FirebaseSyncStatus.idle ||
            _firebaseSync.status == FirebaseSyncStatus.error) {
          if (mounted) {
            setState(() {
              _loadingProgress = 0.1;
              _loadingMessage = 'جاري تهيئة المزامنة...';
            });
          }
          final initSuccess = await _firebaseSync.initialize(
            onProgress: (progress, message) {
              if (mounted) {
                setState(() {
                  _loadingProgress = 0.1 + (progress * 0.1);
                  _loadingMessage = message;
                });
              }
            }
          ).timeout(
            const Duration(minutes: 2),
            onTimeout: () => false,
          );
          if (!initSuccess) {
            throw Exception('فشلت تهيئة المزامنة - تأكد من الاتصال بالإنترنت');
          }
        }
        
        setState(() {
          _loadingProgress = 0.5;
          _loadingMessage = 'جاري جلب بيانات الأجهزة...';
        });
        
        devices = await _firebaseSync.getConnectedDevices();
      }
      final currentDeviceId = _firebaseSync.deviceId;
      
      // المرحلة 3: الانتهاء (80-100%)
      setState(() {
        _loadingProgress = 1.0;
        _loadingMessage = 'تم جلب البيانات!';
      });
      
      await Future.delayed(const Duration(milliseconds: 200));
      
      if (!mounted) return;
      
      // حساب عدد الأجهزة المتصلة فعلياً
      final onlineCount = devices.where((d) => d['isRealtimeSyncActive'] == true).length;
      
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.devices, color: Colors.teal),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('الأجهزة في المجموعة'),
                    Text(
                      '$onlineCount من ${devices.length} متصل الآن',
                      style: TextStyle(
                        fontSize: 12,
                        color: onlineCount > 0 ? Colors.green : Colors.grey,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: devices.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'لا توجد أجهزة مسجلة في هذه المجموعة',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: devices.length,
                    itemBuilder: (context, index) {
                      final device = devices[index];
                      final isCurrentDevice = device['isCurrentDevice'] == true;
                      final isOnline = device['isOnline'] == true;
                      final isRealtimeSyncActive = device['isRealtimeSyncActive'] == true;
                      final realtimeSyncStatus = device['realtimeSyncStatus'] as String? ?? 'غير معروف';
                      
                      // تحديد لون الحالة
                      Color statusColor;
                      IconData statusIcon;
                      if (isRealtimeSyncActive) {
                        statusColor = Colors.green;
                        statusIcon = Icons.sync;
                      } else if (isOnline) {
                        statusColor = Colors.orange;
                        statusIcon = Icons.sync_disabled;
                      } else {
                        statusColor = Colors.grey;
                        statusIcon = Icons.cloud_off;
                      }
                      
                      return Card(
                        color: isCurrentDevice ? Colors.teal.shade50 : null,
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // الصف الأول: اسم الجهاز وحالة الاتصال
                              Row(
                                children: [
                                  // أيقونة الجهاز مع نقطة الحالة
                                  Stack(
                                    children: [
                                      Icon(
                                        _getDeviceIcon(device['platform']),
                                        size: 36,
                                        color: isCurrentDevice ? Colors.teal : Colors.grey.shade600,
                                      ),
                                      Positioned(
                                        right: 0,
                                        bottom: 0,
                                        child: Container(
                                          width: 14,
                                          height: 14,
                                          decoration: BoxDecoration(
                                            color: statusColor,
                                            shape: BoxShape.circle,
                                            border: Border.all(color: Colors.white, width: 2),
                                          ),
                                          child: isRealtimeSyncActive
                                              ? const Icon(Icons.check, size: 8, color: Colors.white)
                                              : null,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(width: 12),
                                  // اسم الجهاز
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                device['deviceName'] ?? 'جهاز غير معروف',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                  color: isCurrentDevice ? Colors.teal.shade700 : null,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (isCurrentDevice) ...[
                                              const SizedBox(width: 8),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Colors.teal,
                                                  borderRadius: BorderRadius.circular(10),
                                                ),
                                                child: const Text(
                                                  'أنت',
                                                  style: TextStyle(color: Colors.white, fontSize: 9),
                                                ),
                                              ),
                                            ],
                                            if (device['isRetired'] == true) ...[
                                              const SizedBox(width: 8),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Colors.orange,
                                                  borderRadius: BorderRadius.circular(10),
                                                ),
                                                child: const Text(
                                                  'خارج الخدمة',
                                                  style: TextStyle(color: Colors.white, fontSize: 9),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _shortenDeviceId(device['deviceId']),
                                          style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // زر اعتبار الجهاز خارج الخدمة / إعادته
                                  if (!isCurrentDevice)
                                    IconButton(
                                      icon: Icon(
                                        device['isRetired'] == true
                                            ? Icons.play_circle_outline
                                            : Icons.power_settings_new,
                                        color: device['isRetired'] == true
                                            ? Colors.green
                                            : Colors.orange,
                                        size: 20,
                                      ),
                                      onPressed: () =>
                                          _confirmToggleRetireDevice(device),
                                      tooltip: device['isRetired'] == true
                                          ? 'إعادة الجهاز للخدمة'
                                          : 'اعتبار الجهاز خارج الخدمة',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                  // زر الحذف
                                  if (!isCurrentDevice)
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                      onPressed: () => _confirmRemoveDevice(device),
                                      tooltip: 'إزالة الجهاز',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              // الصف الثاني: حالة المزامنة
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: statusColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: statusColor.withOpacity(0.3)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(statusIcon, size: 16, color: statusColor),
                                    const SizedBox(width: 6),
                                    Text(
                                      realtimeSyncStatus,
                                      style: TextStyle(
                                        color: statusColor,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 6),
                              // الصف الثالث: آخر ظهور
                              Row(
                                children: [
                                  Icon(Icons.access_time, size: 12, color: Colors.grey.shade400),
                                  const SizedBox(width: 4),
                                  Text(
                                    'آخر نشاط: ${device['lastSeenFormatted'] ?? 'غير معروف'}',
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await _showConnectedDevices(); // تحديث القائمة
              },
              child: const Text('تحديث'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل جلب قائمة الأجهزة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
    
    setState(() {
      _isLoadingDevices = false;
      _loadingProgress = 0.0;
      _loadingMessage = '';
    });
  }
  
  /// الحصول على أيقونة الجهاز حسب المنصة
  IconData _getDeviceIcon(String? platform) {
    switch (platform?.toLowerCase()) {
      case 'windows':
        return Icons.desktop_windows;
      case 'macos':
        return Icons.desktop_mac;
      case 'linux':
        return Icons.computer;
      case 'android':
        return Icons.phone_android;
      case 'ios':
        return Icons.phone_iphone;
      default:
        return Icons.devices_other;
    }
  }
  
  /// اختصار معرف الجهاز
  String _shortenDeviceId(String? deviceId) {
    if (deviceId == null || deviceId.length < 8) return deviceId ?? '';
    return '${deviceId.substring(0, 8)}...';
  }
  
  /// تأكيد إزالة جهاز
  /// 🚫 اعتبار جهاز خارج الخدمة / إعادته للخدمة (قرار يدوي موثّق)
  ///
  /// الجهاز الخارج عن الخدمة لا يُطالَب بتأكيد قراءة (ACK)، فتتاح إزالة
  /// مستنداته القديمة من السحابة بعد قراءة بقية الأجهزة. استخدمه فقط
  /// لجهاز لن يعود (بِيع/تالف) — الجهاز الغائب مؤقتاً يبقى محفوظاً له.
  Future<void> _confirmToggleRetireDevice(Map<String, dynamic> device) async {
    final retiring = device['isRetired'] != true;
    final name = device['deviceName'] ?? 'جهاز غير معروف';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(retiring ? 'اعتبار الجهاز خارج الخدمة' : 'إعادة الجهاز للخدمة'),
        content: Text(
          retiring
              ? 'هل تريد اعتبار الجهاز "$name" خارج الخدمة نهائياً؟\n\n'
                  '• لن يُنتظر هذا الجهاز في مزامنة الحذف من السحابة.\n'
                  '• استخدم هذا الخيار فقط لجهاز بِيع أو تالف أو لن يعود.\n'
                  '• قرارك يُوثّق بالتاريخ، ويمكن التراجع عنه بإعادة الجهاز للخدمة.'
              : 'سيعود الجهاز "$name" للحساب ضمن أجهزة المزامنة، '
                  'وستُنتظر قراءته (ACK) قبل حذف أي بيانات من السحابة.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: retiring ? Colors.orange : Colors.green,
              foregroundColor: Colors.white,
            ),
            child: Text(retiring ? 'خارج الخدمة' : 'إعادة للخدمة'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await SmartPipeCleanupService()
          .setDeviceRetired(device['deviceId'] as String, retiring);
      // تحديث العرض المحلي فوراً
      setState(() => device['isRetired'] = retiring);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(retiring
                ? '🚫 اعتُبر "$name" خارج الخدمة (قرار موثّق بالتاريخ)'
                : '✅ أعيد "$name" للخدمة'),
            backgroundColor: retiring ? Colors.orange : Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ فشل تنفيذ العملية: $e')),
        );
      }
    }
  }

  Future<void> _confirmRemoveDevice(Map<String, dynamic> device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إزالة الجهاز'),
        content: Text(
          'هل تريد إزالة الجهاز "${device['deviceName']}" من المجموعة؟\n\n'
          'سيتم إزالة الجهاز من قائمة الأجهزة المتصلة فقط، '
          'ولن يؤثر ذلك على البيانات المزامنة.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('إزالة'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      Navigator.pop(context); // إغلاق نافذة الأجهزة
      
      final success = await _firebaseSync.removeDevice(device['deviceId']);
      
      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم إزالة الجهاز بنجاح'),
              backgroundColor: Colors.green,
            ),
          );
          // إعادة فتح نافذة الأجهزة
          await _showConnectedDevices();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('فشل إزالة الجهاز'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
  
  /// 📊 عرض إحصائيات التتبع والإقرار
  /// 📋 عرض قائمة العمليات الفاشلة (عملاء ومعاملات لم تصل للسحابة).
  /// كل عنصر يُظهر النوع، الاسم، المبلغ، عدد المحاولات، وآخر خطأ، مع زر
  /// "إعادة المحاولة" وزر "حذف" للتخلي عن العملية.
  Future<void> _showFailedOperations() async {
    if (!mounted) return;

    setState(() {
      _isLoadingTrackingStats = true;
      _loadingMessage = 'جاري جلب العمليات الفاشلة...';
    });

    List<Map<String, dynamic>> failed = [];
    try {
      failed = await _firebaseSync.getFailedSyncOperations();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل جلب العمليات الفاشلة: $e')),
        );
      }
    }

    if (!mounted) return;
    setState(() => _isLoadingTrackingStats = false);

    if (failed.isEmpty) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('المعاملات الفاشلة'),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 48),
              SizedBox(height: 12),
              Text('لا توجد عمليات فاشلة ✅'),
              SizedBox(height: 4),
              Text(
                'كل العملاء والمعاملات والفواتير وصلت إلى السحابة بنجاح.',
                style: TextStyle(fontSize: 13, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('حسنًا'),
            ),
          ],
        ),
      );
      return;
    }

    // عدّ العملاء والمعاملات.
    final customers = failed.where((f) => f['type'] == 'customer').length;
    final transactions = failed.where((f) => f['type'] == 'transaction').length;

    showDialog<void>(
      context: context,
      builder: (ctx) {
        bool isRetrying = false;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'العمليات الفاشلة (${failed.length})',
                      style: const TextStyle(fontSize: 18),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ملخص
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Text(
                        'عملاء فاشلون: $customers | معاملات فاشلة: $transactions\n'
                        'هذه العمليات ستُعاد محاولتها تلقائيًا، أو يمكنك إعادة المحاولة يدويًا.',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // القائمة
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: failed.length,
                        itemBuilder: (ctx, i) {
                          final op = failed[i];
                          final isCustomer = op['type'] == 'customer';
                          final name = op['name'] as String? ?? 'غير معروف';
                          final amount = op['amount'] as double?;
                          final retryCount = op['retryCount'] as int? ?? 0;
                          final lastError = op['lastError'] as String? ?? '';
                          return Card(
                            child: ListTile(
                              leading: Icon(
                                isCustomer ? Icons.person : Icons.receipt_long,
                                color: isCustomer
                                    ? Colors.blue
                                    : Colors.deepOrange,
                              ),
                              title: Text(
                                isCustomer
                                    ? 'عميل: $name'
                                    : 'معاملة: $name'
                                        '${amount != null ? ' (${amount.abs().toStringAsFixed(0)})' : ''}',
                              ),
                              subtitle: Text(
                                'المحاولات: $retryCount'
                                '${lastError.isNotEmpty ? '\nالخطأ: ${lastError.length > 60 ? lastError.substring(0, 60) + '...' : lastError}' : ''}',
                                style: const TextStyle(fontSize: 11),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.grey),
                                tooltip: 'حذف من القائمة',
                                onPressed: () async {
                                  await _firebaseSync
                                      .removeFailedOperation(
                                          op['syncUuid'] as String);
                                  setDialogState(() {
                                    failed.removeAt(i);
                                  });
                                },
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isRetrying
                      ? null
                      : () => Navigator.pop(ctx),
                  child: const Text('إغلاق'),
                ),
                ElevatedButton.icon(
                  icon: isRetrying
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: Text(isRetrying ? 'جاري إعادة المحاولة...' : 'إعادة محاولة الكل'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  onPressed: isRetrying
                      ? null
                      : () async {
                          setDialogState(() => isRetrying = true);
                          try {
                            final res = await _firebaseSync
                                .retryAllFailedOperations();
                            final remaining =
                                res['remaining'] as int? ?? 0;
                            failed = await _firebaseSync
                                .getFailedSyncOperations();
                            setDialogState(() {
                              isRetrying = false;
                            });
                            if (!ctx.mounted) return;
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(
                                content: Text(remaining == 0
                                    ? '✅ تم رفع كل العمليات الفاشلة بنجاح'
                                    : 'بقي $remaining عملية فاشلة (ستُعاد محاولتها تلقائيًا)'),
                              ),
                            );
                          } catch (e) {
                            setDialogState(() => isRetrying = false);
                          }
                        },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showTrackingStats() async {
    
    setState(() {
      _isLoadingTrackingStats = true;
      _loadingProgress = 0.0;
      _loadingMessage = 'جاري جلب الإحصائيات...';
    });
    
    try {
      // 🔄 محاولة التهيئة إذا لم تكن مكتملة
      if (_firebaseSync.status == FirebaseSyncStatus.notConfigured ||
          _firebaseSync.status == FirebaseSyncStatus.idle ||
          _firebaseSync.status == FirebaseSyncStatus.error) {
        setState(() {
          _loadingProgress = 0.05;
          _loadingMessage = 'جاري تهيئة المزامنة...';
        });
        final initSuccess = await _firebaseSync.initialize().timeout(
          const Duration(minutes: 2),
          onTimeout: () => false,
        );
        if (!initSuccess) {
          throw Exception('فشلت تهيئة المزامنة - تأكد من الاتصال بالإنترنت');
        }
      }
      
      // المرحلة 1: جلب إحصائيات التتبع (0-25%)
      setState(() {
        _loadingProgress = 0.15;
        _loadingMessage = 'جاري جلب إحصائيات التتبع...';
      });
      final trackerStats = await _firebaseSync.getOperationTrackerStats();
      
      // المرحلة 2: جلب ملخص التأكيدات (25-50%)
      setState(() {
        _loadingProgress = 0.35;
        _loadingMessage = 'جاري جلب ملخص التأكيدات...';
      });
      final ackSummary = await _firebaseSync.getAckSummary();
      
      // المرحلة 3: جلب التأكيدات المعلقة (50-70%)
      setState(() {
        _loadingProgress = 0.55;
        _loadingMessage = 'جاري جلب التأكيدات المعلقة...';
      });
      final pendingAcks = await _firebaseSync.getPendingAckTransactions();
      
      // المرحلة 4: جلب إحصائيات WAL (70-90%)
      setState(() {
        _loadingProgress = 0.75;
        _loadingMessage = 'جاري جلب إحصائيات الحماية...';
      });
      final walStats = await _firebaseSync.getWalRecoveryStats();
      final pendingWal = await _firebaseSync.getPendingWalOperationsCount();
      
      // المرحلة 5: الانتهاء (90-100%)
      setState(() {
        _loadingProgress = 1.0;
        _loadingMessage = 'تم جلب الإحصائيات!';
      });
      
      await Future.delayed(const Duration(milliseconds: 200));
      
      if (!mounted) return;
      
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: const [
              Icon(Icons.analytics, color: Colors.indigo),
              SizedBox(width: 8),
              Text('إحصائيات التتبع والإقرار'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 🛡️ قسم WAL (الحماية من الانقطاع)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.purple.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '🛡️ الحماية من الانقطاع (WAL)',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      _buildStatRow('العمليات المعلقة', '$pendingWal'),
                      _buildStatRow('إجمالي العمليات', '${walStats['totalOperations'] ?? 0}'),
                      _buildStatRow('العمليات المستردة', '${walStats['recoveredOperations'] ?? 0}'),
                      _buildStatRow('نقاط الاسترداد', '${walStats['activeCheckpoints'] ?? 0}'),
                    ],
                  ),
                ),
                
                const SizedBox(height: 12),
                
                // قسم تتبع العمليات
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '🔄 تتبع العمليات',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      _buildStatRow('العمليات المعلقة', '${trackerStats['pendingOperations'] ?? 0}'),
                      _buildStatRow('الكيانات المتتبعة', '${trackerStats['trackedEntities'] ?? 0}'),
                      _buildStatRow('سجلات العمليات', '${trackerStats['logEntries'] ?? 0}'),
                    ],
                  ),
                ),
                
                const SizedBox(height: 12),
                
                // قسم تأكيدات الاستلام
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '📬 تأكيدات الاستلام (ACK)',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      _buildStatRow('المعاملات المرسلة', '${ackSummary['sentTransactions'] ?? 0}'),
                      _buildStatRow('التأكيدات المستلمة', '${ackSummary['receivedAcks'] ?? 0}'),
                      _buildStatRow('في انتظار التأكيد', '${pendingAcks.length}'),
                    ],
                  ),
                ),
                
                if (pendingAcks.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.warning, color: Colors.orange, size: 18),
                            SizedBox(width: 8),
                            Text(
                              'معاملات لم يتم تأكيدها',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.orange,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'هناك ${pendingAcks.length} معاملة لم يتم تأكيد استلامها من الأجهزة الأخرى بعد.',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                // تنظيف السجلات القديمة
                final deletedAcks = await _firebaseSync.cleanupOldAcks();
                final deletedLogs = await _firebaseSync.cleanupOldOperationLogs();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('تم حذف $deletedAcks تأكيد و $deletedLogs سجل قديم'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              },
              child: const Text('تنظيف القديم'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل جلب الإحصائيات: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
    
    if (!mounted) return;
    setState(() {
      _isLoadingTrackingStats = false;
      _loadingProgress = 0.0;
      _loadingMessage = '';
    });
  }
}
