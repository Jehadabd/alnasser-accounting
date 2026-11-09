// lib/marketing/marketing_screen.dart
//
// 📣 «مركز التسويق» (للمدير): ربط صفحة فيسبوك (وإنستغرامها) بالواجهة الرسمية، جدولة
// المنشورات والنشر الآلي، الحملات، وتقرير التفاعل لكل منشور منشور.

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:url_launcher/url_launcher.dart';

import '../services/auth_service.dart';
import '../widgets/settings_kit.dart';
import 'marketing_publisher.dart';
import 'marketing_store.dart';
import 'meta_graph_client.dart';

final _d = DateFormat('yyyy/MM/dd HH:mm', 'en');

class MarketingScreen extends StatefulWidget {
  const MarketingScreen({super.key});
  @override
  State<MarketingScreen> createState() => _MarketingScreenState();
}

class _MarketingScreenState extends State<MarketingScreen> {
  final _store = MarketingStore();
  int _tab = 0;
  Map<String, String> _cfg = const {};
  bool _hasToken = false;
  List<MkPost> _posts = const [];
  List<Map<String, Object?>> _campaigns = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cfg = await _store.settings();
    final t = await _store.token();
    final p = await _store.posts();
    final c = await _store.campaigns();
    if (!mounted) return;
    setState(() {
      _cfg = cfg;
      _hasToken = t != null && t.isNotEmpty;
      _posts = p;
      _campaigns = c;
    });
  }

  bool get _connected => _hasToken && (_cfg['page_id'] ?? '').isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (!(AuthService().currentUser?.isAdmin ?? false)) {
      return const SettingsScaffold(title: 'مركز التسويق', icon: Icons.campaign_rounded, children: [SetBanner('للمدير فقط', kind: SetBannerKind.warn)]);
    }
    return SettingsScaffold(
      title: 'مركز التسويق',
      icon: Icons.campaign_rounded,
      subtitle: 'صفحة فيسبوك وإنستغرام: جدولة ونشر آلي عبر واجهة Meta الرسمية',
      actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      floatingActionButton: _tab == 1
          ? FloatingActionButton.extended(onPressed: () => _editPost(), icon: const Icon(Icons.add_rounded), label: const Text('منشور'))
          : (_tab == 2
              ? FloatingActionButton.extended(onPressed: _addCampaign, icon: const Icon(Icons.add_rounded), label: const Text('حملة'))
              : null),
      children: [
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('الحساب'), icon: Icon(Icons.link_rounded)),
            ButtonSegment(value: 1, label: Text('المنشورات'), icon: Icon(Icons.schedule_send_rounded)),
            ButtonSegment(value: 2, label: Text('الحملات'), icon: Icon(Icons.flag_rounded)),
          ],
          selected: {_tab},
          onSelectionChanged: (s) => setState(() => _tab = s.first),
        ),
        const SizedBox(height: 12),
        ...(switch (_tab) {
          0 => <Widget>[_AccountCard(store: _store, cfg: _cfg, hasToken: _hasToken, onChanged: _load)],
          1 => _postsView(),
          _ => _campaignsView(),
        }),
        const SizedBox(height: 80),
      ],
    );
  }

  // ───────────── المنشورات ─────────────

  List<Widget> _postsView() => [
        if (!_connected)
          const SetBanner('اربط الصفحة أولاً من تبويب «الحساب» — المنشورات تُحفظ وتنتظر.', kind: SetBannerKind.warn),
        if (_cfg['auto'] != '1' && _connected)
          const SetBanner('النشر الآلي مطفأ: فعّله من «الحساب» لتُنشر المجدولة في وقتها.', kind: SetBannerKind.warn),
        const SizedBox(height: 8),
        if (_posts.isEmpty)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('لا منشورات')))
        else
          for (final p in _posts)
            Card(
              elevation: 0,
              child: ListTile(
                leading: Icon(
                  switch (p.status) {
                    MkStatus.published => Icons.check_circle_rounded,
                    MkStatus.failed => Icons.error_rounded,
                    MkStatus.scheduled => Icons.schedule_rounded,
                    MkStatus.publishing => Icons.sync_rounded,
                    MkStatus.draft => Icons.edit_note_rounded,
                  },
                  color: switch (p.status) {
                    MkStatus.published => kSetGreen,
                    MkStatus.failed => kSetRed,
                    _ => kSetNavy,
                  },
                ),
                title: Text(p.text.isEmpty ? '(صورة فقط)' : p.text, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text([
                  _d.format(p.at),
                  [if (p.facebook) 'فيسبوك', if (p.instagram) 'إنستغرام'].join(' + '),
                  if (p.error != null) p.error!,
                ].join(' • ')),
                onTap: p.status == MkStatus.published ? () => _stats(p) : () => _editPost(p),
              ),
            ),
      ];

  Future<void> _editPost([MkPost? p]) async {
    final saved = await showDialog<bool>(
        context: context, builder: (_) => _PostDialog(store: _store, post: p, campaigns: _campaigns, igReady: (_cfg['ig_id'] ?? '').isNotEmpty));
    if (saved == true) await _load();
  }

  Future<void> _stats(MkPost p) async {
    final token = await _store.token();
    if (token == null || !mounted) return;
    final c = MetaGraphClient(token);
    final lines = <String>[];
    try {
      if (p.fbId != null) {
        final s = await c.facebookStats(p.fbId!);
        lines.add('فيسبوك: ${s.reactions} تفاعل • ${s.comments} تعليق • ${s.shares} مشاركة');
      }
      if (p.igId != null) {
        final s = await c.instagramStats(p.igId!);
        lines.add('إنستغرام: ${s.likes} إعجاب • ${s.comments} تعليق');
      }
    } on MetaException catch (e) {
      lines.add(e.message);
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تقرير المنشور'),
        content: Text([p.text, '', ...lines].join('\n'), style: const TextStyle(height: 1.6)),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق'))],
      ),
    );
  }

  // ───────────── الحملات ─────────────

  List<Widget> _campaignsView() => [
        if (_campaigns.isEmpty)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('لا حملات')))
        else
          for (final c in _campaigns)
            Builder(builder: (_) {
              final posts = _posts.where((p) => p.campaignId == c['id']).toList();
              final done = posts.where((p) => p.status == MkStatus.published).length;
              return SetCard(
                title: '${c['name']}',
                subtitle: '${c['from_day']} ← ${c['to_day']}',
                icon: Icons.flag_rounded,
                child: Text([
                  if ('${c['goal'] ?? ''}'.isNotEmpty) 'الهدف: ${c['goal']}',
                  '${posts.length} منشور • نُشر $done',
                ].join('\n')),
              );
            }),
      ];

  Future<void> _addCampaign() async {
    final name = TextEditingController();
    final goal = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حملة جديدة'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'الاسم')),
          TextField(controller: goal, decoration: const InputDecoration(labelText: 'الهدف (مثل: تخفيضات الشتاء)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('التالي: المدة')),
        ],
      ),
    );
    final n = name.text, g = goal.text;
    name.dispose();
    goal.dispose();
    if (ok != true || n.trim().isEmpty || !mounted) return;
    final r = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (r == null) return;
    await _store.addCampaign(n, r.start, r.end, g);
    await _load();
  }
}

// ═════════════════════ الحساب ═════════════════════

class _AccountCard extends StatefulWidget {
  const _AccountCard({required this.store, required this.cfg, required this.hasToken, required this.onChanged});
  final MarketingStore store;
  final Map<String, String> cfg;
  final bool hasToken;
  final Future<void> Function() onChanged;
  @override
  State<_AccountCard> createState() => _AccountCardState();
}

class _AccountCardState extends State<_AccountCard> {
  late final _page = TextEditingController(text: widget.cfg['page_id'] ?? '');
  final _token = TextEditingController();
  bool _busy = false;
  String? _msg;

  @override
  void dispose() {
    _page.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final token = _token.text.trim().isNotEmpty ? _token.text.trim() : await widget.store.token();
    if (token == null || token.isEmpty || _page.text.trim().isEmpty) {
      setState(() => _msg = 'اكتب رقم الصفحة والرمز');
      return;
    }
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      final p = await MetaGraphClient(token).page(_page.text.trim());
      await widget.store.setToken(token);
      await widget.store.setSetting('page_id', p.id);
      await widget.store.setSetting('page_name', p.name);
      await widget.store.setSetting('ig_id', p.instagramId);
      _token.clear();
      setState(() => _msg = 'رُبطت الصفحة «${p.name}»${p.instagramId == null ? ' (بلا إنستغرام أعمال)' : ' وحساب إنستغرامها'} ✓');
      await widget.onChanged();
    } on MetaException catch (e) {
      setState(() => _msg = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _link(String label, String url) => TextButton.icon(
        style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
        onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
        icon: const Icon(Icons.open_in_new_rounded, size: 16),
        label: Text(label),
      );

  @override
  Widget build(BuildContext context) {
    final cfg = widget.cfg;
    final connected = widget.hasToken && (cfg['page_id'] ?? '').isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SetCard(
        title: connected ? 'مربوطة: ${cfg['page_name'] ?? cfg['page_id']}' : 'ربط صفحة فيسبوك',
        icon: Icons.facebook,
        color: connected ? kSetGreen : kSetNavy,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text(
            '1) في Meta for Developers أنشئ تطبيقاً (نوع Business) وأنت مدير الصفحة.\n'
            '2) من Graph API Explorer اختر التطبيق والصفحة، وأعطِ الصلاحيات: pages_manage_posts و pages_read_engagement '
            '(ولإنستغرام: instagram_basic و instagram_content_publish)، ثم انسخ «Page Access Token».\n'
            '3) الصق رقم الصفحة والرمز هنا. التطبيق في وضع التطوير يكفي لصفحتك أنت — لا تتجاوز قيود Meta.',
            style: TextStyle(fontSize: 12.5, height: 1.6, color: kSetMuted),
          ),
          Wrap(spacing: 12, children: [
            _link('Meta for Developers', 'https://developers.facebook.com/apps'),
            _link('Graph API Explorer', 'https://developers.facebook.com/tools/explorer'),
          ]),
          const SizedBox(height: 8),
          TextField(controller: _page, decoration: const InputDecoration(labelText: 'رقم الصفحة (Page ID)'), textDirection: TextDirection.ltr),
          TextField(
            controller: _token,
            obscureText: true,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(labelText: widget.hasToken ? 'رمز جديد (اتركه فارغاً لإبقاء المحفوظ)' : 'رمز الصفحة (Page Access Token)'),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            FilledButton.icon(onPressed: _busy ? null : _connect, icon: const Icon(Icons.link_rounded), label: const Text('تحقق واربط')),
            if (widget.hasToken)
              TextButton(
                onPressed: () async {
                  await widget.store.setToken(null);
                  await widget.onChanged();
                },
                child: const Text('حذف الرمز'),
              ),
          ]),
          if (_msg != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_msg!)),
        ]),
      ),
      const SizedBox(height: 10),
      SetCard(
        title: 'النشر الآلي',
        icon: Icons.schedule_send_rounded,
        child: SetSwitch(
          title: 'انشر المجدولة في وقتها',
          subtitle: 'ما دام البرنامج مفتوحاً • منشور كل ${MarketingPublisher.minGap.inMinutes} دقيقة على الأكثر • حتى ${MarketingPublisher.maxPerDay} في اليوم',
          value: cfg['auto'] == '1',
          onChanged: !connected
              ? null
              : (v) async {
                  await widget.store.setSetting('auto', v ? '1' : '0');
                  await widget.onChanged();
                },
        ),
      ),
    ]);
  }
}

// ═════════════════════ منشور ═════════════════════

class _PostDialog extends StatefulWidget {
  const _PostDialog({required this.store, this.post, required this.campaigns, required this.igReady});
  final MarketingStore store;
  final MkPost? post;
  final List<Map<String, Object?>> campaigns;
  final bool igReady;
  @override
  State<_PostDialog> createState() => _PostDialogState();
}

class _PostDialogState extends State<_PostDialog> {
  late final _text = TextEditingController(text: widget.post?.text ?? '');
  late final _url = TextEditingController(text: widget.post?.imageUrl ?? '');
  late String? _image = widget.post?.imagePath;
  late DateTime _at = widget.post?.at ?? DateTime.now().add(const Duration(hours: 1));
  late bool _fb = widget.post?.facebook ?? true;
  late bool _ig = widget.post?.instagram ?? false;
  late int? _campaign = widget.post?.campaignId;
  String? _err;

  @override
  void dispose() {
    _text.dispose();
    _url.dispose();
    super.dispose();
  }

  MkPost _build(MkStatus status) => MkPost(
        id: widget.post?.id,
        text: _text.text.trim(),
        imagePath: _image,
        imageUrl: _url.text.trim().isEmpty ? null : _url.text.trim(),
        at: _at,
        facebook: _fb,
        instagram: _ig,
        status: status,
        campaignId: _campaign,
      );

  Future<void> _save(MkStatus status) async {
    final p = _build(status);
    final problem = status == MkStatus.draft ? null : p.problem;
    if (problem != null) {
      setState(() => _err = problem);
      return;
    }
    await widget.store.savePost(p);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _pickTime() async {
    final d = await showDatePicker(context: context, initialDate: _at, firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_at));
    if (t == null) return;
    setState(() => _at = DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.post == null ? 'منشور جديد' : 'تعديل المنشور'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(controller: _text, maxLines: 6, decoration: const InputDecoration(labelText: 'النص', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: Text(_image == null ? 'بلا صورة من الجهاز' : _image!.split(RegExp(r'[\\/]')).last, overflow: TextOverflow.ellipsis)),
                TextButton(
                  onPressed: () async {
                    final r = await FilePicker.platform.pickFiles(type: FileType.image);
                    final path = r?.files.single.path;
                    if (path != null) setState(() => _image = path);
                  },
                  child: const Text('صورة'),
                ),
                if (_image != null) IconButton(onPressed: () => setState(() => _image = null), icon: const Icon(Icons.close_rounded)),
              ]),
              CheckboxListTile(contentPadding: EdgeInsets.zero, title: const Text('فيسبوك'), value: _fb, onChanged: (v) => setState(() => _fb = v ?? false)),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('إنستغرام'),
                subtitle: Text(widget.igReady ? 'يحتاج رابط صورة عاماً (https)' : 'لا حساب إنستغرام أعمال مرتبط بالصفحة'),
                value: _ig,
                onChanged: widget.igReady ? (v) => setState(() => _ig = v ?? false) : null,
              ),
              if (_ig) TextField(controller: _url, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'رابط الصورة العام (https://…)')),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_rounded),
                title: Text('الموعد: ${_d.format(_at)}'),
                onTap: _pickTime,
              ),
              DropdownButton<int?>(
                value: _campaign,
                isExpanded: true,
                hint: const Text('بلا حملة'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('بلا حملة')),
                  for (final c in widget.campaigns) DropdownMenuItem(value: c['id'] as int, child: Text('${c['name']}')),
                ],
                onChanged: (v) => setState(() => _campaign = v),
              ),
              if (_err != null) Text(_err!, style: const TextStyle(color: kSetRed)),
            ]),
          ),
        ),
        actions: [
          if (widget.post?.id != null)
            TextButton(
              onPressed: () async {
                await widget.store.deletePost(widget.post!.id!);
                if (context.mounted) Navigator.pop(context, true);
              },
              child: const Text('حذف', style: TextStyle(color: kSetRed)),
            ),
          TextButton(onPressed: () => _save(MkStatus.draft), child: const Text('مسودة')),
          FilledButton(onPressed: () => _save(MkStatus.scheduled), child: const Text('جدولة')),
        ],
      );
}
