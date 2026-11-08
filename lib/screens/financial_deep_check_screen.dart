// lib/screens/financial_deep_check_screen.dart
//
// 🔬 شاشة الفحص العميق — يعمل فقط حين يضغط المستخدم «ابدأ الفحص».
// قراءة فقط: لا زر إصلاح هنا. النتيجة تُنسخ أو تُشارك كنص.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../services/database_service.dart';
import '../services/database/business/financial_deep_check.dart';

const _navy = Color(0xFF0F3460);
const _red = Color(0xFFB91C1C);
const _amber = Color(0xFFB45309);
const _green = Color(0xFF047857);
const _muted = Color(0xFF64748B);

class FinancialDeepCheckScreen extends StatefulWidget {
  const FinancialDeepCheckScreen({super.key});

  @override
  State<FinancialDeepCheckScreen> createState() => _FinancialDeepCheckScreenState();
}

class _FinancialDeepCheckScreenState extends State<FinancialDeepCheckScreen> {
  DeepCheckReport? _report;
  String? _step;
  bool _running = false;
  String? _error;

  Future<void> _run() async {
    setState(() {
      _running = true;
      _error = null;
      _report = null;
    });
    try {
      final db = await DatabaseService().database;
      final r = await FinancialDeepCheck(db).run(onStep: (s) {
        if (mounted) setState(() => _step = s);
      });
      if (!mounted) return;
      setState(() => _report = r);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _report;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          backgroundColor: _navy,
          foregroundColor: Colors.white,
          title: const Text('الفحص العميق'),
          actions: [
            if (r != null) ...[
              IconButton(
                tooltip: 'نسخ التقرير',
                icon: const Icon(Icons.copy_rounded),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: r.asText()));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('نُسخ التقرير')));
                },
              ),
              IconButton(
                tooltip: 'مشاركة التقرير',
                icon: const Icon(Icons.share_rounded),
                onPressed: () => Share.share(r.asText()),
              ),
            ],
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _intro(),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: _navy, minimumSize: const Size.fromHeight(48)),
              onPressed: _running ? null : _run,
              icon: _running
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.manage_search_rounded),
              label: Text(_running ? 'يفحص: ${_step ?? ''}' : (r == null ? 'ابدأ الفحص' : 'أعد الفحص')),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text('هنا وقع خطأ: $_error', style: const TextStyle(color: _red)),
            ],
            if (r != null) ...[
              const SizedBox(height: 16),
              _summary(r),
              for (final f in r.findings) _findingCard(f),
              if (r.passed.isNotEmpty) _passedCard(r.passed),
            ],
          ],
        ),
      ),
    );
  }

  Widget _intro() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: const Text(
          'يعيد حساب كل دين من مصدره — الفاتورة والمعاملة — ويقارنه بما هو محفوظ، '
          'ثم الموردين والمخزون والدفتر. لا يغيّر أي رقم ولا يصلح شيئاً: يقول ما وجد فقط.\n'
          'إن كان أحد يبيع على جهاز آخر أثناء الفحص فقد يظهر فرق مؤقت — أعد الفحص للتأكد.',
          style: TextStyle(fontSize: 13, height: 1.6, color: Color(0xFF334155)),
        ),
      );

  Widget _summary(DeepCheckReport r) {
    final ok = r.errors == 0 && r.warnings == 0;
    final color = r.errors > 0 ? _red : (r.warnings > 0 ? _amber : _green);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        Icon(ok ? Icons.verified_rounded : Icons.report_rounded, color: color, size: 30),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            ok
                ? 'لم يُعثر على أي خلل (${r.passed.length} فحصاً سليماً)'
                : 'أخطاء: ${r.errors} — تنبيهات: ${r.warnings} — سليم: ${r.passed.length}',
            style: TextStyle(fontWeight: FontWeight.w800, color: color),
          ),
        ),
        Text('${(r.elapsed.inMilliseconds / 1000).toStringAsFixed(1)} ث',
            style: const TextStyle(fontSize: 12, color: _muted)),
      ]),
    );
  }

  Widget _findingCard(DeepFinding f) {
    final (color, icon) = switch (f.severity) {
      DeepSeverity.error => (_red, Icons.error_rounded),
      DeepSeverity.warning => (_amber, Icons.warning_amber_rounded),
      DeepSeverity.info => (_navy, Icons.info_outline_rounded),
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: Icon(icon, color: color),
        title: Text(f.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        subtitle: Text(f.area, style: const TextStyle(fontSize: 12, color: _muted)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (f.explain.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(f.explain, style: const TextStyle(fontSize: 12.5, height: 1.5, color: Color(0xFF334155))),
            ),
          for (final row in f.rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: SelectableText('• $row', style: const TextStyle(fontSize: 12.5)),
            ),
          if (f.total > f.rows.length)
            Text('… و${f.total - f.rows.length} غيرها — يظهر أول ${f.rows.length} فقط',
                style: const TextStyle(fontSize: 12, color: _muted)),
        ],
      ),
    );
  }

  Widget _passedCard(List<String> passed) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('✅ فحوص سليمة', style: TextStyle(fontWeight: FontWeight.w800, color: _green)),
            const SizedBox(height: 6),
            for (final p in passed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text('• $p', style: const TextStyle(fontSize: 12.5)),
              ),
          ]),
        ),
      );
}
