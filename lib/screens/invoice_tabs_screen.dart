// lib/screens/invoice_tabs_screen.dart
//
// 🗂️ تبويبات «إنشاء فاتورة»: أكثر من فاتورة جديدة مفتوحة في الوقت نفسه (كتبويبات المتصفح،
// وكطلبات الكاشير المتعددة في أنظمة نقاط البيع).
//
//   • شريط أعلى الشاشة: كل فاتورة مفتوحة باسم عميلها وعدد أسطرها، والمفتوحة الآن ملوّنة.
//   • «＋ فاتورة أخرى» (أو Ctrl+T) يفتح فاتورة جديدة فارغة. Ctrl+Tab للتالية، Ctrl+W لإغلاق الحالية.
//   • كل تبويب شاشة إنشاء فاتورة كاملة تبقى حيّة في الخلفية (لا يضيع ما كُتب)،
//     ولكل تبويب مسودته المحفوظة: الخروج ثم العودة يعيد التبويبات كما كانت.
//   • المخفية لا تستقبل الباركود ولا الاختصارات (TickerMode + ExcludeFocus).
//   • حفظ فاتورة يُغلق تبويبها فقط؛ وآخر تبويب يُرجع للرئيسية كالسابق.
//   • الكميات بين التبويبات محجوزة (StockReservations): ما في فاتورة محمد لا يُباع في فاتورة جهاد.
//   • «تقسيم الشاشة» (Ctrl+\): فاتورتان جنباً إلى جنب. اللوحة التي تضغط فيها هي النشطة
//     (إطار ملوّن): هي وحدها تستقبل الباركود والاختصارات. يحتاج عرضاً 1000 بكسل على الأقل.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'create_invoice_screen.dart';

class InvoiceTabsScreen extends StatefulWidget {
  const InvoiceTabsScreen({super.key});

  static const int maxTabs = 8;

  @override
  State<InvoiceTabsScreen> createState() => _InvoiceTabsScreenState();
}

class _Tab {
  _Tab(this.slot);
  final String slot; // '' = المسودة الرئيسية، وإلا 't2'..'t8'
  final key = GlobalKey();
  String customer = '';
  int lines = 0;
}

class _InvoiceTabsScreenState extends State<InvoiceTabsScreen> {
  static const _storage = FlutterSecureStorage();

  /// المسودّات المستعملة الآن في كل الشاشات المفتوحة (لا يتقاسم تبويبان مسودة واحدة)
  static final Set<String> _usedSlots = {};

  final List<_Tab> _tabs = [];
  int _active = 0;
  bool _ready = false;

  // ── تقسيم الشاشة: لوحتان (البداية والنهاية)، والنشطة منهما هي _tabs[_active] ──
  static const double _minSplitWidth = 1000;
  bool _split = false;
  _Tab? _paneA; // جهة البداية (اليمين في العربية)
  _Tab? _paneB; // جهة النهاية

  bool get _splitOn =>
      _split && _paneA != null && _paneB != null && !identical(_paneA, _paneB) &&
      _tabs.contains(_paneA) && _tabs.contains(_paneB);

  bool _shown(_Tab t) => identical(t, _paneA) || identical(t, _paneB);

  /// اللوحة الأخرى (غير النشطة) في التقسيم.
  _Tab? get _otherPane => identical(_tabs[_active], _paneA) ? _paneB : _paneA;

  void _toggleSplit() {
    if (_splitOn) {
      setState(() => _split = false);
      return;
    }
    if (MediaQuery.sizeOf(context).width < _minSplitWidth) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('الشاشة ضيقة على فاتورتين جنباً إلى جنب — كبّر النافذة (1000 بكسل على الأقل)')));
      return;
    }
    if (_tabs.length < 2) {
      _newTab(intoSplit: true); // فاتورة ثانية فارغة في النصف الآخر
      return;
    }
    setState(() {
      _paneA = _tabs[_active];
      _paneB = _tabs[(_active + 1) % _tabs.length];
      _split = true;
    });
  }

  /// الضغط داخل لوحة يجعلها النشطة.
  void _focus(_Tab t) {
    final i = _tabs.indexOf(t);
    if (i < 0 || i == _active) return;
    setState(() => _active = i);
  }

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void dispose() {
    for (final t in _tabs) {
      _usedSlots.remove(t.slot);
    }
    super.dispose();
  }

  String? _freeSlot() {
    if (!_usedSlots.contains('')) return '';
    for (var n = 2; n <= InvoiceTabsScreen.maxTabs; n++) {
      if (!_usedSlots.contains('t$n')) return 't$n';
    }
    return null;
  }

  /// يعيد التبويبات التي لها مسودّات محفوظة (أُغلقت الشاشة وفيها فواتير غير محفوظة).
  Future<void> _restore() async {
    final first = _freeSlot() ?? '';
    _usedSlots.add(first);
    _tabs.add(_Tab(first));
    if (first == '') {
      for (var n = 2; n <= InvoiceTabsScreen.maxTabs; n++) {
        final slot = 't$n';
        if (_usedSlots.contains(slot)) continue;
        try {
          final raw = await _storage.read(key: CreateInvoiceScreen.draftKeyFor(slot));
          if (raw == null || raw.isEmpty) continue;
          final items = (jsonDecode(raw) as Map<String, dynamic>)['invoiceItems'];
          final hasLines = items is List && items.any((i) => '${(i as Map)['productName'] ?? ''}'.trim().isNotEmpty);
          if (!hasLines) continue;
          _usedSlots.add(slot);
          _tabs.add(_Tab(slot));
        } catch (_) {}
      }
    }
    if (mounted) setState(() => _ready = true);
  }

  void _newTab({bool intoSplit = false}) {
    final slot = _freeSlot();
    if (slot == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الحد ${InvoiceTabsScreen.maxTabs} فواتير مفتوحة — احفظ أو أغلق واحدة أولاً')),
      );
      return;
    }
    _usedSlots.add(slot);
    // تبويب جديد يبدأ فارغاً: مسودة قديمة في المسودة نفسها لا تُستعاد فيه
    _storage.delete(key: CreateInvoiceScreen.draftKeyFor(slot)).whenComplete(() {
      if (!mounted) return;
      setState(() {
        final t = _Tab(slot);
        final current = _tabs[_active];
        final wasSplit = _splitOn;
        _tabs.add(t);
        if (intoSplit) {
          _paneA = current;
          _paneB = t;
          _split = true;
        } else if (wasSplit) {
          // في التقسيم: الجديدة تأخذ اللوحة الأخرى، وتبقى التي كنت تعمل عليها ظاهرة
          if (identical(current, _paneA)) {
            _paneB = t;
          } else {
            _paneA = t;
          }
        }
        _active = _tabs.length - 1;
      });
    });
  }

  /// يُغلق تبويباً. [saved]: حُفظت فاتورته (لا سؤال). آخر تبويب ⇒ الرجوع كما كان.
  Future<void> _closeTab(_Tab t, {bool saved = false}) async {
    final i = _tabs.indexOf(t);
    if (i < 0) return;
    // آخر تبويب بلا حفظ = زر الرجوع نفسه (تُحفظ مسودته كما كان)
    if (_tabs.length == 1 && !saved) {
      Navigator.of(context).maybePop();
      return;
    }
    if (!saved && t.lines > 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('إغلاق فاتورة غير محفوظة؟'),
          content: Text('${t.customer.isEmpty ? 'هذه الفاتورة' : 'فاتورة ${t.customer}'} فيها ${t.lines} '
              'سطر لم يُحفظ. الإغلاق يحذف مسودتها ويحرّر كمياتها المحجوزة.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('رجوع')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('إغلاق وحذف المسودة'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    if (_tabs.length == 1) {
      // حُفظت فاتورة آخر تبويب: الرجوع للرئيسية كما كان قبل التبويبات
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
      return;
    }
    setState(() {
      final wasSplit = _splitOn;
      final keep = identical(t, _paneA) ? _paneB : (identical(t, _paneB) ? _paneA : null);
      _tabs.removeAt(i);
      if (_active > i) _active--;
      if (_active >= _tabs.length) _active = _tabs.length - 1;
      if (wasSplit && keep != null) {
        // أُغلقت فاتورة ظاهرة في التقسيم: تحلّ محلها فاتورة مخفية، أو يعود العرض واحداً
        _Tab? repl;
        for (final x in _tabs) {
          if (!identical(x, keep)) {
            repl = x;
            break;
          }
        }
        if (repl == null) {
          _split = false;
        } else if (identical(t, _paneA)) {
          _paneA = repl;
        } else {
          _paneB = repl;
        }
        _active = _tabs.indexOf(keep);
      }
    });
    // بعد التخلص من شاشة التبويب (التي تحفظ مسودتها عند الإغلاق) تُحذف المسودة
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await _storage.delete(key: CreateInvoiceScreen.draftKeyFor(t.slot));
      _usedSlots.remove(t.slot);
    });
  }

  void _go(int i) {
    if (i < 0 || i >= _tabs.length || i == _active) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      // في التقسيم: فاتورة مخفية تظهر مكان اللوحة النشطة (الأخرى تبقى كما هي)
      if (_splitOn && !_shown(_tabs[i])) {
        if (identical(_tabs[_active], _paneA)) {
          _paneA = _tabs[i];
        } else {
          _paneB = _tabs[i];
        }
      }
      _active = i;
    });
  }

  String _title(_Tab t, int i) {
    final who = t.customer.isEmpty ? 'فاتورة ${i + 1}' : t.customer;
    return t.lines > 0 ? '$who · ${t.lines}' : who;
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const Scaffold(body: SizedBox.shrink());
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyT, control: true): _newTab,
        const SingleActivator(LogicalKeyboardKey.tab, control: true): () => _go((_active + 1) % _tabs.length),
        const SingleActivator(LogicalKeyboardKey.tab, control: true, shift: true): () =>
            _go((_active - 1 + _tabs.length) % _tabs.length),
        const SingleActivator(LogicalKeyboardKey.keyW, control: true): () => _closeTab(_tabs[_active]),
        const SingleActivator(LogicalKeyboardKey.backslash, control: true): _toggleSplit,
      },
      child: Material(
        color: const Color(0xFFF4F7FB),
        child: Column(children: [
          _strip(),
          Expanded(
            child: LayoutBuilder(builder: (context, c) {
              final split = _splitOn && c.maxWidth >= _minSplitWidth;
              const gap = 6.0;
              final half = (c.maxWidth - gap) / 2;
              final focused = _tabs[_active];
              return Stack(children: [
                for (final t in _tabs) _place(t, focused: focused, split: split, half: half, gap: gap),
              ]);
            }),
          ),
        ]),
      ),
    );
  }

  /// مكان شاشة التبويب: ملء الشاشة، أو نصفها في التقسيم، أو مخفية (حيّة في الخلفية).
  /// المفتاح العام (GlobalKey) يُبقي الفاتورة نفسها بكل ما كُتب فيها عند الانتقال بين هذه الأماكن.
  Widget _place(_Tab t, {required _Tab focused, required bool split, required double half, required double gap}) {
    final isFocused = identical(t, focused);
    final screen = TickerMode(
      enabled: isFocused,
      child: ExcludeFocus(
        excluding: !isFocused,
        child: KeyedSubtree(
          key: t.key,
          child: CreateInvoiceScreen(
            draftSlot: t.slot,
            onTabDone: () => _closeTab(t, saved: true),
            onTabSummary: (c, n) {
              if (!mounted || (t.customer == c && t.lines == n)) return;
              setState(() {
                t.customer = c;
                t.lines = n;
              });
            },
          ),
        ),
      ),
    );
    if (split && _shown(t)) {
      final start = identical(t, _paneA);
      return PositionedDirectional(
        top: 0,
        bottom: 0,
        start: start ? 0 : half + gap,
        width: half,
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => _focus(t),
          child: Container(
            foregroundDecoration: BoxDecoration(
              border: Border.all(
                color: isFocused ? const Color(0xFF3F51B5) : const Color(0xFFCBD5E1),
                width: isFocused ? 2.5 : 1,
              ),
            ),
            child: screen,
          ),
        ),
      );
    }
    if (!split && isFocused) return Positioned.fill(child: screen);
    return Positioned.fill(child: Offstage(child: screen));
  }

  Widget _strip() {
    return SafeArea(
      bottom: false,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
        ),
        child: Row(children: [
          const Icon(Icons.receipt_long_rounded, size: 18, color: Color(0xFF3F51B5)),
          const SizedBox(width: 6),
          Text('فواتير مفتوحة: ${_tabs.length}',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF334155))),
          const SizedBox(width: 8),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(vertical: 5),
              itemCount: _tabs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) => _chip(i),
            ),
          ),
          const SizedBox(width: 6),
          Tooltip(
            message: _splitOn ? 'فاتورة واحدة على الشاشة (Ctrl+\\)' : 'فاتورتان جنباً إلى جنب (Ctrl+\\)',
            child: TextButton.icon(
              onPressed: _toggleSplit,
              icon: Icon(_splitOn ? Icons.crop_square_rounded : Icons.vertical_split_rounded, size: 18),
              label: Text(_splitOn ? 'شاشة واحدة' : 'تقسيم الشاشة'),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
          ),
          Tooltip(
            message: 'فاتورة جديدة أخرى (Ctrl+T)',
            child: TextButton.icon(
              onPressed: _newTab,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('فاتورة أخرى'),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _chip(int i) {
    final t = _tabs[i];
    final on = i == _active;
    final alsoShown = !on && _splitOn && _shown(t); // ظاهرة في اللوحة الأخرى
    return Material(
      color: on ? const Color(0xFF3F51B5) : (alsoShown ? const Color(0xFFE0E7FF) : const Color(0xFFF1F5F9)),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: alsoShown ? const BorderSide(color: Color(0xFF3F51B5)) : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _go(i),
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: 10, end: 2),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(_title(t, i),
                style: TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w700, color: on ? Colors.white : const Color(0xFF334155))),
            IconButton(
              tooltip: 'إغلاق (Ctrl+W)',
              visualDensity: VisualDensity.compact,
              iconSize: 15,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
              icon: Icon(Icons.close_rounded, color: on ? Colors.white70 : const Color(0xFF94A3B8)),
              onPressed: () => _closeTab(t),
            ),
          ]),
        ),
      ),
    );
  }
}
