// screens/invoice_history_screen.dart
// 🕘 سجل تعديلات الفاتورة — خط زمني واضح لصاحب المحل (للعرض فقط)
//
// • الأحدث في الأعلى، و«إنشاء الفاتورة» في أسفل الخط الزمني بأرقامها الأصلية.
// • لكل حدث: التاريخ والوقت، من قام به، وسطر ملخّص لما تغيّر.
// • التفاصيل عند الضغط: جدول بيانات الفاتورة (قبل ← بعد) وجدول الأصناف
//   (مضاف بالأخضر، محذوف بالأحمر، معدّل بقيمته القديمة والجديدة).
// المنطق والمقارنة في invoice_history/invoice_history_model.dart

import 'package:flutter/material.dart';

import '../services/database_service.dart';
import 'invoice_history/invoice_history_model.dart';

class InvoiceHistoryScreen extends StatefulWidget {
  final int invoiceId;
  final String? customerName;

  const InvoiceHistoryScreen({
    super.key,
    required this.invoiceId,
    this.customerName,
  });

  @override
  State<InvoiceHistoryScreen> createState() => _InvoiceHistoryScreenState();
}

class _KindStyle {
  final Color color;
  final IconData icon;
  const _KindStyle(this.color, this.icon);
}

class _InvoiceHistoryScreenState extends State<InvoiceHistoryScreen> {
  static const Color _primary = Color(0xFF3F51B5);
  static const Color _pageBg = Color(0xFFF4F6FA);
  static const Color _border = Color(0xFFE3E7EE);
  static const Color _textDark = Color(0xFF263238);
  static const double _dotSize = 40;

  bool _isLoading = true;
  String? _errorMessage;
  InvoiceHistoryData? _data;
  final Set<int> _expanded = <int>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // تحميل البيانات (قراءة فقط)
  // ═══════════════════════════════════════════════════════════════════════════

  /// قراءة جدول ثانوي بأمان: غيابه أو اختلاف أعمدته لا يُفشل الشاشة
  Future<List<Map<String, dynamic>>> _safeRows(
      Future<List<Map<String, Object?>>> Function() run) async {
    try {
      final rows = await run();
      return rows.map((r) => Map<String, dynamic>.from(r)).toList();
    } catch (e) {
      debugPrint('⚠️ سجل التعديلات: تعذّرت قراءة جزء من البيانات: $e');
      return <Map<String, dynamic>>[];
    }
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final db = await DatabaseService().database;
      final int id = widget.invoiceId;

      final invoiceRows = await _safeRows(() => db.query('invoices',
          where: 'id = ?', whereArgs: [id], limit: 1));
      final Map<String, dynamic>? invoice =
          invoiceRows.isEmpty ? null : invoiceRows.first;

      final List<Map<String, dynamic>> itemRows = invoice == null
          ? <Map<String, dynamic>>[]
          : await _safeRows(() => db.query('invoice_items',
              where: 'invoice_id = ?', whereArgs: [id], orderBy: 'id ASC'));

      // النسخ المحفوظة: المصدر الأساسي (الأصناف نص JSON قديم أو BLOB مضغوط)
      final snapshotRaw = await db.query(
        'invoice_snapshots',
        where: 'invoice_id = ?',
        whereArgs: [id],
        orderBy: 'version_number ASC, id ASC',
      );
      final List<Map<String, dynamic>> snapshots =
          snapshotRaw.map((r) => Map<String, dynamic>.from(r)).toList();

      final List<Map<String, dynamic>> adjustments = await _safeRows(() =>
          db.query('invoice_adjustments',
              where: 'invoice_id = ?',
              whereArgs: [id],
              orderBy: 'created_at ASC, id ASC'));

      // احتياطي للفواتير التي لا تملك أي نسخة محفوظة
      final List<Map<String, dynamic>> auditRows = snapshots.isEmpty
          ? await _safeRows(() => db.query('financial_audit_log',
              where: "entity_type = 'invoice' AND entity_id = ? "
                  "AND operation_type IN ('invoice_create', 'invoice_update')",
              whereArgs: [id],
              orderBy: 'created_at ASC, id ASC'))
          : <Map<String, dynamic>>[];

      final InvoiceHistoryData data = InvoiceHistoryBuilder.build(
        snapshots: snapshots,
        invoice: invoice,
        currentItems: itemRows,
        adjustments: adjustments,
        auditRows: auditRows,
      );

      if (!mounted) return;
      setState(() {
        _data = data;
        _isLoading = false;
        _expanded.clear();
        // افتح أحدث تغيير تلقائياً ليظهر الفرق مباشرة
        if (data.events.isNotEmpty &&
            data.events.first.kind != HistEventKind.created) {
          _expanded.add(0);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'خطأ في تحميل سجل التعديلات: $e';
        _isLoading = false;
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // الواجهة
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final InvoiceHistoryData? data = _data;
    final String? number = data?.invoiceNumber;
    final String shownNumber =
        (number != null && number.isNotEmpty) ? number : '${widget.invoiceId}';
    final int eventCount = data?.events.length ?? 0;
    final bool allExpanded = eventCount > 0 && _expanded.length >= eventCount;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _pageBg,
        appBar: AppBar(
          title: Text('سجل التعديلات — فاتورة #$shownNumber'),
          backgroundColor: _primary,
          foregroundColor: Colors.white,
          actions: [
            if (eventCount > 1)
              IconButton(
                icon: Icon(allExpanded ? Icons.unfold_less : Icons.unfold_more),
                tooltip: allExpanded ? 'طيّ الكل' : 'عرض تفاصيل الكل',
                onPressed: () {
                  setState(() {
                    if (allExpanded) {
                      _expanded.clear();
                    } else {
                      _expanded
                        ..clear()
                        ..addAll(List<int>.generate(eventCount, (i) => i));
                    }
                  });
                },
              ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'تحديث',
              onPressed: _isLoading ? null : _load,
            ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: _primary),
            SizedBox(height: 16),
            Text('جاري تحميل سجل التعديلات...'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(_errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }

    final InvoiceHistoryData? data = _data;
    if (data == null || data.events.isEmpty) return _buildEmptyState();

    final List<HistEvent> events = data.events;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _buildSummary(data),
            const SizedBox(height: 16),
            if (data.editCount == 0 && data.externalCount == 0 && events.length == 1)
              _buildNoEditsBanner(),
            for (int i = 0; i < events.length; i++)
              _buildTimelineRow(events[i], i,
                  isFirst: i == 0, isLast: i == events.length - 1),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 76, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text(
              'لا يوجد سجل تعديلات لهذه الفاتورة',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'لم تُحفظ أي نسخة من هذه الفاتورة بعد. يظهر السجل هنا بعد حفظها أو تعديلها.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoEditsBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, color: Colors.green.shade700),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'لم تُعدَّل هذه الفاتورة منذ إنشائها.',
              style: TextStyle(
                  fontWeight: FontWeight.w600, color: Colors.green.shade900),
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── الملخّص العلوي ─────────────────────────

  Widget _buildSummary(InvoiceHistoryData data) {
    final String customer = (data.customerName ?? '').isNotEmpty
        ? data.customerName!
        : (widget.customerName ?? '').trim();
    final double? original = data.originalTotal;
    final double? currentTotal = data.currentTotal;
    final double? diff = (original != null && currentTotal != null)
        ? currentTotal - original
        : null;
    final DateTime? lastAt = data.lastChangeAt;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.history, color: _primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  customer.isEmpty ? 'سجل تعديلات الفاتورة' : 'فاتورة: $customer',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold, color: _textDark),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _statChip(
                Icons.edit_note,
                data.editCount == 0
                    ? 'لم تُعدَّل'
                    : 'عُدّلت ${_timesText(data.editCount)}',
                Colors.orange.shade800,
              ),
              if (data.externalCount > 0)
                _statChip(
                  Icons.sync_alt,
                  'تغيّرت من خارج شاشة التعديل ${_timesText(data.externalCount)}',
                  Colors.deepPurple.shade400,
                ),
              if (lastAt != null)
                _statChip(Icons.schedule,
                    'آخر تغيير: ${HistFmt.dateTime(lastAt)}', Colors.blueGrey.shade700),
              if (original != null)
                _statChip(Icons.receipt_long,
                    'الإجمالي الأصلي: ${HistFmt.number(original)}', Colors.blue.shade700),
              if (currentTotal != null)
                _statChip(Icons.payments_outlined,
                    'الإجمالي الحالي: ${HistFmt.number(currentTotal)}', _primary),
              if (diff != null && diff.abs() >= 0.005)
                _statChip(
                  diff > 0 ? Icons.trending_up : Icons.trending_down,
                  diff > 0
                      ? 'زاد الإجمالي ${HistFmt.number(diff)}'
                      : 'نقص الإجمالي ${HistFmt.number(diff.abs())}',
                  diff > 0 ? Colors.green.shade700 : Colors.red.shade700,
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _timesText(int n) {
    if (n == 1) return 'مرة واحدة';
    if (n == 2) return 'مرتين';
    return n <= 10 ? '$n مرات' : '$n مرة';
  }

  Widget _statChip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(70)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                  fontSize: 12.5, color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── الخط الزمني ─────────────────────────

  _KindStyle _kindStyle(HistEventKind kind) {
    if (kind == HistEventKind.created) {
      return _KindStyle(Colors.blue.shade700, Icons.note_add_outlined);
    }
    if (kind == HistEventKind.external) {
      return _KindStyle(Colors.deepPurple.shade400, Icons.sync_alt);
    }
    if (kind == HistEventKind.adjustment) {
      return _KindStyle(Colors.teal.shade600, Icons.tune);
    }
    return _KindStyle(Colors.orange.shade800, Icons.edit_note);
  }

  String _title(HistEvent e) {
    if (e.kind == HistEventKind.created) return 'إنشاء الفاتورة';
    if (e.kind == HistEventKind.external) return 'تغيير من خارج شاشة التعديل';
    if (e.kind == HistEventKind.adjustment) return 'تسوية على الفاتورة';
    return 'تعديل رقم ${e.editNumber}';
  }

  String _byLabel(String by) {
    final String v = by.trim();
    if (v.toLowerCase() == 'system') return 'النظام';
    return v;
  }

  Widget _buildTimelineRow(HistEvent e, int index,
      {required bool isFirst, required bool isLast}) {
    final _KindStyle style = _kindStyle(e.kind);
    const double half = _dotSize / 2;
    return Stack(
      children: [
        // خط الزمن الرأسي يربط النقاط
        if (!(isFirst && isLast))
          PositionedDirectional(
            start: half - 1,
            top: isFirst ? half : 0.0,
            bottom: isLast ? null : 0.0,
            height: isLast ? half : null,
            width: 2,
            child: Container(color: Colors.grey.shade300),
          ),
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: _dotSize,
                height: _dotSize,
                decoration: BoxDecoration(
                  color: style.color,
                  shape: BoxShape.circle,
                  border: Border.all(color: _pageBg, width: 3),
                ),
                child: Icon(style.icon, size: 19, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(child: _buildEventCard(e, index, style)),
            ],
          ),
        ),
      ],
    );
  }

  BoxDecoration _cardDecoration({Color? highlight}) {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
          color: highlight ?? _border, width: highlight != null ? 1.4 : 1),
      boxShadow: const [
        BoxShadow(color: Color(0x0F000000), blurRadius: 6, offset: Offset(0, 2)),
      ],
    );
  }

  bool _hasDetails(HistEvent e) {
    if (e.kind == HistEventKind.created) return e.state != null;
    if (e.kind == HistEventKind.adjustment) return e.adjustment != null;
    return e.fields.isNotEmpty ||
        e.items.isNotEmpty ||
        e.itemsUnknown ||
        e.note != null;
  }

  void _toggle(int index) {
    setState(() {
      if (_expanded.contains(index)) {
        _expanded.remove(index);
      } else {
        _expanded.add(index);
      }
    });
  }

  Widget _buildEventCard(HistEvent e, int index, _KindStyle style) {
    final bool expanded = _expanded.contains(index);
    final bool hasDetails = _hasDetails(e);
    final bool newest = index == 0 && e.kind != HistEventKind.created;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: _cardDecoration(highlight: newest ? style.color : null),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: hasDetails ? () => _toggle(index) : null,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildCardHeader(e, style, expanded, hasDetails, newest),
                    const SizedBox(height: 8),
                    Text(
                      e.headline,
                      style: const TextStyle(
                          fontSize: 14.5, height: 1.5, color: _textDark),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: expanded && hasDetails
                ? Container(
                    decoration: const BoxDecoration(
                      border: Border(top: BorderSide(color: _border)),
                    ),
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                    child: _buildDetails(e),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _buildCardHeader(HistEvent e, _KindStyle style, bool expanded,
      bool hasDetails, bool newest) {
    final double? delta = e.delta;
    final DateTime? at = e.at;
    final String? by = e.by;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    _title(e),
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: style.color),
                  ),
                  if (newest) _tag('الأحدث', style.color),
                ],
              ),
            ),
            if (delta != null && delta.abs() >= 0.005) _deltaBadge(delta),
            if (hasDetails)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 6),
                child: Icon(expanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.grey.shade600),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            _meta(Icons.schedule,
                at != null ? HistFmt.dateTime(at) : (e.timeNote ?? 'الوقت غير مسجّل')),
            if (by != null) _meta(Icons.person_outline, 'بواسطة: ${_byLabel(by)}'),
          ],
        ),
      ],
    );
  }

  Widget _tag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.bold, color: color)),
    );
  }

  Widget _deltaBadge(double delta) {
    final bool up = delta > 0;
    final Color color = up ? Colors.green.shade700 : Colors.red.shade700;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: up ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(90)),
      ),
      child: Text(
        HistFmt.signed(delta),
        textDirection: TextDirection.ltr,
        style: TextStyle(
            fontSize: 12.5, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  Widget _meta(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.grey.shade600),
        const SizedBox(width: 4),
        Flexible(
          child: Text(text,
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
        ),
      ],
    );
  }

  // ───────────────────────── التفاصيل ─────────────────────────

  Widget _buildDetails(HistEvent e) {
    final List<Widget> children = <Widget>[];

    if (e.kind == HistEventKind.created) {
      final HistState? s = e.state;
      if (s != null) children.addAll(_buildCreationDetails(s));
    } else if (e.kind == HistEventKind.adjustment) {
      final HistAdjustment? a = e.adjustment;
      if (a != null) children.add(_buildAdjustmentDetails(a));
    } else {
      if (e.fields.isNotEmpty) {
        children.add(_sectionTitle(Icons.receipt_outlined, 'بيانات الفاتورة'));
        children.add(_buildFieldsTable(e.fields));
      }
      if (e.items.isNotEmpty) {
        if (children.isNotEmpty) children.add(const SizedBox(height: 14));
        children.add(_sectionTitle(Icons.inventory_2_outlined, 'الأصناف',
            trailing: _itemsLegend(e.items)));
        children.add(_buildItemsDiffTable(e.items));
      }
      final double? totalAfter = e.totalAfter;
      if (e.field('total') == null && totalAfter != null) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            'الإجمالي بقي كما هو: ${HistFmt.number(totalAfter)}',
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
          ),
        ));
      }
    }

    if (e.itemsUnknown && e.kind != HistEventKind.adjustment) {
      children.add(_notice(Icons.info_outline,
          'تفاصيل الأصناف غير محفوظة في هذه النسخة القديمة — تُعرض المبالغ وبيانات الفاتورة فقط.'));
    }
    final String? note = e.note;
    if (note != null) children.add(_notice(Icons.info_outline, note));
    final String? timeNote = e.timeNote;
    if (e.at != null && timeNote != null) {
      children.add(_notice(Icons.schedule, timeNote));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _sectionTitle(IconData icon, String title, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 17, color: _primary),
          const SizedBox(width: 6),
          Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 13.5, color: _primary)),
          if (trailing != null) ...[
            const SizedBox(width: 10),
            Expanded(child: trailing),
          ],
        ],
      ),
    );
  }

  Widget _tableBox(Widget table) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _border),
      ),
      child: table,
    );
  }

  Widget _cell(Widget child) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: child,
    );
  }

  TableRow _headerRow(List<String> labels) {
    return TableRow(
      decoration: const BoxDecoration(color: Color(0xFFF1F3F8)),
      children: [
        for (final String l in labels)
          _cell(Text(l,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF546E7A)))),
      ],
    );
  }

  /// بيانات الفاتورة: البند | قبل | ← | بعد
  Widget _buildFieldsTable(List<HistFieldChange> fields) {
    return _tableBox(Table(
      columnWidths: const <int, TableColumnWidth>{
        0: FlexColumnWidth(1.3),
        1: FlexColumnWidth(2),
        2: FixedColumnWidth(30),
        3: FlexColumnWidth(2),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        _headerRow(const <String>['البند', 'قبل', '', 'بعد']),
        for (final HistFieldChange f in fields)
          TableRow(
            decoration: BoxDecoration(
              color: f.key == 'total' ? const Color(0xFFF7F8FF) : Colors.white,
              border: const Border(top: BorderSide(color: _border)),
            ),
            children: [
              _cell(Text(f.label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, color: _textDark))),
              _cell(Text(
                f.before,
                style: TextStyle(color: Colors.red.shade700),
              )),
              _cell(Icon(Icons.arrow_forward,
                  size: 16, color: Colors.grey.shade500)),
              _cell(Text(
                f.after,
                style: TextStyle(
                    color: Colors.green.shade800, fontWeight: FontWeight.bold),
              )),
            ],
          ),
      ],
    ));
  }

  Widget _itemsLegend(List<HistItemChange> items) {
    int added = 0;
    int removed = 0;
    int changed = 0;
    for (final HistItemChange c in items) {
      if (c.kind == HistItemChangeKind.added) added++;
      if (c.kind == HistItemChangeKind.removed) removed++;
      if (c.kind == HistItemChangeKind.changed) changed++;
    }
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        if (changed > 0) _tag('معدّل $changed', Colors.orange.shade800),
        if (added > 0) _tag('مضاف $added', Colors.green.shade700),
        if (removed > 0) _tag('محذوف $removed', Colors.red.shade700),
      ],
    );
  }

  String _qtyText(HistItem it) => it.unit.isEmpty
      ? HistFmt.number(it.qty)
      : '${HistFmt.number(it.qty)} ${it.unit}';

  /// الأصناف: الحالة | الصنف | الكمية | السعر | المجموع
  Widget _buildItemsDiffTable(List<HistItemChange> items) {
    return _tableBox(Table(
      columnWidths: const <int, TableColumnWidth>{
        0: FixedColumnWidth(84),
        1: FlexColumnWidth(2.6),
        2: FlexColumnWidth(1.6),
        3: FlexColumnWidth(1.6),
        4: FlexColumnWidth(1.8),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        _headerRow(const <String>['الحالة', 'الصنف', 'الكمية', 'السعر', 'المجموع']),
        for (final HistItemChange c in items) _itemDiffRow(c),
      ],
    ));
  }

  TableRow _itemDiffRow(HistItemChange c) {
    Color bg;
    Color fg;
    String label;
    IconData icon;
    if (c.kind == HistItemChangeKind.added) {
      bg = Colors.green.shade50;
      fg = Colors.green.shade800;
      label = 'مضاف';
      icon = Icons.add_circle_outline;
    } else if (c.kind == HistItemChangeKind.removed) {
      bg = Colors.red.shade50;
      fg = Colors.red.shade700;
      label = 'محذوف';
      icon = Icons.remove_circle_outline;
    } else {
      bg = Colors.amber.shade50;
      fg = Colors.orange.shade900;
      label = 'معدّل';
      icon = Icons.edit_outlined;
    }

    final HistItem? b = c.before;
    final HistItem? a = c.after;
    final bool removed = c.kind == HistItemChangeKind.removed;
    Widget qty;
    Widget price;
    Widget total;
    Widget name;
    if (c.kind == HistItemChangeKind.changed && b != null && a != null) {
      qty = _changeCell(_qtyText(b), _qtyText(a), c.qtyChanged || c.unitChanged);
      price = _changeCell(
          HistFmt.number(b.price), HistFmt.number(a.price), c.priceChanged);
      total = _changeCell(
          HistFmt.number(b.total), HistFmt.number(a.total), c.totalChanged);
      name = Text(a.name,
          style: const TextStyle(fontWeight: FontWeight.w600, color: _textDark));
    } else {
      final HistItem it = c.item;
      qty = _plainCell(_qtyText(it), removed);
      price = _plainCell(HistFmt.number(it.price), removed);
      total = _plainCell(HistFmt.number(it.total), removed);
      name = Text(
        it.name,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: removed ? Colors.red.shade800 : Colors.green.shade900,
          decoration: removed ? TextDecoration.lineThrough : null,
        ),
      );
    }

    return TableRow(
      decoration: BoxDecoration(
        color: bg,
        border: const Border(top: BorderSide(color: Colors.white, width: 2)),
      ),
      children: [
        _cell(Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 4),
            Flexible(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold, color: fg)),
            ),
          ],
        )),
        _cell(name),
        _cell(qty),
        _cell(price),
        _cell(total),
      ],
    );
  }

  /// قيمة معدّلة: القديمة مشطوبة صغيرة، والجديدة بارزة تحتها
  Widget _changeCell(String before, String after, bool changed) {
    if (!changed) {
      return Text(after, style: const TextStyle(fontSize: 13, color: _textDark));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          before,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
            decoration: TextDecoration.lineThrough,
          ),
        ),
        Text(
          after,
          style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.bold,
              color: Colors.orange.shade900),
        ),
      ],
    );
  }

  Widget _plainCell(String text, bool removed) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        color: removed ? Colors.red.shade800 : Colors.green.shade900,
        decoration: removed ? TextDecoration.lineThrough : null,
      ),
    );
  }

  /// جدول «اسم ← قيمة» بسيط
  Widget _kvTable(List<List<String>> rows) {
    return _tableBox(Table(
      columnWidths: const <int, TableColumnWidth>{
        0: FlexColumnWidth(1.2),
        1: FlexColumnWidth(2.2),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        for (int i = 0; i < rows.length; i++)
          TableRow(
            decoration: BoxDecoration(
              color: i.isEven ? Colors.white : const Color(0xFFF8F9FB),
            ),
            children: [
              _cell(Text(rows[i][0],
                  style: TextStyle(color: Colors.grey.shade700))),
              _cell(Text(rows[i][1],
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, color: _textDark))),
            ],
          ),
      ],
    ));
  }

  List<Widget> _buildCreationDetails(HistState s) {
    final List<List<String>> rows = <List<String>>[];
    final String? customer = s.customerName;
    if (customer != null) {
      rows.add(<String>['العميل', customer.isEmpty ? '—' : customer]);
    }
    final String? pay = s.paymentType;
    if (pay != null && pay.isNotEmpty) rows.add(<String>['نوع الدفع', pay]);
    final DateTime? invDate = s.invoiceDate;
    if (invDate != null) {
      rows.add(<String>['تاريخ الفاتورة', HistFmt.date(invDate)]);
    }
    if (s.discount != null) {
      rows.add(<String>['الخصم', HistFmt.number(s.discount)]);
    }
    if (s.loadingFee != null) {
      rows.add(<String>['أجور التحميل', HistFmt.number(s.loadingFee)]);
    }
    if (s.paid != null) {
      rows.add(<String>['المبلغ المدفوع', HistFmt.number(s.paid)]);
    }
    if (s.total != null) {
      rows.add(<String>['الإجمالي', HistFmt.number(s.total)]);
    }

    final List<Widget> out = <Widget>[];
    if (rows.isNotEmpty) {
      out.add(_sectionTitle(Icons.receipt_outlined, 'بيانات الفاتورة الأصلية'));
      out.add(_kvTable(rows));
    }

    final List<HistItem>? items = s.items;
    if (items != null && items.isNotEmpty) {
      if (out.isNotEmpty) out.add(const SizedBox(height: 14));
      out.add(_sectionTitle(
          Icons.inventory_2_outlined, 'الأصناف الأصلية (${items.length})'));
      out.add(_tableBox(Table(
        columnWidths: const <int, TableColumnWidth>{
          0: FlexColumnWidth(2.6),
          1: FlexColumnWidth(1.6),
          2: FlexColumnWidth(1.6),
          3: FlexColumnWidth(1.8),
        },
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          _headerRow(const <String>['الصنف', 'الكمية', 'السعر', 'المجموع']),
          for (int i = 0; i < items.length; i++)
            TableRow(
              decoration: BoxDecoration(
                color: i.isEven ? Colors.white : const Color(0xFFF8F9FB),
                border: const Border(top: BorderSide(color: _border)),
              ),
              children: [
                _cell(Text(items[i].name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, color: _textDark))),
                _cell(Text(_qtyText(items[i]))),
                _cell(Text(HistFmt.number(items[i].price))),
                _cell(Text(HistFmt.number(items[i].total),
                    style: const TextStyle(fontWeight: FontWeight.bold))),
              ],
            ),
        ],
      )));
    }
    return out;
  }

  Widget _buildAdjustmentDetails(HistAdjustment a) {
    final String? product = a.productName;
    final double? q = a.qty;
    final String? unit = a.unit;
    final double? price = a.price;
    final String? pay = a.paymentType;
    final String? note = a.note;
    final List<List<String>> rows = <List<String>>[
      <String>['النوع', a.isCredit ? 'تسوية بالنقص (مرتجع)' : 'تسوية بالزيادة'],
      if (product != null) <String>['الصنف', product],
      if (q != null)
        <String>[
          'الكمية',
          unit != null ? '${HistFmt.number(q)} $unit' : HistFmt.number(q),
        ],
      if (price != null) <String>['السعر', HistFmt.number(price)],
      <String>['المبلغ', HistFmt.number(a.delta.abs())],
      if (pay != null) <String>['طريقة التسوية', pay],
      if (note != null) <String>['ملاحظة', note],
    ];
    return _kvTable(rows);
  }

  Widget _notice(IconData icon, String text) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFFE082)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.orange.shade800),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                  fontSize: 12.5, color: Colors.brown.shade700, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
