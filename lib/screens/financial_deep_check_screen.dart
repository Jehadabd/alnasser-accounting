// lib/screens/financial_deep_check_screen.dart
//
// 🔬 شاشة الفحص العميق — يعمل فقط حين يضغط المستخدم «ابدأ الفحص».
// الفحص قراءة فقط. ملاحظات الفواتير لها زر «معالجة» (deep_check_repair_dialog.dart):
// لا يتغير شيء إلا بقرار المدير وتأكيده، فاتورة فاتورة. النتيجة تُنسخ أو تُشارك كنص.
// الشكل من settings_kit (نفس باقي الإعدادات)، والقطع في deep_check/deep_check_widgets.dart.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../services/database/business/financial_deep_check.dart';
import '../services/database_service.dart';
import '../widgets/settings_kit.dart';
import 'deep_check/deep_check_widgets.dart';
import 'deep_check_repair_dialog.dart';

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

  Future<void> _repair(int invoiceId) async {
    if (await showDeepCheckRepair(context, invoiceId) && mounted) await _run();
  }

  @override
  Widget build(BuildContext context) {
    final r = _report;
    final status = r == null
        ? null
        : SetStatusPill(
            r.errors == 0 && r.warnings == 0
                ? 'كل شيء مطابق'
                : 'أخطاء ${r.errors} • تنبيهات ${r.warnings}',
            ok: r.errors == 0 && r.warnings == 0,
          );
    return SettingsScaffold(
      title: 'الفحص العميق',
      icon: Icons.manage_search_rounded,
      subtitle: 'يعيد حساب كل دين من مصدره',
      actions: [
        if (r != null) ...[
          IconButton(
            tooltip: 'نسخ التقرير',
            icon: const Icon(Icons.copy_rounded),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: r.asText()));
              if (context.mounted) setToast(context, 'نُسخ التقرير');
            },
          ),
          IconButton(
            tooltip: 'مشاركة التقرير',
            icon: const Icon(Icons.share_rounded),
            onPressed: () => Share.share(r.asText()),
          ),
        ],
      ],
      children: [
        SetHero(
          icon: Icons.manage_search_rounded,
          title: 'كل دين من فاتورته ومعاملاته',
          text: 'يقارن ما يجب أن يكون بما هو محفوظ: الفواتير والعملاء والموردين والمخزون والدفتر. '
              'الفحص لا يغيّر أي رقم. ملاحظات الفواتير لها «معالجة»: تختار أنت أيهما الصحيح، '
              'ولا يتغير شيء قبل تأكيدك.',
          status: status,
        ),
        SetPrimaryButton(
          label: _running ? 'يفحص…' : (r == null ? 'ابدأ الفحص' : 'أعد الفحص'),
          icon: r == null ? Icons.play_arrow_rounded : Icons.refresh_rounded,
          busy: _running,
          onPressed: _run,
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: _running
              ? Padding(
                  key: ValueKey(_step),
                  padding: const EdgeInsets.only(top: 10),
                  child: Column(children: [
                    const LinearProgressIndicator(minHeight: 4, borderRadius: BorderRadius.all(Radius.circular(4))),
                    const SizedBox(height: 6),
                    Text(_step ?? '', style: const TextStyle(fontSize: 12.5, color: kSetMuted)),
                  ]),
                )
              : const SizedBox(height: 14),
        ),
        if (_error != null)
          SetBanner('هنا وقع خطأ: $_error', kind: SetBannerKind.error),
        if (r != null) ...[
          DeepSummary(r),
          for (final f in r.findings) DeepFindingCard(f: f, onRepair: _repair, busy: _running),
          if (r.passed.isNotEmpty) DeepPassedCard(r.passed),
          const SizedBox(height: 4),
          const Text(
            'إن كان أحد يبيع على جهاز آخر أثناء الفحص فقد يظهر فرق مؤقت — أعد الفحص للتأكد.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: kSetMuted),
          ),
        ],
      ],
    );
  }
}
