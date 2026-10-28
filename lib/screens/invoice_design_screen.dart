// screens/invoice_design_screen.dart
//
// 🏢 معلومات الشركة والشعار — تظهر في رأس كل فاتورة وإيصال، بأي تصميم.
//   • الشعار، الاسم، الوصف، العنوان، حتى 4 أرقام هواتف، الرقم الضريبي، السجل التجاري، التذييل.
//   • معاينة حيّة لرأس الفاتورة بجانب الحقول.
//   • أعمدة الجدول وترتيبها وعرضها: من «مصمم الفاتورة» وحده (لا مكانين لنفس الشيء).
//   • ألوان «التصميم الأصلي» (حين لا يُختار تصميم من المصمم) في قسم مطويّ.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'package:alnaser/models/app_settings.dart';
import 'package:alnaser/models/invoice_design_settings.dart';
import 'package:alnaser/services/settings_manager.dart';

import '../erp/erp_ui.dart' show ErpPage, ErpSection, ErpColors;
import '../invoice_designer/invoice_designer_screen.dart' show InvoiceDesignerScreen;

class InvoiceDesignScreen extends StatefulWidget {
  const InvoiceDesignScreen({super.key, this.fromDesigner = false});

  /// فُتحت من داخل المصمم: زر «الأعمدة» يرجع إليه بدل فتح نسخة ثانية منه.
  final bool fromDesigner;

  @override
  State<InvoiceDesignScreen> createState() => _InvoiceDesignScreenState();
}

/// لون قابل للتعديل من ألوان التصميم الأصلي.
class _ColorKey {
  const _ColorKey(this.key, this.label);
  final String key;
  final String label;
}

class _InvoiceDesignScreenState extends State<InvoiceDesignScreen> {
  static const int maxPhones = 4;

  late AppSettings _appSettings;
  late InvoiceDesignSettings _invoiceDesign;
  bool _isLoading = true;
  bool _dirty = false;
  bool _saving = false;
  bool _colorsOpen = false;

  final _name = TextEditingController();
  final _description = TextEditingController();
  final _address = TextEditingController();
  final _tax = TextEditingController();
  final _cr = TextEditingController();
  final _footer = TextEditingController();
  final List<TextEditingController> _phones = [];

  /// ☎️ اسم كل رقم («كهربائيات»، «صحيات»…) — بنفس ترتيب [_phones]
  final List<TextEditingController> _phoneLabels = [];

  File? _logoFile;
  final Map<String, Color> _colors = {};

  static const _colorGroups = <(String, IconData, List<_ColorKey>)>[
    ('رأس الفاتورة', Icons.storefront_rounded, [
      _ColorKey('companyName', 'اسم الشركة'),
      _ColorKey('companyDescription', 'وصف الشركة'),
      _ColorKey('phone', 'أرقام الهواتف'),
    ]),
    ('ملخص الفاتورة', Icons.calculate_rounded, [
      _ColorKey('totalBeforeDiscount', 'الإجمالي قبل الخصم'),
      _ColorKey('discount', 'الخصم'),
      _ColorKey('totalAfterDiscount', 'الإجمالي بعد الخصم'),
      _ColorKey('loadingFees', 'أجور التحميل'),
      _ColorKey('paidAmount', 'المبلغ المدفوع'),
      _ColorKey('remainingAmount', 'المبلغ المتبقي'),
      _ColorKey('previousDebt', 'الدين السابق'),
      _ColorKey('currentDebt', 'الدين الحالي'),
    ]),
    ('جدول المواد', Icons.table_rows_rounded, [
      _ColorKey('itemSerial', 'التسلسل'),
      _ColorKey('itemDetails', 'أسماء المواد'),
      _ColorKey('itemQuantity', 'العدد'),
      _ColorKey('itemPrice', 'السعر'),
      _ColorKey('itemTotal', 'المبلغ'),
    ]),
    ('أخرى', Icons.color_lens_rounded, [
      _ColorKey('notice', 'التنويه'),
    ]),
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    for (final c in [_name, _description, _address, _tax, _cr, _footer, ..._phones, ..._phoneLabels]) {
      c.dispose();
    }
    super.dispose();
  }

  void _touch() {
    if (!_dirty) {
      setState(() => _dirty = true);
    } else {
      setState(() {});
    }
  }

  TextEditingController _phoneCtl(String text) => TextEditingController(text: text)..addListener(_touch);

  Future<void> _loadSettings() async {
    _appSettings = await SettingsManager.getAppSettings();
    _invoiceDesign = _appSettings.invoiceDesign;
    final s = _appSettings;
    final d = _invoiceDesign;

    _name.text = d.companyName;
    _description.text = s.companyDescription;
    _address.text = d.companyAddress;
    _tax.text = d.taxNumber;
    _cr.text = d.commercialRegister;
    _footer.text = d.footerNote;
    final src = d.phoneNumbers.isNotEmpty ? d.phoneNumbers : s.phoneNumbers;
    final fromDesign = d.phoneNumbers.isNotEmpty;
    for (var i = 0; i < src.length && _phones.length < maxPhones; i++) {
      if (src[i].trim().isEmpty) continue;
      _phones.add(_phoneCtl(src[i]));
      _phoneLabels.add(_phoneCtl(fromDesign && i < d.phoneLabels.length ? d.phoneLabels[i] : ''));
    }
    if (_phones.isEmpty) {
      _phones.add(_phoneCtl(''));
      _phoneLabels.add(_phoneCtl(''));
    }

    if (d.logoPath != null && d.logoPath!.isNotEmpty) {
      final f = File(d.logoPath!);
      if (await f.exists()) _logoFile = f;
    }

    _colors.addAll({
      'companyName': Color(s.companyNameColor),
      'companyDescription': Color(s.companyDescriptionColor),
      'phone': Color(s.electricPhoneColor),
      'remainingAmount': Color(s.remainingAmountColor),
      'discount': Color(s.discountColor),
      'loadingFees': Color(s.loadingFeesColor),
      'totalBeforeDiscount': Color(s.totalBeforeDiscountColor),
      'totalAfterDiscount': Color(s.totalAfterDiscountColor),
      'previousDebt': Color(s.previousDebtColor),
      'currentDebt': Color(s.currentDebtColor),
      'paidAmount': Color(s.paidAmountColor),
      'itemSerial': Color(s.itemSerialColor),
      'itemDetails': Color(s.itemDetailsColor),
      'itemQuantity': Color(s.itemQuantityColor),
      'itemPrice': Color(s.itemPriceColor),
      'itemTotal': Color(s.itemTotalColor),
      'notice': Color(s.noticeColor),
    });

    for (final c in [_name, _description, _address, _tax, _cr, _footer]) {
      c.addListener(_touch);
    }
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _dirty = false;
    });
  }

  int _c(String k) => (_colors[k] ?? Colors.black).toARGB32();

  List<String> get _phoneList =>
      _phones.map((c) => c.text.trim()).where((p) => p.isNotEmpty).take(maxPhones).toList();

  /// أسماء الأرقام بنفس ترتيب [_phoneList] (رقم فارغ يسقط مع اسمه)
  List<String> get _labelList => [
        for (var i = 0; i < _phones.length; i++)
          if (_phones[i].text.trim().isNotEmpty) _phoneLabels[i].text.trim(),
      ].take(maxPhones).toList();

  /// للمعاينة: «كهربائيات: 0770…»
  List<String> get _labeledPhones {
    final n = _phoneList, l = _labelList;
    return [for (var i = 0; i < n.length; i++) (i < l.length && l[i].isNotEmpty) ? '${l[i]}: ${n[i]}' : n[i]];
  }

  Future<bool> _saveSettings() async {
    setState(() => _saving = true);
    try {
      // يُبنى من جديد (لا copyWith) حتى تُحفظ «إزالة الشعار» فعلاً: copyWith يتجاهل null
      final updatedDesign = InvoiceDesignSettings(
        logoPath: _logoFile?.path,
        companyName: _name.text.trim(),
        companyAddress: _address.text.trim(),
        phoneNumbers: _phoneList,
        phoneLabels: _labelList,
        columns: _invoiceDesign.columns, // أعمدة التصميم الأصلي كما هي
        taxNumber: _tax.text.trim(),
        commercialRegister: _cr.text.trim(),
        footerNote: _footer.text.trim(),
      );
      final updated = _appSettings.copyWith(
        invoiceDesign: updatedDesign,
        companyDescription: _description.text.trim(),
        companyNameColor: _c('companyName'),
        companyDescriptionColor: _c('companyDescription'),
        remainingAmountColor: _c('remainingAmount'),
        discountColor: _c('discount'),
        loadingFeesColor: _c('loadingFees'),
        totalBeforeDiscountColor: _c('totalBeforeDiscount'),
        totalAfterDiscountColor: _c('totalAfterDiscount'),
        previousDebtColor: _c('previousDebt'),
        currentDebtColor: _c('currentDebt'),
        paidAmountColor: _c('paidAmount'),
        electricPhoneColor: _c('phone'),
        healthPhoneColor: _c('phone'),
        itemSerialColor: _c('itemSerial'),
        itemDetailsColor: _c('itemDetails'),
        itemQuantityColor: _c('itemQuantity'),
        itemPriceColor: _c('itemPrice'),
        itemTotalColor: _c('itemTotal'),
        noticeColor: _c('notice'),
      );
      await SettingsManager.saveAppSettings(updated);
      _appSettings = updated;
      _invoiceDesign = updatedDesign;
      if (!mounted) return true;
      setState(() {
        _dirty = false;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        width: 420,
        backgroundColor: ErpColors.green,
        content: const Row(children: [
          Icon(Icons.check_circle_rounded, color: Colors.white),
          SizedBox(width: 8),
          Text('حُفظت معلومات الشركة — تظهر في كل التصاميم'),
        ]),
      ));
      return true;
    } catch (e) {
      if (!mounted) return false;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(backgroundColor: ErpColors.red, content: Text('تعذّر الحفظ: $e')));
      return false;
    }
  }

  /// الخروج بتعديلات غير محفوظة: حفظ، أو تجاهل، أو البقاء.
  Future<void> _leave() async {
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(children: [
          Icon(Icons.edit_note_rounded, color: ErpColors.orange),
          SizedBox(width: 8),
          Text('تعديلات غير محفوظة'),
        ]),
        content: const Text('هل تحفظ معلومات الشركة قبل الرجوع؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'stay'), child: const Text('البقاء هنا')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            child: const Text('رجوع بلا حفظ', style: TextStyle(color: ErpColors.red)),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('حفظ ورجوع')),
        ],
      ),
    );
    if (!mounted || r == null || r == 'stay') return;
    if (r == 'save' && !await _saveSettings()) return;
    if (!mounted) return;
    setState(() => _dirty = false);
    Navigator.of(context).pop();
  }

  // ───────── الشعار ─────────

  Future<void> _pickLogo() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/logo');
    if (!await dir.exists()) await dir.create(recursive: true);
    // اسم جديد لكل صورة: نفس الاسم يُبقي الصورة القديمة في ذاكرة العرض
    final ext = picked.path.contains('.') ? picked.path.substring(picked.path.lastIndexOf('.')) : '.png';
    final saved = await File(picked.path).copy('${dir.path}/company_logo_${DateTime.now().millisecondsSinceEpoch}$ext');
    if (!mounted) return;
    setState(() {
      _logoFile = saved;
      _dirty = true;
    });
  }

  void _removeLogo() => setState(() {
        _logoFile = null;
        _dirty = true;
      });

  // ───────── الهواتف ─────────

  void _addPhone() {
    if (_phones.length >= maxPhones) return;
    setState(() {
      _phones.add(_phoneCtl(''));
      _phoneLabels.add(_phoneCtl(''));
      _dirty = true;
    });
  }

  void _removePhone(int i) {
    final c = _phones.removeAt(i);
    final lc = _phoneLabels.removeAt(i);
    if (_phones.isEmpty) {
      _phones.add(_phoneCtl(''));
      _phoneLabels.add(_phoneCtl(''));
    }
    setState(() => _dirty = true);
    // بعد إعادة البناء: حقلاه لم يعودا على الشاشة
    WidgetsBinding.instance.addPostFrameCallback((_) {
      c.dispose();
      lc.dispose();
    });
  }

  // ───────── الألوان ─────────

  Future<void> _pickColor(_ColorKey k) async {
    var temp = _colors[k.key] ?? Colors.black;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('لون «${k.label}»'),
        content: SizedBox(
          width: 340,
          child: SingleChildScrollView(
            child: BlockPicker(pickerColor: temp, onColorChanged: (c) => temp = c),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('اعتماد')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _colors[k.key] = temp;
      _dirty = true;
    });
  }

  void _openColumns() {
    if (widget.fromDesigner) {
      // فُتحت من المصمم: نرجع إليه (بعد سؤال الحفظ إن لزم)
      Navigator.of(context).maybePop();
      return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => const InvoiceDesignerScreen()));
  }

  // ───────── البناء ─────────

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const ErpPage(
        title: 'معلومات الشركة والشعار',
        icon: Icons.storefront_rounded,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: ErpPage(
        title: 'معلومات الشركة والشعار',
        subtitle: 'تظهر في رأس كل فاتورة وإيصال — بأي تصميم',
        icon: Icons.storefront_rounded,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _dirty ? Colors.white : Colors.white24,
                foregroundColor: _dirty ? ErpColors.navy : Colors.white,
              ),
              onPressed: _dirty && !_saving ? _saveSettings : null,
              icon: _saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(_dirty ? Icons.save_rounded : Icons.check_rounded),
              label: Text(_dirty ? 'حفظ' : 'محفوظ'),
            ),
          ),
        ],
        body: LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= 1050;
          final form = _form();
          if (!wide) {
            return ListView(padding: const EdgeInsets.only(top: 10, bottom: 30), children: [
              Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: _preview()),
              const SizedBox(height: 6),
              ...form,
            ]);
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: ListView(padding: const EdgeInsets.only(top: 10, bottom: 30), children: form),
            ),
            Container(
              width: 460,
              margin: const EdgeInsets.fromLTRB(12, 16, 4, 16),
              child: SingleChildScrollView(child: _preview()),
            ),
          ]);
        }),
      ),
    );
  }

  List<Widget> _form() => [
        ErpSection(
          title: 'الشعار',
          icon: Icons.image_rounded,
          color: const Color(0xFF7C3AED),
          child: Row(children: [
            InkWell(
              onTap: _pickLogo,
              borderRadius: BorderRadius.circular(18),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 118,
                height: 118,
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F3FF),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: _logoFile == null ? const Color(0xFFC4B5FD) : const Color(0xFFE9E5FB),
                    width: _logoFile == null ? 1.6 : 1,
                  ),
                ),
                child: _logoFile == null
                    ? const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.add_photo_alternate_rounded, size: 34, color: Color(0xFF7C3AED)),
                        SizedBox(height: 6),
                        Text('اختر شعاراً', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF7C3AED))),
                      ])
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(17),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Image.file(_logoFile!, fit: BoxFit.contain, key: ValueKey(_logoFile!.path)),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_logoFile == null ? 'لا شعار بعد' : 'الشعار الحالي',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 4),
                const Text('صورة PNG بخلفية شفافة تظهر أنظف على الورق. يظهر الشعار في كل تصميم فيه عنصر «الشعار».',
                    style: TextStyle(fontSize: 12.5, color: ErpColors.muted, height: 1.5)),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton.tonalIcon(
                    onPressed: _pickLogo,
                    icon: const Icon(Icons.upload_rounded, size: 18),
                    label: Text(_logoFile == null ? 'اختيار صورة' : 'تغيير'),
                  ),
                  if (_logoFile != null)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: ErpColors.red),
                      onPressed: _removeLogo,
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      label: const Text('إزالة'),
                    ),
                ]),
              ]),
            ),
          ]),
        ),
        ErpSection(
          title: 'هوية الشركة',
          icon: Icons.badge_rounded,
          child: Column(children: [
            _field(_name, 'اسم الشركة', Icons.storefront_rounded),
            const SizedBox(height: 12),
            _field(_description, 'وصف النشاط (تحت الاسم)', Icons.short_text_rounded,
                hint: 'مثال: لتجارة المواد الكهربائية والصحية'),
          ]),
        ),
        ErpSection(
          title: 'العنوان والهواتف',
          icon: Icons.contact_phone_rounded,
          color: const Color(0xFF0284C7),
          trailing: _counter(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _field(_address, 'العنوان', Icons.location_on_rounded),
            const SizedBox(height: 12),
            for (var i = 0; i < _phones.length; i++)
              Padding(
                key: ObjectKey(_phones[i]),
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0284C7).withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Text('${i + 1}',
                        style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF0284C7))),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 170,
                    child: _field(_phoneLabels[i], 'اسمه (اختياري)', Icons.label_outline_rounded,
                        hint: 'كهربائيات، صحيات…'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _field(_phones[i], 'رقم الهاتف ${i + 1}', Icons.phone_rounded, ltr: true),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: 'حذف الرقم',
                    onPressed: () => _removePhone(i),
                    icon: const Icon(Icons.remove_circle_outline_rounded, color: ErpColors.red),
                  ),
                ]),
              ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: _phones.length >= maxPhones ? null : _addPhone,
                icon: const Icon(Icons.add_circle_rounded),
                label: Text(_phones.length >= maxPhones ? 'الحد الأقصى $maxPhones أرقام' : 'إضافة رقم'),
              ),
            ),
          ]),
        ),
        ErpSection(
          title: 'بيانات رسمية وتذييل',
          icon: Icons.verified_rounded,
          color: ErpColors.green,
          child: Column(children: [
            Row(children: [
              Expanded(child: _field(_tax, 'الرقم الضريبي', Icons.numbers_rounded, ltr: true)),
              const SizedBox(width: 12),
              Expanded(child: _field(_cr, 'السجل التجاري', Icons.assignment_rounded, ltr: true)),
            ]),
            const SizedBox(height: 12),
            _field(_footer, 'عبارة أسفل الفاتورة', Icons.notes_rounded,
                maxLines: 2, hint: 'شكر، شروط، سياسة الإرجاع…'),
          ]),
        ),
        _columnsCard(),
        _colorsSection(),
      ];

  Widget _counter() {
    final n = _phoneList.length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF0284C7).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text('$n / $maxPhones أرقام',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF0284C7))),
    );
  }

  Widget _field(TextEditingController c, String label, IconData icon,
          {int maxLines = 1, String? hint, bool ltr = false}) =>
      TextField(
        controller: c,
        maxLines: maxLines,
        textDirection: ltr ? TextDirection.ltr : null,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, size: 20),
          filled: true,
          fillColor: const Color(0xFFF8FAFD),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: ErpColors.border),
          ),
        ),
      );

  Widget _columnsCard() => Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [ErpColors.navy.withValues(alpha: 0.06), ErpColors.cyan.withValues(alpha: 0.06)],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: ErpColors.navy.withValues(alpha: 0.15)),
        ),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: ErpColors.navy, borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.view_column_rounded, color: Colors.white),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('أعمدة الجدول وترتيبها وعرضها', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
              SizedBox(height: 2),
              Text('من «مصمم الفاتورة»: اضغط جدول المواد ← الأعمدة (ومنها الوزن وتاريخ الانتهاء).',
                  style: TextStyle(fontSize: 12.5, color: ErpColors.muted, height: 1.4)),
            ]),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: ErpColors.navy),
            onPressed: _openColumns,
            icon: Icon(widget.fromDesigner ? Icons.arrow_forward_rounded : Icons.dashboard_customize_rounded, size: 18),
            label: Text(widget.fromDesigner ? 'رجوع للمصمم' : 'افتح المصمم'),
          ),
        ]),
      );

  Widget _colorsSection() => ErpSection(
        title: 'ألوان التصميم الأصلي',
        icon: Icons.palette_rounded,
        color: const Color(0xFFDB2777),
        trailing: IconButton(
          tooltip: _colorsOpen ? 'طيّ' : 'عرض',
          onPressed: () => setState(() => _colorsOpen = !_colorsOpen),
          icon: AnimatedRotation(
            turns: _colorsOpen ? 0.5 : 0,
            duration: const Duration(milliseconds: 200),
            child: const Icon(Icons.expand_more_rounded),
          ),
        ),
        child: AnimatedCrossFade(
          duration: const Duration(milliseconds: 220),
          crossFadeState: _colorsOpen ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          firstChild: InkWell(
            onTap: () => setState(() => _colorsOpen = true),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text('تُستعمل فقط لأنواع الطباعة التي ما زالت على «التصميم الأصلي للبرنامج». '
                  'تصاميم المصمم لها ألوانها الخاصة.',
                  style: TextStyle(fontSize: 12.5, color: ErpColors.muted, height: 1.5)),
            ),
          ),
          secondChild: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final g in _colorGroups) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 8),
                child: Row(children: [
                  Icon(g.$2, size: 16, color: ErpColors.muted),
                  const SizedBox(width: 6),
                  Text(g.$1, style: const TextStyle(fontWeight: FontWeight.w800, color: ErpColors.muted)),
                ]),
              ),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final k in g.$3) _swatch(k),
              ]),
            ],
          ]),
        ),
      );

  Widget _swatch(_ColorKey k) {
    final c = _colors[k.key] ?? Colors.black;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _pickColor(k),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ErpColors.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(k.label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          const SizedBox(width: 10),
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: c,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [BoxShadow(color: c.withValues(alpha: 0.45), blurRadius: 6)],
            ),
          ),
        ]),
      ),
    );
  }

  // ───────── المعاينة ─────────

  Widget _preview() {
    final name = _name.text.trim().isEmpty ? 'اسم الشركة' : _name.text.trim();
    final desc = _description.text.trim();
    final addr = _address.text.trim();
    final phones = _labeledPhones;
    final official = [
      if (_tax.text.trim().isNotEmpty) 'الرقم الضريبي: ${_tax.text.trim()}',
      if (_cr.text.trim().isNotEmpty) 'السجل التجاري: ${_cr.text.trim()}',
    ];
    final nameColor = _colors['companyName'] ?? ErpColors.green;
    Widget bar(double w, {double h = 7, Color? c}) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(color: c ?? const Color(0xFFEFF2F7), borderRadius: BorderRadius.circular(4)),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Row(children: [
          Icon(Icons.visibility_rounded, size: 18, color: ErpColors.muted),
          SizedBox(width: 6),
          Text('معاينة رأس الفاتورة', style: TextStyle(fontWeight: FontWeight.w800, color: ErpColors.muted)),
        ]),
      ),
      AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(color: const Color(0xFF0F172A).withValues(alpha: 0.10), blurRadius: 24, offset: const Offset(0, 10)),
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(children: [
                Text(name,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: nameColor)),
                if (desc.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(desc,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: _colors['companyDescription'] ?? Colors.black87)),
                ],
                if (addr.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.location_on_rounded, size: 13, color: ErpColors.muted),
                    const SizedBox(width: 3),
                    Flexible(child: Text(addr, style: const TextStyle(fontSize: 11.5, color: Colors.black87))),
                  ]),
                ],
                if (phones.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 4, children: [
                    for (final p in phones)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(p,
                            style: TextStyle(
                                fontSize: 11.5, fontWeight: FontWeight.w700, color: _colors['phone'] ?? Colors.black)),
                      ),
                  ]),
                ],
                if (official.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(official.join('   •   '),
                      textAlign: TextAlign.center, style: const TextStyle(fontSize: 10.5, color: ErpColors.muted)),
                ],
              ]),
            ),
            const SizedBox(width: 12),
            Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                color: _logoFile == null ? const Color(0xFFF5F3FF) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFEDE9FE)),
              ),
              child: _logoFile == null
                  ? const Icon(Icons.image_outlined, color: Color(0xFFC4B5FD))
                  : Padding(
                      padding: const EdgeInsets.all(4),
                      child: Image.file(_logoFile!, fit: BoxFit.contain, key: ValueKey('p${_logoFile!.path}')),
                    ),
            ),
          ]),
          const SizedBox(height: 14),
          Container(height: 2, color: nameColor.withValues(alpha: 0.6)),
          const SizedBox(height: 12),
          // هيكل الجدول — الأعمدة الفعلية حسب التصميم المختار في المصمم
          Container(
            height: 22,
            decoration: BoxDecoration(color: ErpColors.navy.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(6)),
          ),
          for (var i = 0; i < 4; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                bar(18),
                const SizedBox(width: 10),
                Expanded(child: Align(alignment: AlignmentDirectional.centerStart, child: bar(120.0 - i * 18))),
                bar(40),
                const SizedBox(width: 10),
                bar(54),
              ]),
            ),
          const SizedBox(height: 8),
          const Text('الأعمدة حسب التصميم المختار في المصمم',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 10.5, color: ErpColors.muted)),
          if (_footer.text.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Text(_footer.text.trim(),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11.5, fontStyle: FontStyle.italic, color: Colors.black87)),
          ],
        ]),
      ),
    ]);
  }
}
