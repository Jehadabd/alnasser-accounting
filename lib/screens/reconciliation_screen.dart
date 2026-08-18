// lib/screens/reconciliation_screen.dart
//
// 📡 الشاشة التفاعلية التكيفية للمطابقة الحية بين الأجهزة (Live Reconciliation)
// تتيح للمستخدم تحديد العملاء وتحديد ما إذا كانت بيانات هذا الجهاز هي الصحيحة أم بيانات الجهاز الآخر،
// مع التنسيق التلقائي والتفاعل البشري الإنساني وتنظيف مجلدات السحابة فور الانتهاء.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../services/firebase_sync/live_match_service.dart';
import '../services/firebase_sync/armored_reconciliation_service.dart';

class ReconciliationScreen extends StatefulWidget {
  const ReconciliationScreen({super.key});

  @override
  State<ReconciliationScreen> createState() => _ReconciliationScreenState();
}

class _ReconciliationScreenState extends State<ReconciliationScreen> {
  final LiveMatchService _live = LiveMatchService();
  final NumberFormat _money = NumberFormat('#,##0.##');

  StreamSubscription<LiveMatchSnapshot>? _subSnap;
  StreamSubscription<String>? _subPeerNotify;
  LiveMatchSnapshot? _snap;
  String _progress = '';
  bool _busy = false;
  Timer? _pollTimer;

  // 🎯 العملاء المحدّدون بالـ Checkbox للمطابقة الجماعية
  final Set<String> _selectedUuids = {};

  // ⏳ العملاء الجاري معالجتهم حياً (لإظهار مؤشر التحميل لكل كارت)
  final Set<String> _busyCustomerUuids = {};

  @override
  void initState() {
    super.initState();
    _live.start();

    // 📡 1) الاستماع للقطات المطابقة الحية
    _subSnap = _live.snapshots.listen((s) {
      if (mounted) {
        setState(() {
          _snap = s;
          // تنظيف التحديدات والحسابات المشغولة التي تم تطبيقها وتمت مطابقتها بنجاح
          final validMismatches = s.mismatches.map((m) => m.customerSyncUuid).toSet();
          _selectedUuids.removeWhere((id) => !validMismatches.contains(id));
          _busyCustomerUuids.removeWhere((id) => !validMismatches.contains(id));
        });
      }
    });

    // 📩 2) الاستماع للإشعارات التفاعلية الواردة من الأجهزة الأخرى
    _subPeerNotify = _live.onPeerNotification.listen((msg) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: const Color(0xFF6C63FF),
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    });

    unawaited(_live.recompute());
  }

  @override
  void dispose() {
    _subSnap?.cancel();
    _subPeerNotify?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  /// 📡 إرسال طلب المطابقة الحية
  Future<void> _requestMatch() async {
    setState(() {
      _busy = true;
      _progress = 'جاري الاتصال ودعوة الأجهزة القريبة...';
    });
    try {
      await _live.recompute();
      final id = await _live.requestLiveMatch();
      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(const Duration(seconds: 2), (t) async {
        if (!mounted) {
          t.cancel();
          return;
        }
        final status = await _live.evaluateSession(id);
        if (status == 'cancelled' || status == 'expired' || status == 'ended') {
          t.cancel();
        }
        await _live.recompute();
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('📡 تم إرسال طلب المطابقة الحية. بانتظار موافقة الجهاز الآخر...'),
          backgroundColor: Color(0xFF4A90E2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = '';
        });
      }
    }
  }

  /// 🧹 إنهاء الجلسة وتنظيف مجلدات المطابقة المؤقتة في السحابة
  Future<void> _endSessionAndClean() async {
    setState(() {
      _busy = true;
      _progress = 'جاري إنهاء الجلسة وتنظيف السحابة...';
    });
    try {
      await _live.endSession();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ تم إنهاء الجلسة وتنظيف المجلدات المؤقتة من السحابة بنجاح!'),
          backgroundColor: Colors.green,
        ),
      );
    } finally {
      if (mounted) setState(() { _busy = false; _progress = ''; });
    }
  }

  // 📤 اعتماد بيانات هذا الجهاز للمحددين (إرسال وتحديث الجهاز الآخر)
  Future<void> _resolveSelectedMineIsTruth(List<LiveCustomerMatch> mismatches) async {
    final targetUuids = _selectedUuids.isEmpty
        ? mismatches.map((m) => m.customerSyncUuid).toSet()
        : Set<String>.from(_selectedUuids);

    if (targetUuids.isEmpty) return;

    final peerName = _snap?.peerDeviceName ?? 'الجهاز الآخر';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.upload_rounded, color: Colors.green),
              SizedBox(width: 8),
              Text('تأكيد واعتماد بيانات جهازي'),
            ],
          ),
          content: Text(
            'هل أنت متأكد أن حسابات العملاء المحددين (${targetUuids.length}) في هذا الجهاز هي الصحيحة والدقيقة؟\n\n'
            '• سيتم إرسال كافة معاملاتهم وتحديث بياناتهم لدى «$peerName» دون حذف أي سجل محلي.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.check_circle),
              label: const Text('نعم، بياناتي هي الصحيحة'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _busy = true;
      _busyCustomerUuids.addAll(targetUuids);
      _progress = 'جاري رفع واعتماد بيانات العملاء المحددين...';
    });

    try {
      // 🛡️ المطابقة المحصّنة المغلقة: رفع الكشف الكامل → الطرف الآخر يطبّق
      //    إدمبوتنت → يرد برصيده → نتحقق من التطابق → حذف فوري من فولدر المطابقة.
      final armored = ArmoredReconciliationService();
      int done = 0, success = 0;
      for (final uuid in targetUuids) {
        if (mounted) {
          setState(() => _progress =
              'جاري مطابقة العميل ${done + 1}/${targetUuids.length}...');
        }
        final ok = await armored.pushMyTruthForCustomer(uuid);
        if (ok) success++;
        done++;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: success == targetUuids.length
              ? Text('✅ تمت مطابقة ${targetUuids.length} عميل مع «$peerName» '
                  'وتأكيد التطابق — ونُظّف فولدر المطابقة!')
              : Text('⚠️ نجحت مطابقة $success من ${targetUuids.length} — '
                  'راجع الرسائل لمعرفة غير المتطابق'),
          backgroundColor: success == targetUuids.length ? Colors.green : Colors.orange,
        ),
      );
      setState(() => _selectedUuids.clear());
    } finally {
      if (mounted) setState(() { _busy = false; _progress = ''; });
    }
  }

  // 📥 اعتماد بيانات الجهاز الآخر للمحددين (تطبيق الفروقات)
  Future<void> _resolveSelectedPeerIsTruth(List<LiveCustomerMatch> mismatches) async {
    final targetUuids = _selectedUuids.isEmpty
        ? mismatches.map((m) => m.customerSyncUuid).toSet()
        : Set<String>.from(_selectedUuids);

    if (targetUuids.isEmpty) return;

    final peerName = _snap?.peerDeviceName ?? 'الجهاز الآخر';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.download_rounded, color: Color(0xFF4A90E2)),
              SizedBox(width: 8),
              Text('تأكيد اعتماد بيانات الجهاز الآخر'),
            ],
          ),
          content: Text(
            'هل تريد تسوية رصيد العملاء المحددين (${targetUuids.length}) بناءً على حسابات «$peerName»؟\n\n'
            '• سيتم إرسال طلب حي للجهاز الآخر لرفع كشوفاتهم فوراً لربطها واحتسابها محلياً دون حذف أي سجل.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4A90E2), foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.check_circle),
              label: const Text('نعم، اعتمد بيانات الجهاز الآخر'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _busy = true;
      _busyCustomerUuids.addAll(targetUuids);
      _progress = 'جاري إرسال طلب لـ «$peerName» وتحديث الحسابات...';
    });

    try {
      // 🛡️ المطابقة المحصّنة (truth_pull): نطلب كشف العميل من «$peerName»،
      //    يرفعه فوراً، نطبّقه محلياً إدمبوتنت (بدون معاملات تصحيحية وهمية)،
      //    نتحقق من تطابق رصيدنا مع الرصيد المرجعي، ثم نحذف فولدر المطابقة.
      final armored = ArmoredReconciliationService();
      int done = 0, success = 0;
      for (final uuid in targetUuids) {
        if (mounted) {
          setState(() => _progress =
              'جاري طلب كشف العميل ${done + 1}/${targetUuids.length} من «$peerName»...');
        }
        final ok = await armored.pullPeerTruthForCustomer(uuid);
        if (ok) success++;
        done++;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: success == targetUuids.length
              ? Text('✅ تم استلام كشوف ${targetUuids.length} عميل من «$peerName» '
                  'وتطبيقها والتأكد من التطابق!')
              : Text('⚠️ نجح $success من ${targetUuids.length} — تأكد أن الجهاز '
                  'الآخر متصل وفعّل المطابقة'),
          backgroundColor: success == targetUuids.length ? Colors.green : Colors.orange,
        ),
      );
    } finally {
      if (mounted) setState(() { _busy = false; _progress = ''; });
    }
  }

  // 👤 إجراء فردي لعميل واحد: بياناتنا صحيحة
  Future<void> _resolveSingleMineIsTruth(LiveCustomerMatch customer) async {
    final uuid = customer.customerSyncUuid;
    setState(() => _busyCustomerUuids.add(uuid));
    try {
      await _resolveSelectedMineIsTruth([customer]);
    } finally {
      if (mounted) setState(() => _busyCustomerUuids.remove(uuid));
    }
  }

  // 👤 إجراء فردي لعميل واحد: الجهاز الآخر صحيح
  Future<void> _resolveSinglePeerIsTruth(LiveCustomerMatch customer) async {
    final uuid = customer.customerSyncUuid;
    setState(() => _busyCustomerUuids.add(uuid));
    try {
      await _resolveSelectedPeerIsTruth([customer]);
    } finally {
      if (mounted) setState(() => _busyCustomerUuids.remove(uuid));
    }
  }

  @override
  Widget build(BuildContext context) {
    final snap = _snap;
    final peerName = snap?.peerDeviceName ?? 'الجهاز الآخر';
    final onlineDevices = snap?.onlineDevices ?? [];
    final mismatches = snap?.mismatches ?? [];
    final allCustomers = snap?.customers ?? [];
    final matchedCustomers = allCustomers.where((c) => c.isMatch).toList();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FB),
        appBar: AppBar(
          title: const Text('المطابقة الحية بين الأجهزة'),
          centerTitle: true,
          backgroundColor: const Color(0xFF1E1E2E),
          elevation: 2,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'تحديث الحسابات',
              onPressed: _busy ? null : () => unawaited(_live.recompute()),
            ),
          ],
        ),
        body: Column(
          children: [
            // 📡 شريط حالة الاتصال والتقدم
            if (_progress.isNotEmpty)
              Container(
                color: Colors.amber.shade700,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _progress,
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  // 📱 كارت حالة الجلسة والأجهزة الحاضرة
                  _buildHeaderCard(snap, onlineDevices),

                  const SizedBox(height: 12),

                  if (snap != null && snap.sessionActive && snap.peerStreamReady) ...[
                    // 🎛️ شريط التحكم واختيار العملاء إذا كان هناك فروقات
                    if (mismatches.isNotEmpty) ...[
                      _buildBatchActionBar(mismatches, peerName),
                      const SizedBox(height: 12),
                      
                      // ⚠️ قائمة الكروت غير المتطابقة
                      Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 22),
                          const SizedBox(width: 6),
                          Text(
                            'عملاء يحتاجون مطابقة (${mismatches.length})',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E1E2E)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ...mismatches.map((c) => _buildCustomerMismatchCard(c, peerName)),
                    ] else ...[
                      // ✅ لا فروقات
                      Card(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        color: const Color(0xFFE8F5E9),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              const Icon(Icons.check_circle_rounded, color: Colors.green, size: 52),
                              const SizedBox(height: 12),
                              Text(
                                'ممتاز! جميع الحسابات متطابقة مع «$peerName» 100%',
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF2E7D32)),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'تتطابق الديون المتبقية وعدد المعاملات بين الجهازين بالكامل.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 12, color: Colors.black54),
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                onPressed: _busy ? null : _endSessionAndClean,
                                icon: const Icon(Icons.cleaning_services_rounded),
                                label: const Text('إنهاء وتنظيف مجلدات السحابة 🧹'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),

                    // 🟢 قائمة العملاء المتطابقين
                    if (matchedCustomers.isNotEmpty) ...[
                      ExpansionTile(
                        initiallyExpanded: mismatches.isEmpty,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        title: Text(
                          'العملاء المتطابقون (${matchedCustomers.length})',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
                        ),
                        leading: const Icon(Icons.verified, color: Colors.green),
                        children: matchedCustomers.map(_buildMatchedCustomerTile).toList(),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 📡 كارت الأجهزة المتصلة وبدء الجلسة
  Widget _buildHeaderCard(LiveMatchSnapshot? snap, List<Map<String, dynamic>> devices) {
    final isSessionActive = snap?.sessionActive == true && snap?.peerStreamReady == true;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isSessionActive ? Colors.green.withOpacity(0.1) : const Color(0xFF4A90E2).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isSessionActive ? Icons.sync_rounded : Icons.cell_tower_rounded,
                    color: isSessionActive ? Colors.green : const Color(0xFF4A90E2),
                    size: 26,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isSessionActive
                            ? 'جلسة مطابقة حية نشطة مع «${snap?.peerDeviceName}»'
                            : 'المطابقة الحية بين الأجهزة',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isSessionActive
                            ? 'تتم المقارنة اللحظية للديون والمعاملات مباشرة بدون مسح'
                            : 'اضغط بدء المطابقة للبحث عن الأجهزة المتصلة ومقارنة الحسابات',
                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.devices, size: 18, color: Colors.grey),
                    const SizedBox(width: 6),
                    Text(
                      'الأجهزة المتصلة: ${devices.length}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                Row(
                  children: [
                    if (isSessionActive) ...[
                      TextButton.icon(
                        style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
                        onPressed: _busy ? null : _endSessionAndClean,
                        icon: const Icon(Icons.cleaning_services_rounded, size: 16),
                        label: const Text('إنهاء 🧹'),
                      ),
                      const SizedBox(width: 6),
                    ],
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isSessionActive ? Colors.amber.shade800 : const Color(0xFF4A90E2),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _busy ? null : _requestMatch,
                      icon: Icon(isSessionActive ? Icons.refresh : Icons.radar, size: 18),
                      label: Text(isSessionActive ? 'تحديث' : 'بدء المطابقة'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 🎛️ شريط الإجراءات الجماعية واختيار العملاء
  Widget _buildBatchActionBar(List<LiveCustomerMatch> mismatches, String peerName) {
    final allSelected = _selectedUuids.length == mismatches.length && mismatches.isNotEmpty;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: const Color(0xFF1E1E2E),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Checkbox(
                  value: allSelected,
                  activeColor: const Color(0xFF6C63FF),
                  onChanged: (val) {
                    setState(() {
                      if (val == true) {
                        _selectedUuids.addAll(mismatches.map((m) => m.customerSyncUuid));
                      } else {
                        _selectedUuids.clear();
                      }
                    });
                  },
                ),
                Text(
                  allSelected
                      ? 'تحديد الكل (${mismatches.length})'
                      : 'تم تحديد (${_selectedUuids.length}) من (${mismatches.length})',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                // 📤 زر اعتماد بياناتنا
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _busy ? null : () => _resolveSelectedMineIsTruth(mismatches),
                    icon: const Icon(Icons.upload_rounded, size: 18),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(_selectedUuids.isEmpty ? 'بياناتي صحيحة (رفع الكل)' : 'بياناتي صحيحة (${_selectedUuids.length})'),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // 📥 زر اعتماد بيانات الجهاز الآخر
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4A90E2),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _busy ? null : () => _resolveSelectedPeerIsTruth(mismatches),
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(_selectedUuids.isEmpty ? '$peerName صحيح (طلب الكل)' : '$peerName صحيح (${_selectedUuids.length})'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// ⚠️ كارت العميل غير المتطابق (تنسيق مريح ومستجيب للجوال مع مؤشر التحميل)
  Widget _buildCustomerMismatchCard(LiveCustomerMatch c, String peerName) {
    final isSelected = _selectedUuids.contains(c.customerSyncUuid);
    final isProcessing = _busyCustomerUuids.contains(c.customerSyncUuid);
    final diff = c.debtDifference;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelected ? const Color(0xFF6C63FF) : Colors.transparent,
          width: 2,
        ),
      ),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // العنوان ومربع التحديد
            Row(
              children: [
                Checkbox(
                  value: isSelected,
                  activeColor: const Color(0xFF6C63FF),
                  onChanged: isProcessing ? null : (val) {
                    setState(() {
                      if (val == true) {
                        _selectedUuids.add(c.customerSyncUuid);
                      } else {
                        _selectedUuids.remove(c.customerSyncUuid);
                      }
                    });
                  },
                ),
                Expanded(
                  child: Text(
                    c.customerName,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'الفرق: ${_money.format(diff.abs())} د.ع',
                    style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // ⏳ مؤشر التحميل التفاعلي أثناء معالجة هذا العميل
            if (isProcessing) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'جاري رفع ومطابقة معاملات «${c.customerName}» حياً...',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],

            // 📊 مقارنة البيانات جنبًا إلى جنب (Responsive Card Layout)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FA),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  // هذا الجهاز
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.computer, size: 14, color: Colors.blue),
                            SizedBox(width: 4),
                            Text('هذا الجهاز (هنا)', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_money.format(c.localDebt)} د.ع',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E1E2E)),
                        ),
                        Text(
                          '${c.localTxCount} معاملة',
                          style: const TextStyle(fontSize: 11, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                  Container(width: 1, height: 36, color: Colors.grey.shade300),
                  const SizedBox(width: 12),
                  // الجهاز الآخر
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.smartphone, size: 14, color: Colors.orange),
                            const SizedBox(width: 4),
                            Text(peerName, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_money.format(c.peerDebt)} د.ع',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E1E2E)),
                        ),
                        Text(
                          '${c.peerTxCount} معاملة',
                          style: const TextStyle(fontSize: 11, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // 👈 👉 أزرار القرار السريع لكل عميل
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.green.shade700,
                      side: BorderSide(color: Colors.green.shade400),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    onPressed: (_busy || isProcessing) ? null : () => _resolveSingleMineIsTruth(c),
                    icon: const Icon(Icons.upload_rounded, size: 16),
                    label: const FittedBox(fit: BoxFit.scaleDown, child: Text('بياناتي صحيحة 📤')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF4A90E2),
                      side: const BorderSide(color: Color(0xFF4A90E2)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    onPressed: (_busy || isProcessing) ? null : () => _resolveSinglePeerIsTruth(c),
                    icon: const Icon(Icons.download_rounded, size: 16),
                    label: FittedBox(fit: BoxFit.scaleDown, child: Text('$peerName صحيح 📥')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 🟢 كارت العميل المتطابق
  Widget _buildMatchedCustomerTile(LiveCustomerMatch c) {
    return ListTile(
      dense: true,
      leading: const Icon(Icons.check_circle, color: Colors.green, size: 20),
      title: Text(c.customerName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      subtitle: Text('الرصيد: ${_money.format(c.localDebt)} د.ع · (${c.localTxCount} معاملة)', style: const TextStyle(fontSize: 11)),
      trailing: const Icon(Icons.lock, color: Colors.grey, size: 16),
    );
  }
}
