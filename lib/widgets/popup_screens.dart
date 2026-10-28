// lib/widgets/popup_screens.dart
//
// 🪟 «فتح الشاشات كنافذة منبثقة»: الكاشير، إنشاء فاتورة، سجل الديون، تعديل الفواتير،
// إدخال بضاعة، الموردون — كل شاشة يختارها المستخدم من الإعدادات ← الواجهة تُفتح
// كنافذة فوق الشاشة الحالية بدل ملء الشاشة. للنافذة زر تكبير (أو نقرتان على
// شريطها) يملأ المساحة كاملة، وزر إغلاق يحترم تنبيه «تغييرات غير محفوظة».
//
// يعمل من مكان واحد (MaterialApp.onGenerateRoute)، فكل طرق الفتح تشملها:
// أزرار الرئيسية، الشريط الجانبي، واختصارات F1…F8.
// فتح شاشة نافذتها مفتوحة أصلاً يجلب النافذة نفسها للأمام (بحالتها) لا نسخة جديدة،
// والشاشات التي تُفتح من داخل النافذة تبقى داخلها.
// إعداد خاص بهذا الجهاز (SharedPreferences) — لا يغيّر أي بيانات.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderStack;
import 'package:shared_preferences/shared_preferences.dart';

import '../services/save_lock.dart';

class PopupScreens {
  PopupScreens._();

  static const _kRoutes = 'popup_screens_routes_v1';
  static const _kSize = 'popup_screens_size_v1';
  static const _kMax = 'popup_screens_maximized_v1';

  /// الشاشات التي يمكن فتحها كنافذة (المسار ← الاسم)
  static const Map<String, String> screens = {
    '/pos': 'الكاشير',
    '/create_invoice': 'إنشاء فاتورة',
    '/debt_register': 'سجل الديون',
    '/edit_invoices': 'تعديل الفواتير',
    '/product_entry': 'إدخال بضاعة',
    '/suppliers': 'الموردون',
  };

  static const Map<String, IconData> icons = {
    '/pos': Icons.point_of_sale_rounded,
    '/create_invoice': Icons.receipt_long_rounded,
    '/debt_register': Icons.account_balance_wallet_rounded,
    '/edit_invoices': Icons.edit_note_rounded,
    '/product_entry': Icons.inventory_2_rounded,
    '/suppliers': Icons.local_shipping_rounded,
  };

  /// أحجام النافذة (نسبة من المساحة المتاحة)
  static final Map<double, String> sizes = {0.8: 'متوسطة', 0.9: 'كبيرة', 0.96: 'شبه كاملة'};

  /// الشاشات المفعّل لها وضع النافذة
  static final ValueNotifier<Set<String>> enabled = ValueNotifier<Set<String>>(<String>{});
  static double size = 0.9;

  /// تفتح النافذة مكبّرة (تملأ المساحة) — يمكن تصغيرها من زرها
  static bool startMaximized = false;

  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      enabled.value = {...?p.getStringList(_kRoutes)}.where(screens.containsKey).toSet();
      final s = p.getDouble(_kSize) ?? 0.9;
      size = sizes.containsKey(s) ? s : 0.9;
      startMaximized = p.getBool(_kMax) ?? false;
      final raw = p.getString(_kGeo);
      if (raw != null) {
        final m = jsonDecode(raw);
        if (m is Map) _geo = Map<String, dynamic>.from(m);
      }
    } catch (_) {}
  }

  static Future<void> setEnabled(String route, bool on) async {
    final next = {...enabled.value};
    on ? next.add(route) : next.remove(route);
    enabled.value = next;
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kRoutes, next.toList());
  }

  static Future<void> setSize(double v) async {
    size = v;
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_kSize, v);
  }

  static Future<void> setStartMaximized(bool v) async {
    startMaximized = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kMax, v);
  }

  static bool isPopup(String? route) => route != null && enabled.value.contains(route);

  // 📐 موضع وحجم نافذة كل شاشة (يُحفظ فتفتح في مكانها المعتاد)
  static const _kGeo = 'popup_screens_geometry_v1';
  static Map<String, dynamic> _geo = {};

  static Rect? _savedRect(String? route) {
    final g = _geo[route];
    if (g is! Map) return null;
    final l = g['l'], t = g['t'], w = g['w'], h = g['h'];
    if (l is! num || t is! num || w is! num || h is! num) return null;
    if (w <= 0.05 || h <= 0.05) return null;
    return Rect.fromLTWH(l.toDouble(), t.toDouble(), w.toDouble(), h.toDouble());
  }

  static bool? _savedMax(String? route) {
    final g = _geo[route];
    return g is Map && g['max'] is bool ? g['max'] as bool : null;
  }

  static Future<void> _saveGeometry(PopupWindow w) async {
    final r = w.rect;
    _geo = {
      ..._geo,
      w.name: {
        if (r != null) ...{'l': r.left, 't': r.top, 'w': r.width, 'h': r.height},
        'max': w.maximized,
      },
    };
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kGeo, jsonEncode(_geo));
    } catch (_) {}
  }

  /// يعيد كل النوافذ لوضعها الافتراضي (في الوسط)
  static Future<void> resetGeometry() async {
    _geo = {};
    final p = await SharedPreferences.getInstance();
    await p.remove(_kGeo);
  }

  // ═══════════════════════ 🪟 مدير النوافذ ═══════════════════════
  // كل النوافذ داخل طبقة واحدة (مسار واحد فوق الشاشة الحالية)، فيمكن تغيير
  // ترتيبها دون فقدان حالتها: فتح شاشة مفتوحة أصلاً يجلب نافذتها للأمام.

  /// ملاح التطبيق الرئيسي (يُضبط في main)
  static GlobalKey<NavigatorState>? rootKey;

  /// النوافذ المفتوحة؛ الأخيرة هي الأمامية
  static final ValueNotifier<List<PopupWindow>> windows = ValueNotifier<List<PopupWindow>>(const []);

  /// مسار الشاشة الأمامية (لتظليل الشريط الجانبي)؛ لا شيء والنوافذ مُنزلة
  static String? get frontName =>
      windows.value.isEmpty || minimized.value ? null : windows.value.last.name;

  /// 🔽 النوافذ مُنزلة خلف الواجهة، كتطبيق مصغّر: تبقى بحالتها كاملة (فاتورة لم
  /// تُحفظ لا تضيع)، والواجهة تحتها تعمل. نقرة خارج النافذة أو زر الرئيسية
  /// يُنزلها، وفتح أي شاشة نافذة من جديد (الشريط الجانبي، الرئيسية، F1…F8) يعيدها.
  static final ValueNotifier<bool> minimized = ValueNotifier<bool>(false);

  static void minimize() {
    if (windows.value.isEmpty || minimized.value) return;
    minimized.value = true;
  }

  static void restore() {
    if (minimized.value) minimized.value = false;
  }

  static PopupHostRoute? _host;
  static int _ids = 0;

  /// مسار الشاشة: نافذة إن فعّلها المستخدم، وإلا شاشة كاملة كالمعتاد
  static Route<dynamic> route(RouteSettings settings, WidgetBuilder builder) {
    if (!isPopup(settings.name)) return MaterialPageRoute(settings: settings, builder: builder);
    final host = _host;
    if (host == null) {
      // أول نافذة: تُنشأ الطبقة ومعها النافذة
      windows.value = [PopupWindow._(++_ids, settings, builder)];
      minimized.value = false;
      final h = PopupHostRoute._();
      _host = h;
      return h;
    }
    // الطبقة موجودة: النافذة نفسها للأمام (أو نافذة جديدة)، ومسار وهمي يختفي فوراً
    _bringOrAdd(settings, builder);
    final dummy = PageRouteBuilder<dynamic>(
      settings: const RouteSettings(name: _kDummy),
      opaque: false,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final nav = rootKey?.currentState;
      final h = _host;
      if (nav == null) return;
      if (h != null && h.isActive) {
        // ما فوق الطبقة (شاشة كاملة فُتحت فوقها) يُغلق لتظهر النوافذ
        nav.popUntil((r) => identical(r, h) || r.isFirst);
      } else if (dummy.isActive) {
        nav.removeRoute(dummy);
      }
    });
    return dummy;
  }

  static const _kDummy = '__popup_dummy';

  static void _bringOrAdd(RouteSettings settings, WidgetBuilder builder) {
    restore();
    final list = [...windows.value];
    final i = list.indexWhere((w) => w.name == settings.name);
    if (i >= 0) {
      final w = list.removeAt(i);
      list.add(w);
      windows.value = list;
      w._focusLater();
    } else {
      list.add(PopupWindow._(++_ids, settings, builder));
      windows.value = list;
    }
  }

  static void bringToFront(PopupWindow w) {
    final list = [...windows.value];
    if (list.isEmpty || identical(list.last, w) || !list.remove(w)) return;
    list.add(w);
    windows.value = list;
  }

  /// إغلاق نافذة (بعد أن تُغلق شاشتها)؛ آخر نافذة تُغلق الطبقة كلها
  static void close(PopupWindow w) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final list = [...windows.value];
      if (!list.remove(w)) return;
      windows.value = list;
      if (list.isEmpty) {
        minimized.value = false;
        final h = _host;
        _host = null;
        final nav = h?.navigator;
        if (h != null && nav != null && h.isActive) {
          h.isCurrent ? nav.pop() : nav.removeRoute(h);
        }
      }
    });
  }

  /// مسار داخل نافذة يطلب شاشة باسمها (الرئيسية، الدخول، شاشة أخرى…):
  /// يُنفَّذ في الملاح الرئيسي، والمسار داخل النافذة يختفي.
  static Route<dynamic> _forward(RouteSettings s) {
    final r = PageRouteBuilder<dynamic>(
      settings: const RouteSettings(name: _kForward),
      opaque: false,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (r.isActive) r.navigator?.removeRoute(r);
      final root = rootKey?.currentState;
      final name = s.name;
      if (root == null || name == null) return;
      const reset = {'/', '/main', '/login', '/license', '/license_check', '/password_setup'};
      if (reset.contains(name)) {
        root.pushNamedAndRemoveUntil(name, (_) => false, arguments: s.arguments);
      } else {
        root.pushNamed(name, arguments: s.arguments);
      }
    });
    return r;
  }

  static const _kForward = '__popup_forward';
}

/// نافذة واحدة: لها ملاحها الخاص، فالشاشات التي تُفتح منها تبقى داخلها
class PopupWindow {
  PopupWindow._(this.id, this.settings, this.builder)
      : maximized = PopupScreens._savedMax(settings.name) ?? PopupScreens.startMaximized,
        rect = PopupScreens._savedRect(settings.name);

  final int id;
  final RouteSettings settings;
  final WidgetBuilder builder;
  bool maximized;

  /// موضع النافذة وحجمها كنسبة من المساحة (0..1)؛ null = في الوسط بالحجم الافتراضي
  Rect? rect;
  final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();
  final FocusScopeNode focusScope = FocusScopeNode(debugLabel: 'popup-window');
  Route<dynamic>? _screenRoute;

  String get name => settings.name ?? '';

  void _focusLater() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (focusScope.context != null) focusScope.requestFocus();
    });
  }
}

/// يراقب ملاح النافذة: إذا أُغلقت شاشتها (رجوع، حفظ ثم عودة، popUntil) تُغلق النافذة
class _WindowObserver extends NavigatorObserver {
  _WindowObserver(this.w);
  final PopupWindow w;

  bool _isMine(Route<dynamic>? r) => r != null && identical(r, w._screenRoute);

  @override
  void didPop(Route route, Route? previousRoute) {
    if (_isMine(route)) PopupScreens.close(w);
  }

  @override
  void didRemove(Route route, Route? previousRoute) {
    if (_isMine(route)) PopupScreens.close(w);
  }

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    if (!_isMine(oldRoute)) return;
    if (newRoute == null || newRoute.settings.name == PopupScreens._kForward) {
      PopupScreens.close(w);
    } else {
      w._screenRoute = newRoute; // الشاشة استبدلت نفسها (فاتورة جديدة بعد الحفظ مثلاً)
    }
  }
}

/// طبقة النوافذ: صفحة شفافة فوق الشاشة الحالية (PageRoute ليبقى الشريط الجانبي يعرفها)
class PopupHostRoute extends PageRouteBuilder<dynamic> {
  PopupHostRoute._()
      : super(
          settings: const RouteSettings(name: '/popup_windows'),
          opaque: false,
          // لا إغلاق بالنقر خارج النافذة ولا بـ Esc: قد تضيع فاتورة لم تُحفظ
          barrierDismissible: false,
          barrierColor: Colors.black.withValues(alpha: 0.45),
          transitionDuration: const Duration(milliseconds: 180),
          reverseTransitionDuration: const Duration(milliseconds: 140),
          pageBuilder: (context, _, __) => const _PopupHost(),
          transitionsBuilder: (context, anim, _, child) {
            final a = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
            return FadeTransition(
              opacity: a,
              child: ScaleTransition(scale: Tween(begin: 0.97, end: 1.0).animate(a), child: child),
            );
          },
        );

  /// الحاجز المظلّل لا يحجب النقر: نقرة خارج النافذة تُنزل النوافذ وتصل إلى
  /// الواجهة تحتها كما هي (كالنقر على تطبيق آخر). والنوافذ مُنزلة لا حاجز أصلاً.
  @override
  Widget buildModalBarrier() {
    return ValueListenableBuilder<bool>(
      valueListenable: PopupScreens.minimized,
      builder: (context, minimized, _) {
        if (minimized) return const SizedBox.shrink();
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => PopupScreens.minimize(),
          child: IgnorePointer(
            child: FadeTransition(
              opacity: animation ?? kAlwaysCompleteAnimation,
              child: ColoredBox(color: barrierColor ?? Colors.transparent, child: const SizedBox.expand()),
            ),
          ),
        );
      },
    );
  }

  @override
  bool didPop(dynamic result) {
    if (identical(PopupScreens._host, this)) PopupScreens._host = null;
    return super.didPop(result);
  }

  @override
  void dispose() {
    if (identical(PopupScreens._host, this)) PopupScreens._host = null;
    if (PopupScreens._host == null) {
      PopupScreens.windows.value = const [];
      PopupScreens.minimized.value = false;
    }
    super.dispose();
  }
}

class _PopupHost extends StatelessWidget {
  const _PopupHost();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<PopupWindow>>(
      valueListenable: PopupScreens.windows,
      builder: (context, list, _) {
        // طبقة قديمة تُغلق (حركة الخروج) بينما فُتحت طبقة جديدة: لا ترسم نوافذ الجديدة
        final me = ModalRoute.of(context);
        if (PopupScreens._host != null && !identical(me, PopupScreens._host)) return const SizedBox.shrink();
        final n = list.length;
        final windowsLayer = LayoutBuilder(builder: (context, box) {
          final area = box.biggest;
          var unplaced = 0; // النوافذ بلا موضع محفوظ تتدرّج قليلاً حتى تظهر حوافها
          return Stack(children: [
            for (var i = 0; i < n; i++)
              KeyedSubtree(
                key: ValueKey('popup-window-${list[i].id}'),
                child: _PopupFrame(
                  window: list[i],
                  isFront: i == n - 1,
                  area: area,
                  cascade: list[i].rect == null ? (unplaced++).clamp(0, 3) : 0,
                ),
              ),
          ]);
        });
        // البنية نفسها في الحالتين، فلا تُبنى النوافذ من جديد عند الإعادة
        return ValueListenableBuilder<bool>(
          valueListenable: PopupScreens.minimized,
          child: windowsLayer,
          builder: (context, minimized, child) => Offstage(
            offstage: minimized,
            child: TickerMode(
              enabled: !minimized,
              child: ExcludeFocus(excluding: minimized, child: child!),
            ),
          ),
        );
      },
    );
  }
}

class _PopupFrame extends StatefulWidget {
  const _PopupFrame({required this.window, required this.isFront, required this.cascade, required this.area});
  final PopupWindow window;
  final bool isFront;
  final int cascade;
  final Size area;

  @override
  State<_PopupFrame> createState() => _PopupFrameState();
}

class _PopupFrameState extends State<_PopupFrame> {
  static const double _barH = 38;
  static const double _minW = 380;
  static const double _minH = 280;
  static const double _grip = 6; // سماكة حواف تغيير الحجم
  late final _WindowObserver _observer = _WindowObserver(widget.window);
  final NavigatorObserver _lockObserver = SaveLock.newObserver();
  bool _live = false; // سحب أو تغيير حجم جارٍ (بلا حركة)

  PopupWindow get w => widget.window;
  Size get area => widget.area;
  bool get _small => area.width < 700;
  bool get _full => _small || w.maximized;

  @override
  void dispose() {
    w.focusScope.dispose();
    super.dispose();
  }

  /// المستطيل الحالي بالبكسل
  Rect _pixelRect() {
    if (_full) return Offset.zero & area;
    final r = w.rect;
    if (r != null) {
      return Rect.fromLTWH(r.left * area.width, r.top * area.height, r.width * area.width, r.height * area.height);
    }
    final f = PopupScreens.size;
    final ww = area.width * f, hh = area.height * f;
    final shift = 22.0 * widget.cascade;
    return Rect.fromLTWH((area.width - ww) / 2 + shift, (area.height - hh) / 2 + shift, ww, hh);
  }

  /// تبقى النافذة داخل المساحة (شريطها ظاهر دائماً)
  Rect _clamp(Rect r) {
    var width = r.width.clamp(_minW.clamp(0.0, area.width), area.width).toDouble();
    var height = r.height.clamp(_minH.clamp(0.0, area.height), area.height).toDouble();
    final left = r.left.clamp(0.0, (area.width - width).clamp(0.0, double.infinity)).toDouble();
    final top = r.top.clamp(0.0, (area.height - height).clamp(0.0, double.infinity)).toDouble();
    return Rect.fromLTWH(left, top, width, height);
  }

  void _setPixelRect(Rect px) {
    final r = _clamp(px);
    w.rect = Rect.fromLTWH(r.left / area.width, r.top / area.height, r.width / area.width, r.height / area.height);
  }

  void _commit() {
    _live = false;
    setState(() {});
    PopupScreens._saveGeometry(w);
  }

  void _toggleMax() {
    setState(() => w.maximized = !w.maximized);
    PopupScreens._saveGeometry(w);
  }

  /// نصف الشاشة: [right] = النصف الأيمن
  void _snap(bool right) {
    setState(() {
      w.maximized = false;
      w.rect = right ? const Rect.fromLTWH(0.5, 0, 0.5, 1) : const Rect.fromLTWH(0, 0, 0.5, 1);
    });
    PopupScreens._saveGeometry(w);
  }

  // ── السحب من شريط العنوان ──
  Offset? _dragGrab; // موضع المؤشر داخل الشريط (نسبة من العرض) عند بدء السحب من وضع مكبّر
  void _dragStart(DragStartDetails d) {
    PopupScreens.bringToFront(w);
    if (_small) return;
    if (w.maximized) {
      // سحب نافذة مكبّرة: تعود لحجمها السابق تحت المؤشر
      final f = PopupScreens.size;
      final prev = w.rect ?? Rect.fromLTWH((1 - f) / 2, (1 - f) / 2, f, f);
      w.maximized = false;
      final pw = prev.width * area.width;
      final ph = prev.height * area.height;
      final gx = d.localPosition.dx / area.width; // الشريط بعرض المساحة كاملة عند التكبير
      _setPixelRect(Rect.fromLTWH(d.globalPosition.dx - gx * pw - _hostOrigin().dx, 0, pw, ph));
    } else if (w.rect == null) {
      _setPixelRect(_pixelRect());
    }
    _dragGrab = d.globalPosition;
    _live = true;
    setState(() {});
  }

  Offset _hostOrigin() {
    final box = context.findAncestorRenderObjectOfType<RenderStack>();
    if (box == null || !box.hasSize) return Offset.zero;
    return box.localToGlobal(Offset.zero);
  }

  void _dragUpdate(DragUpdateDetails d) {
    if (_small || w.rect == null) return;
    final px = _pixelRect().shift(d.delta);
    _setPixelRect(px);
    setState(() {});
  }

  void _dragEnd(DragEndDetails d) {
    if (_small) return;
    final g = _dragGrab;
    _dragGrab = null;
    // سحب المؤشر إلى حافة المساحة اليمنى/اليسرى ⇒ نصف الشاشة؛ إلى الأعلى ⇒ تكبير
    final origin = _hostOrigin();
    final last = _lastPointer;
    if (g != null && last != null) {
      final x = last.dx - origin.dx;
      final y = last.dy - origin.dy;
      if (x <= 4) {
        _snap(false);
        return;
      }
      if (x >= area.width - 4) {
        _snap(true);
        return;
      }
      if (y <= 2) {
        _live = false;
        _toggleMax();
        return;
      }
    }
    _commit();
  }

  Offset? _lastPointer;

  // ── تغيير الحجم من الحواف ──
  void _resize(DragUpdateDetails d, {bool l = false, bool r = false, bool t = false, bool b = false}) {
    if (_full) return;
    var px = _pixelRect();
    final dx = d.delta.dx, dy = d.delta.dy;
    final minW = _minW < area.width ? _minW : area.width;
    final minH = _minH < area.height ? _minH : area.height;
    double left = px.left, top = px.top, right = px.right, bottom = px.bottom;
    if (l) left = (left + dx).clamp(0.0, (right - minW).clamp(0.0, area.width)).toDouble();
    if (r) right = (right + dx).clamp((left + minW).clamp(0.0, area.width), area.width).toDouble();
    if (t) top = (top + dy).clamp(0.0, (bottom - minH).clamp(0.0, area.height)).toDouble();
    if (b) bottom = (bottom + dy).clamp((top + minH).clamp(0.0, area.height), area.height).toDouble();
    px = Rect.fromLTRB(left, top, right, bottom);
    _live = true;
    _setPixelRect(px);
    setState(() {});
  }

  Widget _edge({
    double? left,
    double? right,
    double? top,
    double? bottom,
    double? width,
    double? height,
    required MouseCursor cursor,
    bool l = false,
    bool r = false,
    bool t = false,
    bool b = false,
  }) {
    return Positioned(
      left: left,
      right: right,
      top: top,
      bottom: bottom,
      width: width,
      height: height,
      child: MouseRegion(
        cursor: cursor,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) {
            PopupScreens.bringToFront(w);
            if (w.rect == null) _setPixelRect(_pixelRect());
          },
          onPanUpdate: (d) => _resize(d, l: l, r: r, t: t, b: b),
          onPanEnd: (_) => _commit(),
        ),
      ),
    );
  }

  List<Route<dynamic>> _initialRoutes(NavigatorState nav, String _) {
    final base = PageRouteBuilder<dynamic>(
      settings: const RouteSettings(name: '__popup_base'),
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
    final screen = MaterialPageRoute<dynamic>(settings: w.settings, builder: w.builder);
    w._screenRoute = screen;
    return [base, screen];
  }

  /// زر الإغلاق: كزر الرجوع داخل النافذة — يمرّ بتنبيه «تغييرات غير محفوظة»،
  /// وإن كانت شاشة فرعية مفتوحة داخل النافذة يرجع منها أولاً.
  Future<void> _close() async {
    final nav = w.navKey.currentState;
    if (nav == null) {
      PopupScreens.close(w);
      return;
    }
    await nav.maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final rect = _clamp(_pixelRect());
    final full = _full;
    final radius = full ? 0.0 : 12.0;
    final body = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        border: full ? null : Border.all(color: widget.isFront ? const Color(0xFF0F2A4A) : const Color(0xFF94A3B8)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: widget.isFront ? 0.30 : 0.15),
              blurRadius: widget.isFront ? 28 : 14,
              offset: const Offset(0, 10)),
        ],
      ),
      child: Column(children: [
        _bar(context),
        Expanded(
          // الشاشة تقيس نفسها بحجم النافذة لا بحجم الشاشة كلها
          child: LayoutBuilder(
            builder: (context, inner) => MediaQuery(
              data: mq.copyWith(size: inner.biggest, padding: EdgeInsets.zero, viewPadding: EdgeInsets.zero),
              child: ClipRect(
                child: HeroControllerScope.none(
                  child: Navigator(
                    key: w.navKey,
                    observers: [_observer, _lockObserver],
                    onGenerateInitialRoutes: _initialRoutes,
                    onGenerateRoute: PopupScreens._forward,
                  ),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
    const g = _grip;
    return AnimatedPositioned(
      duration: _live ? Duration.zero : const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: Listener(
        // نقرة على نافذة خلفية تجلبها للأمام؛ ونتتبع المؤشر لإلصاقها بالحافة عند السحب
        behavior: HitTestBehavior.translucent,
        onPointerDown: widget.isFront ? null : (_) => PopupScreens.bringToFront(w),
        onPointerMove: (e) => _lastPointer = e.position,
        child: FocusScope(
          node: w.focusScope,
          child: Stack(children: [
            Positioned.fill(child: body),
            if (!full) ...[
              _edge(left: 0, top: g * 2, bottom: g * 2, width: g, cursor: SystemMouseCursors.resizeLeftRight, l: true),
              _edge(right: 0, top: g * 2, bottom: g * 2, width: g, cursor: SystemMouseCursors.resizeLeftRight, r: true),
              _edge(left: g * 2, right: g * 2, bottom: 0, height: g, cursor: SystemMouseCursors.resizeUpDown, b: true),
              _edge(left: g * 2, right: g * 2, top: 0, height: g / 2, cursor: SystemMouseCursors.resizeUpDown, t: true),
              _edge(left: 0, bottom: 0, width: g * 2, height: g * 2, cursor: SystemMouseCursors.resizeUpRightDownLeft, l: true, b: true),
              _edge(right: 0, bottom: 0, width: g * 2, height: g * 2, cursor: SystemMouseCursors.resizeUpLeftDownRight, r: true, b: true),
              _edge(left: 0, top: 0, width: g * 2, height: g * 2, cursor: SystemMouseCursors.resizeUpLeftDownRight, l: true, t: true),
              _edge(right: 0, top: 0, width: g * 2, height: g * 2, cursor: SystemMouseCursors.resizeUpRightDownLeft, r: true, t: true),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _bar(BuildContext context) {
    final small = _small;
    return Material(
      color: widget.isFront ? const Color(0xFF0F2A4A) : const Color(0xFF475569),
      child: MouseRegion(
        cursor: small ? MouseCursor.defer : SystemMouseCursors.move,
        child: GestureDetector(
          onDoubleTap: small ? null : _toggleMax,
          onPanStart: _dragStart,
          onPanUpdate: _dragUpdate,
          onPanEnd: _dragEnd,
          child: SizedBox(
            height: _barH,
            child: Row(children: [
              const SizedBox(width: 12),
              Icon(PopupScreens.icons[w.name] ?? Icons.web_asset_rounded, size: 18, color: Colors.white70),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  PopupScreens.screens[w.name] ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
              ),
              if (!small) ...[
                _BarButton(
                  icon: Icons.align_horizontal_right_rounded,
                  tooltip: 'النصف الأيمن من الشاشة',
                  onTap: () => _snap(true),
                ),
                _BarButton(
                  icon: Icons.align_horizontal_left_rounded,
                  tooltip: 'النصف الأيسر من الشاشة',
                  onTap: () => _snap(false),
                ),
                _BarButton(
                  icon: w.maximized ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                  tooltip: w.maximized ? 'تصغير النافذة' : 'تكبير النافذة',
                  onTap: _toggleMax,
                ),
              ],
              _BarButton(icon: Icons.close_rounded, tooltip: 'إغلاق', danger: true, onTap: _close),
              const SizedBox(width: 4),
            ]),
          ),
        ),
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({required this.icon, required this.tooltip, required this.onTap, this.danger = false});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        hoverColor: danger ? const Color(0xFFDC2626) : Colors.white12,
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(width: 40, height: 32, child: Icon(icon, size: 19, color: Colors.white)),
      ),
    );
  }
}

/// ⚙️ بطاقة الإعداد في الإعدادات ← الواجهة
class PopupScreensTile extends StatefulWidget {
  const PopupScreensTile({super.key});

  @override
  State<PopupScreensTile> createState() => _PopupScreensTileState();
}

class _PopupScreensTileState extends State<PopupScreensTile> {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Set<String>>(
      valueListenable: PopupScreens.enabled,
      builder: (context, on, _) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            'الشاشات المختارة تُفتح كنافذة فوق الشاشة الحالية بدل ملء الشاشة. '
            'زر ⛶ في شريط النافذة (أو نقرتان عليه) يكبّرها لتملأ المساحة.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.5),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in PopupScreens.screens.entries)
              FilterChip(
                avatar: Icon(PopupScreens.icons[e.key], size: 17),
                label: Text(e.value),
                selected: on.contains(e.key),
                onSelected: (v) => PopupScreens.setEnabled(e.key, v),
              ),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            const Text('حجم النافذة:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(width: 10),
            Expanded(
              child: SegmentedButton<double>(
                segments: [
                  for (final s in PopupScreens.sizes.entries)
                    ButtonSegment<double>(value: s.key, label: Text('${s.value} ${(s.key * 100).round()}%')),
                ],
                selected: {PopupScreens.size},
                showSelectedIcon: false,
                onSelectionChanged: on.isEmpty
                    ? null
                    : (v) async {
                        await PopupScreens.setSize(v.first);
                        if (mounted) setState(() {});
                      },
              ),
            ),
          ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('تفتح مكبّرة', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            subtitle: const Text('النافذة تملأ المساحة عند فتحها، ويمكن تصغيرها من زرها', style: TextStyle(fontSize: 12)),
            value: PopupScreens.startMaximized,
            onChanged: on.isEmpty
                ? null
                : (v) async {
                    await PopupScreens.setStartMaximized(v);
                    if (mounted) setState(() {});
                  },
          ),
          Text(
            'حرّك النافذة بسحب شريطها، وغيّر حجمها من حوافها، أو ألصقها بنصف الشاشة الأيمن/الأيسر '
            'من أزرار الشريط (أو بسحبها إلى حافة الشاشة). كل شاشة تتذكر مكانها.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.5),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              icon: const Icon(Icons.restart_alt_rounded, size: 18),
              label: const Text('إرجاع مواضع النوافذ للوضع الافتراضي'),
              onPressed: () async {
                await PopupScreens.resetGeometry();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('النوافذ ستُفتح في الوسط بالحجم الافتراضي')),
                );
              },
            ),
          ),
        ]);
      },
    );
  }
}
