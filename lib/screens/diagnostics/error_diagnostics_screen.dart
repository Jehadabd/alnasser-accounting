// lib/screens/diagnostics/error_diagnostics_screen.dart
//
// 🩺 «تشخيص الأخطاء» (الإعدادات ← النظام والأدوات — أول بطاقة).
//
// يعرض كل خطأ حدث في البرنامج (ErrorJournal + الخروج المفاجئ من native_errors.log)،
// مجمّعاً بنوعه وعدد مرات حدوثه. الضغط على الخطأ يفتح: ما الذي حدث، السبب المرجح،
// خطوات الحل مرقّمة (ErrorFixes)، ومن يحلّه، والتفاصيل التقنية، و«نسخ التقرير».
// «أدوات الإصلاح»: أزرار تنفّذ الحل (FixActions) — ما يكتب منها لا يعمل قبل رفع قاعدة البيانات
// رفعاً ناجحاً (UploadGate) ثم تأكيد. لا زر يغيّر مبلغاً أو ديناً.

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../lan/lan_settings.dart' show AppNetworkMode;
import '../../services/demo_mode.dart';
import '../../services/diagnostics/error_fixes.dart';
import '../../services/diagnostics/error_journal.dart';
import '../../services/diagnostics/fix_actions.dart';
import '../../services/diagnostics/upload_gate.dart';
import '../financial_deep_check_screen.dart';
import '../../services/dropbox_backup_service.dart';
import '../../widgets/dropbox_troubleshoot.dart';
import '../../widgets/settings_kit.dart';
import '../../widgets/setup_guide.dart';

// ─────────────────────────── أدوات العرض ───────────────────────────

Color _sevColor(FixSeverity s) => switch (s) {
      FixSeverity.critical => kSetRed,
      FixSeverity.error => kSetOrange,
      FixSeverity.warning => const Color(0xFFB45309),
      FixSeverity.info => kSetBlue,
    };

String _sevLabel(FixSeverity s) => switch (s) {
      FixSeverity.critical => 'خطير',
      FixSeverity.error => 'خطأ',
      FixSeverity.warning => 'تنبيه',
      FixSeverity.info => 'معلومة',
    };

String _whoLabel(FixWho w) => switch (w) {
      FixWho.you => 'تحلّه أنت',
      FixWho.developer => 'يحلّه المطوّر',
      FixWho.both => 'أنت والمطوّر',
    };

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'الآن';
  if (d.inMinutes < 60) return 'منذ ${d.inMinutes} دقيقة';
  if (d.inHours < 24) return 'منذ ${d.inHours} ساعة';
  if (d.inDays < 7) return 'منذ ${d.inDays} يوم';
  return DateFormat('yyyy/MM/dd HH:mm').format(t);
}

String _when(DateTime t) => DateFormat('yyyy/MM/dd  HH:mm:ss').format(t);

final _arabic = RegExp(r'[؀-ۿ]');
TextDirection _dirOf(String s) => _arabic.hasMatch(s) ? TextDirection.rtl : TextDirection.ltr;

/// خطأ مع حلّه.
class _Item {
  _Item(this.entry) : fix = ErrorFixes.match(entry.text, source: entry.source);
  final ErrorEntry entry;
  final ErrorFix fix;
  ErrorCategory get cat => ErrorFixes.category(fix.category);
  bool get serious => fix.severity == FixSeverity.critical || fix.severity == FixSeverity.error;
}

String _report(_Item it) {
  final e = it.entry;
  final b = StringBuffer()
    ..writeln('تقرير خطأ — برنامج الناصر للمحاسبة')
    ..writeln('المشكلة: ${it.fix.title} [${it.fix.key}]')
    ..writeln('النوع: ${it.cat.label} — ${_sevLabel(it.fix.severity)} — ${_whoLabel(it.fix.who)}')
    ..writeln('المصدر: ${ErrorSource.label(e.source)}')
    ..writeln('المرات: ${e.count} — أول مرة ${_when(e.first)} — آخر مرة ${_when(e.last)}')
    ..writeln(kIsWeb ? 'النظام: ويب' : 'النظام: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}')
    ..writeln('الرسالة: ${e.message}');
  if (e.detail != null) b..writeln('التفاصيل:')..writeln(e.detail);
  return ErrorJournal.sanitize(b.toString());
}

// ─────────────────────────── بطاقة الإعدادات ───────────────────────────

/// صف «تشخيص الأخطاء» في الإعدادات، بعدد الأخطاء غير المحلولة (يتحدّث مباشرة).
class ErrorDiagnosticsTile extends StatelessWidget {
  const ErrorDiagnosticsTile({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: ErrorJournal.changes,
      builder: (context, _, __) {
        final n = ErrorJournal.unresolvedCount;
        final c = n == 0 ? kSetGreen : kSetRed;
        return Semantics(
          button: true,
          label: 'تشخيص الأخطاء، $n خطأ لم يُحل',
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            hoverColor: kSetRed.withValues(alpha: 0.05),
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: kSetRed.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.health_and_safety_rounded, color: kSetRed, size: 22),
            ),
            title: const Text('تشخيص الأخطاء', style: TextStyle(fontWeight: FontWeight.w700, color: kSetText)),
            subtitle: Text('كل خطأ حدث في البرنامج — اضغط عليه لترى كيف يُحل',
                style: TextStyle(fontSize: 12, color: Colors.grey[600], height: 1.4)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Container(
                  key: ValueKey(n),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                  child: Text(n == 0 ? 'لا أخطاء' : '$n',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: c)),
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.arrow_forward_ios_rounded, size: 15, color: Colors.grey[400]),
            ]),
            onTap: onTap,
          ),
        );
      },
    );
  }
}

// ─────────────────────────── تنفيذ الإصلاح (بعد الرفع) ───────────────────────────

String _hm(DateTime t) => DateFormat('HH:mm').format(t);

/// ينفّذ زر إصلاح: الفحص فوراً؛ وما يكتب في القاعدة بعد رفع ناجح ثم تأكيد.
Future<void> runFixAction(BuildContext context, FixAction a) async {
  if (a.opens) {
    if (a.key == 'deep_check') {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const FinancialDeepCheckScreen()));
    }
    return;
  }
  if (AppNetworkMode.isClient) {
    setToast(context, 'هذا الجهاز طرفية: الإصلاح والفحص من حاسبة السيرفر التي عليها القاعدة', error: true);
    return;
  }
  if (a.writes) {
    // 🔐 1) رفع قاعدة البيانات أولاً (الوضع التجريبي: بيانات وهمية والرفع متوقف أصلاً)
    if (!DemoMode.isOn && !UploadGate.isOpen) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.cloud_upload_rounded, color: kSetNavy, size: 36),
          title: const Text('ارفع قاعدة البيانات أولاً'),
          content: Text(UploadGate.available
              ? 'قبل أي إصلاح تُرفع نسخة كاملة من قاعدة البيانات إلى تيليجرام أو Dropbox أو أي وجهة مفعّلة '
                  '— إن لم يعجبك ناتج الإصلاح تستعيدها.\n\nيكفي نجاح الرفع إلى وجهة واحدة. بعده يبقى الإصلاح مفتوحاً '
                  '${UploadGate.window.inMinutes} دقيقة.'
              : 'زر الرفع غير متاح من هذه الشاشة الآن.\nارجع إلى الشاشة الرئيسية واضغط «رفع البيانات» من هنا بعد فتحها، '
                  'ثم عد إلى «تشخيص الأخطاء».'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(UploadGate.available ? 'إلغاء' : 'حسناً')),
            if (UploadGate.available)
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.cloud_upload_rounded),
                label: const Text('ارفع الآن'),
              ),
          ],
        ),
      );
      if (go != true || !context.mounted) return;
      final ok = await UploadGate.uploadNow();
      if (!context.mounted) return;
      if (!ok) {
        setToast(context, 'لم ينجح الرفع إلى أي وجهة — لم يُنفَّذ الإصلاح', error: true);
        return;
      }
    }
    // 2) تأكيد ما سيحدث بالضبط
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(a.icon, color: kSetGreen, size: 34),
        title: Text(a.title),
        content: Text('${a.what}\n\n'
            '${DemoMode.isOn ? 'الوضع التجريبي: بلا رفع (البيانات وهمية).' : 'نسخة القاعدة رُفعت ${UploadGate.lastOk == null ? '' : 'الساعة ${_hm(UploadGate.lastOk!)}'} ✓'}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kSetGreen),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('نفّذ الإصلاح'),
          ),
        ],
      ),
    );
    if (sure != true || !context.mounted) return;
  }
  // 3) التنفيذ مع مؤشر انتظار
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(children: [
          const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 3)),
          const SizedBox(width: 16),
          Expanded(child: Text('${a.title}…')),
        ]),
      ),
    ),
  );
  final r = await FixActions.run(a.key);
  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop();
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(r.ok ? Icons.check_circle_rounded : Icons.warning_amber_rounded, color: r.ok ? kSetGreen : kSetOrange, size: 38),
      title: Text(a.title),
      content: SelectableText(r.message, style: const TextStyle(height: 1.6)),
      actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('حسناً'))],
    ),
  );
}

/// صف زر إصلاح (في «أدوات الإصلاح» وفي صفحة الخطأ).
class _FixActionRow extends StatelessWidget {
  const _FixActionRow(this.action, {this.onDone});
  final FixAction action;
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    final a = action;
    final c = a.writes ? kSetGreen : kSetBlue;
    return Semantics(
      button: true,
      label: a.title,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          await runFixAction(context, a);
          onDone?.call();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(11)),
              child: Icon(a.icon, color: c, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(
                    child: Text(a.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: kSetText)),
                  ),
                  const SizedBox(width: 8),
                  _Pill(a.writes ? 'يبدأ برفع القاعدة' : (a.opens ? 'يفتح شاشة' : 'قراءة فقط'),
                      a.writes ? kSetOrange : kSetBlue,
                      icon: a.writes ? Icons.cloud_upload_rounded : Icons.visibility_rounded),
                ]),
                const SizedBox(height: 3),
                Text(a.what, style: const TextStyle(fontSize: 12.5, height: 1.5, color: kSetMuted)),
              ]),
            ),
            const SizedBox(width: 6),
            Icon(Icons.play_circle_fill_rounded, color: c, size: 26),
          ]),
        ),
      ),
    );
  }
}

/// حالة بوابة الإصلاح.
class _GatePill extends StatelessWidget {
  const _GatePill();

  @override
  Widget build(BuildContext context) {
    if (DemoMode.isOn) return const SetStatusPill('الوضع التجريبي: الإصلاح بلا رفع', ok: true, icon: Icons.science_rounded);
    final until = UploadGate.openUntil;
    return until == null
        ? const SetStatusPill('كل إصلاح يبدأ برفع قاعدة البيانات', ok: false, icon: Icons.cloud_upload_rounded)
        : SetStatusPill('رُفعت القاعدة — الإصلاح مفتوح حتى ${_hm(until)}', ok: true, icon: Icons.lock_open_rounded);
  }
}

// ─────────────────────────── الشاشة الرئيسية ───────────────────────────

class ErrorDiagnosticsScreen extends StatefulWidget {
  const ErrorDiagnosticsScreen({super.key});

  @override
  State<ErrorDiagnosticsScreen> createState() => _ErrorDiagnosticsScreenState();
}

class _ErrorDiagnosticsScreenState extends State<ErrorDiagnosticsScreen> {
  List<ErrorEntry> _native = const [];
  String _filter = 'open'; // open | serious | all | <category>
  String _query = '';
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    ErrorJournal.changes.addListener(_refresh);
    _loadNative();
  }

  @override
  void dispose() {
    ErrorJournal.changes.removeListener(_refresh);
    _search.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _loadNative() async {
    final n = await ErrorJournal.nativeCrashes();
    if (mounted) setState(() => _native = n);
  }

  List<_Item> get _all => [for (final e in [...ErrorJournal.entries, ..._native]) _Item(e)]
    ..sort((a, b) => b.entry.last.compareTo(a.entry.last));

  bool _keep(_Item it) {
    final ok = switch (_filter) {
      'open' => !it.entry.resolved,
      'serious' => it.serious && !it.entry.resolved,
      'all' => true,
      _ => it.fix.category == _filter,
    };
    if (!ok) return false;
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return it.fix.title.toLowerCase().contains(q) || it.entry.text.toLowerCase().contains(q);
  }

  Future<void> _clear() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('مسح سجل الأخطاء؟'),
        content: const Text('تُمسح قائمة الأخطاء من هذه الشاشة فقط. لا تتغيّر أي بيانات في البرنامج.\n'
            'الخروج المفاجئ (ويندوز) يبقى ظاهراً لأنه يُقرأ من ملف ويندوز.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: kSetRed),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('مسح')),
        ],
      ),
    );
    if (go != true) return;
    ErrorJournal.clear();
    await ErrorJournal.save();
    if (mounted) setToast(context, 'مُسح سجل الأخطاء');
  }

  Future<void> _copyAll(List<_Item> items) async {
    final open = items.where((i) => !i.entry.resolved).toList();
    if (open.isEmpty) {
      setToast(context, 'لا أخطاء غير محلولة لنسخها');
      return;
    }
    await Clipboard.setData(ClipboardData(text: open.take(40).map(_report).join('\n────────────\n')));
    if (mounted) setToast(context, 'نُسخ تقرير ${open.length > 40 ? 40 : open.length} خطأ — الصقه للمطوّر');
  }

  @override
  Widget build(BuildContext context) {
    final all = _all;
    final shown = all.where(_keep).toList();
    final open = all.where((i) => !i.entry.resolved).length;
    final serious = all.where((i) => i.serious && !i.entry.resolved).length;
    final lastAt = all.isEmpty ? null : all.first.entry.last;
    final cats = <String, int>{};
    for (final i in all) {
      cats[i.fix.category] = (cats[i.fix.category] ?? 0) + 1;
    }

    return SettingsScaffold(
      title: 'تشخيص الأخطاء',
      icon: Icons.health_and_safety_rounded,
      subtitle: 'كل خطأ حدث في البرنامج وطريقة حلّه',
      actions: [
        IconButton(
          tooltip: 'تحديث',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: () {
            _loadNative();
            _refresh();
          },
        ),
        IconButton(tooltip: 'نسخ تقرير كل الأخطاء غير المحلولة', icon: const Icon(Icons.copy_all_rounded), onPressed: () => _copyAll(all)),
        IconButton(tooltip: 'مسح السجل', icon: const Icon(Icons.delete_sweep_rounded), onPressed: all.isEmpty ? null : _clear),
      ],
      children: [
        SetHero(
          icon: open == 0 ? Icons.verified_rounded : Icons.health_and_safety_rounded,
          color: serious > 0 ? kSetRed : (open > 0 ? kSetOrange : kSetGreen),
          title: open == 0 ? 'لا أخطاء تحتاج حلاً' : '$open خطأ لم يُحل',
          text: all.isEmpty
              ? 'لم يُسجَّل أي خطأ منذ تفعيل الأداة. أي خطأ يحدث سيظهر هنا مع طريقة حلّه.'
              : 'الأخطاء المتشابهة تُجمع في سطر واحد بعدد مرات حدوثها. اضغط أي خطأ لترى سببه وخطوات حلّه.',
          status: lastAt == null ? null : SetStatusPill('آخر خطأ ${_ago(lastAt)}', ok: open == 0, icon: Icons.schedule_rounded),
        ),
        _StatsRow(serious: serious, open: open, total: all.length),
        const SizedBox(height: 12),
        _Filters(
          selected: _filter,
          open: open,
          serious: serious,
          total: all.length,
          cats: cats,
          onSelect: (f) => setState(() => _filter = f),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _search,
          onChanged: (v) => setState(() => _query = v.trim()),
          decoration: InputDecoration(
            hintText: 'ابحث في الأخطاء (كلمة من الرسالة أو اسم المشكلة)',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      _search.clear();
                      setState(() => _query = '');
                    }),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: kSetBorder)),
            enabledBorder:
                OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: kSetBorder)),
          ),
        ),
        const SizedBox(height: 14),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: shown.isEmpty
              ? _Empty(key: ValueKey('empty$_filter'), filtered: all.isNotEmpty)
              : Column(
                  key: ValueKey('list$_filter$_query${shown.length}'),
                  children: [
                    for (final it in shown)
                      _ErrorCard(
                        item: it,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => ErrorDetailScreen(entry: it.entry)),
                        ).then((_) => _refresh()),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 8),
        SetCard(
          title: 'أدوات الإصلاح',
          subtitle: 'الفحص يعمل فوراً — وكل إصلاح يبدأ برفع قاعدة البيانات ثم تأكيدك',
          icon: Icons.handyman_rounded,
          color: kSetGreen,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(padding: EdgeInsets.fromLTRB(4, 4, 4, 6), child: _GatePill()),
            for (final a in FixActions.all) _FixActionRow(a, onDone: _refresh),
          ]),
        ),
        const SetBanner(
          'الفحص لا يغيّر شيئاً، والإصلاح لا يغيّر مبلغاً ولا ديناً ولا مخزوناً. كلمات المرور ورموز البوتات والمفاتيح '
          'تُمحى من السجل قبل حفظه، فالتقرير المنسوخ آمن للإرسال.',
          icon: Icons.lock_outline_rounded,
        ),
      ],
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.serious, required this.open, required this.total});
  final int serious, open, total;

  @override
  Widget build(BuildContext context) {
    Widget tile(String label, int n, Color c, IconData icon) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kSetBorder),
              boxShadow: const [BoxShadow(color: Color(0x0A0F172A), blurRadius: 10, offset: Offset(0, 3))],
            ),
            child: Row(children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, size: 19, color: c),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: n.toDouble()),
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, __) => Text('${v.round()}',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: n == 0 ? kSetMuted : c)),
                  ),
                  Text(label, style: const TextStyle(fontSize: 12, color: kSetMuted), overflow: TextOverflow.ellipsis),
                ]),
              ),
            ]),
          ),
        );
    return Row(children: [
      tile('خطيرة', serious, kSetRed, Icons.report_rounded),
      const SizedBox(width: 10),
      tile('لم تُحل', open, kSetOrange, Icons.pending_actions_rounded),
      const SizedBox(width: 10),
      tile('كل الأخطاء', total, kSetNavy, Icons.list_alt_rounded),
    ]);
  }
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.selected,
    required this.open,
    required this.serious,
    required this.total,
    required this.cats,
    required this.onSelect,
  });
  final String selected;
  final int open, serious, total;
  final Map<String, int> cats;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    Widget chip(String key, String label, int n, Color c, IconData? icon) {
      final sel = selected == key;
      return Padding(
        padding: const EdgeInsetsDirectional.only(end: 8),
        child: ChoiceChip(
          selected: sel,
          onSelected: (_) => onSelect(key),
          avatar: icon == null ? null : Icon(icon, size: 16, color: sel ? Colors.white : c),
          label: Text('$label ($n)'),
          labelStyle: TextStyle(color: sel ? Colors.white : kSetText, fontWeight: FontWeight.w700, fontSize: 12.5),
          selectedColor: c,
          backgroundColor: Colors.white,
          showCheckmark: false,
          side: BorderSide(color: sel ? c : kSetBorder),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        chip('open', 'لم تُحل', open, kSetOrange, Icons.pending_actions_rounded),
        chip('serious', 'خطيرة', serious, kSetRed, Icons.report_rounded),
        chip('all', 'الكل', total, kSetNavy, Icons.list_alt_rounded),
        for (final c in ErrorFixes.categories)
          if ((cats[c.key] ?? 0) > 0) chip(c.key, c.label, cats[c.key]!, c.color, c.icon),
      ]),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({super.key, required this.filtered});
  final bool filtered;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kSetBorder),
      ),
      child: Column(children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.6, end: 1),
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutBack,
          builder: (_, s, c) => Transform.scale(scale: s, child: c),
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: kSetGreen.withValues(alpha: 0.10), shape: BoxShape.circle),
            child: const Icon(Icons.verified_rounded, size: 40, color: kSetGreen),
          ),
        ),
        const SizedBox(height: 12),
        Text(filtered ? 'لا أخطاء في هذا التصنيف' : 'لا أخطاء مسجّلة',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: kSetText)),
        const SizedBox(height: 4),
        Text(filtered ? 'اختر «الكل» لرؤية كل الأخطاء، ومنها ما علّمته «تم الحل».' : 'البرنامج يعمل بلا أخطاء مسجّلة.',
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: kSetMuted)),
      ]),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.item, required this.onTap});
  final _Item item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final e = item.entry, f = item.fix, c = item.cat;
    final sev = _sevColor(f.severity);
    return Semantics(
      button: true,
      label: '${f.title}، ${_sevLabel(f.severity)}، ${e.count} مرة',
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: e.resolved ? kSetBorder : sev.withValues(alpha: 0.28)),
          boxShadow: const [BoxShadow(color: Color(0x0A0F172A), blurRadius: 10, offset: Offset(0, 3))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            hoverColor: sev.withValues(alpha: 0.04),
            child: IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(width: 5, color: e.resolved ? kSetBorder : sev),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 10, 12),
                    child: Row(children: [
                      Hero(
                        tag: 'err-${e.id}',
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(color: c.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(13)),
                          child: Icon(c.icon, color: c.color, size: 22),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(f.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w800,
                                  color: e.resolved ? kSetMuted : kSetText,
                                  decoration: e.resolved ? TextDecoration.lineThrough : null)),
                          const SizedBox(height: 2),
                          Text(e.message,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textDirection: _dirOf(e.message),
                              style: const TextStyle(fontSize: 12, color: kSetMuted)),
                          const SizedBox(height: 6),
                          Wrap(spacing: 6, runSpacing: 4, children: [
                            _Pill(_sevLabel(f.severity), sev),
                            if (e.count > 1) _Pill('×${e.count}', kSetNavy),
                            _Pill(_ago(e.last), kSetMuted, icon: Icons.schedule_rounded),
                            if (e.resolved) const _Pill('تم الحل', kSetGreen, icon: Icons.check_rounded),
                            if (f.harmless && !e.resolved) const _Pill('لا يضر البيانات', kSetGreen),
                          ]),
                        ]),
                      ),
                      Icon(Icons.chevron_left_rounded, color: Colors.grey[400]),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, this.color, {this.icon});
  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 12, color: color), const SizedBox(width: 3)],
        Text(text, style: TextStyle(fontSize: 11.5, color: color, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

// ─────────────────────────── تفاصيل الخطأ وحلّه ───────────────────────────

class ErrorDetailScreen extends StatefulWidget {
  const ErrorDetailScreen({super.key, required this.entry});
  final ErrorEntry entry;

  @override
  State<ErrorDetailScreen> createState() => _ErrorDetailScreenState();
}

class _ErrorDetailScreenState extends State<ErrorDetailScreen> {
  late final _Item _it = _Item(widget.entry);
  bool _showAll = false;
  DropboxProblem? _dropbox; // حل أدق من «حل مشاكل Dropbox» إن تعرّف على الرسالة

  @override
  void initState() {
    super.initState();
    if (_it.fix.key == 'dropbox') _loadDropbox();
  }

  Future<void> _loadDropbox() async {
    try {
      final s = DropboxBackupService();
      final p = DropboxTroubleshoot.match(_it.entry.text, appKey: await s.appKey(), appName: await s.appName());
      if (mounted && p != null) setState(() => _dropbox = p);
    } catch (_) {}
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _report(_it)));
    if (mounted) setToast(context, 'نُسخ التقرير — الصقه للمطوّر في واتساب أو تيليجرام');
  }

  void _toggleResolved() {
    final e = _it.entry;
    ErrorJournal.setResolved(e.id, !e.resolved);
    setState(() {});
    setToast(context, e.resolved ? 'عُلّم «تم الحل» — يعود إن تكرّر الخطأ' : 'أُعيد إلى «لم تُحل»');
  }

  @override
  Widget build(BuildContext context) {
    final e = _it.entry, f = _it.fix, c = _it.cat;
    final sev = _sevColor(f.severity);
    final native = e.source == ErrorSource.native;
    final steps = _dropbox?.steps ?? f.steps;
    final technical = e.detail == null ? e.message : '${e.message}\n\n${e.detail}';
    final lines = technical.split('\n');
    final short = lines.length <= 8;

    return SettingsScaffold(
      title: 'تشخيص الخطأ',
      icon: Icons.health_and_safety_rounded,
      subtitle: c.label,
      actions: [IconButton(tooltip: 'نسخ التقرير', icon: const Icon(Icons.copy_rounded), onPressed: _copy)],
      bottom: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: const BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(color: Color(0x140F172A), blurRadius: 12, offset: Offset(0, -3))],
          ),
          child: Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: _copy,
                icon: const Icon(Icons.copy_rounded),
                label: const Text('نسخ التقرير'),
              ),
            ),
            if (!native) ...[
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 48), backgroundColor: e.resolved ? kSetMuted : kSetGreen),
                  onPressed: _toggleResolved,
                  icon: Icon(e.resolved ? Icons.undo_rounded : Icons.check_circle_rounded),
                  label: Text(e.resolved ? 'لم يُحل بعد' : 'تم الحل'),
                ),
              ),
            ],
          ]),
        ),
      ),
      children: [
        // ── الرأس ──
        Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: [Color.alphaBlend(sev.withValues(alpha: 0.10), Colors.white), Colors.white],
              begin: AlignmentDirectional.topStart,
              end: AlignmentDirectional.bottomEnd,
            ),
            border: Border.all(color: sev.withValues(alpha: 0.25)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Hero(
                tag: 'err-${e.id}',
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: c.color,
                    borderRadius: BorderRadius.circular(17),
                    boxShadow: [BoxShadow(color: c.color.withValues(alpha: 0.30), blurRadius: 14, offset: const Offset(0, 6))],
                  ),
                  child: Icon(c.icon, color: Colors.white, size: 30),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_dropbox?.title ?? f.title,
                      style: const TextStyle(fontSize: 17.5, fontWeight: FontWeight.w800, color: kSetText)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    _Pill(_sevLabel(f.severity), sev),
                    _Pill(_whoLabel(f.who), kSetNavy, icon: Icons.person_outline_rounded),
                    if (e.resolved) const _Pill('تم الحل', kSetGreen, icon: Icons.check_rounded),
                  ]),
                ]),
              ),
            ]),
            const SizedBox(height: 14),
            Text(_dropbox?.symptom ?? f.what, style: const TextStyle(fontSize: 14, height: 1.6, color: kSetText)),
            const SizedBox(height: 12),
            Wrap(spacing: 14, runSpacing: 6, children: [
              _Meta(Icons.repeat_rounded, 'المرات', '${e.count}'),
              _Meta(Icons.history_rounded, 'أول مرة', _when(e.first)),
              _Meta(Icons.schedule_rounded, 'آخر مرة', _when(e.last)),
              _Meta(Icons.source_outlined, 'المصدر', ErrorSource.label(e.source)),
            ]),
          ]),
        ),
        if (f.harmless)
          const Padding(
            padding: EdgeInsets.only(bottom: 14),
            child: SetBanner('هذا لا يضر بياناتك: البرنامج تصرّف كما يجب أو يعيد المحاولة وحده.', kind: SetBannerKind.ok),
          )
        else if (f.who == FixWho.developer)
          const Padding(
            padding: EdgeInsets.only(bottom: 14),
            child: SetBanner(
              'هذا خلل في البرنامج نفسه — لا تسببه أنت ولا يُحل نهائياً من عندك. الخطوات أدناه تقلّل أثره، '
              'و«نسخ التقرير» يعطي المطوّر مكانه بالضبط.',
              kind: SetBannerKind.warn,
            ),
          ),
        SetCard(
          title: 'السبب المرجح',
          icon: Icons.psychology_alt_rounded,
          color: c.color,
          child: Text(_dropbox == null ? f.cause : 'من يصلح: ${_dropbox!.who}',
              style: const TextStyle(fontSize: 13.5, height: 1.6, color: kSetText)),
        ),
        SetCard(
          title: 'طريقة الحل',
          subtitle: 'نفّذ الخطوات بالترتيب',
          icon: Icons.build_circle_rounded,
          color: kSetGreen,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: SetupGuide(steps: steps, color: kSetGreen),
        ),
        if (f.actions.isNotEmpty)
          SetCard(
            title: 'أصلح من هنا',
            subtitle: 'الفحص فوراً — والإصلاح بعد رفع قاعدة البيانات',
            icon: Icons.handyman_rounded,
            color: kSetGreen,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(padding: EdgeInsets.fromLTRB(4, 4, 4, 6), child: _GatePill()),
              for (final k in f.actions)
                if (FixActions.byKey(k) != null) _FixActionRow(FixActions.byKey(k)!, onDone: () => setState(() {})),
            ]),
          ),
        SetCard(
          title: 'التفاصيل التقنية',
          subtitle: 'للمطوّر — يُنسخ مع التقرير',
          icon: Icons.code_rounded,
          color: kSetMuted,
          trailing: IconButton(tooltip: 'نسخ', icon: const Icon(Icons.copy_rounded, size: 20), onPressed: _copy),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(12)),
                child: SelectableText(
                  _showAll || short ? technical : '${lines.take(8).join('\n')}\n…',
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(fontFamily: 'Consolas', fontSize: 12, height: 1.5, color: Color(0xFFE2E8F0)),
                ),
              ),
            ),
            if (!short)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => setState(() => _showAll = !_showAll),
                  icon: Icon(_showAll ? Icons.expand_less_rounded : Icons.expand_more_rounded),
                  label: Text(_showAll ? 'أقل' : 'عرض الكل (${lines.length} سطر)'),
                ),
              ),
          ]),
        ),
      ],
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta(this.icon, this.label, this.value);
  final IconData icon;
  final String label, value;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 15, color: kSetMuted),
      const SizedBox(width: 4),
      Text('$label: ', style: const TextStyle(fontSize: 12, color: kSetMuted)),
      Text(value, style: const TextStyle(fontSize: 12, color: kSetText, fontWeight: FontWeight.w700)),
    ]);
  }
}
