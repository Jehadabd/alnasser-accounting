// lib/services/import/xls_reader.dart
//
// 📄 قارئ ملف Excel القديم (‎.xls، Excel 97–2003 وما قبله حتى Excel 5/95)
// بلا أي مكتبة خارجية. قراءة فقط.
//
// الملف «مستند مركّب» (OLE2 / Compound File Binary): نظام ملفات صغير بقطاعات
// وجدول FAT، فيه تيار «Workbook» (BIFF8) أو «Book» (BIFF5) هو سجلات Excel:
//   • BOUNDSHEET: أسماء الأوراق وموضع كل ورقة في التيار.
//   • SST (+ CONTINUE): جدول النصوص المشتركة (BIFF8).
//   • في كل ورقة: LABELSST/LABEL/RSTRING (نص)، NUMBER/RK/MULRK (رقم)،
//     FORMULA (+ STRING) (ناتج المعادلة)، BOOLERR.
//   • CODEPAGE: ترميز النصوص ذات البايت الواحد في BIFF5 (1256 = عربي).
//
// الرقم يُكتب نصاً كما هو (بلا فواصل ولا تقريب)، والتحويل الصارم في ImportNumbers.
// ملف محمي بكلمة سر (FILEPASS) يُرفض برسالة واضحة.

import 'dart:convert';
import 'dart:typed_data';

class XlsSheet {
  XlsSheet(this.name, this.rows);
  final String name;
  final List<List<String>> rows;
}

class XlsFormatException implements Exception {
  XlsFormatException(this.message);
  final String message;
  @override
  String toString() => message;
}

class XlsReader {
  XlsReader._();

  static bool isOle(Uint8List b) =>
      b.length >= 512 &&
      b[0] == 0xD0 &&
      b[1] == 0xCF &&
      b[2] == 0x11 &&
      b[3] == 0xE0 &&
      b[4] == 0xA1 &&
      b[5] == 0xB1 &&
      b[6] == 0x1A &&
      b[7] == 0xE1;

  /// نص بترميز ويندوز العربي (1256) — لتصديرات HTML القديمة.
  static String decodeCp1256(Uint8List bytes) {
    final sb = StringBuffer();
    for (final c in bytes) {
      sb.writeCharCode(c < 0x80 ? c : _Biff._cp1256.codeUnitAt(c - 0x80));
    }
    return sb.toString();
  }

  /// يقرأ كل أوراق العمل (يتجاهل أوراق الرسوم والماكرو).
  static List<XlsSheet> read(Uint8List bytes) {
    if (!isOle(bytes)) throw XlsFormatException('ليس ملف Excel ‏(‎.xls) صالحاً');
    final cfb = _Cfb(bytes);
    final wb = cfb.stream('Workbook') ?? cfb.stream('Book');
    if (wb == null) {
      throw XlsFormatException('الملف مستند Office لكنه ليس جدول Excel (لا يوجد فيه مصنف)');
    }
    return _Biff(wb).sheets();
  }
}

// ═══════════════════════════ المستند المركّب (OLE2) ═══════════════════════════

class _Cfb {
  _Cfb(this.b) {
    final bd = ByteData.sublistView(b);
    final sectorShift = bd.getUint16(0x1E, Endian.little);
    final miniShift = bd.getUint16(0x20, Endian.little);
    if (sectorShift != 9 && sectorShift != 12) throw XlsFormatException('ملف .xls تالف (حجم قطاع غير معروف)');
    _sector = 1 << sectorShift;
    _mini = 1 << miniShift;
    final numFat = bd.getUint32(0x2C, Endian.little);
    final firstDir = bd.getUint32(0x30, Endian.little);
    _cutoff = bd.getUint32(0x38, Endian.little);
    final firstMiniFat = bd.getUint32(0x3C, Endian.little);
    var difatNext = bd.getUint32(0x44, Endian.little);
    final numDifat = bd.getUint32(0x48, Endian.little);

    // DIFAT: أول 109 في الرأس، والباقي في سلسلة قطاعات DIFAT
    final fatSectors = <int>[];
    for (var i = 0; i < 109 && fatSectors.length < numFat; i++) {
      final s = bd.getUint32(0x4C + i * 4, Endian.little);
      if (s < _maxReg) fatSectors.add(s);
    }
    final per = _sector ~/ 4 - 1;
    var guard = 0;
    while (difatNext < _maxReg && fatSectors.length < numFat && guard++ <= numDifat + 1) {
      final off = _off(difatNext);
      for (var i = 0; i < per && fatSectors.length < numFat; i++) {
        final s = bd.getUint32(off + i * 4, Endian.little);
        if (s < _maxReg) fatSectors.add(s);
      }
      difatNext = bd.getUint32(off + per * 4, Endian.little);
    }
    final fat = <int>[];
    for (final s in fatSectors) {
      final off = _off(s);
      for (var i = 0; i < _sector ~/ 4; i++) {
        fat.add(bd.getUint32(off + i * 4, Endian.little));
      }
    }
    _fat = fat;

    final dir = _chain(firstDir, _fat, _sector, _readSector);
    _dir = dir;
    // القطاعات الصغيرة: جدولها، وتيارها (يبدأ من المدخل الجذر)
    final rootStart = _u32(dir, 0x74);
    _miniStream = _chain(rootStart, _fat, _sector, _readSector);
    _miniFat = <int>[];
    if (firstMiniFat < _maxReg) {
      final mf = _chain(firstMiniFat, _fat, _sector, _readSector);
      final mbd = ByteData.sublistView(mf);
      for (var i = 0; i + 4 <= mf.length; i += 4) {
        _miniFat.add(mbd.getUint32(i, Endian.little));
      }
    }
  }

  static const _maxReg = 0xFFFFFFFA; // أكبر من هذا = نهاية سلسلة / قطاع خاص

  final Uint8List b;
  late final int _sector;
  late final int _mini;
  late final int _cutoff;
  late final List<int> _fat;
  late final Uint8List _dir;
  late final Uint8List _miniStream;
  late final List<int> _miniFat;

  int _off(int sector) {
    final o = (sector + 1) * _sector;
    // صارم: قطاع ناقص يعني ملفاً مقطوعاً — لا نكمله بأصفار فتُقرأ بيانات ناقصة بصمت
    if (o < 0 || o + _sector > b.length) {
      throw XlsFormatException('ملف .xls تالف أو ناقص (قطاع خارج الملف). افتحه في Excel واحفظه بصيغة xlsx.');
    }
    return o;
  }

  Uint8List _readSector(int s) {
    final o = _off(s);
    return Uint8List.sublistView(b, o, o + _sector);
  }

  Uint8List _readMini(int s) {
    final o = s * _mini;
    final out = Uint8List(_mini);
    if (o >= _miniStream.length) throw XlsFormatException('ملف .xls تالف (قطاع صغير خارج التيار)');
    final end = o + _mini > _miniStream.length ? _miniStream.length : o + _mini;
    out.setRange(0, end - o, _miniStream, o);
    return out;
  }

  /// يتبع سلسلة القطاعات (مع حماية من الحلقات).
  static Uint8List _chain(int start, List<int> fat, int size, Uint8List Function(int) read) {
    final out = BytesBuilder(copy: false);
    var s = start;
    final seen = <int>{};
    while (s < _maxReg) {
      if (s >= fat.length) throw XlsFormatException('ملف .xls تالف (سلسلة قطاعات مكسورة)');
      if (!seen.add(s)) throw XlsFormatException('ملف .xls تالف (سلسلة قطاعات دائرية)');
      out.add(read(s));
      s = fat[s];
    }
    return out.takeBytes();
  }

  static int _u32(Uint8List d, int o) => ByteData.sublistView(d).getUint32(o, Endian.little);

  /// تيار بالاسم (بلا اعتبار لحالة الحروف) — null إن لم يوجد.
  Uint8List? stream(String name) {
    final bd = ByteData.sublistView(_dir);
    for (var e = 0; e + 128 <= _dir.length; e += 128) {
      final type = _dir[e + 0x42];
      if (type != 2) continue; // تيار
      final nameLen = bd.getUint16(e + 0x40, Endian.little);
      if (nameLen < 2 || nameLen > 64) continue;
      final chars = <int>[];
      for (var i = 0; i < nameLen - 2; i += 2) {
        chars.add(bd.getUint16(e + i, Endian.little));
      }
      if (String.fromCharCodes(chars).toLowerCase() != name.toLowerCase()) continue;
      final start = bd.getUint32(e + 0x74, Endian.little);
      final size = bd.getUint32(e + 0x78, Endian.little);
      final data = size < _cutoff
          ? _chain(start, _miniFat, _mini, _readMini)
          : _chain(start, _fat, _sector, _readSector);
      if (data.length < size) throw XlsFormatException('ملف .xls ناقص (التيار أقصر من حجمه)');
      return Uint8List.sublistView(data, 0, size);
    }
    return null;
  }
}

// ═══════════════════════════ سجلات BIFF ═══════════════════════════

class _Rec {
  _Rec(this.type, this.offset, this.data);
  final int type;
  final int offset; // موضع رأس السجل في التيار
  final Uint8List data;
}

class _Biff {
  _Biff(this.s) : bd = ByteData.sublistView(s);
  final Uint8List s;
  final ByteData bd;

  bool _biff8 = true;
  int _codepage = 1252;
  final List<String> _sst = [];

  static const _bof = 0x0809, _eof = 0x000A, _continue = 0x003C;

  _Rec? _recAt(int pos) {
    if (pos + 4 > s.length) return null;
    final type = bd.getUint16(pos, Endian.little);
    final len = bd.getUint16(pos + 2, Endian.little);
    final end = pos + 4 + len;
    if (end > s.length) return null;
    return _Rec(type, pos, Uint8List.sublistView(s, pos + 4, end));
  }

  List<XlsSheet> sheets() {
    final first = _recAt(0);
    if (first == null || first.type != _bof || first.data.length < 4) {
      // BOF قديم (BIFF2–4: 0x0009/0x0209/0x0409)
      throw XlsFormatException('صيغة Excel قديمة جداً (قبل Excel 5) غير مدعومة. احفظ الملف بصيغة xlsx.');
    }
    final ver = ByteData.sublistView(first.data).getUint16(0, Endian.little);
    if (ver == 0x0600) {
      _biff8 = true;
    } else if (ver == 0x0500) {
      _biff8 = false;
    } else {
      throw XlsFormatException('إصدار ملف Excel غير معروف (0x${ver.toRadixString(16)}). احفظه بصيغة xlsx.');
    }

    // ── الأوراق والنصوص المشتركة من قسم المصنف ──
    final sheets = <(String, int)>[];
    var pos = 0;
    _Rec? sstRec;
    final sstConts = <Uint8List>[];
    var inSst = false;
    while (true) {
      final r = _recAt(pos);
      if (r == null) break;
      pos += 4 + r.data.length;
      if (r.type == _eof) break;
      if (inSst && r.type == _continue) {
        sstConts.add(r.data);
        continue;
      }
      inSst = false;
      switch (r.type) {
        case 0x002F: // FILEPASS
          throw XlsFormatException('الملف محمي بكلمة سر. افتحه في Excel وأزل كلمة السر ثم احفظه وأعد المحاولة.');
        case 0x0042: // CODEPAGE
          if (r.data.length >= 2) _codepage = ByteData.sublistView(r.data).getUint16(0, Endian.little);
        case 0x0085: // BOUNDSHEET
          {
            if (r.data.length < 8) break;
            final at = ByteData.sublistView(r.data).getUint32(0, Endian.little);
            final kind = r.data[5]; // 0 = ورقة عمل
            if (kind != 0) break;
            String name;
            if (_biff8) {
              name = _readChars(r.data, 8, r.data[6], (r.data[7] & 1) != 0).$1;
            } else {
              final len = r.data[6];
              name = _decode8(Uint8List.sublistView(r.data, 7, (7 + len).clamp(7, r.data.length)));
            }
            sheets.add((name, at));
          }
        case 0x00FC: // SST
          sstRec = r;
          inSst = true;
      }
    }
    if (sstRec != null) _readSst(sstRec.data, sstConts);

    final out = <XlsSheet>[];
    for (final (name, at) in sheets) {
      out.add(XlsSheet(name, _readSheet(at)));
    }
    if (out.isEmpty) throw XlsFormatException('لا توجد أوراق عمل في الملف');
    return out;
  }

  // ─── النصوص ───

  /// يقرأ [cch] حرفاً من [d] بدءاً من [o]: عريضة (UTF-16) أو مضغوطة (بايت واحد = Latin-1).
  (String, int) _readChars(Uint8List d, int o, int cch, bool wide) {
    if (wide) {
      final n = (o + cch * 2 > d.length) ? (d.length - o) ~/ 2 : cch;
      final codes = List<int>.generate(n, (i) => d[o + i * 2] | (d[o + i * 2 + 1] << 8));
      return (String.fromCharCodes(codes), o + n * 2);
    }
    final n = (o + cch > d.length) ? d.length - o : cch;
    return (String.fromCharCodes(Uint8List.sublistView(d, o, o + n)), o + n);
  }

  /// نص بايت واحد في BIFF5 حسب CODEPAGE.
  String _decode8(Uint8List bytes) {
    if (_codepage == 1200) return String.fromCharCodes(bytes);
    if (_codepage == 65001) return utf8.decode(bytes, allowMalformed: true);
    final table = _codepage == 1256 ? _cp1256 : (_codepage == 1252 || _codepage == 32769 ? _cp1252 : null);
    if (table == null) return latin1.decode(bytes);
    final sb = StringBuffer();
    for (final c in bytes) {
      sb.writeCharCode(c < 0x80 ? c : table.codeUnitAt(c - 0x80));
    }
    return sb.toString();
  }

  /// XLUnicodeString (BIFF8: طول 16 بت + خيارات) أو نص BIFF5 (طول 16 بت + بايتات).
  String _labelString(Uint8List d, int o) {
    if (o + 2 > d.length) return '';
    final cch = d[o] | (d[o + 1] << 8);
    if (!_biff8) return _decode8(Uint8List.sublistView(d, o + 2, (o + 2 + cch).clamp(o + 2, d.length)));
    if (o + 3 > d.length) return '';
    final flags = d[o + 2];
    var p = o + 3;
    if ((flags & 0x08) != 0) p += 2; // عدد مقاطع التنسيق
    if ((flags & 0x04) != 0) p += 4; // حجم البيانات الشرقية
    return _readChars(d, p, cch, (flags & 1) != 0).$1;
  }

  /// جدول النصوص المشتركة: السجل وما يتبعه من CONTINUE. النص قد ينقسم بين
  /// سجلين، وعندها يبدأ السجل التالي ببايت خيارات جديد (مضغوط/عريض).
  void _readSst(Uint8List first, List<Uint8List> conts) {
    final segs = <Uint8List>[first, ...conts];
    var si = 0, p = 8; // بعد الإجمالي والعدد الفريد
    final unique = first.length >= 8 ? ByteData.sublistView(first).getUint32(4, Endian.little) : 0;

    bool ensure() {
      while (si < segs.length && p >= segs[si].length) {
        si++;
        p = 0;
      }
      return si < segs.length;
    }

    int u8() {
      if (!ensure()) throw RangeError('sst');
      return segs[si][p++];
    }

    int u16() => u8() | (u8() << 8);
    int u32() => u16() | (u16() << 16);
    void skip(int n) {
      while (n > 0) {
        if (!ensure()) throw RangeError('sst');
        final take = (segs[si].length - p) < n ? segs[si].length - p : n;
        p += take;
        n -= take;
      }
    }

    try {
      for (var k = 0; k < unique; k++) {
        final cch = u16();
        final flags = u8();
        var wide = (flags & 1) != 0;
        final runs = (flags & 0x08) != 0 ? u16() : 0;
        final ext = (flags & 0x04) != 0 ? u32() : 0;
        final sb = StringBuffer();
        var left = cch;
        while (left > 0) {
          if (si < segs.length && p >= segs[si].length) {
            // انقسام النص: السجل التالي يبدأ ببايت خيارات الجزء الباقي
            si++;
            p = 0;
            if (si >= segs.length) throw RangeError('sst');
            wide = (segs[si][p++] & 1) != 0;
            continue;
          }
          if (si >= segs.length) throw RangeError('sst');
          final seg = segs[si];
          final avail = seg.length - p;
          if (wide) {
            final n = (avail ~/ 2) < left ? avail ~/ 2 : left;
            if (n == 0) {
              // بايت يتيم في آخر السجل (ملف غير قياسي) — يُتجاوز
              p = seg.length;
              continue;
            }
            for (var i = 0; i < n; i++) {
              sb.writeCharCode(seg[p] | (seg[p + 1] << 8));
              p += 2;
            }
            left -= n;
          } else {
            final n = avail < left ? avail : left;
            for (var i = 0; i < n; i++) {
              sb.writeCharCode(seg[p++]);
            }
            left -= n;
          }
        }
        skip(runs * 4 + ext);
        _sst.add(sb.toString());
      }
    } on RangeError {
      // جدول أقصر من المعلن: نكتفي بما قُرئ؛ الخلايا التي تشير لما بعده تبقى فارغة
    }
  }

  // ─── الأرقام ───

  static String _num(double v) {
    if (v.isNaN || v.isInfinite) return '';
    if (v == v.truncateToDouble() && v.abs() < 1e15) return v.toInt().toString();
    return v.toString();
  }

  static double _rk(int rk) {
    double v;
    if ((rk & 0x02) != 0) {
      v = (rk.toSigned(32) >> 2).toDouble();
    } else {
      final b = ByteData(8)..setUint32(4, rk & 0xFFFFFFFC, Endian.little);
      v = b.getFloat64(0, Endian.little);
    }
    if ((rk & 0x01) != 0) v /= 100;
    return v;
  }

  // ─── ورقة ───

  List<List<String>> _readSheet(int at) {
    final cells = <int, Map<int, String>>{};
    void put(int row, int col, String v) {
      if (v.isEmpty) return;
      (cells[row] ??= <int, String>{})[col] = v;
    }

    var pos = at;
    var depth = 0;
    var pendingFormula = (-1, -1); // صف وعمود معادلة نصية تنتظر سجل STRING
    var guard = 0;
    while (guard++ < 5000000) {
      final r = _recAt(pos);
      if (r == null) break;
      pos += 4 + r.data.length;
      final d = r.data;
      final bdd = ByteData.sublistView(d);
      if (r.type == _bof) {
        depth++;
        continue;
      }
      if (r.type == _eof) {
        depth--;
        if (depth <= 0) break;
        continue;
      }
      if (depth != 1) continue; // رسم مضمّن داخل الورقة
      if (d.length < 6 && r.type != 0x0207) continue;
      switch (r.type) {
        case 0x00FD: // LABELSST
          if (d.length >= 10) {
            final i = bdd.getUint32(6, Endian.little);
            if (i < _sst.length) put(bdd.getUint16(0, Endian.little), bdd.getUint16(2, Endian.little), _sst[i]);
          }
        case 0x0204: // LABEL
        case 0x00D6: // RSTRING
          put(bdd.getUint16(0, Endian.little), bdd.getUint16(2, Endian.little), _labelString(d, 6));
        case 0x0203: // NUMBER
          if (d.length >= 14) {
            put(bdd.getUint16(0, Endian.little), bdd.getUint16(2, Endian.little),
                _num(bdd.getFloat64(6, Endian.little)));
          }
        case 0x027E: // RK
          if (d.length >= 10) {
            put(bdd.getUint16(0, Endian.little), bdd.getUint16(2, Endian.little),
                _num(_rk(bdd.getUint32(6, Endian.little))));
          }
        case 0x00BD: // MULRK
          {
            final row = bdd.getUint16(0, Endian.little);
            final c0 = bdd.getUint16(2, Endian.little);
            final n = (d.length - 6) ~/ 6;
            for (var i = 0; i < n; i++) {
              put(row, c0 + i, _num(_rk(bdd.getUint32(4 + i * 6 + 2, Endian.little))));
            }
          }
        case 0x0205: // BOOLERR
          if (d.length >= 8 && d[7] == 0) {
            put(bdd.getUint16(0, Endian.little), bdd.getUint16(2, Endian.little), d[6] != 0 ? 'TRUE' : 'FALSE');
          }
        case 0x0006: // FORMULA: الناتج المحفوظ
          {
            if (d.length < 14) break;
            final row = bdd.getUint16(0, Endian.little);
            final col = bdd.getUint16(2, Endian.little);
            if (d[12] == 0xFF && d[13] == 0xFF) {
              if (d[6] == 0) {
                pendingFormula = (row, col); // النص في سجل STRING التالي
              } else if (d[6] == 1) {
                put(row, col, d[8] != 0 ? 'TRUE' : 'FALSE');
              } // 2 = خطأ، 3 = نص فارغ
            } else {
              put(row, col, _num(bdd.getFloat64(6, Endian.little)));
            }
          }
        case 0x0207: // STRING (ناتج المعادلة النصية)
          if (pendingFormula.$1 >= 0) {
            put(pendingFormula.$1, pendingFormula.$2, _labelString(d, 0));
            pendingFormula = (-1, -1);
          }
      }
    }

    if (cells.isEmpty) return const [];
    final maxRow = cells.keys.reduce((a, b) => a > b ? a : b);
    return [
      for (var r = 0; r <= maxRow; r++)
        () {
          final m = cells[r];
          if (m == null) return <String>[];
          final maxCol = m.keys.reduce((a, b) => a > b ? a : b);
          return [for (var c = 0; c <= maxCol; c++) m[c] ?? ''];
        }(),
    ];
  }

  // ─── جداول الترميز (0x80–0xFF) ───

  static const _cp1256 =
      '€پ‚ƒ„…†‡ˆ‰ٹ‹Œچژڈ'
      'گ‘’“”•–—ک™ڑ›œ‌‍ں'
      ' ،¢£¤¥¦§¨©ھ«¬­®¯'
      '°±²³´µ¶·¸¹؛»¼½¾؟'
      'ہءآأؤإئابةتثجحخد'
      'ذرزسشصض×طظعغـفقك'
      'àلâمنهوçèéêëىيîï'
      'ًٌٍَôُِ÷ّùْûü‎‏ے';

  static const _cp1252 =
      '€\u0081‚ƒ„…†‡ˆ‰Š‹Œ\u008DŽ\u008F'
      '\u0090‘’“”•–—˜™š›œ\u009DžŸ'
      ' ¡¢£¤¥¦§¨©ª«¬­®¯'
      '°±²³´µ¶·¸¹º»¼½¾¿'
      'ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏ'
      'ÐÑÒÓÔÕÖ×ØÙÚÛÜÝÞß'
      'àáâãäåæçèéêëìíîï'
      'ðñòóôõö÷øùúûüýþÿ';
}
