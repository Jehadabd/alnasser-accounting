// lib/wa_messages/wa_send_notice.dart
//
// 🔔 لوحة صغيرة أعلى يسار الشاشة لنتيجة إرسال المستندات عبر واتساب — فوق كل الشاشات، فتبقى
// ظاهرة ولو أُغلقت الشاشة التي ضُغط منها الزر:
//   • «جارٍ إرسال…» ثم تتحول إلى النتيجة.
//   • النتيجة (نجح أخضر / فشل أحمر / وصل النص دون الملف برتقالي) تبقى 5 ثوانٍ ثم تختفي،
//     ويمكن إغلاقها قبل ذلك بـ ✕. السبب محفوظ أيضاً في «سجل الرسائل».
//   • إشعار مطابق لآخر ظاهر لا يتكرر (يُجدَّد وقته فقط).
// المضيف [WaSendNoticeHost] يُلفّ حول التطبيق مرة واحدة (main.dart).

import 'dart:async';

import 'package:flutter/material.dart';

enum WaNoticeState { sending, ok, warn, failed }

class WaNotice {
  const WaNotice(this.id, this.state, this.title, [this.detail]);
  final int id;
  final WaNoticeState state;
  final String title;
  final String? detail;
}

class WaSendNotice {
  WaSendNotice._();

  static final notices = ValueNotifier<List<WaNotice>>(const []);
  static int _seq = 0;
  static int _hosts = 0;
  static const _showFor = Duration(seconds: 5);
  static const _max = 5;

  /// هل المضيف مركّب؟ (وإلا يعود المستدعي إلى شريط أسفل الشاشة)
  static bool get available => _hosts > 0;

  /// يعرض «جارٍ…» ويعيد معرّفه لتحديثه بالنتيجة.
  static int start(String title) {
    final id = ++_seq;
    _put(WaNotice(id, WaNoticeState.sending, title));
    return id;
  }

  /// نتيجة: يستبدل «جارٍ…» (أو يضيف جديداً إن لم يُمرَّر [id]).
  static void finish(int? id, WaNoticeState state, String title, [String? detail]) {
    // نفس الإشعار ظاهر الآن (ضغط الزر مرتين) ⇒ لا يتكرر
    final same = notices.value.where((x) => x.id != id && x.state == state && x.title == title && x.detail == detail);
    if (same.isNotEmpty && id == null) {
      _arm(same.first.id);
      return;
    }
    if (same.isNotEmpty && id != null) dismiss(same.first.id);
    final n = WaNotice(id ?? ++_seq, state, title, detail);
    _put(n);
    _arm(n.id);
  }

  static final _timers = <int, Timer>{};

  /// يبدأ (أو يجدّد) عدّاد الثواني الخمس بعد ظهور النتيجة.
  static void _arm(int id) {
    _timers.remove(id)?.cancel();
    _timers[id] = Timer(_showFor, () => dismiss(id));
  }

  static void dismiss(int id) {
    _timers.remove(id)?.cancel();
    notices.value = [for (final n in notices.value) if (n.id != id) n];
  }

  static void _put(WaNotice n) {
    final l = [for (final x in notices.value) if (x.id != n.id) x, n];
    // الحد الأقصى: يُسقط الأقدم من النتائج (لا «جارٍ…»)
    while (l.length > _max) {
      final i = l.indexWhere((x) => x.state != WaNoticeState.sending);
      final gone = l.removeAt(i < 0 ? 0 : i);
      _timers.remove(gone.id)?.cancel();
    }
    notices.value = l;
  }
}

/// يُلفّ حول التطبيق: اللوحات فوق كل شيء أعلى يسار الشاشة.
class WaSendNoticeHost extends StatefulWidget {
  const WaSendNoticeHost({super.key, required this.child});
  final Widget child;
  @override
  State<WaSendNoticeHost> createState() => _WaSendNoticeHostState();
}

class _WaSendNoticeHostState extends State<WaSendNoticeHost> {
  @override
  void initState() {
    super.initState();
    WaSendNotice._hosts++;
  }

  @override
  void dispose() {
    WaSendNotice._hosts--;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(children: [
        Positioned.fill(child: widget.child),
        Positioned(
          top: 12,
          left: 12,
          child: ValueListenableBuilder<List<WaNotice>>(
            valueListenable: WaSendNotice.notices,
            builder: (_, l, __) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [for (final n in l) _NoticeCard(key: ValueKey(n.id), n: n)],
            ),
          ),
        ),
      ]);
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({super.key, required this.n});
  final WaNotice n;

  @override
  Widget build(BuildContext context) {
    final (Color c, IconData icon) = switch (n.state) {
      WaNoticeState.sending => (const Color(0xFF0F3460), Icons.send_to_mobile_rounded),
      WaNoticeState.ok => (const Color(0xFF047857), Icons.check_circle_rounded),
      WaNoticeState.warn => (const Color(0xFFB45309), Icons.warning_amber_rounded),
      WaNoticeState.failed => (const Color(0xFFB91C1C), Icons.error_rounded),
    };
    final stays = n.state != WaNoticeState.sending; // ✕ لإغلاقه قبل الثواني الخمس
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 180),
        builder: (_, v, child) => Opacity(opacity: v, child: Transform.translate(offset: Offset(-16 * (1 - v), 0), child: child)),
        child: Material(
          elevation: 6,
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 340,
            padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 6, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c, width: 1.5),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: n.state == WaNoticeState.sending
                    ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: c))
                    : Icon(icon, color: c, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(n.title, style: TextStyle(fontWeight: FontWeight.w800, color: c, fontSize: 13.5)),
                  if (n.detail != null && n.detail!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(n.detail!, style: const TextStyle(fontSize: 12.5, color: Color(0xFF334155))),
                    ),
                ]),
              ),
              if (stays)
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => WaSendNotice.dismiss(n.id),
                  child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.close_rounded, size: 18, color: Color(0xFF64748B))),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
