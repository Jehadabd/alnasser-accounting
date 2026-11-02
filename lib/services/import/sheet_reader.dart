// lib/services/import/sheet_reader.dart
//
// 📄 قارئ جداول للاستيراد: ملف Excel (‎.xlsx) أو CSV ← أوراق، ولكل ورقة صفوف نصية.
//
//   • xlsx = ملف مضغوط فيه XML: أسماء الأوراق (workbook.xml)، والنصوص المشتركة
//     (sharedStrings.xml)، وخلايا كل ورقة. يُقرأ بمكتبتي archive و xml الموجودتين أصلاً
//     — لا مكتبة جديدة.
//   • الخلية تُقرأ نصاً كما هي (الأرقام كما خزّنها Excel)، والتحويل إلى رقم في
//     [ImportNumbers] حتى يُرفض الرقم غير الواضح بدل أن يُخمَّن.
//   • ‎.xls القديم (ثنائي) غير مدعوم: يُطلب حفظه بصيغة xlsx أو CSV.
//   • CSV: يُكتشف الفاصل (, ; Tab)، ويجب أن يكون الترميز UTF-8.
//
// قراءة فقط: هذا الملف لا يكتب في قاعدة البيانات.

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// ورقة واحدة: صفوف من خلايا نصية (الصف قد يكون أقصر من غيره).
class SheetTable {
  SheetTable(this.name, this.rows);
  final String name;
  final List<List<String>> rows;

  /// عدد الأعمدة = أطول صف.
  int get columnCount => rows.fold(0, (m, r) => r.length > m ? r.length : m);

  /// الخلية (فارغة إن لم توجد).
  String cell(int row, int col) {
    if (row < 0 || row >= rows.length) return '';
    final r = rows[row];
    return col < r.length ? r[col] : '';
  }

  /// أول صف فيه خلية غير فارغة (صف العناوين الافتراضي).
  int get firstNonEmptyRow {
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].any((c) => c.trim().isNotEmpty)) return i;
    }
    return 0;
  }
}

class SheetReadException implements Exception {
  SheetReadException(this.message);
  final String message;
  @override
  String toString() => message;
}

class SheetReader {
  SheetReader._();

  /// يقرأ الملف حسب امتداده ومحتواه.
  static List<SheetTable> read(Uint8List bytes, String fileName) {
    final lower = fileName.toLowerCase();
    final isZip = bytes.length > 4 && bytes[0] == 0x50 && bytes[1] == 0x4B;
    final isOle = bytes.length > 8 && bytes[0] == 0xD0 && bytes[1] == 0xCF && bytes[2] == 0x11 && bytes[3] == 0xE0;
    if (isOle || lower.endsWith('.xls')) {
      throw SheetReadException('ملف Excel القديم (‎.xls) غير مدعوم. افتحه في Excel واحفظه باسم «مصنف Excel ‎(.xlsx)» ثم أعد المحاولة.');
    }
    if (isZip) return readXlsx(bytes);
    if (lower.endsWith('.csv') || lower.endsWith('.txt') || lower.endsWith('.tsv')) {
      return [readCsv(bytes, name: _baseName(fileName))];
    }
    throw SheetReadException('صيغة غير معروفة. المقبول: ‎.xlsx أو ‎.csv');
  }

  static String _baseName(String f) {
    final n = f.split(RegExp(r'[\\/]')).last;
    final dot = n.lastIndexOf('.');
    return dot > 0 ? n.substring(0, dot) : n;
  }

  // ─────────────────────────── xlsx ───────────────────────────

  static Iterable<XmlElement> _all(XmlNode n, String local) =>
      n.descendants.whereType<XmlElement>().where((e) => e.name.local == local);

  static String? _attr(XmlElement e, String local) {
    for (final a in e.attributes) {
      if (a.name.local == local) return a.value;
    }
    return null;
  }

  static List<SheetTable> readXlsx(Uint8List bytes) {
    Archive zip;
    try {
      zip = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      throw SheetReadException('تعذّرت قراءة ملف Excel (الملف تالف أو ليس xlsx): $e');
    }
    String? text(String path) {
      final want = path.toLowerCase();
      for (final f in zip.files) {
        if (f.isFile && f.name.toLowerCase() == want) {
          return utf8.decode(f.content as List<int>, allowMalformed: true);
        }
      }
      return null;
    }

    final wb = text('xl/workbook.xml');
    if (wb == null) throw SheetReadException('الملف ليس مصنف Excel (لا يوجد xl/workbook.xml)');
    final rels = text('xl/_rels/workbook.xml.rels');
    final relTarget = <String, String>{};
    if (rels != null) {
      for (final r in _all(XmlDocument.parse(rels), 'Relationship')) {
        final id = _attr(r, 'Id');
        final t = _attr(r, 'Target');
        if (id != null && t != null) relTarget[id] = t;
      }
    }

    // النصوص المشتركة
    final shared = <String>[];
    final ss = text('xl/sharedStrings.xml');
    if (ss != null) {
      for (final si in _all(XmlDocument.parse(ss), 'si')) {
        // نص بسيط <t> أو نص منسَّق <r><t>..</t></r> — تُجمع كل <t> (عدا النطق <rPh>)
        final b = StringBuffer();
        for (final t in _all(si, 't')) {
          if (t.parent is XmlElement && (t.parent as XmlElement).name.local == 'rPh') continue;
          b.write(t.innerText);
        }
        shared.add(b.toString());
      }
    }

    final out = <SheetTable>[];
    var index = 0;
    for (final s in _all(XmlDocument.parse(wb), 'sheet')) {
      index++;
      final name = _attr(s, 'name') ?? 'ورقة $index';
      final rid = _attr(s, 'id'); // r:id
      var target = rid == null ? null : relTarget[rid];
      target ??= 'worksheets/sheet$index.xml';
      final path = target.startsWith('/') ? target.substring(1) : 'xl/$target';
      final xml = text(path);
      if (xml == null) continue;
      out.add(SheetTable(name, _parseSheet(XmlDocument.parse(xml), shared)));
    }
    if (out.isEmpty) throw SheetReadException('لا توجد أوراق مقروءة في الملف');
    return out;
  }

  /// رقم العمود من مرجع الخلية: A1 ← 0، AB12 ← 27.
  static int colIndex(String ref) {
    var n = 0;
    for (final c in ref.toUpperCase().codeUnits) {
      if (c < 65 || c > 90) break;
      n = n * 26 + (c - 64);
    }
    return n - 1;
  }

  static List<List<String>> _parseSheet(XmlDocument doc, List<String> shared) {
    final rows = <List<String>>[];
    var nextRow = 0;
    for (final row in _all(doc, 'row')) {
      final rAttr = int.tryParse(_attr(row, 'r') ?? '');
      final ri = (rAttr != null && rAttr > 0) ? rAttr - 1 : nextRow;
      while (rows.length < ri) {
        rows.add(<String>[]); // صفوف فارغة محذوفة من الملف
      }
      final cells = <String>[];
      var nextCol = 0;
      for (final c in row.childElements.where((e) => e.name.local == 'c')) {
        final ref = _attr(c, 'r');
        final ci = ref == null ? nextCol : colIndex(ref);
        if (ci < 0) continue;
        while (cells.length < ci) {
          cells.add('');
        }
        cells.add(_cellText(c, shared));
        nextCol = ci + 1;
      }
      while (cells.isNotEmpty && cells.last.trim().isEmpty) {
        cells.removeLast();
      }
      if (ri < rows.length) {
        rows[ri] = cells;
      } else {
        rows.add(cells);
      }
      nextRow = ri + 1;
    }
    while (rows.isNotEmpty && rows.last.every((c) => c.trim().isEmpty)) {
      rows.removeLast();
    }
    return rows;
  }

  static String _cellText(XmlElement c, List<String> shared) {
    final t = _attr(c, 't');
    String? v;
    for (final e in c.childElements) {
      if (e.name.local == 'v') v = e.innerText;
    }
    switch (t) {
      case 's':
        final i = int.tryParse(v ?? '');
        return (i != null && i >= 0 && i < shared.length) ? shared[i] : '';
      case 'inlineStr':
        final b = StringBuffer();
        for (final e in _all(c, 't')) {
          b.write(e.innerText);
        }
        return b.toString();
      case 'b':
        return v == '1' ? 'TRUE' : 'FALSE';
      case 'e':
        return ''; // خطأ في صيغة (#DIV/0!...) = لا قيمة
      default:
        return v ?? '';
    }
  }

  // ─────────────────────────── CSV ───────────────────────────

  static SheetTable readCsv(Uint8List bytes, {String name = 'CSV'}) {
    var b = bytes;
    if (b.length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) b = Uint8List.sublistView(b, 3);
    String s;
    try {
      s = utf8.decode(b);
    } on FormatException {
      throw SheetReadException('ملف CSV ليس بترميز UTF-8. احفظه من Excel باسم «CSV UTF-8» أو بصيغة xlsx.');
    }
    final firstLine = s.split('\n').first;
    String delim = ',';
    var best = 0;
    for (final d in const [',', ';', '\t']) {
      final n = d.allMatches(firstLine).length;
      if (n > best) {
        best = n;
        delim = d;
      }
    }
    return SheetTable(name, parseCsv(s, delim));
  }

  /// CSV قياسي: حقول بين علامتي تنصيص، و"" داخلها = علامة تنصيص.
  static List<List<String>> parseCsv(String s, String delim) {
    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < s.length; i++) {
      final ch = s[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < s.length && s[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          field.write(ch);
        }
      } else if (ch == '"') {
        inQuotes = true;
      } else if (ch == delim) {
        row.add(field.toString());
        field.clear();
      } else if (ch == '\n' || ch == '\r') {
        if (ch == '\r' && i + 1 < s.length && s[i + 1] == '\n') i++;
        row.add(field.toString());
        field.clear();
        rows.add(row);
        row = <String>[];
      } else {
        field.write(ch);
      }
    }
    if (field.isNotEmpty || row.isNotEmpty) {
      row.add(field.toString());
      rows.add(row);
    }
    while (rows.isNotEmpty && rows.last.every((c) => c.trim().isEmpty)) {
      rows.removeLast();
    }
    return rows;
  }
}

/// تحويل نص خلية إلى رقم — صارم: ما لا يُفهم بوضوح يُرفض (null) ولا يُخمَّن.
class ImportNumbers {
  ImportNumbers._();

  static const _arabicDigits = '٠١٢٣٤٥٦٧٨٩';
  static const _persianDigits = '۰۱۲۳۴۵۶۷۸۹';

  /// نتيجة التحويل: [ok] = false يعني نصاً غير فارغ لا يُفهم رقماً.
  static ({bool ok, double? value}) parse(String raw) {
    var s = raw.trim();
    if (s.isEmpty || s == '-') return (ok: true, value: null);
    final b = StringBuffer();
    for (final ch in s.split('')) {
      final a = _arabicDigits.indexOf(ch);
      final p = _persianDigits.indexOf(ch);
      if (a >= 0) {
        b.write(a);
      } else if (p >= 0) {
        b.write(p);
      } else if (ch == '٫') {
        b.write('.'); // الفاصلة العشرية العربية
      } else if (ch == '٬' || ch == '،') {
        b.write(','); // فاصل الآلاف العربي
      } else if (ch == '−' || ch == '–') {
        b.write('-');
      } else {
        b.write(ch);
      }
    }
    s = b.toString().trim();
    // (5000) = سالب (أسلوب المحاسبين)
    var negative = false;
    if (s.startsWith('(') && s.endsWith(')')) {
      negative = true;
      s = s.substring(1, s.length - 1).trim();
    }
    // رموز العملة والنصوص المرافقة: د.ع، IQD، $، دينار، دولار
    s = s.replaceAll(RegExp(r'(د\.?\s*ع\.?|دينار|دولار|IQD|USD|\$)', caseSensitive: false), '').trim();
    if (s.endsWith('-')) {
      negative = !negative;
      s = s.substring(0, s.length - 1).trim();
    }
    s = s.replaceAll(' ', '').replaceAll(' ', '');
    // فاصل الآلاف: الفاصلة فقط، وبين مجموعات من 3 أرقام (1,234,567.5)
    if (s.contains(',')) {
      if (!RegExp(r'^[+-]?\d{1,3}(,\d{3})+(\.\d+)?$').hasMatch(s)) return (ok: false, value: null);
      s = s.replaceAll(',', '');
    }
    if (!RegExp(r'^[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?$').hasMatch(s)) return (ok: false, value: null);
    final v = double.tryParse(s);
    if (v == null || v.isNaN || v.isInfinite) return (ok: false, value: null);
    return (ok: true, value: negative ? -v : v);
  }

  /// تقريب المبالغ إلى فلسين (منزلتين).
  static double money(double v) => (v * 100).roundToDouble() / 100;
}
