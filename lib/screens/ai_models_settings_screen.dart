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

  static Color _scoreColor(AiProbeResult r) => r.passed ? kSetGreen : (r.ok && r.score > 0 ? kSetOrange : kSetRed);
  static String _secs(int ms) => '${(ms / 1000).toStringAsFixed(1)} ث';
  static String _name(AiProbeResult r) => r.name.isEmpty ? r.model : r.name;

  void _toggle(AiProbeResult r) {
    if (!r.ok) return;
    setState(() => _picked.contains(r.model) ? _picked.remove(r.model) : _picked.add(r.model));
  }

  @override
  Widget build(BuildContext context) {
    final c = _providerColor(widget.provider);
    final best = widget.results.where((r) => r.passed).toList();
    final h = MediaQuery.of(context).size.height;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      backgroundColor: kSetBg,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.96, end: 1),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        builder: (_, v, child) => Opacity(opacity: ((v - 0.96) / 0.04).clamp(0.0, 1.0), child: Transform.scale(scale: v, child: child)),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 600, maxHeight: h * 0.88),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _header(c),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (best.isNotEmpty) _bestCard(best.first, c) else _noneCard(),
                  const SizedBox(height: 18),
                  Row(children: [
                    const Expanded(child: _SectionLabel('كل النماذج المختبرة')),
                    Text('${_picked.length} مختار', style: TextStyle(fontSize: 12.5, color: c, fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 8),
                  for (var i = 0; i < widget.results.length; i++) _resultCard(i, widget.results[i], c),
                  const SizedBox(height: 6),
                  const _NoteCard(
                    note: _GuideNote(Icons.info_outline_rounded,
                        'الدرجة = كم رقماً قرأه النموذج صحيحاً من فاتورة تجريبية فيها 3 أسطر ومجموع (10 أرقام). '
                        'المختارة تُضاف إلى «ترتيب النماذج» بهذا الترتيب، والفاشلة تُعطَّل.'),
                  ),
                ]),
              ),
            ),
            _footer(c),
          ]),
        ),
      ),
    );
  }

  Widget _header(Color c) {
    final dark = Color.lerp(c, Colors.black, 0.28)!;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [c, dark], begin: AlignmentDirectional.topStart, end: AlignmentDirectional.bottomEnd),
      ),
      child: Row(children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.32)),
          ),
          child: const Icon(Icons.science_rounded, color: Colors.white, size: 28),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('نتيجة اختبار ${widget.provider.label}',
                style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('اختُبر ${widget.results.length} نموذج على قراءة فاتورة تجريبية',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.88))),
          ]),
        ),
        IconButton(
          tooltip: 'إغلاق',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close_rounded, color: Colors.white),
        ),
      ]),
    );
  }

  /// بطاقة «الأفضل لك»: حلقة الدرجة، الاسم، الزمن.
  Widget _bestCard(AiProbeResult r, Color c) {
    const gold = Color(0xFFD97706);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kSetGreen.withValues(alpha: 0.35), width: 1.4),
        boxShadow: [BoxShadow(color: kSetGreen.withValues(alpha: 0.10), blurRadius: 24, offset: const Offset(0, 8))],
      ),
      child: Row(children: [
        _ScoreRing(score: r.score, total: r.total, color: kSetGreen, size: 76),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.emoji_events_rounded, color: gold, size: 20),
              const SizedBox(width: 6),
              Text('الأفضل لك', style: TextStyle(color: gold.withValues(alpha: 0.95), fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 4),
            Text(_name(r), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: kSetText)),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              _pill(Icons.timer_outlined, _secs(r.ms), c),
              _pill(Icons.check_circle_outline_rounded, r.note, kSetGreen),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _noneCard() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: kSetRed.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kSetRed.withValues(alpha: 0.25)),
        ),
        child: const Row(children: [
          Icon(Icons.report_gmailerrorred_rounded, color: kSetRed, size: 30),
          SizedBox(width: 12),
          Expanded(
            child: Text('لم ينجح أي نموذج في قراءة الفاتورة التجريبية بدقة كافية بهذا المفتاح. '
                'جرّب مزوّداً آخر، أو أعد الاختبار لاحقاً إن كانت الحصة قد نفدت.',
                style: TextStyle(color: kSetText, height: 1.55)),
          ),
        ]),
      );

  Widget _pill(IconData i, String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(i, size: 14, color: c),
          const SizedBox(width: 4),
          Flexible(child: Text(t, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c))),
        ]),
      );

  /// نتيجة نموذج: الترتيب، الاسم، شريط الدرجة، الزمن، والاختيار.
  Widget _resultCard(int i, AiProbeResult r, Color c) {
    final picked = _picked.contains(r.model);
    final sc = _scoreColor(r);
    return Semantics(
      button: r.ok,
      selected: picked,
      label: '${_name(r)}، ${r.score} من ${r.total}',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: picked ? c.withValues(alpha: 0.06) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: picked ? c : kSetBorder, width: picked ? 1.6 : 1),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: r.ok ? () => _toggle(r) : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
              child: Row(children: [
                CircleAvatar(
                  radius: 15,
                  backgroundColor: sc.withValues(alpha: 0.12),
                  child: Text('${i + 1}', style: TextStyle(fontWeight: FontWeight.w800, color: sc, fontSize: 13)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_name(r),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.w800, color: r.ok ? kSetText : kSetMuted)),
                    if (r.name.isNotEmpty && r.name != r.model)
                      Text(r.model,
                          textDirection: TextDirection.ltr,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, color: kSetMuted)),
                    const SizedBox(height: 8),
                    if (r.ok) ...[
                      Row(children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0, end: r.total == 0 ? 0 : r.score / r.total),
                              duration: Duration(milliseconds: 500 + i * 120),
                              curve: Curves.easeOutCubic,
                              builder: (_, v, __) => LinearProgressIndicator(
                                value: v,
                                minHeight: 7,
                                color: sc,
                                backgroundColor: sc.withValues(alpha: 0.12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text('${r.score}/${r.total}', style: TextStyle(fontWeight: FontWeight.w800, color: sc)),
                        const SizedBox(width: 8),
                        Text(_secs(r.ms), style: const TextStyle(fontSize: 12, color: kSetMuted)),
                      ]),
                      const SizedBox(height: 4),
                    ],
                    Text(r.note, style: TextStyle(fontSize: 12, color: r.ok ? kSetMuted : kSetRed, height: 1.4)),
                  ]),
                ),
                Checkbox(
                  value: picked,
                  activeColor: c,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                  onChanged: r.ok ? (_) => _toggle(r) : null,
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _footer(Color c) => Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: kSetBorder))),
        child: Row(children: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
          const Spacer(),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: c,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: _picked.isEmpty
                ? null
                : () => Navigator.pop(context, [for (final r in widget.results) if (_picked.contains(r.model)) r]),
            icon: const Icon(Icons.check_rounded, size: 18),
            label: Text('اعتماد ${_picked.length} بهذا الترتيب', style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ]),
      );
}

/// حلقة الدرجة (تمتلئ بحركة).
class _ScoreRing extends StatelessWidget {
  const _ScoreRing({required this.score, required this.total, required this.color, this.size = 72});
  final int score;
  final int total;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final target = total == 0 ? 0.0 : score / total;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: target),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (_, v, __) => SizedBox(
        width: size,
        height: size,
        child: Stack(alignment: Alignment.center, children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: v,
              strokeWidth: 7,
              strokeCap: StrokeCap.round,
              color: color,
              backgroundColor: color.withValues(alpha: 0.12),
            ),
          ),
          Column(mainAxisSize: MainAxisSize.min, children: [
            Text('$score', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color, height: 1)),
            Text('من $total', style: const TextStyle(fontSize: 11, color: kSetMuted)),
          ]),
        ]),
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

/// رابط في دليل المفتاح.
class _GuideLink {
  const _GuideLink(this.label, this.url, [this.icon = Icons.open_in_new_rounded]);
  final String label;
  final String url;
  final IconData icon;
}

/// خطوة: عنوان، شرح، ونص يُنسخ (بداية المفتاح)، وروابطها.
class _GuideStep {
  const _GuideStep(this.title, this.body, {this.code, this.links = const []});
  final String title;
  final String body;
  final String? code;
  final List<_GuideLink> links;
}

/// ملاحظة أسفل الخطوات.
class _GuideNote {
  const _GuideNote(this.icon, this.text, {this.warn = false});
  final IconData icon;
  final String text;
  final bool warn;
}

class _Guide {
  const _Guide({required this.title, required this.tagline, required this.badges, required this.links, required this.steps, required this.notes});
  final String title;
  final String tagline;
  final List<String> badges;
  final List<_GuideLink> links;
  final List<_GuideStep> steps;
  final List<_GuideNote> notes;

  static _Guide of(AiProvider p) => switch (p) {
        AiProvider.gemini => const _Guide(
            title: 'مفتاح Google Gemini مجاني',
            tagline: 'الأقوى بين المجانيات، ويقرأ ملف الـ PDF مباشرة',
            badges: ['بالإيميل فقط', 'بلا بطاقة', 'يقرأ PDF'],
            links: [
              _GuideLink('Google AI Studio', 'https://aistudio.google.com', Icons.home_rounded),
              _GuideLink('صفحة المفاتيح', 'https://aistudio.google.com/app/apikey', Icons.key_rounded),
              _GuideLink('حدود الاستخدام', 'https://aistudio.google.com/rate-limit', Icons.speed_rounded),
              _GuideLink('الحصة المجانية', 'https://ai.google.dev/gemini-api/docs/pricing', Icons.receipt_long_rounded),
            ],
            steps: [
              _GuideStep('سجّل الدخول', 'افتح Google AI Studio وادخل بحساب Google — إيميل فقط، بلا رقم هاتف ولا بطاقة.',
                  links: [_GuideLink('افتح AI Studio', 'https://aistudio.google.com')]),
              _GuideStep('أنشئ المفتاح', 'من صفحة المفاتيح اضغط «Create API key»، واختر مشروعاً أو أنشئ مشروعاً جديداً.',
                  links: [_GuideLink('صفحة المفاتيح', 'https://aistudio.google.com/app/apikey')]),
              _GuideStep('انسخه', 'المفتاح يبدأ هكذا:', code: 'AIza…'),
              _GuideStep('الصقه واختبر', 'في خانة Google Gemini هنا ثم «حفظ واختبار» — يختبر البرنامج نماذج Gemini المتاحة لحسابك ويرتّبها لك.'),
            ],
            notes: [
              _GuideNote(Icons.autorenew_rounded, 'الحصة مجانية وتتجدد يومياً. أرقامها الدقيقة في صفحة «حدود الاستخدام».'),
              _GuideNote(Icons.layers_rounded, 'مفاتيح المشروع نفسه تتشارك الحصة نفسها — المفتاح الثاني ينفع فقط إن كان من مشروع آخر.'),
              _GuideNote(Icons.privacy_tip_outlined, 'في الطبقة المجانية قد تستعمل Google المحتوى المرسل لتحسين منتجاتها.', warn: true),
            ],
          ),
        AiProvider.groq => const _Guide(
            title: 'مفتاح Groq مجاني',
            tagline: 'سريع جداً — Qwen 3.8 يقرأ صور الفواتير',
            badges: ['بالإيميل فقط', 'بلا بطاقة', '1000 طلب يومياً'],
            links: [
              _GuideLink('Groq Console', 'https://console.groq.com', Icons.home_rounded),
              _GuideLink('صفحة المفاتيح', 'https://console.groq.com/keys', Icons.key_rounded),
              _GuideLink('قراءة الصور', 'https://console.groq.com/docs/vision', Icons.image_search_rounded),
            ],
            steps: [
              _GuideStep('أنشئ حساباً', 'سجّل بالإيميل أو بحساب Google أو GitHub.',
                  links: [_GuideLink('افتح Groq Console', 'https://console.groq.com')]),
              _GuideStep('أنشئ المفتاح', 'من «API Keys» اضغط «Create API Key»، اكتب اسماً مثل «الناصر» ثم Submit.',
                  links: [_GuideLink('صفحة المفاتيح', 'https://console.groq.com/keys')]),
              _GuideStep('انسخه فوراً', 'يظهر مرة واحدة فقط، ويبدأ هكذا:', code: 'gsk_…'),
              _GuideStep('الصقه واختبر', 'في خانة Groq هنا ثم «حفظ واختبار».'),
            ],
            notes: [
              _GuideNote(Icons.image_rounded, 'النموذج الذي يقرأ الصور: qwen/qwen3.8-27b — 3 صور في الطلب، والـ PDF الطويل يُقسم تلقائياً.'),
              _GuideNote(Icons.handshake_rounded, 'حدّه 8000 توكن في الدقيقة: يعمل مع «التعاون بين نموذجين» ولا يستطيع رؤية قائمة موادك كاملة.'),
            ],
          ),
        AiProvider.openrouter => const _Guide(
            title: 'مفتاح OpenRouter مجاني',
            tagline: 'نماذج مجانية متعددة تقرأ الصور (Gemma، Nemotron…)',
            badges: ['بالإيميل فقط', 'بلا بطاقة', '50 طلباً يومياً'],
            links: [
              _GuideLink('موقع OpenRouter', 'https://openrouter.ai', Icons.home_rounded),
              _GuideLink('صفحة المفاتيح', 'https://openrouter.ai/settings/keys', Icons.key_rounded),
              _GuideLink('إعدادات الخصوصية', 'https://openrouter.ai/settings/privacy', Icons.shield_outlined),
              _GuideLink('النماذج المجانية', 'https://openrouter.ai/collections/free-models', Icons.card_giftcard_rounded),
            ],
            steps: [
              _GuideStep('أنشئ حساباً', 'اضغط «Sign in» وسجّل بحساب Google أو GitHub أو بإيميلك. لا رقم هاتف ولا بطاقة.',
                  links: [_GuideLink('افتح OpenRouter', 'https://openrouter.ai')]),
              _GuideStep('افتح صفحة المفاتيح', 'من القائمة: Settings ← Keys.',
                  links: [_GuideLink('صفحة المفاتيح', 'https://openrouter.ai/settings/keys')]),
              _GuideStep('أنشئ المفتاح', 'اضغط «Create Key»، اكتب اسماً مثل «الناصر»، اترك Credit limit فارغاً ثم Create.'),
              _GuideStep('انسخه فوراً', 'يظهر مرة واحدة فقط، ويبدأ هكذا:', code: 'sk-or-v1-…'),
              _GuideStep('الصقه واختبر',
                  'في خانة OpenRouter هنا ثم «حفظ واختبار»: يجلب البرنامج النماذج المجانية التي تقرأ الصور، ويختبر أفضل 5، ويرتّبها لك.'),
              _GuideStep('إن ظهر خطأ «data policy»', 'افتح إعدادات الخصوصية واسمح بالنماذج المجانية، ثم أعد الاختبار.',
                  links: [_GuideLink('إعدادات الخصوصية', 'https://openrouter.ai/settings/privacy')]),
            ],
            notes: [
              _GuideNote(Icons.autorenew_rounded,
                  '50 طلباً يومياً لكل النماذج المجانية معاً، و1000 إن شحنت 10\$ مرة واحدة (لا تُصرف على المجانية). كل فاتورة ≈ طلبان.'),
              _GuideNote(Icons.swap_horiz_rounded, 'النماذج المجانية تتبدل كل أسابيع — أعد الاختبار شهرياً.'),
              _GuideNote(Icons.picture_as_pdf_outlined,
                  'لا يُرسل البرنامج ملف PDF إلى OpenRouter أبداً (يقرؤه بخدمة مدفوعة) — يحوّل الصفحات إلى صور بنفسه.',
                  warn: true),
            ],
          ),
      };
}

/// يفتح الرابط في المتصفح، وإن تعذّر يُنسخ.
Future<void> _openLink(BuildContext context, String url) async {
  var ok = false;
  try {
    ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (ok) return;
  await Clipboard.setData(ClipboardData(text: url));
  if (context.mounted) setToast(context, 'تعذّر فتح المتصفح — نُسخ الرابط: $url');
}

class _GuideDialog extends StatelessWidget {
  const _GuideDialog({required this.provider});
  final AiProvider provider;

  @override
  Widget build(BuildContext context) {
    final g = _Guide.of(provider);
    final c = _providerColor(provider);
    final h = MediaQuery.of(context).size.height;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      backgroundColor: kSetBg,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.96, end: 1),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        builder: (_, v, child) => Opacity(opacity: ((v - 0.96) / 0.04).clamp(0.0, 1.0), child: Transform.scale(scale: v, child: child)),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 620, maxHeight: h * 0.88),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _GuideHeader(guide: g, provider: provider, color: c),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const _SectionLabel('روابط سريعة'),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [for (final l in g.links) _LinkChip(link: l, color: c)]),
                  const SizedBox(height: 20),
                  const _SectionLabel('الخطوات'),
                  const SizedBox(height: 10),
                  for (var i = 0; i < g.steps.length; i++)
                    _StepTile(index: i, step: g.steps[i], color: c, last: i == g.steps.length - 1),
                  if (g.notes.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const _SectionLabel('معلومات مهمة'),
                    const SizedBox(height: 8),
                    for (final n in g.notes) _NoteCard(note: n),
                  ],
                ]),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: kSetBorder))),
              child: Row(children: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
                const Spacer(),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: c,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => _openLink(context, provider.keysUrl),
                  icon: const Icon(Icons.key_rounded, size: 18),
                  label: const Text('افتح صفحة المفاتيح', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _GuideHeader extends StatelessWidget {
  const _GuideHeader({required this.guide, required this.provider, required this.color});
  final _Guide guide;
  final AiProvider provider;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final dark = Color.lerp(color, Colors.black, 0.28)!;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [color, dark], begin: AlignmentDirectional.topStart, end: AlignmentDirectional.bottomEnd),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.32)),
            ),
            child: Icon(_providerIcon(provider), color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(guide.title, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(guide.tagline, style: TextStyle(color: Colors.white.withValues(alpha: 0.88), height: 1.4)),
            ]),
          ),
          IconButton(
            tooltip: 'إغلاق',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded, color: Colors.white),
          ),
        ]),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final b in guide.badges)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.check_rounded, size: 15, color: Colors.white),
                const SizedBox(width: 4),
                Text(b, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700)),
              ]),
            ),
        ]),
      ]),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: kSetMuted, letterSpacing: 0.2));
}

/// رابط قابل للضغط: يفتح المتصفح، ويتلوّن عند المرور عليه.
class _LinkChip extends StatefulWidget {
  const _LinkChip({required this.link, required this.color});
  final _GuideLink link;
  final Color color;
  @override
  State<_LinkChip> createState() => _LinkChipState();
}

class _LinkChipState extends State<_LinkChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.color;
    return Semantics(
      link: true,
      label: widget.link.label,
      child: Tooltip(
        message: widget.link.url,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            decoration: BoxDecoration(
              color: _hover ? c.withValues(alpha: 0.12) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _hover ? c : c.withValues(alpha: 0.28)),
              boxShadow: _hover ? [BoxShadow(color: c.withValues(alpha: 0.18), blurRadius: 12, offset: const Offset(0, 4))] : const [],
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _openLink(context, widget.link.url),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(widget.link.icon, size: 17, color: c),
                    const SizedBox(width: 6),
                    Text(widget.link.label, style: TextStyle(color: c, fontWeight: FontWeight.w700, decoration: _hover ? TextDecoration.underline : null)),
                    const SizedBox(width: 4),
                    Icon(Icons.north_west_rounded, size: 13, color: c.withValues(alpha: 0.7)),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// خطوة في خط زمني مرقّم.
class _StepTile extends StatelessWidget {
  const _StepTile({required this.index, required this.step, required this.color, required this.last});
  final int index;
  final _GuideStep step;
  final Color color;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 34,
          child: Column(children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [color, Color.lerp(color, Colors.black, 0.2)!]),
                boxShadow: [BoxShadow(color: color.withValues(alpha: 0.30), blurRadius: 8, offset: const Offset(0, 3))],
              ),
              child: Text('${index + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            ),
            if (!last)
              Expanded(
                child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: 4), color: color.withValues(alpha: 0.18)),
              ),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: last ? 4 : 18, top: 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(step.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: kSetText)),
              const SizedBox(height: 4),
              Text(step.body, style: const TextStyle(color: kSetMuted, height: 1.55)),
              if (step.code != null) ...[
                const SizedBox(height: 8),
                _CodeChip(code: step.code!, color: color),
              ],
              if (step.links.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  for (final l in step.links)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: color,
                        backgroundColor: color.withValues(alpha: 0.08),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => _openLink(context, l.url),
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: Text(l.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                ]),
              ],
            ]),
          ),
        ),
      ]),
    );
  }
}

/// بداية المفتاح بخط ثابت — ليعرف المستخدم أنه نسخ الشيء الصحيح.
class _CodeChip extends StatelessWidget {
  const _CodeChip({required this.code, required this.color});
  final String code;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.vpn_key_rounded, size: 15, color: Color(0xFF94A3B8)),
          const SizedBox(width: 8),
          Text(code,
              textDirection: TextDirection.ltr,
              style: const TextStyle(color: Color(0xFFE2E8F0), fontFamily: 'monospace', fontWeight: FontWeight.w700, letterSpacing: 0.5)),
        ]),
      );
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note});
  final _GuideNote note;

  @override
  Widget build(BuildContext context) {
    final c = note.warn ? kSetOrange : kSetBlue;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.withValues(alpha: 0.22)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
          child: Icon(note.icon, size: 17, color: c),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(note.text, style: const TextStyle(color: kSetText, height: 1.55))),
      ]),
    );
  }
}
