// lib/screens/ai_models_settings_screen.dart
//
// 🤖 الإعدادات ← النظام والأدوات ← «نماذج الذكاء الاصطناعي» (حساب المالك واشتراك المزامنة).
//
//   • مفاتيح لكل مزوّد (Gemini، Groq، OpenRouter) — مع خطوات إنشاء كل مفتاح.
//   • «حفظ واختبار»: يجلب نماذج المزوّد، ويختبر أفضل 5 تقرأ الصور على فاتورة تجريبية،
//     ويرتّبها لك بالدقة ثم السرعة — وتعتمد الترتيب بضغطة.
//   • ترتيب النماذج بالسحب، وتفعيل/تعطيل كل نموذج، واختباره وحده.
//   • التعاون بين نموذجين: قارئ يستخرج الأسطر، ومطابِق يربطها بموادك مع «رسائل التعلّم».
// المفاتيح في خزنة النظام لهذا الجهاز فقط (لا تُزامَن ولا تذهب مع النسخ الاحتياطية).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../owner/ai_invoice/ai_alias_store.dart';
import '../services/ai_models/ai_model_probe.dart';
import '../services/ai_models/ai_models_config.dart';
import '../services/sync_perks.dart';
import '../widgets/settings_kit.dart';

const _aiColor = Color(0xFF4F46E5);

Color _providerColor(AiProvider p) => switch (p) {
      AiProvider.gemini => const Color(0xFF1A73E8),
      AiProvider.groq => const Color(0xFFF55036),
      AiProvider.openrouter => const Color(0xFF6D28D9),
    };

IconData _providerIcon(AiProvider p) => switch (p) {
      AiProvider.gemini => Icons.auto_awesome_rounded,
      AiProvider.groq => Icons.bolt_rounded,
      AiProvider.openrouter => Icons.hub_rounded,
    };

class AiModelsSettingsScreen extends StatefulWidget {
  const AiModelsSettingsScreen({super.key});

  @override
  State<AiModelsSettingsScreen> createState() => _AiModelsSettingsScreenState();
}

class _AiModelsSettingsScreenState extends State<AiModelsSettingsScreen> {
  bool _loading = true;
  AiModelsConfig _cfg = AiModelsConfig(models: AiModelsConfig.defaults());
  List<AiKey> _keys = const [];
  List<AiKey> _envKeys = const [];
  int _learned = 0;
  final Map<AiProvider, TextEditingController> _add = {for (final p in AiProvider.values) p: TextEditingController()};
  AiProvider? _testing;
  String _testStatus = '';
  String? _probing; // معرّف نموذج يُختبر وحده

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _add.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final cfg = await AiModelsStore.config();
    final keys = await AiModelsStore.savedKeys();
    var learned = 0;
    try {
      learned = await AiAliasStore.count();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _cfg = cfg;
      _keys = keys;
      _envKeys = AiModelsStore.envGeminiKeys();
      _learned = learned;
      _loading = false;
    });
  }

  Future<void> _saveCfg() async {
    await AiModelsStore.saveConfig(_cfg);
    if (mounted) setState(() {});
  }

  List<AiKey> _keysOf(AiProvider p) {
    final saved = _keys.where((k) => k.provider == p).toList();
    if (p == AiProvider.gemini && saved.isEmpty) return _envKeys;
    return saved;
  }

  // ───────────────────────── المفاتيح ─────────────────────────

  Future<void> _addKey(AiProvider p) async {
    final raw = _add[p]!.text.trim();
    if (raw.length < 12 || raw.contains(' ')) {
      setToast(context, 'المفتاح غير مكتمل — انسخه كاملاً من موقع ${p.label}', error: true);
      return;
    }
    final k = await AiModelsStore.addKey(p, raw);
    _add[p]!.clear();
    await _load();
    if (!mounted) return;
    await _test(p, k);
  }

  Future<void> _removeKey(AiKey k) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف المفتاح؟'),
        content: Text('مفتاح ${k.provider.label} ${k.masked} يُحذف من هذا الجهاز فقط (حسابك في الموقع يبقى كما هو).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kSetRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await AiModelsStore.removeKey(k.id);
    await _load();
  }

  // ───────────────────────── الاختبار ─────────────────────────

  Future<void> _test(AiProvider p, AiKey k) async {
    if (_testing != null) return;
    setState(() {
      _testing = p;
      _testStatus = 'بدء الاختبار…';
    });
    final report = await AiModelProbe.testProvider(p, k.key, onStatus: (s) {
      if (mounted) setState(() => _testStatus = s);
    });
    if (!mounted) return;
    setState(() => _testing = null);
    if (report.error != null && report.results.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('اختبار ${p.label}'),
          content: Text(report.error!, style: const TextStyle(height: 1.6)),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('حسناً'))],
        ),
      );
      return;
    }
    final chosen = await showDialog<List<AiProbeResult>>(
      context: context,
      builder: (_) => _TestResultsDialog(provider: p, results: report.results),
    );
    if (chosen == null) {
      _recordResults(p, report.results, adopt: const []);
    } else {
      _recordResults(p, report.results, adopt: chosen);
      if (mounted) setToast(context, 'اعتُمد ترتيب ${chosen.length} نموذج من ${p.label}');
    }
    await _saveCfg();
  }

  /// يحفظ نتائج الاختبار، ويضع [adopt] بترتيبها مكان نماذج هذا المزوّد في القائمة.
  void _recordResults(AiProvider p, List<AiProbeResult> results, {required List<AiProbeResult> adopt}) {
    final models = _cfg.models;
    AiModelEntry? find(String model) {
      for (final m in models) {
        if (m.provider == p && m.model == model) return m;
      }
      return null;
    }

    final now = DateTime.now();
    for (final r in results) {
      final e = find(r.model);
      if (e == null) continue;
      e.testScore = r.ok ? r.score : 0;
      e.testTotal = r.total;
      e.testMs = r.ms;
      e.testedAt = now;
      e.testNote = r.note;
      if (!r.ok) e.enabled = false; // لا يعمل بهذا المفتاح (لا يقرأ الصور، أو مدفوع)
    }
    if (adopt.isEmpty) return;
    final firstPos = models.indexWhere((m) => m.provider == p);
    final adopted = <AiModelEntry>[];
    for (final r in adopt) {
      final e = find(r.model) ??
          AiModelEntry(
            provider: p,
            model: r.model,
            label: r.name.isEmpty || r.name == r.model ? '' : r.name,
            testScore: r.score,
            testTotal: r.total,
            testMs: r.ms,
            testedAt: now,
            testNote: r.note,
          );
      e.enabled = true;
      adopted.add(e);
    }
    models.removeWhere((m) => adopted.contains(m));
    final at = firstPos < 0 ? models.length : firstPos.clamp(0, models.length);
    models.insertAll(at, adopted);
  }

  Future<void> _probeOne(AiModelEntry e) async {
    final keys = _keysOf(e.provider);
    if (keys.isEmpty) {
      setToast(context, 'أضف مفتاح ${e.provider.label} أولاً', error: true);
      return;
    }
    setState(() => _probing = e.id);
    final r = await AiModelProbe.probe(e.provider, e.model, keys.first.key, name: e.shownName);
    if (!mounted) return;
    _recordResults(e.provider, [r], adopt: const []);
    setState(() => _probing = null);
    await _saveCfg();
    if (mounted) setToast(context, '${e.shownName}: ${r.ok ? '${r.score}/${r.total} • ${r.ms} ms' : r.note}', error: !r.passed);
  }

  Future<void> _addModelManually() async {
    final res = await showDialog<AiModelEntry>(context: context, builder: (_) => const _AddModelDialog());
    if (res == null) return;
    if (_cfg.byId(res.id) != null) {
      if (mounted) setToast(context, 'النموذج موجود في القائمة', error: true);
      return;
    }
    _cfg.models.add(res);
    await _saveCfg();
  }

  // ───────────────────────── الواجهة ─────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!SyncPerks.enabled) {
      return const SettingsScaffold(
        title: 'نماذج الذكاء الاصطناعي',
        icon: Icons.auto_awesome_rounded,
        children: [SetBanner('هذه الإعدادات لحساب المالك واشتراك المزامنة', kind: SetBannerKind.warn)],
      );
    }
    final keysCount = AiProvider.values.fold<int>(0, (s, p) => s + _keysOf(p).length);
    final active = _cfg.models.where((m) => m.enabled && _keysOf(m.provider).isNotEmpty).length;
    return SettingsScaffold(
      title: 'نماذج الذكاء الاصطناعي',
      subtitle: 'المفاتيح، ترتيب النماذج، التعاون بين نموذجين',
      icon: Icons.auto_awesome_rounded,
      loading: _loading,
      children: [
        SetHero(
          icon: Icons.document_scanner_rounded,
          color: _aiColor,
          title: 'قراءة فواتير الموردين بالذكاء الاصطناعي',
          text: 'أضف مفتاحاً مجانياً واحداً على الأقل. النماذج تُجرَّب بالترتيب: إن نفدت حصة مفتاح انتقل البرنامج '
              'إلى المفتاح التالي، وإن فشل النموذج انتقل إلى النموذج التالي — دورة واحدة فقط. '
              'لا يُقبل إلا نموذج يقرأ الصور (ويُختبر على فاتورة تجريبية).',
          status: SetStatusPill(
            keysCount == 0 ? 'لا مفاتيح بعد' : '$keysCount مفتاح • $active نموذج جاهز',
            ok: active > 0,
          ),
        ),
        for (final p in AiProvider.values) _providerCard(p),
        _modelsCard(),
        _collabCard(),
        SetCard(
          title: 'التعلّم من تصحيحاتك',
          icon: Icons.psychology_rounded,
          color: const Color(0xFF0D9488),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('تعلّم البرنامج $_learned تسمية من تصحيحاتك.',
                style: const TextStyle(fontWeight: FontWeight.w700, color: kSetText)),
            const SizedBox(height: 6),
            const Text(
              'حين تغيّر مادة سطر في مراجعة الفاتورة يُحفظ: «هذا الاسم عند هذا المورد = هذه المادة». '
              'في الفاتورة التالية: يُفرض هذا الربط مباشرة، ويُرسل للنموذج المطابِق كرسالة تعلّم '
              '(«ظهر هذا الاسم فغيّره المستخدم إلى هذه المادة») ليتعلّم أسلوب المورد في التسمية، '
              'ويُعطى القارئ أسماء المورد السابقة ليقرأ خطه واختصاراته.',
              style: TextStyle(color: kSetMuted, height: 1.6),
            ),
          ]),
        ),
        const SetBanner(
          'الخصوصية: في الحصص المجانية قد تستعمل Google وبعض مزوّدي OpenRouter الفواتير المرسلة لتحسين نماذجهم. '
          'لا يُرسل إلا صورة الفاتورة وأسماء موادك المرشحة — لا ديون ولا عملاء. '
          'المفاتيح محفوظة في خزنة النظام على هذا الجهاز فقط: لا تُزامَن ولا تذهب مع النسخ الاحتياطية.',
          kind: SetBannerKind.warn,
          icon: Icons.privacy_tip_outlined,
        ),
      ],
    );
  }

  Widget _providerCard(AiProvider p) {
    final keys = _keysOf(p);
    final busy = _testing == p;
    final c = _providerColor(p);
    final blurb = switch (p) {
      AiProvider.gemini => 'الأقوى بين المجانيات، ويقرأ الـ PDF مباشرة. تسجيل بإيميل Google.',
      AiProvider.groq => 'سريع جداً. Qwen 3.8 يقرأ الصور (3 صور في الطلب). تسجيل بالإيميل.',
      AiProvider.openrouter => 'نماذج مجانية متعددة تتبدل (Gemma، Nemotron…). 50 طلباً يومياً. تسجيل بالإيميل.',
    };
    return SetCard(
      title: p.label,
      subtitle: blurb,
      icon: _providerIcon(p),
      color: c,
      trailing: TextButton.icon(
        onPressed: () => showDialog<void>(context: context, builder: (_) => _GuideDialog(provider: p)),
        icon: const Icon(Icons.help_outline_rounded, size: 18),
        label: const Text('كيف أحصل على مفتاح؟'),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final k in keys)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.withValues(alpha: 0.18)),
              ),
              child: Row(children: [
                Icon(Icons.key_rounded, size: 18, color: c),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('${k.masked}${k.label.isEmpty ? '' : '  •  ${k.label}'}',
                      style: const TextStyle(fontWeight: FontWeight.w700, color: kSetText)),
                ),
                TextButton(onPressed: busy || _testing != null ? null : () => _test(p, k), child: const Text('اختبار')),
                if (!k.fromEnv)
                  IconButton(
                    tooltip: 'حذف',
                    icon: const Icon(Icons.delete_outline_rounded, color: kSetRed),
                    onPressed: busy ? null : () => _removeKey(k),
                  ),
              ]),
            ),
          ),
        if (busy)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              LinearProgressIndicator(color: c, minHeight: 3),
              const SizedBox(height: 6),
              Text(_testStatus, style: const TextStyle(color: kSetMuted, fontSize: 12.5)),
            ]),
          ),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _add[p],
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                isDense: true,
                hintText: keys.isEmpty ? 'الصق مفتاح ${p.label} هنا' : 'مفتاح إضافي (من حساب آخر)',
                prefixIcon: const Icon(Icons.vpn_key_outlined, size: 19),
                suffixIcon: IconButton(
                  tooltip: 'لصق',
                  icon: const Icon(Icons.content_paste_rounded, size: 19),
                  onPressed: () async {
                    final d = await Clipboard.getData(Clipboard.kTextPlain);
                    final t = d?.text?.trim() ?? '';
                    if (t.isNotEmpty) _add[p]!.text = t;
                  },
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onSubmitted: (_) => _addKey(p),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _testing != null ? null : () => _addKey(p),
            style: FilledButton.styleFrom(backgroundColor: c, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14)),
            icon: const Icon(Icons.science_rounded, size: 18),
            label: const Text('حفظ واختبار'),
          ),
        ]),
        if (p == AiProvider.gemini && _envKeys.isNotEmpty && _keys.every((k) => k.provider != AiProvider.gemini))
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('يُستعمل الآن مفتاح ملف ‎.env. إن أضفت مفتاحاً هنا فهو الذي يُستعمل.',
                style: TextStyle(color: kSetMuted, fontSize: 12)),
          ),
      ]),
    );
  }

  Widget _modelsCard() {
    final models = _cfg.models;
    return SetCard(
      title: 'ترتيب النماذج',
      subtitle: 'اسحب لتغيير الأولوية — الأول يُجرَّب أولاً',
      icon: Icons.format_list_numbered_rounded,
      color: _aiColor,
      trailing: TextButton.icon(
        onPressed: _addModelManually,
        icon: const Icon(Icons.add_rounded, size: 18),
        label: const Text('نموذج يدوياً'),
      ),
      child: models.isEmpty
          ? const SetBanner('لا نماذج — اختبر مفتاحاً ليضيف البرنامج أفضل النماذج')
          : ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: models.length,
              onReorder: (o, n) {
                setState(() {
                  if (n > o) n -= 1;
                  final m = models.removeAt(o);
                  models.insert(n, m);
                });
                _saveCfg();
              },
              itemBuilder: (_, i) => _modelTile(models[i], i),
            ),
    );
  }

  Widget _modelTile(AiModelEntry e, int i) {
    final c = _providerColor(e.provider);
    final hasKey = _keysOf(e.provider).isNotEmpty;
    final probing = _probing == e.id;
    String? badge;
    Color badgeColor = kSetMuted;
    if (e.tested) {
      final sc = e.testScore ?? 0;
      badge = '$sc/${e.testTotal}${e.testMs != null && sc > 0 ? ' • ${(e.testMs! / 1000).toStringAsFixed(1)} ث' : ''}';
      badgeColor = e.testPassed ? kSetGreen : (sc > 0 ? kSetOrange : kSetRed);
    }
    return Container(
      key: ValueKey(e.id),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: e.enabled && hasKey ? c.withValues(alpha: 0.35) : kSetBorder),
      ),
      child: Row(children: [
        ReorderableDragStartListener(
          index: i,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 14),
            child: Icon(Icons.drag_indicator_rounded, color: kSetMuted),
          ),
        ),
        CircleAvatar(
          radius: 13,
          backgroundColor: c.withValues(alpha: e.enabled ? 0.15 : 0.06),
          child: Text('${i + 1}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: c)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.shownName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w800, color: e.enabled ? kSetText : kSetMuted)),
              const SizedBox(height: 2),
              Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                _chip(e.provider.label, c),
                _chip(e.provider.nativePdf ? 'يقرأ PDF مباشرة' : 'PDF ⇐ صور', kSetMuted),
                if (badge != null) _chip(badge, badgeColor),
                if (!hasKey) _chip('بلا مفتاح', kSetOrange),
              ]),
              if (e.testNote.isNotEmpty && !e.testPassed)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(e.testNote, style: const TextStyle(fontSize: 11.5, color: kSetMuted)),
                ),
              Text(e.model, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 11, color: kSetMuted)),
            ]),
          ),
        ),
        probing
            ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
            : IconButton(
                tooltip: 'اختبار هذا النموذج',
                icon: const Icon(Icons.science_outlined),
                onPressed: _probing != null || !hasKey ? null : () => _probeOne(e),
              ),
        Switch(
          value: e.enabled,
          onChanged: (v) {
            setState(() => e.enabled = v);
            _saveCfg();
          },
        ),
        IconButton(
          tooltip: 'إزالة من القائمة',
          icon: const Icon(Icons.close_rounded, color: kSetMuted),
          onPressed: () {
            setState(() => _cfg.models.remove(e));
            _saveCfg();
          },
        ),
      ]),
    );
  }

  Widget _chip(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(8)),
        child: Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c)),
      );

  Widget _collabCard() {
    final options = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: '', child: Text('تلقائي (حسب الترتيب)')),
      for (final m in _cfg.models)
        if (m.enabled) DropdownMenuItem(value: m.id, child: Text('${m.shownName} — ${m.provider.label}', overflow: TextOverflow.ellipsis)),
    ];
    String valid(String v) => options.any((o) => o.value == v) ? v : '';
    return SetCard(
      title: 'التعاون بين نموذجين',
      subtitle: 'نموذج يقرأ الفاتورة، وآخر يطابق موادها',
      icon: Icons.handshake_rounded,
      color: const Color(0xFF7C3AED),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SetSwitch(
          title: 'شغّل التعاون بين نموذجين (مستحسن)',
          subtitle: 'القارئ يرى الفاتورة ويستخرج الأسطر. ثم يختار البرنامج لكل سطر أقرب 8 مواد من موادك، '
              'والمطابِق يرى الفاتورة + الأسطر + المرشحين + رسائل التعلّم ويختار منها فقط. '
              'يعمل مع كل المزوّدين مهما كثرت موادك. بإطفائه: نموذج واحد يرى قائمة موادك كاملة (يناسب Gemini).',
          value: _cfg.collaboration,
          onChanged: (v) {
            setState(() => _cfg.collaboration = v);
            _saveCfg();
          },
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          key: ValueKey('reader_${_cfg.readerId}_${options.length}'),
          initialValue: valid(_cfg.readerId),
          isExpanded: true,
          decoration: InputDecoration(
            labelText: _cfg.collaboration ? 'النموذج القارئ' : 'النموذج',
            prefixIcon: const Icon(Icons.document_scanner_outlined),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          items: options,
          onChanged: (v) {
            _cfg.readerId = v ?? '';
            _saveCfg();
          },
        ),
        if (_cfg.collaboration) ...[
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            key: ValueKey('matcher_${_cfg.matcherId}_${options.length}'),
            initialValue: valid(_cfg.matcherId),
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'النموذج المطابِق',
              helperText: 'تلقائي = نموذج غير الذي قرأ (رأي ثانٍ)، ثم القارئ نفسه إن لم يوجد غيره',
              prefixIcon: const Icon(Icons.join_inner_rounded),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            items: options,
            onChanged: (v) {
              _cfg.matcherId = v ?? '';
              _saveCfg();
            },
          ),
        ],
      ]),
    );
  }
}

// ───────────────────────── نتائج الاختبار ─────────────────────────

class _TestResultsDialog extends StatefulWidget {
  const _TestResultsDialog({required this.provider, required this.results});
  final AiProvider provider;
  final List<AiProbeResult> results;

  @override
  State<_TestResultsDialog> createState() => _TestResultsDialogState();
}

class _TestResultsDialogState extends State<_TestResultsDialog> {
  late final Set<String> _picked = {for (final r in widget.results) if (r.passed) r.model};

  @override
  Widget build(BuildContext context) {
    final best = widget.results.where((r) => r.passed).toList();
    return AlertDialog(
      title: Text('نتيجة اختبار ${widget.provider.label}'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              best.isEmpty
                  ? 'لم ينجح أي نموذج في قراءة الفاتورة التجريبية بدقة كافية بهذا المفتاح.'
                  : 'الأفضل لك: ${best.first.name.isEmpty ? best.first.model : best.first.name} — قرأ ${best.first.score} من ${best.first.total} أرقام في ${(best.first.ms / 1000).toStringAsFixed(1)} ثانية.',
              style: const TextStyle(fontWeight: FontWeight.w700, height: 1.5),
            ),
            const SizedBox(height: 4),
            const Text('الدرجة: كم رقماً قرأه صحيحاً من فاتورة تجريبية فيها 3 أسطر ومجموع.',
                style: TextStyle(color: kSetMuted, fontSize: 12)),
            const SizedBox(height: 10),
            for (var i = 0; i < widget.results.length; i++) _row(i, widget.results[i]),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
        FilledButton.icon(
          onPressed: _picked.isEmpty
              ? null
              : () => Navigator.pop(context, [for (final r in widget.results) if (_picked.contains(r.model)) r]),
          icon: const Icon(Icons.check_rounded),
          label: Text('اعتماد ${_picked.length} بهذا الترتيب'),
        ),
      ],
    );
  }

  Widget _row(int i, AiProbeResult r) {
    final color = r.passed ? kSetGreen : (r.ok && r.score > 0 ? kSetOrange : kSetRed);
    return CheckboxListTile(
      value: _picked.contains(r.model),
      onChanged: r.ok
          ? (v) => setState(() {
                if (v == true) {
                  _picked.add(r.model);
                } else {
                  _picked.remove(r.model);
                }
              })
          : null,
      dense: true,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text('${i + 1}. ${r.name.isEmpty ? r.model : r.name}', style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(
        r.ok ? '${r.score}/${r.total} • ${(r.ms / 1000).toStringAsFixed(1)} ث • ${r.note}' : r.note,
        style: TextStyle(color: color),
      ),
    );
  }
}

// ───────────────────────── إضافة نموذج يدوياً ─────────────────────────

class _AddModelDialog extends StatefulWidget {
  const _AddModelDialog();

  @override
  State<_AddModelDialog> createState() => _AddModelDialogState();
}

class _AddModelDialogState extends State<_AddModelDialog> {
  AiProvider _p = AiProvider.openrouter;
  final _id = TextEditingController();

  @override
  void dispose() {
    _id.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hint = switch (_p) {
      AiProvider.gemini => 'gemini-3.8-flash',
      AiProvider.groq => 'qwen/qwen3.8-27b',
      AiProvider.openrouter => 'google/gemma-4-31b-it:free',
    };
    return AlertDialog(
      title: const Text('إضافة نموذج يدوياً'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SegmentedButton<AiProvider>(
            segments: [for (final p in AiProvider.values) ButtonSegment(value: p, label: Text(p.label))],
            selected: {_p},
            onSelectionChanged: (s) => setState(() => _p = s.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _id,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText: 'معرّف النموذج (Model ID)',
              hintText: hint,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 8),
          const Text('بعد الإضافة اضغط «اختبار» بجانبه: إن لم يقرأ الصور يُعطَّل وحده.',
              style: TextStyle(color: kSetMuted, fontSize: 12)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
          onPressed: () {
            final id = _id.text.trim();
            if (id.isEmpty) return;
            Navigator.pop(context, AiModelEntry(provider: _p, model: id));
          },
          child: const Text('إضافة'),
        ),
      ],
    );
  }
}

// ───────────────────────── خطوات إنشاء المفتاح ─────────────────────────

class _GuideDialog extends StatelessWidget {
  const _GuideDialog({required this.provider});
  final AiProvider provider;

  List<String> get _steps => switch (provider) {
        AiProvider.gemini => const [
            'افتح Google AI Studio (الزر أدناه) وسجّل الدخول بحساب Google — إيميل فقط، بلا رقم هاتف ولا بطاقة.',
            'اضغط «Create API key» (أو Get API key ثم Create). اختر مشروعاً أو أنشئ مشروعاً جديداً.',
            'انسخ المفتاح (يبدأ بـ AIza…) والصقه في خانة Google Gemini هنا، ثم «حفظ واختبار».',
            'يختبر البرنامج نماذج Gemini المتاحة لحسابك ويرتّبها. الأفضل عادةً Gemini 3.8 Flash ثم Flash-Lite.',
            'الحصة مجانية وتتجدد يومياً. أرقامها الدقيقة في AI Studio ← Rate limits. '
                'مفاتيح المشروع نفسه تتشارك الحصة نفسها — المفتاح الثاني ينفع فقط إن كان من مشروع آخر.',
            'الخصوصية: في الطبقة المجانية قد تستعمل Google المحتوى المرسل لتحسين منتجاتها.',
          ],
        AiProvider.groq => const [
            'افتح Groq Console (الزر أدناه) وسجّل بالإيميل أو بحساب Google/GitHub.',
            'من القائمة: API Keys ← Create API Key ← اكتب اسماً (مثلاً «الناصر») ← Submit.',
            'انسخ المفتاح فوراً (يبدأ بـ gsk_…) — لا يظهر مرة أخرى. الصقه في خانة Groq هنا، ثم «حفظ واختبار».',
            'النموذج الذي يقرأ الصور: qwen/qwen3.8-27b — حصته المجانية 1000 طلب يومياً.',
            'حدوده: 3 صور في الطلب (الـ PDF الطويل يُقسم تلقائياً)، و8000 توكن في الدقيقة — '
                'لهذا يعمل مع «التعاون بين نموذجين» ولا يستطيع رؤية قائمة موادك كاملة.',
          ],
        AiProvider.openrouter => const [
            'افتح openrouter.ai واضغط Sign in — سجّل بحساب Google أو GitHub أو بإيميلك. لا رقم هاتف ولا بطاقة.',
            'افتح صفحة المفاتيح (الزر أدناه، أو من القائمة: Settings ← Keys).',
            'اضغط «Create Key»، اكتب اسماً (مثلاً «الناصر»)، اترك Credit limit فارغاً، ثم Create.',
            'انسخ المفتاح فوراً (يبدأ بـ sk-or-v1-…) — لا يظهر مرة أخرى.',
            'الصقه في خانة OpenRouter هنا واضغط «حفظ واختبار»: يجلب البرنامج النماذج المجانية التي تقرأ الصور، '
                'ويختبر أفضل 5 على فاتورة تجريبية، ويرتّبها لك — اعتمد المقترحة بضغطة.',
            'إن ظهر خطأ «data policy» أو «No endpoints found»: افتح Settings ← Privacy في OpenRouter '
                'واسمح بالنماذج المجانية، ثم أعد الاختبار.',
            'الحصة: 50 طلباً يومياً لكل النماذج المجانية (:free) معاً، وترتفع إلى 1000 يومياً إن شحنت 10\$ مرة واحدة '
                '(لا تُصرف على المجانية). كل فاتورة ≈ طلبان (قراءة + مطابقة).',
            'النماذج المجانية تتبدل كل أسابيع: أعد الاختبار شهرياً. البرنامج لا يرسل PDF إلى OpenRouter أبداً '
                '(يقرؤه بخدمة مدفوعة) — يحوّل الصفحات إلى صور بنفسه.',
          ],
      };

  @override
  Widget build(BuildContext context) {
    final c = _providerColor(provider);
    return AlertDialog(
      title: Row(children: [
        Icon(_providerIcon(provider), color: c),
        const SizedBox(width: 8),
        Expanded(child: Text('مفتاح ${provider.label} — خطوة بخطوة')),
      ]),
      content: SizedBox(width: 560, child: SingleChildScrollView(child: SetSteps(_steps, color: c))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: c),
          onPressed: () async {
            try {
              await launchUrl(Uri.parse(provider.keysUrl), mode: LaunchMode.externalApplication);
            } catch (_) {
              await Clipboard.setData(ClipboardData(text: provider.keysUrl));
              if (context.mounted) setToast(context, 'نُسخ الرابط: ${provider.keysUrl}');
            }
          },
          icon: const Icon(Icons.open_in_new_rounded),
          label: const Text('افتح صفحة المفاتيح'),
        ),
      ],
    );
  }
}
