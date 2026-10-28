// lib/widgets/global_search.dart
//
// 🔎 البحث الشامل (Ctrl+K): عميل، مادة، أو رقم فاتورة من أي شاشة.
// قراءة فقط: يفتح الشاشة المناسبة ولا يغيّر شيئاً.
//   • النتائج مجمّعة (عملاء، مواد، فواتير) مع تصفية بنقرة.
//   • ↑ ↓ للتنقل، Enter يفتح المحدد، Esc يغلق.
//   • المادة: سعر المفرد الفعلي (price1) والمخزون، والبحث بالاسم أو الرمز أو الباركود.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../accounting/screens/acc_ui.dart' show fmtMoney, requirePermission;
import '../erp/stock_helpers.dart' show ErpStock;
import '../inventory/item_card_editor_screen.dart';
import '../models/app_user.dart';
import '../models/customer.dart';
import '../screens/create_invoice_screen.dart';
import '../screens/customer_details_screen.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../services/name_search.dart'; // 🔤 الأسماء بلا مسافات

enum _Kind { customer, product, invoice }

class _Chip {
  const _Chip(this.text, {this.icon, this.color});
  final String text;
  final IconData? icon;
  final Color? color;
}

class _Hit {
  _Hit(this.kind, this.id, this.title, this.chips);
  final _Kind kind;
  final int id;
  final String title;
  final List<_Chip> chips;
}

/// ألوان متسقة مع النظام (كحلي + لون لكل نوع).
class _S {
  static const navy = Color(0xFF0F3460);
  static const text = Color(0xFF0F172A);
  static const muted = Color(0xFF64748B);
  static const border = Color(0xFFE6EBF2);
  static const soft = Color(0xFFF5F7FB);
  static const red = Color(0xFFDC2626);
  static const green = Color(0xFF059669);

  static Color of(_Kind k) => switch (k) {
        _Kind.customer => const Color(0xFF2563EB),
        _Kind.product => const Color(0xFF0D9488),
        _Kind.invoice => const Color(0xFFEA580C),
      };

  static IconData icon(_Kind k) => switch (k) {
        _Kind.customer => Icons.person_rounded,
        _Kind.product => Icons.inventory_2_rounded,
        _Kind.invoice => Icons.receipt_long_rounded,
      };

  static String label(_Kind k) => switch (k) {
        _Kind.customer => 'العملاء',
        _Kind.product => 'المواد',
        _Kind.invoice => 'الفواتير',
      };
}

Future<void> showGlobalSearch(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'بحث',
    barrierColor: const Color(0xFF0F172A).withValues(alpha: 0.45),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, __, ___) => const _GlobalSearchDialog(),
    transitionBuilder: (_, a, __, child) {
      final c = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: c,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, -0.03), end: Offset.zero).animate(c),
          child: child,
        ),
      );
    },
  );
}

class _GlobalSearchDialog extends StatefulWidget {
  const _GlobalSearchDialog();
  @override
  State<_GlobalSearchDialog> createState() => _GlobalSearchDialogState();
}

class _GlobalSearchDialogState extends State<_GlobalSearchDialog> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;
  List<_Hit> _hits = const [];
  _Kind? _only; // تصفية بنوع واحد
  int _sel = 0;
  bool _busy = false;
  int _seq = 0;
  final Map<int, GlobalKey> _keys = {};

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<_Hit> get _shown => _only == null ? _hits : _hits.where((h) => h.kind == _only).toList();

  int _count(_Kind k) => _hits.where((h) => h.kind == k).length;

  void _onChanged(String q) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () => _run(q.trim()));
  }

  Future<void> _run(String q) async {
    final seq = ++_seq;
    if (q.isEmpty) {
      setState(() {
        _hits = const [];
        _busy = false;
        _sel = 0;
      });
      return;
    }
    setState(() => _busy = true);
    final hits = <_Hit>[];
    try {
      final db = await DatabaseService().database;
      // 👤 كل موظف يرى في البحث ما تسمح به صلاحياته فقط
      final auth = AuthService();
      final canCustomers = auth.hasPermission(AppPermissions.debtRegister);
      final canProducts = auth.hasPermission(AppPermissions.itemCard);
      final canInvoices = auth.hasPermission(AppPermissions.editInvoices);

      final nameQ = NameSearch.where('name', q, phoneCol: 'phone');
      if (canCustomers && nameQ != null) {
        final ord = NameSearch.order('name', q);
        final customers = await db.rawQuery('''
          SELECT id, name, phone, current_total_debt FROM customers
          WHERE COALESCE(is_deleted, 0) = 0 AND ${nameQ.sql}
          ORDER BY ${ord.sql} LIMIT 8
        ''', [...nameQ.args, ...ord.args]);
        for (final r in customers) {
          final debt = (r['current_total_debt'] as num?)?.toDouble() ?? 0;
          final phone = '${r['phone'] ?? ''}'.trim();
          hits.add(_Hit(_Kind.customer, r['id'] as int, '${r['name']}', [
            if (phone.isNotEmpty) _Chip(phone, icon: Icons.phone_rounded),
            debt.abs() < 0.5
                ? const _Chip('لا دين', icon: Icons.check_circle_rounded, color: _S.green)
                : _Chip('الدين ${fmtMoney(debt)}',
                    icon: Icons.account_balance_wallet_rounded, color: debt > 0 ? _S.red : _S.green),
          ]));
        }
      }

      if (canProducts) {
        // نفس بحث شاشات المواد: الاسم، رمز المادة، الباركود، الرقم — وأسعار المستويات الفعلية
        final products = await ErpStock.search(q, limit: 8);
        for (final p in products) {
          final price = p.prices.isNotEmpty ? p.prices.first : 0.0;
          hits.add(_Hit(_Kind.product, p.id, p.name, [
            if ((p.itemCode ?? '').isNotEmpty) _Chip(p.itemCode!, icon: Icons.tag_rounded),
            _Chip(price > 0 ? 'مفرد ${fmtMoney(price)}' : 'بلا سعر',
                icon: Icons.sell_rounded, color: price > 0 ? null : _S.muted),
            _Chip('المخزون ${fmtMoney(p.stock)} ${p.baseUnitName}',
                icon: Icons.warehouse_rounded, color: p.stock > 0 ? _S.green : _S.red),
          ]));
        }
      }

      if (canInvoices) {
        final isNumber = RegExp(r'^\d+$').hasMatch(q);
        final invoices = await db.rawQuery('''
          SELECT id, invoice_number, customer_name, total_amount, invoice_date, payment_type FROM invoices
          WHERE COALESCE(is_deleted, 0) = 0 AND (invoice_number = ? ${isNumber ? 'OR id = ?' : ''} OR ${NameSearch.sqlNorm('customer_name')} LIKE ?)
          ORDER BY id DESC LIMIT 8
        ''', [q, if (isNumber) int.parse(q), '%${NameSearch.compact(q)}%']);
        for (final r in invoices) {
          final no = (r['invoice_number'] as String?)?.isNotEmpty == true ? r['invoice_number'] : r['id'];
          final date = '${r['invoice_date'] ?? ''}';
          final pay = '${r['payment_type'] ?? ''}';
          hits.add(_Hit(_Kind.invoice, r['id'] as int, 'فاتورة $no — ${r['customer_name'] ?? ''}', [
            _Chip(date.length >= 10 ? date.substring(0, 10).replaceAll('-', '/') : date, icon: Icons.event_rounded),
            _Chip(fmtMoney((r['total_amount'] as num?) ?? 0), icon: Icons.payments_rounded),
            if (pay.isNotEmpty) _Chip(pay, color: pay == 'نقد' ? _S.green : const Color(0xFFB45309)),
          ]));
        }
      }
    } catch (_) {}
    if (!mounted || seq != _seq) return;
    setState(() {
      _hits = hits;
      _busy = false;
      _sel = 0;
      if (_only != null && _count(_only!) == 0) _only = null;
    });
  }

  Future<void> _open(_Hit h) async {
    final nav = Navigator.of(context);
    final db = DatabaseService();
    switch (h.kind) {
      case _Kind.customer:
        if (!requirePermission(context, AppPermissions.debtRegister)) return;
        final Customer? c = await db.getCustomerById(h.id);
        if (c == null) return;
        nav.pop();
        nav.push(MaterialPageRoute(builder: (_) => CustomerDetailsScreen(customer: c)));
        break;
      case _Kind.product:
        if (!requirePermission(context, AppPermissions.itemCard)) return;
        nav.pop();
        nav.push(MaterialPageRoute(builder: (_) => ItemCardEditorScreen(productId: h.id)));
        break;
      case _Kind.invoice:
        if (!requirePermission(context, AppPermissions.editInvoices)) return;
        final inv = await db.getInvoiceById(h.id);
        if (inv == null) return;
        nav.pop();
        nav.push(MaterialPageRoute(
          builder: (_) => CreateInvoiceScreen(
            existingInvoice: inv,
            isViewOnly: inv.status == 'محفوظة' || !inv.isCreatedByMe,
          ),
        ));
        break;
    }
  }

  void _move(int d) {
    final n = _shown.length;
    if (n == 0) return;
    setState(() => _sel = (_sel + d) % n); // باقي القسمة في Dart موجب دائماً
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _keys[_sel]?.currentContext;
      if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 120), alignment: 0.5);
    });
  }

  void _submit() {
    final s = _shown;
    if (s.isNotEmpty) _open(s[_sel.clamp(0, s.length - 1)]);
  }

  @override
  Widget build(BuildContext context) {
    final q = _controller.text.trim();
    final shown = _shown;
    final size = MediaQuery.of(context).size;
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: EdgeInsets.only(top: size.height > 700 ? 70 : 24, left: 16, right: 16),
          child: Material(
            color: Colors.white,
            elevation: 0,
            borderRadius: BorderRadius.circular(22),
            clipBehavior: Clip.antiAlias,
            child: Container(
              constraints: BoxConstraints(maxWidth: 700, maxHeight: size.height * 0.78),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: _S.border),
                boxShadow: [
                  BoxShadow(color: const Color(0xFF0F172A).withValues(alpha: 0.22), blurRadius: 40, offset: const Offset(0, 18)),
                ],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _searchHeader(q),
                if (_hits.isNotEmpty) _filters(),
                const Divider(height: 1, color: _S.border),
                Flexible(child: _body(q, shown)),
                _footer(),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _searchHeader(String q) => Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF7F9FD), Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
            const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
            const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop(),
          },
          child: TextField(
            controller: _controller,
            autofocus: true,
            onChanged: _onChanged,
            onSubmitted: (_) => _submit(),
            style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600, color: _S.text),
            decoration: InputDecoration(
              hintText: 'ابحث عن عميل، هاتف، مادة، رمز، باركود، رقم فاتورة…',
              hintStyle: const TextStyle(color: _S.muted, fontWeight: FontWeight.w400, fontSize: 14.5),
              filled: true,
              fillColor: _S.soft,
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
              prefixIcon: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF0F3460), Color(0xFF16508A)]),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.search_rounded, color: Colors.white, size: 21),
                ),
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 54, minHeight: 40),
              suffixIcon: _busy
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2)),
                    )
                  : (q.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'مسح',
                          icon: const Icon(Icons.close_rounded, color: _S.muted),
                          onPressed: () {
                            _controller.clear();
                            _onChanged('');
                          },
                        )),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: _S.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: _S.navy, width: 1.6),
              ),
            ),
          ),
        ),
      );

  Widget _filters() {
    Widget chip(_Kind? k, String label, int n, Color c) {
      final on = _only == k;
      return Padding(
        padding: const EdgeInsetsDirectional.only(end: 6),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => setState(() {
            _only = k;
            _sel = 0;
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: on ? c : c.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: on ? c : c.withValues(alpha: 0.22)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: on ? Colors.white : c)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: on ? Colors.white.withValues(alpha: 0.25) : c.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('$n',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: on ? Colors.white : c)),
              ),
            ]),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          chip(null, 'الكل', _hits.length, _S.navy),
          for (final k in _Kind.values)
            if (_count(k) > 0) chip(k, _S.label(k), _count(k), _S.of(k)),
        ]),
      ),
    );
  }

  Widget _body(String q, List<_Hit> shown) {
    if (q.isEmpty) return _welcome();
    if (shown.isEmpty) {
      return _busy
          ? const SizedBox(height: 120)
          : Padding(
              padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.search_off_rounded, size: 46, color: _S.muted.withValues(alpha: 0.6)),
                const SizedBox(height: 10),
                Text('لا نتائج لـ «$q»', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: _S.text)),
                const SizedBox(height: 4),
                const Text('جرّب جزءاً من الاسم، أو آخر أرقام الهاتف، أو رقم الفاتورة',
                    style: TextStyle(color: _S.muted, fontSize: 12.5)),
              ]),
            );
    }
    final children = <Widget>[];
    _Kind? last;
    for (var i = 0; i < shown.length; i++) {
      final h = shown[i];
      if (_only == null && h.kind != last) {
        children.add(_sectionTitle(h.kind));
        last = h.kind;
      }
      final key = _keys.putIfAbsent(i, () => GlobalKey());
      children.add(_HitTile(
        key: key,
        hit: h,
        query: q,
        selected: i == _sel,
        onTap: () => _open(h),
        onHover: () {
          if (_sel != i) setState(() => _sel = i);
        },
      ));
    }
    return ListView(
      controller: _scroll,
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
      children: children,
    );
  }

  Widget _sectionTitle(_Kind k) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
        child: Row(children: [
          Container(width: 4, height: 14, decoration: BoxDecoration(color: _S.of(k), borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 8),
          Text(_S.label(k),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _S.muted, letterSpacing: 0.2)),
          const SizedBox(width: 8),
          const Expanded(child: Divider(height: 1, color: _S.border)),
        ]),
      );

  Widget _welcome() {
    Widget tip(_Kind k, String t, String ex) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _S.of(k).withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _S.of(k).withValues(alpha: 0.18)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(_S.icon(k), color: _S.of(k), size: 22),
              const SizedBox(height: 8),
              Text(t, style: const TextStyle(fontWeight: FontWeight.w800, color: _S.text, fontSize: 13.5)),
              const SizedBox(height: 2),
              Text(ex, style: const TextStyle(color: _S.muted, fontSize: 11.5, height: 1.4)),
            ]),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        tip(_Kind.customer, 'عميل', 'جزء من الاسم أو آخر أرقام الهاتف'),
        const SizedBox(width: 10),
        tip(_Kind.product, 'مادة', 'الاسم، رمز المادة، أو الباركود'),
        const SizedBox(width: 10),
        tip(_Kind.invoice, 'فاتورة', 'رقم الفاتورة أو اسم العميل'),
      ]),
    );
  }

  Widget _footer() {
    Widget key(String k) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: _S.border),
            boxShadow: const [BoxShadow(color: _S.border, offset: Offset(0, 1.5))],
          ),
          child: Text(k, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _S.text)),
        );
    const t = TextStyle(fontSize: 11.5, color: _S.muted);
    return Container(
      color: _S.soft,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(children: [
        key('↑'),
        const SizedBox(width: 3),
        key('↓'),
        const Text('  تنقّل', style: t),
        const SizedBox(width: 14),
        key('Enter'),
        const Text('  فتح', style: t),
        const SizedBox(width: 14),
        key('Esc'),
        const Text('  إغلاق', style: t),
        const Spacer(),
        if (_hits.isNotEmpty) Text('${_shown.length} نتيجة', style: t),
      ]),
    );
  }
}

class _HitTile extends StatelessWidget {
  const _HitTile({
    super.key,
    required this.hit,
    required this.query,
    required this.selected,
    required this.onTap,
    required this.onHover,
  });
  final _Hit hit;
  final String query;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onHover;

  /// يبرز الجزء المطابق من الاسم.
  List<TextSpan> _highlight(String text, Color c) {
    final q = query.trim();
    if (q.isEmpty) return [TextSpan(text: text)];
    final i = text.toLowerCase().indexOf(q.toLowerCase());
    if (i < 0) return [TextSpan(text: text)];
    return [
      TextSpan(text: text.substring(0, i)),
      TextSpan(
        text: text.substring(i, i + q.length),
        style: TextStyle(color: c, backgroundColor: c.withValues(alpha: 0.12)),
      ),
      TextSpan(text: text.substring(i + q.length)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = _S.of(hit.kind);
    return MouseRegion(
      onEnter: (_) => onHover(),
      child: Semantics(
        button: true,
        label: hit.title,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          margin: const EdgeInsets.only(bottom: 4),
          decoration: BoxDecoration(
            color: selected ? c.withValues(alpha: 0.07) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? c.withValues(alpha: 0.35) : Colors.transparent),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Row(children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [c.withValues(alpha: 0.16), c.withValues(alpha: 0.06)],
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(_S.icon(hit.kind), color: c, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text.rich(
                      TextSpan(children: _highlight(hit.title, c)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: _S.text),
                    ),
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 4, children: [
                      for (final ch in hit.chips) _chip(ch),
                    ]),
                  ]),
                ),
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 140),
                  opacity: selected ? 1 : 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(8)),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('فتح', style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
                      SizedBox(width: 2),
                      Icon(Icons.keyboard_return_rounded, color: Colors.white, size: 14),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(_Chip ch) {
    final col = ch.color ?? _S.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: (ch.color ?? _S.muted).withValues(alpha: ch.color == null ? 0.07 : 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (ch.icon != null) ...[Icon(ch.icon, size: 13, color: col), const SizedBox(width: 4)],
        Text(ch.text,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: ch.color ?? const Color(0xFF475569))),
      ]),
    );
  }
}
