// lib/screens/firebase_sync_settings_screen.dart
// شاشة إعدادات المزامنة عبر Firebase مع حماية صارمة

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import '../services/firebase_sync/firebase_sync_config.dart';
import '../services/firebase_sync/sync_diagnostics.dart'; // 🩺
import 'package:firebase_auth/firebase_auth.dart';
import '../services/firebase_sync/firebase_sync_service.dart';
import 'package:sqflite/sqflite.dart';
import '../services/firebase_sync/firebase_custom_config.dart';
import '../services/firebase_sync/invoice_sync_service.dart';
import '../services/firebase_sync/smart_pipe_cleanup_service.dart';
import '../services/database_service.dart';
import 'firebase_custom_setup_screen.dart';
import 'reconciliation_screen.dart';
import 'web_hosting_guide_screen.dart';
import '../erp/erp_kit.dart' show ErpDialog;
import '../widgets/settings_kit.dart';

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
  bool _strictSignature = false;
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
    _strictSignature = await FirebaseSyncSecuritySettings.isStrictSignatureEnabled();
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
      child: SettingsScaffold(
        title: 'مزامنة الأجهزة',
        subtitle: 'Firebase — مزامنة فورية للديون والفواتير بين أجهزتك',
        icon: Icons.sync_rounded,
        maxWidth: 900,
        loading: _isLoading,
        actions: [
          IconButton(
            tooltip: 'إعدادات ربط Firebase',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FirebaseCustomSetupScreen()),
            ),
            icon: const Icon(Icons.settings_rounded),
          ),
        ],
        children: _isLoading
            ? null
            : [
                _buildStatusCard(),
                _buildSettingsCard(),
                if (_isEnabled) ...[
                  _buildStatsCard(),
                  _buildActionsCard(),
                  _buildSecuritySettingsCard(),
                  _buildConflictPolicyCard(),
                  _buildDangerCard(),
                ],
                _buildNotesCard(),
              ],
      ),
    );
  }

  static const _fbOrange = Color(0xFFEA580C);

  Widget _buildStatusCard() {
    final status = _firebaseSync.status;
    final (Color statusColor, String statusText, IconData statusIcon) = switch (status) {
      FirebaseSyncStatus.online => (kSetGreen, 'متصل ويستمع للتغييرات اللحظية', Icons.cloud_done_rounded),
      FirebaseSyncStatus.syncing => (kSetBlue, 'جارٍ المزامنة مع السحابة...', Icons.sync_rounded),
      FirebaseSyncStatus.offline => (kSetOrange, 'غير متصل — يعمل محلياً فقط', Icons.cloud_off_rounded),
      FirebaseSyncStatus.error => (kSetRed, 'خطأ في الاتصال بالمزامنة', Icons.error_rounded),
      FirebaseSyncStatus.disabled => (kSetMuted, 'المزامنة السحابية معطّلة', Icons.pause_circle_rounded),
      _ => (const Color(0xFF475569), 'غير مُعدّة بعد', Icons.settings_rounded),
    };
    return SetHero(
      icon: statusIcon,
      color: statusColor,
      title: statusText,
      text: _projectId == null
          ? 'اربط مشروع Firebase من «إعدادات ربط Firebase» ثم فعّل المزامنة.'
          : 'المشروع: $_projectId',
      status: Wrap(spacing: 8, runSpacing: 6, children: [
        SetStatusPill(_isEnabled ? 'المزامنة نشطة' : 'المزامنة معطّلة', ok: _isEnabled),
        if (_isEnabled && _syncStats?['lastSync'] != null)
          SetStatusPill('آخر مزامنة: ${_formatLastSync(_syncStats?['lastSync'])}',
              ok: true, icon: Icons.schedule_rounded),
      ]),
    );
  }

  /// 🩺 عرض بطاقة تشخيص المزامنة والمصادقة — أخطاء واضحة مترجمة
  Future<void> _showSyncDiagnostics() async {
    final snap = SyncDiagnostics.snapshot();
    final events = (snap['recentEvents'] as List).cast<String>().take(12).toList();

    await showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Row(children: [
            Icon(Icons.health_and_safety, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('🩺 حالة المزامنة والتشخيص'),
          ]),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                _diagRow('المنصة', snap['platform'] as String),
                _diagRow(
                    'المصادقة', snap['authenticated'] == true
                        ? '✅ نشطة (${snap['authUid']?.toString().substring(0, 12)}...)'
                        : '❌ غير نشطة'),
                if (snap['lastAuthError'] != null)
                  _diagBlock('آخر خطأ مصادقة', snap['lastAuthError'] as String),
                if (snap['lastListenerError'] != null)
                  _diagBlock('آخر خطأ مستمعي المزامنة', snap['lastListenerError'] as String),
                if (events.isNotEmpty) ...[
                  const Divider(),
                  const Text('آخر الأحداث:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  ...events.map((e) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(e,
                            style: const TextStyle(fontSize: 12, height: 1.5)),
                      )),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.build, size: 18),
              label: const Text('🔧 تشخيص وإصلاح فوري'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
              onPressed: () => _runInteractiveDiagnosis(context),
            ),
          ],
        ),
      ),
    );
  }


  /// 🔧 تشخيص وإصلاح تفاعلي: خطوات تظهر تباعاً + إنعاش تلقائي
  Future<void> _runInteractiveDiagnosis(BuildContext ctx) async {
    Navigator.pop(ctx); // أغلق حوار الحالة السابق

    final steps = <DiagStep>[];
    StateSetter? dlgSet;
    await showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (dialogCtx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('🔧 التشخيص والإصلاح الفوري'),
          content: SizedBox(
            width: double.maxFinite,
            child: StatefulBuilder(
              builder: (dialogCtx, setDlg) {
                dlgSet = setDlg;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: steps.isEmpty
                      ? [const Center(child: CircularProgressIndicator())]
                      : steps
                          .map((st) => Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                        st.detail.isEmpty
                                            ? Icons.hourglass_top
                                            : st.ok
                                                ? Icons.check_circle
                                                : Icons.cancel,
                                        color: st.detail.isEmpty
                                            ? Colors.grey
                                            : st.ok
                                                ? Colors.green
                                                : Colors.red,
                                        size: 20),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(st.name,
                                              style: const TextStyle(
                                                  fontWeight:
                                                      FontWeight.bold)),
                                          if (st.detail.isNotEmpty)
                                            Text(st.detail,
                                                style: const TextStyle(
                                                    fontSize: 12,
                                                    height: 1.4)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ))
                          .toList(),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      ),
    );

    // التنفيذ التدريجي — لا نحظر الحوار (يُحدَّث عبر setState الداخلي)
    // ignore: use_build_context_synchronously
    final results = await runFullDiagnosis(
      onStep: (st) {
        steps.add(st);
        try {
          dlgSet?.call(() {});
        } catch (_) {}
      },
    );
    try {
      dlgSet?.call(() {});
    } catch (_) {}

    // إنعاش فوري إن كانت المصادقة سليمة
    final authOk = results.length > 1 && results[1].ok;
    if (authOk) {
      try {
        await FirebaseSyncService().recoverNow();
        steps.add(DiagStep('الإنعاش التلقائي',
            ok: true, detail: 'مستمعون + سحب كامل أعيد تشغيلهم'));
      } catch (e) {
        steps.add(DiagStep('الإنعاش التلقائي', ok: false, detail: '$e'));
      }
    }
  }

  Widget _diagRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Text('$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
            Expanded(child: Text(value)),
          ],
        ),
      );

  Widget _diagBlock(String title, String body) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
            const SizedBox(height: 4),
            Text(body, style: const TextStyle(fontSize: 12.5, height: 1.6)),
          ],
        ),
      );

  Widget _buildSettingsCard() {
    return SetCard(
      title: 'المزامنة الفورية',
      icon: Icons.sync_rounded,
      color: _fbOrange,
      child: SetSwitch(
        title: 'تفعيل المزامنة التلقائية الحيّة',
        subtitle: _isEnabled
            ? 'مفعّلة — تتزامن الديون والفواتير تلقائياً عبر الأجهزة'
            : 'معطّلة — يعمل التطبيق في الوضع المحلي فقط',
        icon: Icons.bolt_rounded,
        color: _fbOrange,
        value: _isEnabled,
        onChanged: (value) => _toggleSync(value),
      ),
    );
  }

  Widget _buildStatsCard() {
    final pct = (_loadingProgress * 100).toInt();
    return SetCard(
      title: 'إحصائيات السحابة',
      icon: Icons.analytics_rounded,
      color: kSetBlue,
      trailing: _isLoadingStats
          ? Row(mainAxisSize: MainAxisSize.min, children: [
              Text('$pct%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _fbOrange)),
              const SizedBox(width: 8),
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: _loadingProgress > 0 ? _loadingProgress : null,
                  color: _fbOrange,
                  backgroundColor: const Color(0xFFFFEDD5),
                ),
              ),
              const SizedBox(width: 6),
            ])
          : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 12),
        if (_isLoadingStats && _syncStats == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _loadingProgress > 0 ? _loadingProgress : null,
                  minHeight: 8,
                  color: _fbOrange,
                  backgroundColor: const Color(0xFFFFEDD5),
                ),
              ),
              const SizedBox(height: 10),
              Text('$pct%', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: _fbOrange)),
              const SizedBox(height: 2),
              Text(_loadingMessage, textAlign: TextAlign.center, style: const TextStyle(color: kSetMuted, fontSize: 12)),
            ]),
          )
        else if (_syncStats?['error'] != null)
          SetBanner(
            _syncStats!['timeout'] == true ? 'انتهت مهلة التحميل — اضغط «مزامنة الآن»' : 'خطأ: ${_syncStats!['error']}',
            kind: SetBannerKind.warn,
          )
        else ...[
          LayoutBuilder(builder: (context, c) {
            final cols = c.maxWidth >= 520 ? 3 : 1;
            final w = (c.maxWidth - (cols - 1) * 10) / cols;
            return Wrap(spacing: 10, runSpacing: 10, children: [
              _statTile(w, Icons.people_alt_rounded, 'العملاء', '${_syncStats?['customersInCloud'] ?? 0}', kSetBlue),
              _statTile(w, Icons.swap_vert_rounded, 'المعاملات', '${_syncStats?['transactionsInCloud'] ?? 0}', kSetGreen),
              _statTile(w, Icons.receipt_long_rounded, 'الفواتير', '${_syncStats?['invoicesInCloud'] ?? 0}', _fbOrange),
            ]);
          }),
          const SizedBox(height: 12),
          _infoLine(Icons.cloud_outlined, 'معرّف المشروع', _projectId ?? 'غير متصل'),
          _infoLine(Icons.fingerprint_rounded, 'معرّف المصادقة', FirebaseAuth.instance.currentUser?.uid ?? 'غير مصادق'),
          _infoLine(Icons.schedule_rounded, 'آخر مزامنة', _formatLastSync(_syncStats?['lastSync'])),
        ],
        const SizedBox(height: 14),
        _buildActionButton(
          icon: Icons.sync_rounded,
          label: 'مزامنة الآن',
          isLoading: _isSyncing,
          progress: _isSyncing ? _loadingProgress : null,
          message: _isSyncing ? _loadingMessage : null,
          color: _fbOrange,
          onPressed: _isSyncing ? null : _performManualSync,
          isPrimary: true,
        ),
      ]),
    );
  }

  Widget _statTile(double width, IconData icon, String label, String value, Color c) => Container(
        width: width,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.withValues(alpha: 0.18)),
        ),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(11)),
            child: Icon(icon, color: c, size: 21),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 12, color: kSetMuted)),
              Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c)),
            ]),
          ),
        ]),
      );

  Widget _infoLine(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Icon(icon, size: 17, color: kSetMuted),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 13, color: kSetMuted)),
          const SizedBox(width: 10),
          Expanded(
            child: SelectableText(
              value,
              maxLines: 1,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: kSetText),
            ),
          ),
        ]),
      );

  /// أدوات المزامنة مجمّعة حسب الغرض بدل عمود طويل من الأزرار.
  Widget _buildActionsCard() {
    Widget group(String title, List<Widget> tiles) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Text(title, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: kSetMuted)),
          ),
          LayoutBuilder(builder: (context, c) {
            final cols = c.maxWidth >= 600 ? 2 : 1;
            final w = (c.maxWidth - (cols - 1) * 10) / cols;
            return Wrap(spacing: 10, runSpacing: 10, children: [for (final t in tiles) SizedBox(width: w, child: t)]);
          }),
        ]);

    return SetCard(
      title: 'أدوات المزامنة',
      subtitle: 'رفع، تشخيص، ومراقبة الأجهزة',
      icon: Icons.build_circle_outlined,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        group('الرفع والإصلاح', [
          _buildActionButton(
            icon: Icons.cloud_upload_rounded,
            label: 'الرفع الشامل',
            subtitle: 'إصلاح معرّفات المزامنة ورفع كل العملاء والمعاملات',
            isLoading: _isRepairing,
            progress: _isRepairing ? _loadingProgress : null,
            message: _isRepairing ? _loadingMessage : null,
            color: kSetBlue,
            onPressed: _isRepairing ? null : _repairAndSyncAll,
          ),
          _buildActionButton(
            icon: Icons.receipt_long_rounded,
            label: 'رفع الفواتير المعلقة',
            subtitle: 'الفواتير التي لم تصل إلى السحابة بعد',
            isLoading: _isSyncingInvoices,
            color: const Color(0xFF4F46E5),
            onPressed: _isSyncingInvoices ? null : _syncInvoices,
          ),
          _buildActionButton(
            icon: Icons.done_all_rounded,
            label: 'اعتبار الفواتير القديمة مرفوعة',
            subtitle: 'مرة واحدة عند البدء لتجنّب رفع الأرشيف كاملاً',
            isLoading: _isMarkingOldInvoices,
            color: const Color(0xFF475569),
            onPressed: _isMarkingOldInvoices ? null : _markOldInvoicesAsSynced,
          ),
        ]),
        group('التشخيص والمراقبة', [
          _buildActionButton(
            icon: Icons.health_and_safety_rounded,
            label: 'حالة المزامنة والتشخيص',
            subtitle: 'أخطاء المصادقة والمستمعين بلغة واضحة',
            isLoading: false,
            color: const Color(0xFFDC2626),
            onPressed: () => _showSyncDiagnostics(),
          ),
          _buildActionButton(
            icon: Icons.rule_rounded,
            label: 'المطابقة بين الأجهزة',
            subtitle: 'مقارنة الأرصدة والسجلات بين الأجهزة',
            isLoading: false,
            color: const Color(0xFF7C3AED),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReconciliationScreen())),
          ),
          _buildActionButton(
            icon: Icons.devices_rounded,
            label: 'الأجهزة المتصلة',
            subtitle: 'الأجهزة في المجموعة وحالة كل منها',
            isLoading: _isLoadingDevices,
            color: const Color(0xFF9333EA),
            onPressed: _isLoadingDevices ? null : _showConnectedDevices,
          ),
          _buildActionButton(
            icon: Icons.error_outline_rounded,
            label: 'المعاملات الفاشلة',
            subtitle: 'العمليات التي لم تكتمل ومحاولات إعادتها',
            isLoading: _isLoadingTrackingStats,
            color: kSetRed,
            onPressed: _isLoadingTrackingStats ? null : _showFailedOperations,
          ),
        ]),
        group('الإعداد', [
          _buildActionButton(
            icon: Icons.settings_rounded,
            label: 'إعدادات ربط Firebase',
            subtitle: 'المشروع المخصّص وسرّ المجموعة',
            isLoading: false,
            color: const Color(0xFF0F766E),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FirebaseCustomSetupScreen()),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _buildDangerCard() {
    return SetCard(
      title: 'منطقة الخطر',
      subtitle: 'عمليات لا يمكن التراجع عنها',
      icon: Icons.warning_amber_rounded,
      color: kSetRed,
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: _buildActionButton(
          icon: Icons.delete_forever_rounded,
          label: 'حذف قاعدة البيانات السحابية بالكامل',
          subtitle: 'تُحذف بيانات المجموعة من السحابة — البيانات المحلية تبقى',
          isLoading: _isCleaning,
          progress: _isCleaning ? _loadingProgress : null,
          message: _isCleaning ? _loadingMessage : null,
          color: const Color(0xFF991B1B),
          onPressed: _isCleaning ? null : _deleteCloudDatabase,
        ),
      ),
    );
  }

  /// زر إجراء: الأساسي = زر عريض مملوء، والبقية = بطاقة صغيرة بأيقونة وشرح وتقدّم.
  Widget _buildActionButton({
    required IconData icon,
    required String label,
    String? subtitle,
    required bool isLoading,
    double? progress,
    String? message,
    required Color color,
    required VoidCallback? onPressed,
    bool isPrimary = false,
  }) {
    final pctLabel = isLoading && progress != null ? ' (${(progress * 100).toInt()}%)' : '';
    if (isPrimary) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: color, minimumSize: const Size(0, 50)),
          onPressed: onPressed,
          icon: isLoading
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, value: progress, color: Colors.white),
                )
              : Icon(icon, size: 20),
          label: Text('$label$pctLabel', style: const TextStyle(fontSize: 15)),
        ),
        if (isLoading && message != null && message.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: kSetMuted)),
          ),
      ]);
    }

    final enabled = onPressed != null;
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: isLoading ? color.withValues(alpha: 0.5) : kSetBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        hoverColor: color.withValues(alpha: 0.05),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(11)),
                child: isLoading
                    ? Padding(
                        padding: const EdgeInsets.all(10),
                        child: CircularProgressIndicator(strokeWidth: 2, value: progress, color: color),
                      )
                    : Icon(icon, size: 21, color: enabled ? color : kSetMuted),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('$label$pctLabel',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: enabled || isLoading ? kSetText : kSetMuted)),
                  if (subtitle != null)
                    Text(subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: kSetMuted, height: 1.35)),
                ]),
              ),
            ]),
            if (isLoading) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 5,
                  color: color,
                  backgroundColor: color.withValues(alpha: 0.12),
                ),
              ),
              if (message != null && message.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(message, style: TextStyle(fontSize: 11.5, color: color)),
                ),
            ],
          ]),
        ),
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
    Widget daysChips(List<int> options, int value, ValueChanged<int> onPick, Color c) => Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final d in options)
              ChoiceChip(
                label: Text('$d يوم'),
                selected: value == d,
                showCheckmark: false,
                selectedColor: c.withValues(alpha: 0.12),
                side: BorderSide(color: value == d ? c : kSetBorder),
                labelStyle: TextStyle(fontWeight: FontWeight.w700, color: value == d ? c : kSetText),
                onSelected: (_) => onPick(d),
              ),
          ],
        );
    const ttlOptions = [30, 60, 90, 180, 365, 730];

    return SetCard(
      title: 'إعدادات الأمان',
      subtitle: 'حماية البيانات المتزامنة من الأخطاء والتلاعب',
      icon: Icons.security_rounded,
      color: kSetGreen,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SetSwitch(
          title: 'رفض المعاملات القديمة',
          subtitle: _rejectOldTransactions
              ? 'تُرفض المعاملات الأقدم من $_maxTransactionAgeDays يوم'
              : 'قبول جميع المعاملات بغض النظر عن تاريخها',
          icon: Icons.history_rounded,
          color: kSetGreen,
          value: _rejectOldTransactions,
          onChanged: (value) async {
            await FirebaseSyncSecuritySettings.setRejectOldTransactionsEnabled(value);
            if (mounted) setState(() => _rejectOldTransactions = value);
          },
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: AlignmentDirectional.topStart,
          child: !_rejectOldTransactions
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsetsDirectional.only(start: 50, bottom: 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('الحد الأقصى لعمر المعاملة', style: TextStyle(fontSize: 12.5, color: kSetMuted)),
                    const SizedBox(height: 6),
                    daysChips(const [7, 14, 30, 60, 90], _maxTransactionAgeDays, (v) async {
                      await FirebaseSyncSecuritySettings.setMaxTransactionAgeDays(v);
                      if (mounted) setState(() => _maxTransactionAgeDays = v);
                    }, kSetGreen),
                  ]),
                ),
        ),
        const Divider(height: 20),
        Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: kSetOrange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.auto_delete_rounded, size: 19, color: kSetOrange),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('الحذف التلقائي للبيانات القديمة (TTL)',
                  style: TextStyle(fontWeight: FontWeight.w700, color: kSetText)),
              Text('تُحذف البيانات الأقدم من $_autoDeleteDays يوم نهائياً من السحابة لتوفير المساحة.',
                  style: const TextStyle(fontSize: 12.5, color: kSetMuted, height: 1.4)),
            ]),
          ),
        ]),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 50, top: 8, bottom: 6),
          child: daysChips(ttlOptions, ttlOptions.contains(_autoDeleteDays) ? _autoDeleteDays : 90, (v) async {
            await FirebaseSyncSecuritySettings.setAutoDeleteDays(v);
            if (mounted) setState(() => _autoDeleteDays = v);
          }, kSetOrange),
        ),
        const Divider(height: 20),
        SetSwitch(
          title: 'التحقق من الأرصدة بعد المزامنة',
          subtitle: _postSyncVerification
              ? 'يُتحقَّق من صحة الأرصدة بعد كل مزامنة'
              : 'لن يُتحقَّق من الأرصدة تلقائياً',
          icon: Icons.account_balance_wallet_rounded,
          color: kSetGreen,
          value: _postSyncVerification,
          onChanged: (value) async {
            await FirebaseSyncSecuritySettings.setPostSyncVerificationEnabled(value);
            if (mounted) setState(() => _postSyncVerification = value);
          },
        ),
        const Divider(height: 20),
        SetSwitch(
          title: 'رفض البيانات غير الموقّعة (الوضع الصارم)',
          subtitle: _strictSignature
              ? 'يُرفض أي مستند لم يوقَّع بسرّ المجموعة — يحمي من الكتابة المزوّرة'
              : 'تُقبل البيانات غير الموقّعة (للتوافق مع الأجهزة القديمة)',
          icon: Icons.verified_user_rounded,
          color: kSetGreen,
          value: _strictSignature,
          onChanged: _onStrictSignatureChanged,
        ),
      ]),
    );
  }

  /// 🔐 الوضع الصارم للتوقيع: رفض أي بيانات لم توقَّع بسرّ المجموعة
  Future<void> _onStrictSignatureChanged(bool value) async {
    if (value) {
      // 🛡️ لا نفعّله إن كان جهاز لا يشارك نفس السرّ: كانت بياناته
      // ستُرفض بصمت وتفترق الأرصدة.
      List<String> mismatched;
      try {
        mismatched = await _firebaseSync.devicesWithMismatchedSecret();
      } catch (e) {
        if (!mounted) return;
        setToast(context, 'تعذّر التحقق من أسرار الأجهزة (يلزم اتصال): $e', error: true);
        return;
      }
      if (mismatched.isNotEmpty) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => ErpDialog(
            title: 'لا يمكن التفعيل الآن',
            subtitle: 'أجهزة لا تشارك نفس سرّ المجموعة أو لم تُحدَّث بعد',
            icon: Icons.gpp_maybe_rounded,
            color: kSetOrange,
            content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final d in mismatched)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [
                    const Icon(Icons.computer_rounded, size: 18, color: kSetOrange),
                    const SizedBox(width: 8),
                    Expanded(child: Text(d, style: const TextStyle(fontWeight: FontWeight.w700))),
                  ]),
                ),
              const SizedBox(height: 8),
              const SetBanner(
                'أدخل نفس السرّ عليها (إعداد Firebase المخصص) وحدّثها، ثم افتحها مرة واحدة متصلة، ثم أعد المحاولة.',
              ),
            ]),
            actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('حسناً'))],
          ),
        );
        return;
      }
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => ErpDialog(
          title: 'تفعيل الوضع الصارم',
          icon: Icons.verified_user_rounded,
          color: kSetGreen,
          content: const Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SetSteps([
              'حدّث كل الأجهزة إلى هذه النسخة.',
              'أدخل نفس سرّ المجموعة على كل الأجهزة.',
            ], color: kSetGreen),
            SizedBox(height: 6),
            SetBanner(
              'وإلا ستُرفض بيانات أي جهاز يختلف سرّه، ولن تصل معاملاته إلى هذا الجهاز حتى يُصحَّح السرّ.',
              kind: SetBannerKind.warn,
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: kSetGreen),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('تفعيل'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    await FirebaseSyncSecuritySettings.setStrictSignatureEnabled(value);
    if (mounted) setState(() => _strictSignature = value);
  }

  /// 🔀 بطاقة سياسة معالجة تعارض حذف العملاء
  Widget _buildConflictPolicyCard() {
    Widget option({
      required CustomerConflictPolicy value,
      required String title,
      required String text,
      required IconData icon,
      required Color color,
      String? badge,
    }) {
      final selected = _customerConflictPolicy == value;
      return Material(
        color: selected ? color.withValues(alpha: 0.06) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: selected ? color : kSetBorder, width: selected ? 1.6 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () async {
            await FirebaseSyncSecuritySettings.setCustomerConflictPolicy(value);
            if (mounted) setState(() => _customerConflictPolicy = value);
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: selected ? color : color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 21, color: selected ? Colors.white : color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: selected ? color : kSetText)),
                    if (badge != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                        child: Text(badge, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w800)),
                      ),
                  ]),
                  const SizedBox(height: 4),
                  Text(text, style: const TextStyle(fontSize: 12.5, color: kSetMuted, height: 1.5)),
                ]),
              ),
              const SizedBox(width: 8),
              Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                  color: selected ? color : const Color(0xFFB8C2CF)),
            ]),
          ),
        ),
      );
    }

    return SetCard(
      title: 'سياسة تعارض حذف العملاء',
      subtitle: 'إذا حُذف عميل من جهاز بينما أضاف جهاز آخر (بلا إنترنت) فاتورة أو ديناً له',
      icon: Icons.alt_route_rounded,
      color: const Color(0xFF0F766E),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 12),
        option(
          value: CustomerConflictPolicy.smartReactivate,
          title: 'إعادة التنشيط الذكي',
          badge: 'موصى به',
          text: 'يُعاد تنشيط العميل تلقائياً ويُسجَّل عليه فقط مبلغ المعاملة الجديدة التي أُنشئت أوفلاين، '
              'مع إبقاء ديونه القديمة المحذوفة ملغاة ومصفّرة.',
          icon: Icons.auto_awesome_rounded,
          color: const Color(0xFF0F766E),
        ),
        const SizedBox(height: 10),
        option(
          value: CustomerConflictPolicy.strictDelete,
          title: 'الحذف الصارم',
          text: 'قرار الحذف نهائي: تُلغى أي فاتورة أو حركة أُضيفت للعميل أثناء انقطاع الإنترنت لمنع أي حركة غير مصرّح بها.',
          icon: Icons.delete_forever_rounded,
          color: kSetRed,
        ),
      ]),
    );
  }

  Widget _buildNotesCard() {
    return SetCard(
      title: 'ملاحظات مهمة',
      icon: Icons.lightbulb_outline_rounded,
      color: kSetBlue,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 10),
        for (final n in const [
          'المزامنة تتم تلقائياً في الخلفية.',
          'يعمل التطبيق بدون إنترنت ويزامن عند عودة الاتصال.',
          'كل مجموعة مستقلة تماماً عن الأخرى.',
          'تغيير المجموعة يتطلب تأكيداً صارماً.',
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(
                padding: EdgeInsets.only(top: 3),
                child: Icon(Icons.check_circle_rounded, size: 16, color: kSetBlue),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(n, style: const TextStyle(fontSize: 13, color: kSetText, height: 1.5))),
            ]),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48), foregroundColor: const Color(0xFF0369A1)),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const WebHostingGuideScreen()),
          ),
          icon: const Icon(Icons.language_rounded, size: 20),
          label: const Text('دليل واستضافة نسخة المتصفح (Web App)'),
        ),
      ]),
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
    
    final sw = Stopwatch()..start();
    debugPrint('⏱️ [_performManualSync/UI] ▶️ ═══════════════════════════════════════');
    debugPrint('⏱️ [_performManualSync/UI] ▶️ المستخدم ضغط على زر مزامنة الآن...');
    
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
        var swStep = Stopwatch()..start();
        debugPrint('⏱️ [_performManualSync/UI] 🔧 بدء التهيئة...');
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
        debugPrint('⏱️ [_performManualSync/UI] 🔧 انتهت التهيئة في ${swStep.elapsedMilliseconds}ms | النتيجة: ${initSuccess ? "نجاح" : "فشل"}');
        if (!initSuccess) {
          throw Exception('فشلت تهيئة المزامنة - تأكد من الاتصال بالإنترنت');
        }
      }
      
      // استخدام callback للتقدم
      var swSync = Stopwatch()..start();
      debugPrint('⏱️ [_performManualSync/UI] 🔄 بدء performFullSync...');
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
      debugPrint('⏱️ [_performManualSync/UI] 🔄 انتهت performFullSync في ${swSync.elapsedMilliseconds}ms (${(swSync.elapsedMilliseconds / 1000).toStringAsFixed(1)}s)');
      
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
      
      sw.stop();
      debugPrint('⏱️ [_performManualSync/UI] ⏹️ ═══════════════════════════════════════');
      debugPrint('⏱️ [_performManualSync/UI] ⏹️ إجمالي وقت العملية: ${sw.elapsedMilliseconds}ms (${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)}s)');
      debugPrint('⏱️ [_performManualSync/UI] ⏹️ ═══════════════════════════════════════');
      
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
        title: const Row(
          children: [
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
                        'الرصيد المسجل: ${intl.NumberFormat('#,##0.##', 'en_US').format((issue['recordedBalance'] as num?) ?? 0)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text(
                        'الرصيد المحسوب: ${intl.NumberFormat('#,##0.##', 'en_US').format((issue['calculatedBalance'] as num?) ?? 0)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text(
                        'الفرق: ${intl.NumberFormat('#,##0.##', 'en_US').format((issue['difference'] as num?) ?? 0)}',
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
        title: const Row(
          children: [
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

      if (!mounted) return;
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
        title: const Row(
          children: [
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
        debugPrint('📊 تم جلب الأجهزة من الكاش اللحظي (${devices.length} جهاز)');
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
                                  color: statusColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
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
      if (mounted) Navigator.pop(context); // إغلاق نافذة الأجهزة
      
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
                                        '${amount != null ? ' (${intl.NumberFormat('#,##0', 'en_US').format(amount.abs())})' : ''}',
                              ),
                              subtitle: Text(
                                'المحاولات: $retryCount'
                                '${lastError.isNotEmpty ? '\nالخطأ: ${lastError.length > 60 ? '${lastError.substring(0, 60)}...' : lastError}' : ''}',
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

}
