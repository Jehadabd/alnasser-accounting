// lib/widgets/upload_progress_dialog.dart
//
// ☁️ نافذة «رفع البيانات»: حلقة تقدّم بنسبة واضحة، والخطوة الجارية، وبطاقة لكل وجهة
// (تيليجرام، دروب بوكس، Google Drive، ديسكورد) بحالتها: تنتظر / جارية / تمت / فشلت /
// تُخطّيت. ونافذة النتيجة عند الفشل بالشكل نفسه.

import 'dart:async';

import 'package:flutter/material.dart';

import '../services/upload_targets.dart';
import 'app_dialog_shell.dart';

const _navy = Color(0xFF0F3460);
const _blue = Color(0xFF2563EB);
const _green = Color(0xFF047857);
const _red = Color(0xFFB91C1C);
const _muted = Color(0xFF64748B);
const _amber = Color(0xFFB45309);
const _text = Color(0xFF1E293B);

const _targetIcons = {
  UploadTargets.telegram: Icons.telegram,
  UploadTargets.dropbox: Icons.cloud_rounded,
  UploadTargets.discord: Icons.discord,
  UploadTargets.gdrive: Icons.add_to_drive_rounded,
};
const _targetColors = {
  UploadTargets.telegram: Color(0xFF229ED9),
  UploadTargets.dropbox: Color(0xFF0061FE),
  UploadTargets.discord: Color(0xFF5865F2),
  UploadTargets.gdrive: Color(0xFF1A73E8),
};

class UploadProgressDialog extends StatefulWidget {
  const UploadProgressDialog({
    super.key,
    required this.progress,
    required this.status,
    required this.targets,
    required this.current,
    required this.results,
    this.etaEnd,
    this.stalled,
  });

  final ValueNotifier<double> progress;
  final ValueNotifier<String> status;
  final ValueNotifier<List<String>> targets;
  final ValueNotifier<String?> current;

  /// 1 نجح، 0 فشل، 2 تُخطّي.
  final ValueNotifier<Map<String, int>> results;

  /// ⏱️ موعد الانتهاء المتوقع (يُعاد ضبطه بعد كل وجهة). null = لم يُحسب بعد.
  final ValueNotifier<DateTime?>? etaEnd;

  /// الرفع لا يتقدّم الآن (انقطاع الإنترنت أو بطء شديد) — لا يُعرض رقم مضلِّل.
  final ValueNotifier<bool>? stalled;

  @override
  State<UploadProgressDialog> createState() => _UploadProgressDialogState();
}

class _UploadProgressDialogState extends State<UploadProgressDialog> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);

  // عدّاد ثانية بثانية للوقت المتبقي
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.etaEnd?.value != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  static String _fmt(Duration d) {
    final s = d.inSeconds;
    final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(sec)}' : '$m:${two(sec)}';
  }

  Widget _eta() {
    final n = widget.etaEnd;
    if (n == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: Listenable.merge([n, if (widget.stalled != null) widget.stalled!]),
      builder: (_, __) {
        final end = n.value;
        final isStalled = widget.stalled?.value ?? false;
        final String text;
        final IconData icon;
        if (isStalled) {
          text = 'الرفع متوقف — بانتظار الإنترنت...';
          icon = Icons.wifi_off_rounded;
        } else if (end == null) {
          text = 'حساب الوقت المتوقع...';
          icon = Icons.hourglass_top_rounded;
        } else {
          final left = end.difference(DateTime.now());
          if (left.inSeconds <= 0) {
            text = 'يوشك على الانتهاء...';
            icon = Icons.hourglass_bottom_rounded;
          } else {
            text = 'الوقت المتبقي تقريباً ${_fmt(left)}';
            icon = Icons.timer_outlined;
          }
        }
        return Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: (isStalled ? _amber : _blue).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: (isStalled ? _amber : _blue).withValues(alpha: 0.3)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 17, color: isStalled ? _amber : _blue),
              const SizedBox(width: 6),
              Text(text,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: isStalled ? _amber : _navy,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )),
            ]),
          ),
          const SizedBox(height: 4),
          const Text('يُحسب كل ثانية من حجم ما بقي وسرعة الرفع الفعلية الآن',
              style: TextStyle(fontSize: 11, color: _muted)),
        ]);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AppDialogShell(
        icon: Icons.cloud_upload_rounded,
        color: _navy,
        title: 'رفع البيانات',
        subtitle: 'نسخة احتياطية إلى الوجهات المفعّلة بالترتيب',
        maxWidth: 520,
        iconWidget: AnimatedBuilder(
          animation: _pulse,
          builder: (_, child) => Transform.translate(
            offset: Offset(0, -3 * Curves.easeInOut.transform(_pulse.value)),
            child: child,
          ),
          child: const Icon(Icons.cloud_upload_rounded, color: Colors.white, size: 26),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(child: _ring()),
            const SizedBox(height: 12),
            Center(child: _eta()),
            const SizedBox(height: 12),
            ValueListenableBuilder<String>(
              valueListenable: widget.status,
              builder: (_, status, __) => AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: Text(
                  status,
                  key: ValueKey(status),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _text, fontSize: 14, fontWeight: FontWeight.w600, height: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 18),
            _targetsList(),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(color: const Color(0xFFFFF7ED), borderRadius: BorderRadius.circular(12)),
              child: const Row(children: [
                Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFFC2410C)),
                SizedBox(width: 8),
                Expanded(
                  child: Text('لا تغلق البرنامج حتى تنتهي العملية — يمكنك متابعة النافذة فقط.',
                      style: TextStyle(fontSize: 12.5, color: Color(0xFF9A3412))),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _ring() => ValueListenableBuilder<double>(
        valueListenable: widget.progress,
        builder: (_, p, __) {
          final v = p.clamp(0.0, 1.0);
          return TweenAnimationBuilder<double>(
            tween: Tween(end: v),
            // تحديث كل ثانية + حركة خطية بطول الثانية ⇒ تقدّم متصل بلا قفزات
            duration: const Duration(milliseconds: 950),
            curve: Curves.linear,
            builder: (_, a, __) => SizedBox(
              width: 132,
              height: 132,
              child: Stack(alignment: Alignment.center, children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: a <= 0.001 ? null : a,
                    strokeWidth: 11,
                    strokeCap: StrokeCap.round,
                    color: a >= 1 ? _green : _blue,
                    backgroundColor: const Color(0xFFE8EEF7),
                  ),
                ),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('${(a * 100).round()}%',
                      style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: a >= 1 ? _green : _navy)),
                  Text(a >= 1 ? 'اكتمل' : 'جارٍ الرفع', style: const TextStyle(fontSize: 12, color: _muted)),
                ]),
              ]),
            ),
          );
        },
      );

  Widget _targetsList() => AnimatedBuilder(
        animation: Listenable.merge([widget.targets, widget.current, widget.results]),
        builder: (_, __) {
          final list = widget.targets.value;
          if (list.isEmpty) {
            return const Center(
              child: Text('تجهيز الوجهات...', style: TextStyle(color: _muted, fontSize: 12.5)),
            );
          }
          return Column(children: [
            for (final t in list) ...[
              _TargetRow(
                target: t,
                state: widget.results.value.containsKey(t)
                    ? switch (widget.results.value[t]) { 1 => _St.done, 2 => _St.skipped, _ => _St.failed }
                    : (widget.current.value == t ? _St.running : _St.waiting),
              ),
              const SizedBox(height: 8),
            ],
          ]);
        },
      );
}

enum _St { waiting, running, done, failed, skipped }

class _TargetRow extends StatelessWidget {
  const _TargetRow({required this.target, required this.state});
  final String target;
  final _St state;

  @override
  Widget build(BuildContext context) {
    final c = _targetColors[target] ?? _blue;
    final active = state == _St.running;
    final (String label, Color tone, Widget trailing) = switch (state) {
      _St.waiting => ('بالانتظار', _muted, const Icon(Icons.schedule_rounded, size: 18, color: _muted)),
      _St.running => (
          'جارٍ الآن',
          c,
          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4, color: c)),
        ),
      _St.done => ('تم', _green, const Icon(Icons.check_circle_rounded, size: 20, color: _green)),
      _St.failed => ('لم يكتمل', _red, const Icon(Icons.error_rounded, size: 20, color: _red)),
      _St.skipped => ('تُخطّيت — غير مربوطة', _muted, const Icon(Icons.remove_circle_outline_rounded, size: 20, color: _muted)),
    };
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: active ? c.withValues(alpha: 0.07) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: active ? c.withValues(alpha: 0.45) : const Color(0xFFE6EBF2), width: active ? 1.5 : 1),
      ),
      child: Row(children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: state == _St.waiting || state == _St.skipped ? c.withValues(alpha: 0.12) : c,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(_targetIcons[target] ?? Icons.cloud_rounded,
              size: 19, color: state == _St.waiting || state == _St.skipped ? c : Colors.white),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(UploadTargets.labels[target] ?? target,
              style: TextStyle(fontWeight: FontWeight.w800, color: state == _St.skipped ? _muted : _text)),
        ),
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: tone)),
        const SizedBox(width: 8),
        trailing,
      ]),
    );
  }
}

/// ❌ نافذة النتيجة عند فشل جزء من الرفع: ما نجح وما فشل، والسبب، وما يمكن فعله.
class UploadFailedDialog extends StatelessWidget {
  const UploadFailedDialog({super.key, required this.error, required this.results});
  final String error;

  /// 1 نجح، 0 فشل، 2 تُخطّي.
  final Map<String, int> results;

  @override
  Widget build(BuildContext context) {
    return AppDialogShell(
      icon: Icons.cloud_off_rounded,
      color: _red,
      title: 'لم يكتمل رفع البيانات',
      subtitle: 'ما نجح من الوجهات رُفع فعلاً — المشكلة في الباقي فقط',
      onClose: () => Navigator.pop(context),
      maxWidth: 540,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (results.isNotEmpty) ...[
            for (final e in results.entries) ...[
              _TargetRow(target: e.key, state: switch (e.value) { 1 => _St.done, 2 => _St.skipped, _ => _St.failed }),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 6),
          ],
          const Text('السبب', style: TextStyle(fontWeight: FontWeight.w800, color: _text)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFECACA)),
            ),
            child: SelectableText(error, style: const TextStyle(fontSize: 13, height: 1.6, color: Color(0xFF7F1D1D))),
          ),
          const SizedBox(height: 14),
          const Text('ماذا أفعل؟', style: TextStyle(fontWeight: FontWeight.w800, color: _text)),
          const SizedBox(height: 6),
          for (final t in const [
            'تأكّد من اتصال الإنترنت.',
            'تأكّد من ربط الوجهة المذكورة: الإعدادات ← النسخ الاحتياطي ← «إعدادات …» تحتها.',
            'أعد المحاولة بعد قليل.',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Icon(Icons.circle, size: 7, color: _muted),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(t, style: const TextStyle(fontSize: 13, height: 1.55, color: _text))),
              ]),
            ),
        ]),
      ),
      actions: [
        const Spacer(),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: _navy, minimumSize: const Size(120, 46)),
          onPressed: () => Navigator.pop(context),
          child: const Text('حسناً'),
        ),
      ],
    );
  }
}
