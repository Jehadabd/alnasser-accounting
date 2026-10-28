// lib/screens/product_entry/pe_widgets.dart
//
// عناصر واجهة شاشة «إدخال بضاعة» (تعريف مادة جديدة):
//   • بطاقة قسم بعنوان وأيقونة (PeSectionCard)
//   • عنوان حقل مع علامة الإلزام * (PeFieldLabel)
//   • شكل موحّد لحقول الإدخال (peInputDecoration)
//   • شارة نسبة الربح بجانب كل سعر (PeProfitBadge)
//   • نافذة «سعر بنسبة ربح» (showPeMarkupDialog)
//
// واجهة فقط — لا تلمس قاعدة البيانات.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class PeColors {
  static const Color primary = Color(0xFF5D5FEF);
  static const Color background = Color(0xFFF5F7FA);
  static const Color card = Colors.white;
  static const Color text = Color(0xFF1E1E2E);
  static const Color inputFill = Color(0xFFF8F9FA);
  static const Color border = Color(0xFFE3E7EE);
  static const Color muted = Color(0xFF6B7280);
  static const Color success = Color(0xFF059669);
  static const Color danger = Color(0xFFDC2626);
  static const Color warning = Color(0xFFD97706);
}

final NumberFormat _peIntFormat = NumberFormat('#,##0', 'en_US');
final NumberFormat _peDecFormat = NumberFormat('#,##0.######', 'en_US');

/// رقم بفواصل الآلاف (1,500 أو 1,562.5) — يُقرأ ثانيةً بـ peParseNumber.
String peFormatNumber(double v) {
  if (v.isNaN || v.isInfinite) return '0';
  if (v == v.roundToDouble()) return _peIntFormat.format(v);
  return _peDecFormat.format(v);
}

/// قراءة رقم مكتوب بفواصل الآلاف. الفارغ أو غير الصالح = 0.
double peParseNumber(String s) {
  final t = s.replaceAll(',', '').trim();
  if (t.isEmpty) return 0.0;
  return double.tryParse(t) ?? 0.0;
}

/// شكل موحّد لحقول الشاشة (خلفية فاتحة، حدود ناعمة، رسائل خطأ واضحة).
InputDecoration peInputDecoration({
  String? hint,
  Widget? prefixIcon,
  Widget? suffixIcon,
  String? suffixText,
  String? helperText,
  Color? helperColor,
}) {
  OutlineInputBorder outline(Color color, [double width = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: color, width: width),
      );
  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: PeColors.inputFill,
    hintText: hint,
    hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    suffixText: suffixText,
    suffixStyle: TextStyle(fontSize: 11.5, color: Colors.grey[600], fontWeight: FontWeight.w600),
    helperText: helperText,
    helperMaxLines: 2,
    helperStyle: TextStyle(fontSize: 11, color: helperColor ?? Colors.grey[600]),
    errorMaxLines: 2,
    errorStyle: const TextStyle(fontSize: 11, height: 1.2),
    border: outline(PeColors.border),
    enabledBorder: outline(PeColors.border),
    focusedBorder: outline(PeColors.primary, 1.6),
    errorBorder: outline(PeColors.danger),
    focusedErrorBorder: outline(PeColors.danger, 1.6),
  );
}

/// بطاقة قسم: رأس ملوّن (أيقونة + عنوان + وصف) ثم المحتوى.
class PeSectionCard extends StatelessWidget {
  const PeSectionCard({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.child,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: PeColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: PeColors.border),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 12, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: color.withValues(alpha: 0.05),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: PeColors.text),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11.5, color: Colors.grey[600]),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  trailing!,
                ],
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: color.withValues(alpha: 0.12)),
          Padding(padding: const EdgeInsets.all(16), child: child),
        ],
      ),
    );
  }
}

/// عنوان حقل صغير فوق الحقل، مع * للحقول المطلوبة وعنصر اختياري في الطرف.
class PeFieldLabel extends StatelessWidget {
  const PeFieldLabel(
    this.text, {
    super.key,
    this.isRequired = false,
    this.icon,
    this.iconColor,
    this.trailing,
  });

  final String text;
  final bool isRequired;
  final IconData? icon;
  final Color? iconColor;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: iconColor ?? PeColors.muted),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text.rich(
              TextSpan(
                text: text,
                children: [
                  if (isRequired)
                    const TextSpan(
                      text: ' *',
                      style: TextStyle(color: PeColors.danger, fontWeight: FontWeight.bold),
                    ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: PeColors.text),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// شارة «ربح 25%» / «خسارة 5%» / «بدون ربح» بحسب السعر والكلفة.
class PeProfitBadge extends StatelessWidget {
  const PeProfitBadge({super.key, required this.cost, required this.price});

  final double cost;
  final double price;

  /// نسبة مختصرة: 25 أو 2.5 (بدون .0 زائدة).
  static String pctText(double v) {
    final s = v >= 10 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  @override
  Widget build(BuildContext context) {
    if (price <= 0) return const SizedBox.shrink();
    if (cost <= 0) {
      return _chip('بدون كلفة', Colors.grey.shade600, 'أدخل سعر الكلفة لحساب نسبة الربح');
    }
    final diff = price - cost;
    if (diff.abs() < 0.000001) {
      return _chip('بدون ربح', PeColors.warning, 'السعر يساوي الكلفة');
    }
    final pct = pctText((diff / cost * 100).abs());
    if (diff > 0) {
      return _chip('ربح $pct%', PeColors.success, 'ربح ${peFormatNumber(diff)} في كل وحدة');
    }
    return _chip('خسارة $pct%', PeColors.danger, 'السعر أقل من الكلفة بـ ${peFormatNumber(-diff)}');
  }

  Widget _chip(String text, Color color, String tooltip) {
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
      ),
    );
  }
}

/// نتيجة نافذة «سعر بنسبة ربح».
class PeMarkupResult {
  const PeMarkupResult(this.price, this.percent);
  final double price;
  final double percent;
}

/// نافذة تحسب سعراً = الكلفة × (1 + النسبة%) مع تقريب اختياري لأعلى.
Future<PeMarkupResult?> showPeMarkupDialog(
  BuildContext context, {
  required double cost,
  required String tierLabel,
  double? initialPercent,
}) {
  return showDialog<PeMarkupResult>(
    context: context,
    builder: (_) => PeMarkupDialog(cost: cost, tierLabel: tierLabel, initialPercent: initialPercent),
  );
}

class PeMarkupDialog extends StatefulWidget {
  const PeMarkupDialog({super.key, required this.cost, required this.tierLabel, this.initialPercent});

  final double cost;
  final String tierLabel;
  final double? initialPercent;

  @override
  State<PeMarkupDialog> createState() => _PeMarkupDialogState();
}

class _PeMarkupDialogState extends State<PeMarkupDialog> {
  static const List<double> _roundOptions = [0, 50, 250, 1000];

  late final TextEditingController _percentController;
  double _round = 0;

  @override
  void initState() {
    super.initState();
    final p = widget.initialPercent;
    final text = p == null ? '' : peFormatNumber(p);
    _percentController = TextEditingController(text: text);
    _percentController.selection = TextSelection(baseOffset: 0, extentOffset: text.length);
  }

  @override
  void dispose() {
    _percentController.dispose();
    super.dispose();
  }

  bool get _hasPercent => _percentController.text.trim().isNotEmpty;

  double get _percent => peParseNumber(_percentController.text);

  double get _price {
    double v = widget.cost * (1 + _percent / 100);
    if (_round > 0) {
      v = (v / _round).ceil() * _round;
    } else {
      v = (v * 1000).round() / 1000;
    }
    return v;
  }

  void _apply() {
    if (!_hasPercent) return;
    Navigator.of(context).pop(PeMarkupResult(_price, _percent));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.percent_rounded, color: PeColors.primary),
          const SizedBox(width: 8),
          Expanded(child: Text('سعر ${widget.tierLabel} بنسبة ربح', style: const TextStyle(fontSize: 17))),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'الكلفة: ${peFormatNumber(widget.cost)} د.ع',
              style: TextStyle(color: Colors.grey[700], fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            const PeFieldLabel('نسبة الربح فوق الكلفة'),
            TextField(
              controller: _percentController,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              decoration: peInputDecoration(hint: 'مثال: 25', suffixText: '%'),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _apply(),
            ),
            const SizedBox(height: 12),
            Text('تقريب السعر لأعلى إلى:', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final r in _roundOptions)
                  ChoiceChip(
                    label: Text(r == 0 ? 'بدون تقريب' : peFormatNumber(r)),
                    selected: _round == r,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => setState(() => _round = r),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: PeColors.success.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: PeColors.success.withValues(alpha: 0.25)),
              ),
              child: Text(
                _hasPercent ? 'السعر الناتج: ${peFormatNumber(_price)} د.ع' : 'اكتب النسبة لعرض السعر الناتج',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: _hasPercent ? PeColors.success : Colors.grey[600],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('إلغاء')),
        FilledButton.icon(
          onPressed: _hasPercent ? _apply : null,
          icon: const Icon(Icons.check_rounded),
          label: const Text('تطبيق'),
        ),
      ],
    );
  }
}
