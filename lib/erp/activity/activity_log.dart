// lib/erp/activity/activity_log.dart
//
// 🕵️ سجل حركات النظام (مثل «سجل حركات النظام» في سهل): من فعل ماذا ومتى وفي أي شاشة.
//   • العمليات: إنشاء/إلغاء/اعتماد المستندات، الأسعار، السندات، الإقفال، الدخول...
//   • التصفح: فتح الشاشات (مرة كل دقيقة لكل شاشة، حتى لا يمتلئ السجل).
// التسجيل لا يرمي أبداً ولا يوقف العملية الأصلية. الشاشة تدمج هذا السجل مع
// سجل التدقيق المالي الموجود (financial_audit_log).

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../accounting/screens/acc_ui.dart';
import '../../services/auth_service.dart';
import '../../services/database_service.dart';
import '../erp_common.dart';
import '../erp_ui.dart';
import '../report_export.dart';

class ActivityLog {
  ActivityLog._();

  static bool _ready = false;
  static final Map<String, DateTime> _lastView = {};

  static Future<void> _ensure(DatabaseExecutor db) async {
    if (_ready) return;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS activity_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        at TEXT NOT NULL,
        user_name TEXT,
        action TEXT NOT NULL,
        screen TEXT,
        details TEXT
      )''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_activity_at ON activity_logs(at)');
    _ready = true;
  }

  /// تسجيل عملية. [action]: إنشاء | تعديل | حذف | إلغاء | اعتماد | دخول | خروج | تصفح ...
  static Future<void> log(String action, String screen, [String? details]) async {
    try {
      final db = await DatabaseService().database;
      await _ensure(db);
      await db.insert('activity_logs', {
        'at': DateTime.now().toIso8601String(),
        'user_name': AuthService().currentUser?.username ?? 'admin',
        'action': action,
        'screen': screen,
        'details': details,
      });
    } catch (_) {}
  }

  /// فتح شاشة (مرة في الدقيقة لكل شاشة).
  static void viewed(String screen) {
    final now = DateTime.now();
    final last = _lastView[screen];
    if (last != null && now.difference(last).inSeconds < 60) return;
    _lastView[screen] = now;
    log('تصفح', screen, 'فتح شاشة «$screen»');
  }

  static Future<List<Map<String, Object?>>> query({
    required DateTime from,
    required DateTime to,
    String? user,
    String? text,
    bool includeViews = true,
    bool includeFinancial = true,
  }) async {
    final db = await DatabaseService().database;
    await _ensure(db);
    final where = <String>['at >= ?', 'at < ?'];
    final args = <Object?>[isoDay(from), isoDayAfter(to)];
    if (user != null && user.isNotEmpty) {
      where.add('user_name = ?');
      args.add(user);
    }
    if (!includeViews) where.add("action != 'تصفح'");
    final t = (text ?? '').trim();
    if (t.isNotEmpty) {
      where.add('(details LIKE ? OR screen LIKE ? OR action LIKE ?)');
      args.addAll(['%$t%', '%$t%', '%$t%']);
    }
    final a = await db.rawQuery(
        'SELECT at, user_name, action, screen, details FROM activity_logs WHERE ${where.join(' AND ')} ORDER BY at DESC LIMIT 3000',
        args);
    final out = <Map<String, Object?>>[...a];
    if (includeFinancial && (user == null || user.isEmpty)) {
      try {
        final fw = <String>['created_at >= ?', 'created_at < ?'];
        final fa = <Object?>[isoDay(from), isoDayAfter(to)];
        if (t.isNotEmpty) {
          fw.add('(notes LIKE ? OR operation_type LIKE ? OR entity_type LIKE ?)');
          fa.addAll(['%$t%', '%$t%', '%$t%']);
        }
        final f = await db.rawQuery('''
          SELECT created_at AS at, NULL AS user_name, operation_type AS action, entity_type AS screen,
                 COALESCE(notes, entity_type || ' #' || entity_id) AS details
          FROM financial_audit_log WHERE ${fw.join(' AND ')} ORDER BY created_at DESC LIMIT 3000''', fa);
        out.addAll(f.map((r) => {...r, 'financial': 1}));
      } catch (_) {}
    }
    out.sort((x, y) => '${y['at']}'.compareTo('${x['at']}'));
    return out;
  }

  static Future<List<String>> users() async {
    final db = await DatabaseService().database;
    await _ensure(db);
    final r = await db.rawQuery('SELECT DISTINCT user_name FROM activity_logs WHERE user_name IS NOT NULL ORDER BY user_name');
    return [for (final x in r) '${x['user_name']}'];
  }
}

// ═══════════════════════════ الشاشة ═══════════════════════════

class ActivityLogScreen extends StatefulWidget {
  const ActivityLogScreen({super.key});
  @override
  State<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends State<ActivityLogScreen> {
  DateTime _from = DateTime.now().subtract(const Duration(days: 7));
  DateTime _to = DateTime.now();
  String? _user;
  String _q = '';
  bool _views = false;
  List<String> _users = const [];
  List<Map<String, Object?>> _rows = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    ActivityLog.users().then((u) {
      if (mounted) setState(() => _users = u);
    });
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await ActivityLog.query(from: _from, to: _to, user: _user, text: _q, includeViews: _views);
    if (mounted) {
      setState(() {
        _rows = r;
        _loading = false;
      });
    }
  }

  static const Map<String, Color> _actionColors = {
    'إنشاء': ErpColors.green,
    'حذف': ErpColors.red,
    'إلغاء': ErpColors.red,
    'تعديل': ErpColors.orange,
    'اعتماد': ErpColors.purple,
    'دخول': ErpColors.blue,
    'خروج': ErpColors.muted,
    'تصفح': ErpColors.muted,
  };

  Color _color(String a) {
    for (final e in _actionColors.entries) {
      if (a.contains(e.key)) return e.value;
    }
    if (a.contains('delete')) return ErpColors.red;
    if (a.contains('create')) return ErpColors.green;
    if (a.contains('update')) return ErpColors.orange;
    return ErpColors.navy;
  }

  String _time(Object? at) {
    final d = DateTime.tryParse('$at');
    if (d == null) return '$at';
    return '${fmtDate(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return ErpPage(
      title: 'سجل حركات النظام',
      subtitle: 'من فعل ماذا ومتى — ${_rows.length} حركة',
      icon: Icons.manage_search_rounded,
      actions: [
        ...exportActions(context,
            title: 'سجل حركات النظام',
            subtitle: () => '${fmtDate(_from)} — ${fmtDate(_to)}',
            headers: () => ['#', 'التاريخ والوقت', 'المستخدم', 'نوع الحركة', 'الشاشة', 'التفاصيل'],
            rows: () => [
                  for (var i = 0; i < _rows.length; i++)
                    [
                      '${i + 1}',
                      _time(_rows[i]['at']),
                      '${_rows[i]['user_name'] ?? '—'}',
                      '${_rows[i]['action']}',
                      '${_rows[i]['screen'] ?? ''}',
                      '${_rows[i]['details'] ?? ''}',
                    ],
                ]),
      ],
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
            DateButton(label: 'من', value: _from, onChanged: (d) {
              _from = d;
              _load();
            }),
            DateButton(label: 'إلى', value: _to, onChanged: (d) {
              _to = d;
              _load();
            }),
            DropBox<String?>(
              label: 'المستخدم',
              value: _user,
              width: 180,
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('الكل')),
                for (final u in _users) DropdownMenuItem<String?>(value: u, child: Text(u)),
              ],
              onChanged: (v) {
                _user = v;
                _load();
              },
            ),
            SizedBox(
              width: 240,
              child: SearchBox(
                  hint: 'بحث في السجل',
                  onChanged: (v) {
                    _q = v;
                    _load();
                  }),
            ),
            FilterChip(
              label: const Text('إظهار التصفح'),
              selected: _views,
              onSelected: (v) {
                _views = v;
                _load();
              },
            ),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _rows.isEmpty
                  ? const EmptyState('لا توجد حركات', icon: Icons.manage_search_outlined)
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                      itemCount: _rows.length,
                      itemBuilder: (_, i) {
                        final r = _rows[i];
                        final a = '${r['action']}';
                        final c = _color(a);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border(right: BorderSide(color: c, width: 4)),
                          ),
                          child: ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              radius: 16,
                              backgroundColor: c.withOpacity(.12),
                              child: Icon(r['financial'] == 1 ? Icons.account_balance_outlined : Icons.person_outline,
                                  size: 18, color: c),
                            ),
                            title: Text('${r['details'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                                '${_time(r['at'])} • ${r['user_name'] ?? 'تدقيق مالي'} • ${r['screen'] ?? ''}'),
                            trailing: StatusBadge(a, color: c),
                          ),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}
