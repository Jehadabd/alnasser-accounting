// lib/widgets/global_side_nav.dart
//
// 🧭 اللوحة الجانبية لكل الشاشات: توضع مرة واحدة حول الملاح (MaterialApp.builder)
// فتظهر في كل شاشة، حتى الشاشات التي تُفتح من داخل المراكز.
//
// الأقسام التي لها مركز (المبيعات، المخزون، المحاسبة) تنفتح عند الضغط إلى
// الأسفل وتعرض أزرارها نفسها (من menu() في كل مركز — مصدر واحد)، فتدخل أي زر
// مباشرة بلا المرور بشاشة المركز.
//
// ملاحظة: هذه اللوحة فوق الملاح، فلا Overlay هنا (لا Tooltip)؛ والنوافذ تُفتح
// بسياق الملاح نفسه.

import 'package:flutter/material.dart';

import '../accounting/screens/acc_ui.dart' show requirePermission;
import '../accounting/screens/accounting_home_screen.dart';
import '../erp/erp_common.dart' show HubSection;
import '../erp/inventory/inventory_hub_screen.dart';
import '../erp/sales/sales_hub_screen.dart';
import '../models/app_user.dart';
import '../screens/general_settings_screen.dart';
import '../screens/reports_screen.dart';
import '../services/auth_service.dart';
import '../services/license_service.dart';
import '../services/settings_manager.dart';
import 'home_destinations.dart';
import 'popup_screens.dart'; // 🪟

/// يتتبع مكدس الشاشات: أي شاشة في الأعلى، وآخر قسم مسمّى (للتظليل).
class SideNavObserver extends NavigatorObserver {
  final List<Route<dynamic>> _stack = [];
  final ValueNotifier<int> changes = ValueNotifier<int>(0);

  bool _page(Route<dynamic> r) => r is PageRoute;

  Route<dynamic>? get top {
    for (var i = _stack.length - 1; i >= 0; i--) {
      if (_page(_stack[i])) return _stack[i];
    }
    return null;
  }

  /// آخر شاشة مسمّاة في المكدس (شاشة مفتوحة من مركز المبيعات تبقى «المبيعات»)
  String? get section {
    for (var i = _stack.length - 1; i >= 0; i--) {
      final n = _stack[i].settings.name;
      if (_page(_stack[i]) && _stack[i] is! PopupHostRoute && n != null) return n;
    }
    return null;
  }

  /// طبقة النوافذ المنبثقة إن كانت في المكدس
  PopupHostRoute? get popupHost {
    for (var i = _stack.length - 1; i >= 0; i--) {
      final r = _stack[i];
      if (r is PopupHostRoute) return r;
    }
    return null;
  }

  /// الشاشات بين الرئيسية و[upper] (لا تشمل أياً منهما)
  List<Route<dynamic>> between(bool Function(String? name) isHome, Route<dynamic> upper) {
    final u = _stack.indexOf(upper);
    var h = -1;
    for (var k = 0; k < u; k++) {
      if (isHome(_stack[k].settings.name)) h = k;
    }
    if (u < 0 || h < 0) return const [];
    return _stack.sublist(h + 1, u);
  }

  bool hasRoute(bool Function(String? name) test) => _stack.any((r) => _page(r) && test(r.settings.name));

  void _changed() => WidgetsBinding.instance.addPostFrameCallback((_) => changes.value++);

  @override
  void didPush(Route route, Route? previousRoute) {
    _stack.add(route);
    _changed();
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    _stack.remove(route);
    _changed();
  }

  @override
  void didRemove(Route route, Route? previousRoute) {
    _stack.remove(route);
    _changed();
  }

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    final i = oldRoute == null ? -1 : _stack.indexOf(oldRoute);
    if (i >= 0 && newRoute != null) {
      _stack[i] = newRoute;
    } else {
      if (oldRoute != null) _stack.remove(oldRoute);
      if (newRoute != null) _stack.add(newRoute);
    }
    _changed();
  }
}

class GlobalSideNav extends StatefulWidget {
  const GlobalSideNav({super.key, required this.navigatorKey, required this.observer, required this.child});
  final GlobalKey<NavigatorState> navigatorKey;
  final SideNavObserver observer;
  final Widget child;

  /// شاشة تمنع اللوحة وهي مفتوحة (قارئ الأسعار أمام الزبائن): ++ عند الفتح، -- عند الإغلاق
  static final ValueNotifier<int> suppress = ValueNotifier<int>(0);

  /// شاشات بلا لوحة: الدخول والترخيص
  static const hiddenRoutes = {'/license', '/license_check', '/password_setup', '/login'};

  @override
  State<GlobalSideNav> createState() => _GlobalSideNavState();
}

class _NavEntry {
  const _NavEntry(this.dest, {this.permission, this.fullOnly = false, this.menu});
  final HomeDest dest;
  final String? permission;
  final bool fullOnly;
  final List<HubSection> Function(BuildContext context, void Function(Widget) go)? menu;
}

class _GlobalSideNavState extends State<GlobalSideNav> {
  String? _open; // القسم المفتوح (route)

  static const _collapsed = 76.0;
  static const _wide = 216.0;

  static final _entries = <_NavEntry>[
    const _NavEntry(HomeDests.pos, permission: AppPermissions.posAccess, fullOnly: true),
    const _NavEntry(HomeDests.createInvoice, permission: AppPermissions.createInvoice, fullOnly: true),
    const _NavEntry(HomeDests.debtRegister, permission: AppPermissions.debtRegister),
    const _NavEntry(HomeDests.editInvoices, permission: AppPermissions.editInvoices, fullOnly: true),
    const _NavEntry(HomeDests.productEntry, permission: AppPermissions.productEntry, fullOnly: true),
    const _NavEntry(HomeDests.suppliers, permission: AppPermissions.suppliers, fullOnly: true),
    const _NavEntry(HomeDests.sales, permission: AppPermissions.salesDocs, fullOnly: true, menu: SalesHubScreen.menu),
    const _NavEntry(HomeDests.inventory, fullOnly: true, menu: InventoryHubScreen.menu),
    const _NavEntry(HomeDests.accounting, permission: AppPermissions.accounting, fullOnly: true, menu: AccountingHomeScreen.menu),
    const _NavEntry(HomeDests.reports, permission: AppPermissions.reports, menu: ReportsScreen.menu),
    const _NavEntry(HomeDests.settings, permission: AppPermissions.settings, menu: GeneralSettingsScreen.menu),
  ];

  @override
  void initState() {
    super.initState();
    SettingsManager.getAppSettings().then((s) { SettingsManager.sideNavEnabled.value = s.showSideNav; }).catchError((_) {});
  }

  NavigatorState? get _nav => widget.navigatorKey.currentState;

  /// سياق تحت الملاح (للنوافذ والرسائل)
  BuildContext? get _navCtx => _nav?.overlay?.context;

  bool _isHome(String? n) => n == '/' || n == '/main';

  void _goSection(_NavEntry e) {
    final nav = _nav;
    final ctx = _navCtx;
    if (nav == null || ctx == null) return;
    if (e.permission != null && !requirePermission(ctx, e.permission!)) return;
    setState(() => _open = null);
    final route = e.dest.route!;
    // 🪟 شاشة تُفتح كنافذة: تُفتح فوق الحالية (أو تُجلب نافذتها للأمام) دون إغلاق شيء
    if (PopupScreens.isPopup(route)) {
      nav.pushNamed(route);
      return;
    }
    if (widget.observer.top?.settings.name == route) return;
    // 🪟 النوافذ المفتوحة لا تُغلق (قد تحمل فاتورة لم تُحفظ): تنزل، والشاشة فوقها
    final host = widget.observer.popupHost;
    if (host != null) {
      PopupScreens.minimize();
      nav.pushNamedAndRemoveUntil(route, (r) => identical(r, host));
      return;
    }
    // نفس سلوك اللوحة السابقة: الرئيسية تبقى تحت الشاشة (زر الرجوع يعود إليها)
    if (widget.observer.hasRoute(_isHome)) {
      nav.pushNamedAndRemoveUntil(route, (r) => _isHome(r.settings.name));
    } else {
      nav.pushNamed(route);
    }
  }

  void _goHome() {
    final nav = _nav;
    if (nav == null) return;
    setState(() => _open = null);
    if (_isHome(widget.observer.top?.settings.name)) return;
    // 🪟 النوافذ لا تُغلق بزر الرئيسية: تنزل خلفها بحالتها، والرئيسية تظهر وتعمل
    final host = widget.observer.popupHost;
    if (host != null) {
      PopupScreens.minimize();
      final under = widget.observer.between(_isHome, host).toList();
      nav.popUntil((r) => identical(r, host) || _isHome(r.settings.name));
      if (host.isActive) {
        for (final r in under) {
          if (r.isActive) nav.removeRoute(r);
        }
      }
      return;
    }
    if (widget.observer.hasRoute(_isHome)) {
      nav.popUntil((r) => _isHome(r.settings.name));
    } else {
      nav.pushNamedAndRemoveUntil('/main', (r) => false);
    }
  }

  void _push(Widget w) {
    setState(() => _open = null);
    _nav?.push(MaterialPageRoute(builder: (_) => w));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(
          [SettingsManager.sideNavEnabled, GlobalSideNav.suppress, widget.observer.changes, PopupScreens.windows,
           PopupScreens.minimized]),
      builder: (context, _) {
        final topName = widget.observer.top?.settings.name;
        final show = SettingsManager.sideNavEnabled.value &&
            GlobalSideNav.suppress.value <= 0 &&
            widget.observer.top != null &&
            !GlobalSideNav.hiddenRoutes.contains(topName) &&
            AuthService().isLoggedIn;
        return Row(children: [
          if (show) _rail(context),
          Expanded(child: widget.child),
        ]);
      },
    );
  }

  Widget _rail(BuildContext context) {
    final license = LicenseService().getStoredLicense();
    final debtsOnly = license?.isDebtsOnly ?? false;
    final auth = AuthService();
    final items = _entries
        .where((e) => !(debtsOnly && e.fullOnly))
        .where((e) => e.permission == null || auth.hasPermission(e.permission!))
        .toList();
    // فوق طبقة النوافذ: يُظلَّل قسم النافذة الأمامية
    final current = widget.observer.top is PopupHostRoute
        ? (PopupScreens.frontName ?? widget.observer.section)
        : widget.observer.section;
    final wide = _open != null;

    // بلا تحريك للعرض: صفوف القائمة العريضة لا تتسع في 76 أثناء الانتقال
    return Container(
        width: wide ? _wide : _collapsed,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF020F2B), Color(0xFF0F3460)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 10, offset: const Offset(2, 0))],
        ),
        // Material فوق التدرّج: لموجة الضغط وخط النص (لا Material فوق الملاح هنا)
        child: Material(
          type: MaterialType.transparency,
          child: SafeArea(
          child: Column(children: [
            const SizedBox(height: 12),
            InkWell(
              onTap: _goHome,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.home_rounded, color: Colors.white, size: 26, semanticLabel: 'الرئيسية'),
              ),
            ),
            const SizedBox(height: 12),
            const Divider(color: Colors.white24, height: 1, indent: 12, endIndent: 12),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 4),
                children: [
                  for (final e in items) ...[
                    _sectionButton(e, selected: current == e.dest.route, expanded: _open == e.dest.route, wide: wide),
                    if (_open == e.dest.route && e.menu != null) ..._subItems(e),
                  ],
                ],
              ),
            ),
          ]),
          ),
        ),
    );
  }

  Widget _sectionButton(_NavEntry e, {required bool selected, required bool expanded, required bool wide}) {
    final d = e.dest;
    final hot = selected || expanded;
    final onTap = e.menu == null ? () => _goSection(e) : () => setState(() => _open = expanded ? null : d.route);
    final label = Text(
      d.title,
      textAlign: wide ? TextAlign.start : TextAlign.center,
      style: TextStyle(
        color: hot ? Colors.white : Colors.white70,
        fontSize: wide ? 13 : 10,
        fontWeight: hot ? FontWeight.bold : FontWeight.w500,
      ),
      maxLines: wide ? 1 : 2,
      overflow: TextOverflow.ellipsis,
    );
    final icon = Icon(d.icon, color: hot ? d.color : Colors.white70, size: 22);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.symmetric(vertical: 7, horizontal: wide ? 10 : 2),
          decoration: BoxDecoration(
            color: hot ? d.color.withValues(alpha: 0.25) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: hot ? d.color : Colors.transparent, width: 1.5),
          ),
          child: wide
              ? Row(children: [
                  icon,
                  const SizedBox(width: 10),
                  Expanded(child: label),
                  if (e.menu != null)
                    Icon(expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: Colors.white60, size: 18),
                ])
              : Column(mainAxisSize: MainAxisSize.min, children: [
                  // السهم فوق زاوية الأيقونة لا بجانبها: عرض الأيقونة ثابت (22)
                  // فلا يتجاوز عرض اللوحة المطوية (كان 22 + 16 > 37 فيظهر خطأ التجاوز)
                  Stack(clipBehavior: Clip.none, children: [
                    icon,
                    if (e.menu != null)
                      const PositionedDirectional(
                        start: -12,
                        bottom: -6,
                        child: Icon(Icons.arrow_drop_down_rounded, color: Colors.white38, size: 16),
                      ),
                  ]),
                  const SizedBox(height: 2),
                  label,
                ]),
        ),
      ),
    );
  }

  List<Widget> _subItems(_NavEntry e) {
    final ctx = _navCtx;
    if (ctx == null) return const [];
    final auth = AuthService();
    final sections = e.menu!(ctx, _push);
    final out = <Widget>[
      _subRow(Icons.open_in_new_rounded, 'شاشة ${e.dest.title}', e.dest.color, () => _goSection(e)),
    ];
    for (final s in sections) {
      final tiles = s.tiles.where((t) => t.permission == null || auth.hasPermission(t.permission!)).toList();
      if (tiles.isEmpty) continue;
      out.add(Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(22, 8, 12, 2),
        child: Text(s.title, style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w700)),
      ));
      for (final t in tiles) {
        out.add(_subRow(t.icon, t.title, t.color, () {
          if (t.permission != null && !requirePermission(ctx, t.permission!)) return;
          setState(() => _open = null);
          t.onTap();
        }));
      }
    }
    out.add(const Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Divider(color: Colors.white24, height: 1, indent: 12, endIndent: 12),
    ));
    return out;
  }

  Widget _subRow(IconData icon, String title, Color color, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 1, 8, 1),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 8),
          child: Row(children: [
            Icon(icon, size: 18, color: Color.lerp(color, Colors.white, 0.35)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(title,
                  style: const TextStyle(color: Colors.white, fontSize: 12.5), maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
          ]),
        ),
      ),
    );
  }
}
