// 🛡️ واجهات حارس الهجرة: ملخص التحقق بعد الاستيراد، ورفض قاعدة تغيّرت أرقامها.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/database/core/migration_guard.dart';
import '../services/database_service.dart' show DatabaseService;

/// نص نتيجة الاستعادة: تحقق حارس الهجرة + ما فعله النظام وحده + ما يحتاج قرارك.
String restoreSummaryText() => [
      if (MigrationGuard.lastReport != null)
        migrationReportText(MigrationGuard.lastReport!)
      else
        'تمت استعادة كافة الفواتير والديون والبيانات بنجاح.',
      if (DatabaseService.lastRestoreReport != null) DatabaseService.lastRestoreReport!,
      'سيُعاد تحميل التطبيق الآن.',
    ].join('\n\n');

String _n(num v) {
  final neg = v < 0;
  final s = v.abs().round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return '${neg ? '-' : ''}$b';
}

/// سطر الملخص بعد استيراد ناجح.
String migrationReportText(MigrationReport r) {
  final orphan = r.orphanTransactions > 0
      ? '\n• ${_n(r.orphanTransactions)} معاملة لعملاء محذوفين في البرنامج السابق: بقيت كما هي ولا تدخل في أي رصيد (كما كانت).'
      : '';
  return 'تحقق البرنامج رقماً رقماً قبل التحويل وبعده — مطابق تماماً:\n'
      '• ${_n(r.customers)} عميل، مجموع الديون ${_n(r.totalDebt)}\n'
      '• ${_n(r.transactions)} معاملة، ${_n(r.invoices)} فاتورة$orphan\n'
      '• نسخة من الملف قبل التحويل محفوظة في:\n${r.backupPath}';
}

Widget _problemsBox(List<String> problems) => Container(
      constraints: const BoxConstraints(maxHeight: 260),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4F4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF1C4C4)),
      ),
      padding: const EdgeInsets.all(10),
      child: SingleChildScrollView(
        child: SelectableText(
          problems.map((p) => '• $p').join('\n'),
          style: const TextStyle(fontSize: 12.5, height: 1.5),
        ),
      ),
    );

String _fullText(MigrationGuardException e) =>
    'حارس الهجرة — ${e.problems.length} اختلاف\n'
    'النسخة الأصلية: ${e.backupPath}\n\n${e.problems.join('\n')}';

/// الاستيراد رُفض: القاعدة الحالية بقيت كما هي.
Future<void> showMigrationRejectedDialog(
    BuildContext context, MigrationGuardException e) {
  return showDialog(
    context: context,
    builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Row(children: [
          Icon(Icons.gpp_bad_rounded, color: Colors.red, size: 28),
          SizedBox(width: 8),
          Expanded(child: Text('رُفض الاستيراد لحماية الديون')),
        ]),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'تحويل الملف إلى صيغة البرنامج كان سيغيّر أرقاماً مالية، فأوقفه '
                'البرنامج ولم يطبّق شيئاً. قاعدتك الحالية بقيت كما هي تماماً، '
                'والملف المستورد لم يُمسّ. أرسل هذا التقرير للدعم:',
                style: TextStyle(height: 1.5),
              ),
              const SizedBox(height: 10),
              _problemsBox(e.problems),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('نسخ التقرير'),
            onPressed: () => Clipboard.setData(ClipboardData(text: _fullText(e))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('حسناً'),
          ),
        ],
      ),
    ),
  );
}

/// تشغيل البرنامج رُفض (تحديث غيّر أرقاماً): القاعدة أُعيدت كما كانت.
class MigrationBlockedApp extends StatelessWidget {
  final MigrationGuardException error;
  const MigrationBlockedApp({super.key, required this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: const Color(0xFFF3F6FB),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Card(
                margin: const EdgeInsets.all(16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(children: [
                        Icon(Icons.gpp_bad_rounded, color: Colors.red, size: 30),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text('أُوقف التشغيل لحماية الديون',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ),
                      ]),
                      const SizedBox(height: 12),
                      const Text(
                        'تجهيز قاعدة البيانات لهذا الإصدار كان سيغيّر أرقاماً مالية، '
                        'فأعاد البرنامج القاعدة كما كانت حرفياً ولم يفتحها. لا شيء '
                        'ضاع ولا شيء تغيّر. أرسل التقرير للدعم، أو ارجع للإصدار السابق '
                        'من البرنامج حتى يصلك الإصلاح.',
                        style: TextStyle(height: 1.6),
                      ),
                      const SizedBox(height: 12),
                      _problemsBox(error.problems),
                      if (error.backupPath.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        SelectableText('نسخة قبل التحويل: ${error.backupPath}',
                            style: const TextStyle(fontSize: 12, color: Colors.black54)),
                      ],
                      const SizedBox(height: 16),
                      Row(children: [
                        Builder(
                          builder: (c) => OutlinedButton.icon(
                            icon: const Icon(Icons.copy_rounded, size: 18),
                            label: const Text('نسخ التقرير'),
                            onPressed: () async {
                              await Clipboard.setData(ClipboardData(text: _fullText(error)));
                              if (c.mounted) {
                                ScaffoldMessenger.of(c).showSnackBar(
                                    const SnackBar(content: Text('نُسخ التقرير')));
                              }
                            },
                          ),
                        ),
                        const Spacer(),
                        ElevatedButton(
                          onPressed: () => exit(0),
                          child: const Text('إغلاق البرنامج'),
                        ),
                      ]),
                    ],
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
