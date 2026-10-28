// lib/services/save_lock.dart
//
// 🔒 قفل الحفظ: يمنع تنفيذ أي عملية حفظ مرتين مهما كانت سرعة الضغط.
//
//  • القفل يُأخذ فوراً (قبل أي انتظار لقاعدة البيانات)، فالضغطة الثانية —
//    حتى لو جاءت في نفس اللحظة أو من Enter/اختصار — تُرفض ولا يحدث شيء.
//  • أثناء التنفيذ تُغطّى الشاشة كلها: لا فأرة ولا لوحة مفاتيح، حتى ينتهي كل شيء
//    على القاعدة. بعد ~¼ ثانية تظهر بطاقة «جارٍ الحفظ…».
//  • نافذة سؤال تظهر أثناء الحفظ (طباعة؟ تأكيد؟) تبقى قابلة للضغط: الغطاء
//    يختفي ما دامت مفتوحة، ثم يعود حتى نهاية الحفظ — فلا تتجمد الشاشة.
//  • قفل واحد للبرنامج كله: لا حفظان في وقت واحد (ولو من نافذتين منبثقتين).
//  • عملية حفظ تستدعي حفظاً آخر داخلها (فاتورة ← تذكير مطالبة) تمرّ؛ أما حفظ
//    جديد من الخارج أثناء التنفيذ فيُرفض.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SaveLock {
  SaveLock._();

  /// true أثناء أي عملية حفظ
  static final ValueNotifier<bool> busy = ValueNotifier<bool>(false);
  static String message = 'جارٍ الحفظ…';

  static int _seq = 0;
  static int? _activeId;
  static final Object _zoneKey = Object();

  /// المسارات (نوافذ/شاشات) التي فُتحت أثناء الحفظ — يختفي الغطاء ما دامت مفتوحة
  static final ValueNotifier<int> _routesDuringSave = ValueNotifier<int>(0);
  static final Set<Route<dynamic>> _counted = {};

  /// هل الحفظ جارٍ الآن؟ (للأزرار التي تريد أن تبدو معطّلة)
  static bool get isBusy => busy.value;

  /// ينفّذ [action] تحت القفل. يُرجع null إن رُفض لأن حفظاً آخر جارٍ.
  static Future<T?> run<T>(Future<T> Function() action, {String message = 'جارٍ الحفظ…'}) async {
    // حفظ داخل حفظ (من نفس السلسلة): يمرّ مباشرة
    final zid = Zone.current[_zoneKey];
    if (zid != null && zid == _activeId && busy.value) return await action();
    if (busy.value) {
      HapticFeedback.selectionClick();
      return null; // ضغطة ثانية — تُتجاهل
    }
    final id = ++_seq;
    _activeId = id;
    SaveLock.message = message;
    busy.value = true; // ⬅️ قبل أي await: هذا ما يجعل الضغطة الثانية مستحيلة
    try {
      return await runZoned(action, zoneValues: {_zoneKey: id});
    } finally {
      _activeId = null;
      _counted.clear();
      _routesDuringSave.value = 0;
      busy.value = false;
    }
  }

  /// مراقب لكل ملاح (الرئيسي وملاحات النوافذ المنبثقة) — نسخة لكل ملاح
  static NavigatorObserver newObserver() => _SaveLockObserver();

  static void _pushed(Route<dynamic> r) {
    if (!busy.value || r.settings.name == '__popup_dummy' || r.settings.name == '__popup_forward') return;
    if (_counted.add(r)) _routesDuringSave.value = _counted.length;
  }

  static void _gone(Route<dynamic>? r) {
    if (r != null && _counted.remove(r)) _routesDuringSave.value = _counted.length;
  }
}

class _SaveLockObserver extends NavigatorObserver {
  @override
  void didPush(Route route, Route? previousRoute) => SaveLock._pushed(route);
  @override
  void didPop(Route route, Route? previousRoute) => SaveLock._gone(route);
  @override
  void didRemove(Route route, Route? previousRoute) => SaveLock._gone(route);
  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    SaveLock._gone(oldRoute);
    if (newRoute != null) SaveLock._pushed(newRoute);
  }
}

/// 🛡️ الغطاء: يوضع مرة واحدة فوق كل الشاشات (MaterialApp.builder)
class SaveLockBarrier extends StatefulWidget {
  const SaveLockBarrier({super.key, required this.child});
  final Widget child;

  @override
  State<SaveLockBarrier> createState() => _SaveLockBarrierState();
}

class _SaveLockBarrierState extends State<SaveLockBarrier> {
  final FocusNode _focus = FocusNode(debugLabel: 'save-lock', skipTraversal: true);
  FocusNode? _prevFocus;
  bool _showCard = false;
  Timer? _cardTimer;
  bool _wasBlocking = false;

  @override
  void initState() {
    super.initState();
    SaveLock.busy.addListener(_changed);
    SaveLock._routesDuringSave.addListener(_changed);
  }

  @override
  void dispose() {
    SaveLock.busy.removeListener(_changed);
    SaveLock._routesDuringSave.removeListener(_changed);
    _cardTimer?.cancel();
    _focus.dispose();
    super.dispose();
  }

  bool get _blocking => SaveLock.busy.value && SaveLock._routesDuringSave.value == 0;

  void _changed() {
    final blocking = _blocking;
    if (blocking && !_wasBlocking) {
      // يأخذ لوحة المفاتيح: لا Enter ولا اختصار يصل للشاشة أثناء الحفظ
      _prevFocus = FocusManager.instance.primaryFocus;
      _cardTimer?.cancel();
      _cardTimer = Timer(const Duration(milliseconds: 250), () {
        if (mounted && _blocking) setState(() => _showCard = true);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _blocking) _focus.requestFocus();
      });
    } else if (!blocking && _wasBlocking) {
      _cardTimer?.cancel();
      _showCard = false;
      // تعود لوحة المفاتيح لمكانها (إن بقيت الخانة موجودة)
      final prev = _prevFocus;
      _prevFocus = null;
      if (!SaveLock.busy.value) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (prev != null && prev.context != null && prev.canRequestFocus && _focus.hasFocus) {
            prev.requestFocus();
          } else if (_focus.hasFocus) {
            _focus.unfocus();
          }
        });
      } else if (_focus.hasFocus) {
        _focus.unfocus(); // نافذة سؤال ظهرت: هي تأخذ لوحة المفاتيح
      }
    }
    _wasBlocking = blocking;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final blocking = _blocking;
    return Stack(children: [
      widget.child,
      if (blocking)
        Positioned.fill(
          child: Focus(
            focusNode: _focus,
            onKeyEvent: (_, __) => KeyEventResult.handled, // يبتلع كل المفاتيح
            child: MouseRegion(
              cursor: SystemMouseCursors.progress,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque, // يبتلع كل النقرات
                onTap: () {},
                onPanStart: (_) {},
                child: AnimatedOpacity(
                  opacity: _showCard ? 1 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.08),
                    alignment: Alignment.center,
                    child: Directionality(
                      textDirection: TextDirection.rtl,
                      child: Material(
                        elevation: 8,
                        borderRadius: BorderRadius.circular(14),
                        color: Colors.white,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.6),
                            ),
                            const SizedBox(width: 14),
                            Text(SaveLock.message,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
    ]);
  }
}
