// lib/erp/activity/screen_usage.dart
//
// 📈 استعمال الشاشات: عدد مرات فتح كل شاشة في كل يوم — لمعرفة ما يستعمله
// الموظفون فعلاً قبل إضافة شاشات جديدة أو إخفاء ما لا يُستعمل.
//
//   • جدول صغير screen_usage (اليوم، الشاشة، العدد) — سطر واحد لكل شاشة في اليوم،
//     لا سطر لكل فتح. يُحتفظ به 120 يوماً (DataRetention). بيانات تشغيلية فقط.
//   • يُحدَّث من ActivityLog.viewed (مرة في الدقيقة لكل شاشة)، ومن الشاشات
//     الرئيسية المفتوحة بأسمائها (/create_invoice...) عبر [ScreenUsageObserver].
//   • اسم الشاشة يُقطع عند « — » أو «: » حتى لا يصير اسم كل عميل شاشة مستقلة.
//   • لا يرمي أبداً ولا يبطئ فتح الشاشة.

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../services/database_service.dart';
import 'activity_log.dart';

class ScreenUsage {
  ScreenUsage._();

  static const int keepDays = 120;
  static int _readyGen = -1;

  static Future<void> ensure(DatabaseExecutor db) async {
    if (_readyGen == DatabaseService.openGeneration) return;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS screen_usage (
        day TEXT NOT NULL,
        screen TEXT NOT NULL,
        opens INTEGER NOT NULL DEFAULT 0 CHECK (opens >= 0),
        PRIMARY KEY (day, screen)
      ) WITHOUT ROWID''');
    _readyGen = DatabaseService.openGeneration;
  }

  /// اسم ثابت للشاشة: بلا الجزء المتغير بعد « — » أو «: »، وبطول معقول.
  static String normalize(String screen) {
    var s = screen.trim();
    for (final sep in const [' — ', ': ']) {
      final i = s.indexOf(sep);
      if (i > 0) s = s.substring(0, i).trim();
    }
    return s.length > 60 ? s.substring(0, 60) : s;
  }

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// +1 لفتح [screen] اليوم.
  static Future<void> bump(DatabaseExecutor db, String screen, {DateTime? now}) async {
    final s = normalize(screen);
    if (s.isEmpty) return;
    try {
      await ensure(db);
      await db.rawInsert(
          'INSERT INTO screen_usage(day, screen, opens) VALUES (?, ?, 1) '
          'ON CONFLICT(day, screen) DO UPDATE SET opens = opens + 1',
          [_day(now ?? DateTime.now()), s]);
    } catch (_) {}
  }

  /// الشاشات في آخر [days] يوماً: عدد مرات الفتح، وعدد الأيام، وآخر يوم.
  static Future<List<({String screen, int opens, int days, String lastDay})>> top(DatabaseExecutor db,
      {int days = 30, DateTime? now}) async {
    await ensure(db);
    final from = _day((now ?? DateTime.now()).subtract(Duration(days: days - 1)));
    final r = await db.rawQuery('''
      SELECT screen, SUM(opens) AS opens, COUNT(*) AS days, MAX(day) AS last_day
      FROM screen_usage WHERE day >= ?
      GROUP BY screen ORDER BY opens DESC, screen''', [from]);
    return [
      for (final x in r)
        (
          screen: '${x['screen']}',
          opens: ((x['opens'] as num?) ?? 0).toInt(),
          days: ((x['days'] as num?) ?? 0).toInt(),
          lastDay: '${x['last_day'] ?? ''}',
        ),
    ];
  }
}

/// يسجّل فتح الشاشات الرئيسية المسمّاة (/create_invoice ...) بأسمائها العربية.
class ScreenUsageObserver extends NavigatorObserver {
  ScreenUsageObserver(this.labels);

  /// المسار ← الاسم الظاهر (من أزرار الرئيسية).
  final Map<String, String> labels;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final name = route.settings.name;
    final label = name == null ? null : labels[name];
    if (label != null) ActivityLog.viewed(label);
  }
}

/// نافذة «استعمال الشاشات» (آخر 30 يوماً).
Future<void> showScreenUsageDialog(BuildContext context) async {
  final rows = await ScreenUsage.top(await DatabaseService().database);
  if (!context.mounted) return;
  final max = rows.isEmpty ? 1 : rows.first.opens;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('استعمال الشاشات — آخر 30 يوماً'),
      content: SizedBox(
        width: 520,
        height: 460,
        child: rows.isEmpty
            ? const Center(child: Text('لا بيانات بعد — تتجمع مع استعمال البرنامج.'))
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('عدد مرات الفتح (مرة في الدقيقة على الأكثر لكل شاشة). الشاشة التي لا تظهر هنا لم تُفتح.',
                    style: TextStyle(fontSize: 12.5, color: Colors.black54, height: 1.5)),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final r = rows[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Row(children: [
                            Expanded(child: Text(r.screen, style: const TextStyle(fontWeight: FontWeight.w700))),
                            Text('${r.opens} مرة • ${r.days} يوم', style: const TextStyle(color: Colors.black54)),
                          ]),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(value: r.opens / max, minHeight: 6),
                          ),
                          Text('آخر استعمال ${r.lastDay}', style: const TextStyle(fontSize: 11, color: Colors.black45)),
                        ]),
                      );
                    },
                  ),
                ),
              ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق'))],
    ),
  );
}
