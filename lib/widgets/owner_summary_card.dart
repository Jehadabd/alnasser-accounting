// lib/widgets/owner_summary_card.dart
//
// 📊 بطاقة «ملخص المالك اليومي» في إعدادات تيليجرام: تفعيل، وقت الإرسال،
// معاينة، وإرسال تجريبي. الإعداد لهذا الجهاز فقط.

import 'package:flutter/material.dart';

import '../services/owner_summary.dart';
import 'settings_kit.dart';

class OwnerSummaryCard extends StatefulWidget {
  const OwnerSummaryCard({super.key, required this.telegramReady});

  /// التوكن والقناة محفوظان (وإلا لا يُرسل شيء).
  final bool telegramReady;

  @override
  State<OwnerSummaryCard> createState() => _OwnerSummaryCardState();
}

class _OwnerSummaryCardState extends State<OwnerSummaryCard> {
  static const _c = Color(0xFF0E7490);
  bool? _enabled;
  TimeOfDay _time = const TimeOfDay(hour: 21, minute: 0);
  String? _last;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final e = await OwnerSummary.enabled();
    final t = await OwnerSummary.time();
    final l = await OwnerSummary.lastSent();
    if (!mounted) return;
    setState(() {
      _enabled = e;
      _time = TimeOfDay(hour: t.hour, minute: t.minute);
      _last = l;
    });
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: _time, helpText: 'وقت إرسال الملخص');
    if (t == null) return;
    await OwnerSummary.setTime(t.hour, t.minute);
    if (mounted) setState(() => _time = t);
  }

  Future<void> _preview() async {
    setState(() => _busy = true);
    try {
      final text = OwnerSummary.format(await OwnerSummary.build(DateTime.now()));
      if (!mounted) return;
      // عرض بلا وسوم HTML
      final plain = text
          .replaceAll(RegExp(r'</?b>'), '')
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&amp;', '&');
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('معاينة ملخص اليوم'),
          content: SizedBox(width: 460, child: SingleChildScrollView(child: SelectableText(plain, style: const TextStyle(height: 1.7)))),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق'))],
        ),
      );
    } catch (e) {
      if (mounted) setToast(context, 'تعذّر بناء الملخص: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendNow() async {
    setState(() => _busy = true);
    // تجريبي: لا يُحسب «إرسال اليوم» — الملخص التلقائي يُرسل في موعده بأرقام اليوم كاملاً
    final err = await OwnerSummary.sendFor(DateTime.now(), markSent: false);
    if (!mounted) return;
    setState(() => _busy = false);
    setToast(context, err == null ? 'أُرسل ملخص اليوم إلى القناة' : 'لم يُرسل: $err', error: err != null);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _enabled;
    final canSend = OwnerSummary.deviceCanSend;
    return SetCard(
      title: 'ملخص المالك اليومي',
      subtitle: 'رسالة واحدة كل يوم: المبيعات، المقبوض، الديون، الصناديق، العمليات الحساسة، المخزون، مطالبات الغد',
      icon: Icons.summarize_rounded,
      color: _c,
      child: enabled == null
          ? const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (!canSend)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: SetBanner(
                    'هذا الجهاز لا يرسل الملخص (طرفية شبكة، أو شاشة غير الأولى، أو الوضع التجريبي). '
                    'فعّله على حاسبة السيرفر أو الجهاز المستقل.',
                    kind: SetBannerKind.warn,
                  ),
                ),
              if (!widget.telegramReady)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: SetBanner('احفظ التوكن والقناة أولاً.', kind: SetBannerKind.warn),
                ),
              SetSwitch(
                title: 'إرسال الملخص تلقائياً',
                subtitle: 'مرة واحدة يومياً بعد الوقت المحدد — فعّله على جهاز واحد فقط حتى لا يتكرر',
                icon: Icons.schedule_send_rounded,
                color: _c,
                value: enabled,
                onChanged: (v) async {
                  await OwnerSummary.setEnabled(v);
                  if (mounted) setState(() => _enabled = v);
                },
              ),
              const SizedBox(height: 6),
              Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
                OutlinedButton.icon(
                  onPressed: _pickTime,
                  icon: const Icon(Icons.access_time_rounded, size: 18),
                  label: Text('وقت الإرسال: ${_time.format(context)}'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _preview,
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('معاينة ملخص اليوم'),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: _c),
                  onPressed: _busy || !widget.telegramReady ? null : _sendNow,
                  icon: _busy
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send_rounded, size: 18),
                  label: const Text('إرسال تجريبي الآن'),
                ),
              ]),
              if (_last != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('آخر ملخص أُرسل تلقائياً: يوم $_last', style: const TextStyle(fontSize: 12.5, color: kSetMuted)),
                ),
              const SizedBox(height: 6),
              const Text(
                'إن كان البرنامج مغلقاً وقت الإرسال يُرسل ملخص الأمس عند تشغيله التالي. الملخص قراءة فقط ولا يغيّر أي رقم.',
                style: TextStyle(fontSize: 12, color: kSetMuted, height: 1.5),
              ),
            ]),
    );
  }
}
