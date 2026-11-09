// lib/owner/wa_auto/wa_auto_screen.dart
//
// ⚙️ «طريقة الإرسال والأمان» لرسائل واتساب (لمدير البرنامج): التفعيل والموافقة على الخطر،
// WhatsApp Desktop أو الخادم، الفواصل والحد اليومي، النص الافتراضي وعنوان المحل، ورسالة
// تجربة. لمن ومتى: في «القواعد التلقائية» و«إرسال الآن» (lib/wa_messages/).

import 'package:flutter/material.dart';

import '../../wa_messages/wa_compose.dart';
import '../../widgets/settings_kit.dart';
import 'wa_auto_reminder.dart';
import 'wa_desktop.dart';
import 'wa_server_screen.dart';
import 'wa_usage_banner.dart';
import 'wa_usage_mark.dart';

class WaAutoScreen extends StatefulWidget {
  const WaAutoScreen({super.key});

  @override
  State<WaAutoScreen> createState() => _WaAutoScreenState();
}

class _WaAutoScreenState extends State<WaAutoScreen> {
  WaAutoSettings? _s;
  final _tpl = TextEditingController();
  final _addr = TextEditingController();
  final _minDelay = TextEditingController();
  final _maxDelay = TextEditingController();
  final _perDay = TextEditingController();
  final _loadWait = TextEditingController();
  final _testPhone = TextEditingController();
  bool _testing = false;
  String? _testResult;
  String _shop = '';
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_tpl, _addr, _minDelay, _maxDelay, _perDay, _loadWait, _testPhone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final s = await WaAutoReminder.load();
    _tpl.text = s.template;
    _addr.text = await WaCompose.address();
    _minDelay.text = '${s.minDelay}';
    _maxDelay.text = '${s.maxDelay}';
    _perDay.text = '${s.maxPerDay}';
    _loadWait.text = '${s.loadWait}';
    _shop = await WaAutoReminder.shopName();
    if (mounted) setState(() => _s = s);
  }

  int _int(TextEditingController c, int def) => int.tryParse(c.text.replaceAll(',', '').trim()) ?? def;

  WaAutoSettings _fromFields(WaAutoSettings s) => s.copyWith(
        template: _tpl.text.trim().isEmpty ? WaAutoSettings.defaultTemplate : _tpl.text,
        minDelay: _int(_minDelay, s.minDelay),
        maxDelay: _int(_maxDelay, s.maxDelay),
        maxPerDay: _int(_perDay, s.maxPerDay),
        loadWait: _int(_loadWait, s.loadWait),
      );

  Future<void> _save([WaAutoSettings? next]) async {
    await WaAutoReminder.save(_fromFields(next ?? _s!));
    await WaCompose.setAddress(_addr.text);
    final reloaded = await WaAutoReminder.load();
    if (!mounted) return;
    setState(() {
      _s = reloaded;
      _dirty = false;
      _minDelay.text = '${reloaded.minDelay}';
      _maxDelay.text = '${reloaded.maxDelay}';
      _perDay.text = '${reloaded.maxPerDay}';
      _loadWait.text = '${reloaded.loadWait}';
    });
  }

  Future<void> _enable(bool on) async {
    if (on && !(_s!.riskAccepted)) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded, color: Color(0xFFB45309), size: 36),
          title: const Text('إرسال آلي من رقم واتساب عادي'),
          content: const Text(
            'هذه ليست طريقة رسمية من واتساب. واتساب قد يقيّد أو يحظر الرقم إن رأى رسائل آلية كثيرة، '
            'خاصة إن أبلغ عنها المستلمون.\n\n'
            'البرنامج يقلل الخطر (فاصل عشوائي، حد يومي، قواعد تمنع التكرار)، لكنه لا يلغيه.',
            style: TextStyle(height: 1.6),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB45309)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('أفهم الخطر وأتحمّله'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      await WaUsageMark.record(_s!.via); // 🔖 علامة دائمة لا يمحوها الإطفاء
      await _save(_s!.copyWith(enabled: true, riskAccepted: true));
      return;
    }
    if (on) await WaUsageMark.record(_s!.via);
    await _save(_s!.copyWith(enabled: on));
  }

  Future<void> _test() async {
    if (_dirty) await _save();
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final err = await WaAutoReminder.sendTest(_testPhone.text);
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResult = err == null ? 'أُرسلت ✓ — تأكد من وصولها على الرقم الآخر' : 'لم تُرسل: $err';
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    if (s == null) {
      return const SettingsScaffold(title: 'طريقة الإرسال والأمان', icon: Icons.tune_rounded, loading: true);
    }
    return SettingsScaffold(
      title: 'طريقة الإرسال والأمان',
      icon: Icons.tune_rounded,
      subtitle: 'تُطبَّق على كل رسائل واتساب: القواعد التلقائية والإرسال اليدوي',
      bottom: _dirty
          ? Padding(
              padding: const EdgeInsets.all(12),
              child: SetPrimaryButton(label: 'حفظ التعديلات', icon: Icons.save_rounded, onPressed: () => _save()),
            )
          : null,
      children: [
        const WaUsageBanner(),
        const SetBanner(
          'الإرسال من رقم واتساب عادي ليس طريقة رسمية: قد يُقيَّد الرقم. لا يتغيّر أي دين أو معاملة — البرنامج يقرأ المبلغ فقط.',
          kind: SetBannerKind.warn,
        ),
        const SizedBox(height: 12),
        SetCard(
          title: 'التشغيل',
          icon: Icons.power_settings_new_rounded,
          child: Column(children: [
            SetSwitch(
              title: 'تفعيل الإرسال الآلي عبر واتساب',
              subtitle: s.riskAccepted ? 'وافقت على الخطر' : 'يطلب موافقتك على الخطر أول مرة',
              value: s.enabled,
              onChanged: _enable,
            ),
            if (WaAutoReminder.desktopPossible)
            SetSwitch(
              title: 'إرجاع البرنامج إلى المقدمة بعد كل رسالة',
              subtitle: 'مع WhatsApp Desktop: يظهر واتساب بضع ثوانٍ لكل رسالة ثم تعود شاشة البرنامج',
              value: s.refocus,
              onChanged: (v) => _save(s.copyWith(refocus: v)),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        SetCard(
          title: 'طريقة الإرسال',
          icon: Icons.alt_route_rounded,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (!WaAutoReminder.desktopPossible)
              const Text('📱 على هذا الجهاز: الإرسال عبر «الخادم» دائماً (WhatsApp Desktop على ويندوز فقط). '
                  'الخادم إما على هذا الهاتف نفسه، أو على حاسبة المحل — تختار من «خادم واتساب».',
                  style: TextStyle(fontWeight: FontWeight.w700, height: 1.6))
            else
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'server', label: Text('الخادم (موصى به)'), icon: Icon(Icons.dns_rounded)),
                ButtonSegment(value: 'desktop', label: Text('WhatsApp Desktop'), icon: Icon(Icons.desktop_windows_rounded)),
              ],
              selected: {s.via},
              onSelectionChanged: (v) => _save(s.copyWith(via: v.first)),
            ),
            const SizedBox(height: 8),
            Text(
              s.viaServer
                  ? 'يرسل الخادم في الخلفية من رقم المحل المرتبط به، ويرسل ملفات PDF — تستطيع العمل أثناء الإرسال.'
                  : (WaDesktop.supported
                      ? 'البرنامج يفتح WhatsApp Desktop ويضغط «إرسال» بنفسه — يقاطع عملك، ولا يرسل ملفات (الكشف يصل نصاً).'
                      : 'الإرسال الآلي يعمل على ويندوز فقط.'),
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WaServerScreen())),
                icon: const Icon(Icons.dns_rounded),
                label: const Text('خادم واتساب: التشغيل والربط'),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        SetCard(
          title: 'الرسالة الافتراضية وعنوان المحل',
          icon: Icons.edit_note_rounded,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('المتغيرات: {الاسم} {المبلغ} {المحل} {العنوان} {التاريخ} — التحية في أولها تتنوع بين الزبائن',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
            const SizedBox(height: 8),
            _field(_tpl, 'النص الافتراضي', lines: 5),
            const SizedBox(height: 10),
            _field(_addr, 'عنوان المحل (يُضاف للرسالة إن اخترت ذلك)', lines: 2),
            const SizedBox(height: 10),
            const Text('معاينة:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFDCF8C6), borderRadius: BorderRadius.circular(12)),
              child: Text(
                WaCompose.renderText(
                  _tpl.text.trim().isEmpty ? WaAutoSettings.defaultTemplate : _tpl.text,
                  WaTarget(id: 0, name: 'أحمد', phone: '', debt: 125000),
                  _shop,
                  address: _addr.text,
                ),
                style: const TextStyle(height: 1.6),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        SetCard(
          title: 'الأمان والسرعة',
          icon: Icons.shield_outlined,
          child: Column(children: [
            Row(children: [
              Expanded(child: _field(_minDelay, 'أقل فاصل (ثانية)', number: true)),
              const SizedBox(width: 10),
              Expanded(child: _field(_maxDelay, 'أكثر فاصل (ثانية)', number: true)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _field(_perDay, 'حد الرسائل في اليوم', number: true)),
              const SizedBox(width: 10),
              Expanded(child: _field(_loadWait, 'مهلة تحميل المحادثة (Desktop، ثانية)', number: true)),
            ]),
          ]),
        ),
        const SizedBox(height: 12),
        SetCard(
          title: 'رسالة تجربة',
          icon: Icons.science_outlined,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('النص الافتراضي باسم «تجربة» ومبلغ 125,000 إلى الرقم الذي تكتبه — لا تُسجَّل ولا تخص أي عميل.',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B), height: 1.5)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _testPhone,
                  keyboardType: TextInputType.phone,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(
                      labelText: 'رقم التجربة (مثل 07701234567)', border: OutlineInputBorder(), isDense: true),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: !s.enabled || _testing ? null : _test,
                icon: _testing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded),
                label: const Text('أرسل تجربة'),
              ),
            ]),
            if (_testResult != null) ...[
              const SizedBox(height: 8),
              Text(_testResult!,
                  style: TextStyle(
                      color: _testResult!.startsWith('أُرسلت') ? const Color(0xFF047857) : const Color(0xFFB91C1C))),
            ],
          ]),
        ),
        const SizedBox(height: 60),
      ],
    );
  }

  Widget _field(TextEditingController c, String label, {bool number = false, int lines = 1}) => TextField(
        controller: c,
        maxLines: lines,
        keyboardType: number ? TextInputType.number : TextInputType.multiline,
        onChanged: (_) => setState(() => _dirty = true),
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
      );
}
