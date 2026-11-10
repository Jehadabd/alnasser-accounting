// lib/owner/owner_settings_cards.dart
//
// 👑 بطاقات «ميزات المالك» في الإعدادات العامة (تظهر لحساب المالك فقط):
//   1) المؤسسون: النقاط لكل 100,000 (الافتراضي للفواتير الجديدة) + فتح التقارير.
//   (Google Drive صار شاشة خاصة: الإعدادات ← النسخ الاحتياطي ← وجهات «رفع البيانات».)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../accounting/screens/acc_ui.dart' show accRoute;
import '../widgets/settings_kit.dart';
import 'founder_service.dart';
import 'founders_screen.dart';

String _fmtRate(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

class OwnerSettingsCards extends StatelessWidget {
  const OwnerSettingsCards({super.key});

  @override
  Widget build(BuildContext context) => const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _OwnerBadge(),
          _FoundersCard(),
        ],
      );
}

class _OwnerBadge extends StatelessWidget {
  const _OwnerBadge();
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF0F3460), Color(0xFF92400E)]),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Row(children: [
          Icon(Icons.workspace_premium_rounded, color: Color(0xFFFDE68A), size: 30),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'حساب مالك: هذه الميزات مفعّلة من سيرفر الترخيص لهذا الحساب فقط، ولا تظهر في الحسابات الأخرى.',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, height: 1.5),
            ),
          ),
        ]),
      );
}

// ═════════════════════════════ المؤسسون ═════════════════════════════

class _FoundersCard extends StatefulWidget {
  const _FoundersCard();
  @override
  State<_FoundersCard> createState() => _FoundersCardState();
}

class _FoundersCardState extends State<_FoundersCard> {
  final _rate = TextEditingController();
  double? _saved;

  @override
  void initState() {
    super.initState();
    FounderService.defaultRate().then((v) {
      if (!mounted) return;
      setState(() {
        _saved = v;
        _rate.text = _fmtRate(v);
      });
    });
  }

  @override
  void dispose() {
    _rate.dispose();
    super.dispose();
  }

  double? get _value => double.tryParse(_rate.text.replaceAll(',', '.'));

  Future<void> _save() async {
    final v = _value;
    if (v == null || v < 0) return setToast(context, 'اكتب رقماً صحيحاً', error: true);
    await FounderService.setDefaultRate(v);
    if (!mounted) return;
    setState(() => _saved = v);
    setToast(context, 'حُفظ: ${_fmtRate(v)} نقطة لكل 100,000');
  }

  @override
  Widget build(BuildContext context) {
    final v = _value;
    final dirty = _saved != null && v != null && v != _saved;
    return SetCard(
      title: 'المؤسسون والفنيون',
      subtitle: 'نقاط المؤسس تُحسب من صافي كل فاتورة',
      icon: Icons.engineering_rounded,
      color: const Color(0xFFD97706),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 6),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: TextField(
              controller: _rate,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(
                labelText: 'النقاط لكل 100,000 دينار',
                helperText: v == null ? null : 'مثال: فاتورة بمليون = ${_fmtRate(FounderService.pointsFor(1000000, v))} نقطة',
                prefixIcon: const Icon(Icons.stars_rounded),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: FilledButton.icon(
              onPressed: dirty ? _save : null,
              icon: const Icon(Icons.save_rounded, size: 18),
              label: const Text('حفظ'),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        const SetBanner('هذا المعدل الافتراضي للفواتير الجديدة. يمكن تغييره لكل فاتورة من زر «المؤسس» أعلى شاشة الفاتورة، '
            'ويُحفظ مع الفاتورة نفسها، فتغييره هنا لا يغيّر نقاط الفواتير القديمة.'),
        const SizedBox(height: 10),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed: () => Navigator.push(context, accRoute(const FoundersScreen())),
            icon: const Icon(Icons.leaderboard_rounded),
            label: const Text('فتح تقارير المؤسسين'),
          ),
        ),
      ]),
    );
  }
}

// ═════════════════════════════ Google Drive ═════════════════════════════
