// lib/screens/duplicate_customers_screen.dart
// 🔗 دمج الحسابات المكررة في سجل الديون
//
// تعرض كل اسم له أكثر من حساب، مع رصيد كل حساب وعدد معاملاته وفواتيره.
// المستخدم يختار الحساب الذي يبقى، ولا يُدمج شيء إلا بعد تأكيده. قبل كل دمج
// نسخة احتياطية كاملة، والدمج يُلغى كله إن لم يساوِ الرصيد بعده مجموع الأرصدة.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;

import '../services/customer_merge_service.dart';
import '../services/database/business/customer_name_rule.dart';
import '../widgets/loading_dialog.dart';

class DuplicateCustomersScreen extends StatefulWidget {
  const DuplicateCustomersScreen({super.key});

  @override
  State<DuplicateCustomersScreen> createState() => _DuplicateCustomersScreenState();
}

class _DuplicateCustomersScreenState extends State<DuplicateCustomersScreen> {
  static final _money = intl.NumberFormat('#,##0.##', 'en_US');

  bool _loading = true;
  bool _available = true;
  String? _error;
  List<DuplicateCustomerGroup> _groups = const [];

  /// الحساب الباقي المختار لكل مجموعة (المفتاح: اسم المجموعة بلا مسافات).
  final Map<String, int> _survivor = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final available = await CustomerMergeService.isAvailable();
      final groups = await CustomerMergeService.duplicateGroups();
      if (!mounted) return;
      setState(() {
        _available = available;
        _groups = groups;
        _survivor.removeWhere((k, _) => !groups.any((g) => g.key == k));
        for (final g in groups) {
          _survivor.putIfAbsent(g.key, () => g.accounts.first.id);
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _merge(DuplicateCustomerGroup group) async {
    final survivorId = _survivor[group.key] ?? group.accounts.first.id;
    final survivor = group.accounts.firstWhere((a) => a.id == survivorId);
    final others = group.accounts.where((a) => a.id != survivorId).toList();
    final total = group.accounts.fold<double>(0, (s, a) => s + a.balance);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد دمج الحسابات'),
        content: Text(
          'سيُدمج ${others.length == 1 ? 'حساب واحد' : '${others.length} حسابات'} '
          'في حساب «${survivor.name}»${(survivor.phone ?? '').isEmpty ? '' : ' (${survivor.phone})'}.\n\n'
          'كل المعاملات والفواتير والسندات تنتقل إليه، ورصيده بعد الدمج: ${_money.format(total)}\n'
          '(مجموع أرصدة الحسابات، لا يتغير أي مبلغ).\n\n'
          'تؤخذ نسخة احتياطية كاملة قبل الدمج.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('دمج')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    LoadingDialog.show(context);
    String message;
    Color color;
    try {
      final r = await CustomerMergeService.merge(survivorId, others.map((a) => a.id).toList());
      message = 'تم الدمج. الرصيد: ${_money.format(r.result.balanceAfter)} '
          '(مطابق لمجموع الحسابات ${_money.format(r.result.balanceBefore)})'
          '${r.result.uniqueIndexActive ? '\nلم يبقَ تكرار: قاعدة البيانات ترفض الآن أي اسم مكرر.' : ''}';
      color = Colors.green.shade700;
    } catch (e) {
      message = 'لم يتم الدمج: $e';
      color = Colors.red.shade700;
    }
    LoadingDialog.hide();
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: color,
      duration: const Duration(seconds: 6),
    ));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('دمج الحسابات المكررة'),
          actions: [
            IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh), tooltip: 'تحديث'),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('تعذّر تحميل الحسابات: $_error', textAlign: TextAlign.center),
        ),
      );
    }
    if (_groups.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.verified_outlined, size: 56, color: Colors.green),
              SizedBox(height: 12),
              Text('لا توجد حسابات مكررة في سجل الديون', style: TextStyle(fontSize: 16)),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (!_available)
          Card(
            color: Colors.orange.shade50,
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'المزامنة السحابية مفعّلة على هذا الجهاز، والدمج فيها معطّل حالياً: '
                'الأجهزة الأخرى تحمل هذه الحسابات منفصلة، ودمجها هنا وحده يجعل '
                'الأرصدة تختلف بين الأجهزة.',
              ),
            ),
          ),
        for (final g in _groups) _buildGroup(g),
      ],
    );
  }

  Widget _buildGroup(DuplicateCustomerGroup group) {
    final total = group.accounts.fold<double>(0, (s, a) => s + a.balance);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '«${group.accounts.first.name.trim()}» — ${group.accounts.length} حسابات',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text('اختر الحساب الذي يبقى. مجموع الأرصدة: ${_money.format(total)}',
                style: TextStyle(color: Colors.grey.shade700)),
            const SizedBox(height: 8),
            RadioGroup<int>(
              groupValue: _survivor[group.key],
              onChanged: (v) {
                if (v != null) setState(() => _survivor[group.key] = v);
              },
              child: Column(
                children: [
                  for (final a in group.accounts)
                    RadioListTile<int>(
                      value: a.id,
                      enabled: _available,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${a.name}${(a.phone ?? '').trim().isEmpty ? '' : '  •  ${a.phone}'}',
                      ),
                      subtitle: Text(
                        'الرصيد: ${_money.format(a.balance)}  •  '
                        '${a.transactionCount} معاملة  •  ${a.invoiceCount} فاتورة'
                        '${a.createdAt == null ? '' : '  •  أُنشئ ${a.createdAt!.split('T').first}'}',
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.icon(
                onPressed: _available ? () => _merge(group) : null,
                icon: const Icon(Icons.merge_type),
                label: const Text('دمج'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
