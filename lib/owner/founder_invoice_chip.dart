// lib/owner/founder_invoice_chip.dart
//
// 👷 زر «المؤسس» في رأس شاشة الفاتورة (يظهر لحساب المالك فقط):
// اسم المؤسس + نقاط لكل 100,000 لهذه الفاتورة، ومعاينة نقاطها.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'founder_service.dart';

class FounderInvoiceChip extends StatelessWidget {
  const FounderInvoiceChip({
    super.key,
    required this.nameController,
    required this.rate,
    required this.enabled,
    required this.invoiceTotal,
    required this.onChanged,
  });

  final TextEditingController nameController;
  final double rate;
  final bool enabled;
  final double Function() invoiceTotal;
  final void Function(String name, double rate) onChanged;

  @override
  Widget build(BuildContext context) {
    final name = nameController.text.trim();
    final has = name.isNotEmpty;
    return Tooltip(
      message: has ? 'المؤسس: $name — ${_fmt(rate)} نقطة لكل 100,000' : 'إضافة مؤسس/فني لهذه الفاتورة',
      child: InkWell(
        onTap: () => _open(context),
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: has ? const Color(0xFFF59E0B).withValues(alpha: 0.22) : Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: has ? const Color(0xFFFBBF24) : Colors.white24),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.engineering_rounded, color: has ? const Color(0xFFFDE68A) : Colors.white, size: 18),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: Text(
                has ? name : 'المؤسس',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            if (has) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: const Color(0xFFD97706), borderRadius: BorderRadius.circular(10)),
                child: Text('${_fmt(FounderService.pointsFor(invoiceTotal(), rate))} ن',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final r = await showDialog<(String, double)>(
      context: context,
      builder: (_) => _FounderDialog(
        initialName: nameController.text.trim(),
        initialRate: rate,
        enabled: enabled,
        invoiceTotal: invoiceTotal(),
      ),
    );
    if (r != null) onChanged(r.$1, r.$2);
  }
}

String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

class _FounderDialog extends StatefulWidget {
  const _FounderDialog({required this.initialName, required this.initialRate, required this.enabled, required this.invoiceTotal});
  final String initialName;
  final double initialRate;
  final bool enabled;
  final double invoiceTotal;

  @override
  State<_FounderDialog> createState() => _FounderDialogState();
}

class _FounderDialogState extends State<_FounderDialog> {
  late final TextEditingController _rate = TextEditingController(text: _fmt(widget.initialRate));
  String _name = '';
  List<String> _names = const [];
  double? _defaultRate;

  @override
  void initState() {
    super.initState();
    _name = widget.initialName;
    FounderService.names().then((v) {
      if (mounted) setState(() => _names = v);
    });
    FounderService.defaultRate().then((v) {
      if (mounted) setState(() => _defaultRate = v);
    });
  }

  @override
  void dispose() {
    _rate.dispose();
    super.dispose();
  }

  double get _rateValue => double.tryParse(_rate.text.replaceAll(',', '.')) ?? 0;

  @override
  Widget build(BuildContext context) {
    final points = FounderService.pointsFor(widget.invoiceTotal, _rateValue);
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: EdgeInsets.zero,
      title: Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [Color(0xFF0F3460), Color(0xFF1B5E8C)]),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: const Row(children: [
          Icon(Icons.engineering_rounded, color: Color(0xFFFDE68A)),
          SizedBox(width: 10),
          Text('مؤسس الفاتورة', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
        ]),
      ),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: 6),
          Autocomplete<String>(
            initialValue: TextEditingValue(text: widget.initialName),
            optionsBuilder: (v) {
              final q = v.text.trim();
              if (q.isEmpty) return _names.take(12);
              return _names.where((n) => n.contains(q)).take(12);
            },
            onSelected: (v) => setState(() => _name = v),
            fieldViewBuilder: (context, ctrl, focus, onSubmit) => TextField(
              controller: ctrl,
              focusNode: focus,
              enabled: widget.enabled,
              autofocus: widget.enabled && widget.initialName.isEmpty,
              onChanged: (v) => setState(() => _name = v),
              decoration: InputDecoration(
                labelText: 'اسم المؤسس / الفني',
                hintText: 'اختر من القائمة أو اكتب اسماً جديداً',
                prefixIcon: const Icon(Icons.person_search_rounded),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _rate,
            enabled: widget.enabled,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'النقاط لكل 100,000 (لهذه الفاتورة)',
              prefixIcon: const Icon(Icons.stars_rounded),
              helperText: _defaultRate == null ? null : 'الافتراضي من الإعدادات: ${_fmt(_defaultRate!)}',
              suffixIcon: _defaultRate == null || !widget.enabled
                  ? null
                  : IconButton(
                      tooltip: 'إرجاع الافتراضي',
                      icon: const Icon(Icons.restart_alt_rounded),
                      onPressed: () => setState(() => _rate.text = _fmt(_defaultRate!)),
                    ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Row(children: [
              const Icon(Icons.emoji_events_rounded, color: Color(0xFFD97706)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _name.trim().isEmpty ? 'بلا مؤسس: لا تُحسب نقاط لهذه الفاتورة' : 'نقاط هذه الفاتورة لـ «${_name.trim()}»',
                  style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF92400E)),
                ),
              ),
              if (_name.trim().isNotEmpty)
                Text(_fmt(points),
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFFB45309))),
            ]),
          ),
          const SizedBox(height: 6),
          const Text('تُحسب من صافي الفاتورة عند الحفظ، وتتعدّل تلقائياً عند تعديل الفاتورة أو إرجاع جزء منها.',
              style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B))),
        ]),
      ),
      actions: [
        if (widget.enabled && widget.initialName.isNotEmpty)
          TextButton.icon(
            onPressed: () => Navigator.pop(context, ('', _rateValue)),
            icon: const Icon(Icons.person_remove_rounded, color: Color(0xFFB91C1C)),
            label: const Text('إزالة المؤسس', style: TextStyle(color: Color(0xFFB91C1C))),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        if (widget.enabled)
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, (_name.trim(), _rateValue)),
            icon: const Icon(Icons.check_rounded),
            label: const Text('اعتماد'),
          ),
      ],
    );
  }
}
