// lib/screens/reconciliation_screen.dart
//
// مطابقة حية بين الأجهزة المتصلة (لا مقابل السحابة):
// تطلب موافقة الأجهزة الحاضرة، ثم يقارن كل جهاز ديونه الحالية
// وعدد معاملاته مع الجهاز النظير عبر بث Firestore الحيّ.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../services/firebase_sync/live_match_service.dart';

class ReconciliationScreen extends StatefulWidget {
  const ReconciliationScreen({super.key});

  @override
  State<ReconciliationScreen> createState() => _ReconciliationScreenState();
}

class _ReconciliationScreenState extends State<ReconciliationScreen> {
  final LiveMatchService _live = LiveMatchService();
  final NumberFormat _money = NumberFormat('#,##0.##');

  StreamSubscription<LiveMatchSnapshot>? _sub;
  LiveMatchSnapshot? _snap;
  String _progress = '';
  bool _busy = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _live.start();
    _sub = _live.snapshots.listen((s) {
      if (mounted) setState(() => _snap = s);
    });
    // أول تحديث فوري حتى لا تبقى الشاشة على قائمة فارغة.
    unawaited(_live.recompute());
  }

  @override
  void dispose() {
    _sub?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _requestMatch() async {
    setState(() {
      _busy = true;
      _progress = 'جاري دعوة الأجهزة المتصلة...';
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
          content: Text(
              'أُرسل طلب المطابقة الحية. بانتظار موافقة الأجهزة خلال دقيقتين.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
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

  /// تأكيد صريح: هذا الجهاز هو المصدر الصحيح — لا حذف أبداً.
  Future<bool> _confirmThisDeviceIsTruth({required String actionLabel}) async {
    final peer = _snap?.peerDeviceName ?? 'الجهاز الآخر';
    final choice = await showDialog<String>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تأكيد مصدر البيانات'),
          content: Text(
            'هل أنت متأكد أن المعلومات في هذا الحاسوب هي الدقيقة، '
            'وأن بيانات «$peer» هي الخطأ؟\n\n'
            '• موافق: $actionLabel (رفع فقط — لا يُحذف أي معاملة).\n'
            '• النظير صحيح: تُضاف معاملات تصحيحية للفروقات فقط (بدون حذف).\n'
            '• إلغاء: لا تغيير.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'cancel'),
              child: const Text('إلغاء'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'peer'),
              child: const Text('النظير صحيح'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, 'local'),
              child: const Text('موافق — بياناتي صحيحة'),
            ),
          ],
        ),
      ),
    );
    if (choice == 'peer') {
      setState(() {
        _busy = true;
        _progress = 'جاري إضافة معاملات تصحيحية (بدون حذف)...';
      });
      try {
        final n = await _live.addCorrectiveTransactionsForPeerTruth();
        if (!mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(n == 0
                ? 'لا فروقات تحتاج تصحيحاً'
                : 'أُضيفت $n معاملة تصحيحية — لم يُحذف شيء'),
          ),
        );
      } finally {
        if (mounted) {
          setState(() {
            _busy = false;
            _progress = '';
          });
        }
      }
      return false;
    }
    return choice == 'local';
  }

  Future<void> _inspectAll() async {
    if (_snap?.sessionActive != true) return;
    final ok = await _confirmThisDeviceIsTruth(
      actionLabel: 'ملء طابور إعادة رفع المعاملات غير المتطابقة فقط',
    );
    if (!ok || !mounted) return;

    setState(() {
      _busy = true;
      _progress = 'جاري فحص الفروقات (قراءة فقط — بلا حذف)...';
    });
    try {
      final added = await _live.inspectAndQueueMismatches();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(added == 0
              ? 'لا توجد معاملات مملوكة لهذا الجهاز تحتاج إعادة رفع'
              : 'أُضيفت $added معاملة إلى طابور إعادة الرفع (لم يُحذف شيء)'),
        ),
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

  Future<void> _inspectOne(LiveCustomerMatch c) async {
    final added = await _live.inspectCustomer(c.customerSyncUuid);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(added == 0
            ? 'لا مشاكل مملوكة عند ${c.customerName}'
            : 'أُضيفت $added معاملة لـ ${c.customerName} (بلا حذف)'),
      ),
    );
  }

  Future<void> _forceUploadQueue() async {
    final n = _snap?.uploadQueue.length ?? 0;
    if (n == 0) return;
    final ok = await _confirmThisDeviceIsTruth(
      actionLabel: 'إعادة رفع $n معاملة يملكها هذا الجهاز',
    );
    if (!ok || !mounted) return;

    setState(() {
      _busy = true;
      _progress = 'جاري الرفع القسري (بلا حذف)...';
    });
    try {
      final result = await _live.forceUploadQueue(
        onProgress: (done, total, name) {
          if (mounted) {
            setState(() => _progress = 'رفع $done/$total — $name');
          }
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'تم: ${result.ok} · فشل: ${result.failed} · تُخطّي: ${result.skipped}'),
        ),
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

  Future<void> _forceReuploadEverything() async {
    if (_snap?.sessionActive != true) return;
    final ok = await _confirmThisDeviceIsTruth(
      actionLabel:
          'رفع جميع العملاء الحاليين مع جميع معاملاتهم مجدداً (حتى المرفوعة مسبقاً)، ثم يطلب من الجهاز الآخر تنزيلها والتحقق',
    );
    if (!ok || !mounted) return;

    setState(() {
      _busy = true;
      _progress = 'جاري رفع كل العملاء والمعاملات مجدداً...';
    });
    try {
      final result = await _live.forceReuploadAllCustomersAndOwnedTxs(
        onProgress: (done, total, msg) {
          if (mounted) setState(() => _progress = msg);
        },
      );
      if (!mounted) return;
      final success = result['success'] == true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: success ? null : Colors.red,
          content: Text(success
              ? 'اكتمل الرفع: ${result['uploadedCustomers'] ?? 0} عميل، '
                  '${result['uploadedTransactions'] ?? 0} معاملة — لم يُحذف شيء. '
                  'اطلب من الجهاز الآخر المزامنة/التنزيل للتحقق.'
              : 'فشل: ${result['error'] ?? 'خطأ غير معروف'}'),
        ),
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

  @override
  Widget build(BuildContext context) {
    final snap = _snap;
    final others = snap?.otherDeviceCount ?? 0;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('المطابقة الحية بين الأجهزة'),
          actions: [
            IconButton(
              tooltip: 'تحديث الأجهزة',
              onPressed: _busy ? null : () => _live.recompute(),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: snap == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  if (_busy || _progress.isNotEmpty)
                    const LinearProgressIndicator(),
                  if (_progress.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child:
                          Text(_progress, style: const TextStyle(fontSize: 12)),
                    ),
                  _buildHeader(snap, others),
                  _buildActions(snap, others),
                  Expanded(child: _buildBody(snap)),
                ],
              ),
      ),
    );
  }

  Widget _buildHeader(LiveMatchSnapshot snap, int others) {
    final active = snap.sessionActive && snap.peerStreamReady;
    final debtOk = active &&
        (snap.localTotalDebt - snap.peerTotalDebt).abs() <= 1.0;

    return Card(
      margin: const EdgeInsets.all(12),
      color: !snap.sessionActive
          ? Colors.blue.shade50
          : (debtOk ? Colors.green.shade50 : Colors.orange.shade50),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  active ? Icons.sensors : Icons.sensors_off,
                  color: active ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    snap.statusMessage ?? '',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'المقارنة: ديون هذا الجهاز الحالية ↔ ديون الجهاز المتصل الحالية '
              '(ليست السحابة).',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            const Divider(),
            _kv('أجهزة متصلة الآن', '${snap.onlineDeviceCount}'),
            _kv('أجهزة أخرى حاضرة', '$others',
                warn: others == 0 && snap.onlineDeviceCount > 0),
            _kv('هذا الجهاز — إجمالي الديون',
                '${_money.format(snap.localTotalDebt)} د.ع'),
            if (active) ...[
              _kv('${snap.peerDeviceName} — إجمالي الديون',
                  '${_money.format(snap.peerTotalDebt)} د.ع'),
              _kv(
                'فرق الإجمالي',
                _money.format(snap.localTotalDebt - snap.peerTotalDebt),
                warn: (snap.localTotalDebt - snap.peerTotalDebt).abs() > 1,
              ),
              _kv('عملاء غير متطابقين', '${snap.mismatches.length}',
                  warn: snap.mismatches.isNotEmpty),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActions(LiveMatchSnapshot snap, int others) {
    final queue = snap.uploadQueue;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          if (!snap.sessionActive)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _busy || others == 0 ? null : _requestMatch,
                icon: const Icon(Icons.groups),
                label: Text(others == 0
                    ? 'لا يوجد جهاز آخر متصل'
                    : 'طلب مطابقة حية مع الأجهزة المتصلة ($others)'),
              ),
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _busy ? null : _inspectAll,
                    icon: const Icon(Icons.search),
                    label: Text(
                        'فحص الفروقات (${snap.mismatches.length})'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed:
                        _busy || queue.isEmpty ? null : _forceUploadQueue,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepOrange,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.cloud_upload),
                    label: Text('رفع الطابور (${queue.length})'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _busy ? null : _forceReuploadEverything,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal.shade700,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.upload_file),
                label: const Text(
                    'رفع جميع العملاء ومعاملاتهم مجدداً (تجاوز المرفوع)'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'لا يوجد حذف معاملات في المطابقة الحية. الفحص يقرأ فقط؛ '
                'الرفع يعيد إرسال البيانات ويطلب من النظير التنزيل والتحقق.',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
              ),
            ),
          ],
          if (snap.sessionActive)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        await _live.endSession();
                        await _live.recompute();
                      },
                icon: const Icon(Icons.stop_circle_outlined, size: 18),
                label: const Text('إنهاء جلسة المطابقة الحية'),
              ),
            ),
          if (queue.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _busy ? null : _live.clearQueue,
                icon: const Icon(Icons.clear_all, size: 18),
                label: const Text('تفريغ الطابور'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody(LiveMatchSnapshot snap) {
    final waitingForPeer = snap.sessionStatus == 'requesting' ||
        (snap.sessionActive && !snap.peerStreamReady) ||
        _busy;

    if (waitingForPeer) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              Text(
                snap.sessionStatus == 'requesting'
                    ? 'جاري انتظار موافقة الأجهزة وبدء المطابقة...'
                    : (snap.statusMessage ?? 'جاري تحميل المطابقة...'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'تتم مقارنة الديون وعدد المعاملات مع الجهاز الآخر مباشرة.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
            ],
          ),
        ),
      );
    }

    if (!snap.sessionActive || !snap.peerStreamReady) {
      final devices = snap.onlineDevices;
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('الأجهزة الحاضرة (${devices.length})',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (devices.isEmpty)
                    const Text(
                      'لا أجهزة متصلة بنبضة حيّة الآن.\n'
                      'تأكد أن الجهاز الآخر مفتوح والمزامنة مفعّلة.',
                    )
                  else
                    ...devices.map((d) => ListTile(
                          dense: true,
                          leading: Icon(
                            d['isCurrentDevice'] == true
                                ? Icons.smartphone
                                : Icons.computer,
                            color: Colors.green,
                          ),
                          title: Text(d['deviceName'] as String? ?? ''),
                          subtitle: Text(d['isCurrentDevice'] == true
                              ? 'هذا الجهاز'
                              : 'متصل — يمكن دعوته للمطابقة'),
                        )),
                ],
              ),
            ),
          ),
        ],
      );
    }

    final mismatches = snap.mismatches;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        if (mismatches.isNotEmpty) ...[
          _buildMismatchTable(mismatches, snap.peerDeviceName ?? 'الجهاز الآخر'),
          const SizedBox(height: 12),
          Text(
            'تفاصيل غير المتطابقين (${mismatches.length})',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 6),
          ...mismatches.map(_buildCustomerTile),
          const Divider(height: 28),
          Text(
            'المتطابقون (${snap.customers.length - mismatches.length})',
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Colors.grey.shade700),
          ),
          const SizedBox(height: 6),
          ...snap.customers.where((c) => c.isMatch).map(_buildCustomerTile),
        ] else ...[
          Card(
            color: Colors.green.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'كل العملاء متطابقون مع ${snap.peerDeviceName}: '
                'نفس الدين ونفس عدد المعاملات.',
              ),
            ),
          ),
          const SizedBox(height: 8),
          ...snap.customers.map(_buildCustomerTile),
        ],
      ],
    );
  }

  Widget _buildMismatchTable(
      List<LiveCustomerMatch> mismatches, String peerName) {
    return Card(
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'جدول الفروقات مع $peerName (${mismatches.length})',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: Colors.red),
            ),
            const SizedBox(height: 4),
            const Text(
              'لكل عميل: الدين الحالي وعدد المعاملات على الجهازين.',
              style: TextStyle(fontSize: 11, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 36,
                dataRowMinHeight: 40,
                dataRowMaxHeight: 56,
                columnSpacing: 14,
                columns: [
                  const DataColumn(label: Text('العميل')),
                  const DataColumn(label: Text('دين هنا'), numeric: true),
                  DataColumn(label: Text('دين $peerName'), numeric: true),
                  const DataColumn(label: Text('الفرق'), numeric: true),
                  const DataColumn(label: Text('معاملات هنا'), numeric: true),
                  DataColumn(label: Text('معاملات $peerName'), numeric: true),
                ],
                rows: mismatches.map((c) {
                  final diff = c.debtDifference;
                  return DataRow(cells: [
                    DataCell(SizedBox(
                      width: 130,
                      child: Text(c.customerName,
                          overflow: TextOverflow.ellipsis),
                    )),
                    DataCell(Text(_money.format(c.localDebt))),
                    DataCell(Text(_money.format(c.peerDebt))),
                    DataCell(Text(
                      _money.format(diff),
                      style: TextStyle(
                        color: diff.abs() > 0.01 ? Colors.red : null,
                        fontWeight: FontWeight.bold,
                      ),
                    )),
                    DataCell(Text('${c.localTxCount}')),
                    DataCell(Text('${c.peerTxCount}')),
                  ]);
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerTile(LiveCustomerMatch c) {
    final ok = c.isMatch;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: Icon(
          ok ? Icons.check_circle : Icons.warning_amber,
          color: ok ? Colors.green : Colors.orange,
        ),
        title: Text(c.customerName),
        subtitle: Text(
          ok
              ? 'متطابق · ${_money.format(c.localDebt)} · ${c.localTxCount} معاملة'
              : 'فرق · هنا ${_money.format(c.localDebt)}/${c.localTxCount}'
                  ' · ${c.peerDeviceName} ${_money.format(c.peerDebt)}/${c.peerTxCount}',
          style: TextStyle(
            fontSize: 12,
            color: ok ? Colors.green.shade700 : Colors.orange.shade800,
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!ok) ...[
                  ...c.mismatchReasons.map((r) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('⚠ $r',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.red)),
                      )),
                  const Divider(),
                ],
                _kv('دين هنا', _money.format(c.localDebt)),
                _kv('دين ${c.peerDeviceName}', _money.format(c.peerDebt)),
                _kv('فرق الدين', _money.format(c.debtDifference),
                    warn: c.debtDifference.abs() > 0.01),
                _kv('معاملات هنا', '${c.localTxCount}'),
                _kv('معاملات ${c.peerDeviceName}', '${c.peerTxCount}'),
                if (c.ownedProblems.isNotEmpty) ...[
                  const Divider(),
                  Text(
                    'معاملات هذا الجهاز المرشّحة (${c.ownedProblems.length})',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.red),
                  ),
                  ...c.ownedProblems.take(20).map((p) => Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '• ${_money.format(p.amount)} — ${p.reason}',
                          style: const TextStyle(fontSize: 11),
                        ),
                      )),
                ],
                if (!ok) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _inspectOne(c),
                    icon: const Icon(Icons.playlist_add),
                    label: const Text('إضافة للطابور'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v, {bool warn = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k, style: const TextStyle(fontSize: 13)),
          Text(v,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: warn ? Colors.red : null,
              )),
        ],
      ),
    );
  }
}
