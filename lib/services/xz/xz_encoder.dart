// lib/services/xz/xz_encoder.dart
//
// 🗜️ ضاغط XZ حقيقي بلغة Dart خالصة (لا مكتبات أصلية).
//
// لماذا: مكتبة archive (حتى 4.6) لا تملك ضاغط XZ — XZEncoder فيها «يخزّن» البيانات
// بلا ضغط، فكانت نسخة تيليجرام «XZ Ultra» بحجم القاعدة نفسه.
//
// ما هو: خوارزمية LZMA من حزمة 7-Zip (LZMA SDK، ملكية عامة) — باحث تطابقات BT4
// وتحليل أمثل (optimal parsing) — مترجمة سطراً بسطر عن نسخة Java مرجعية تحققنا منها:
//   • مخرجات LZMA مطابقة بايتاً ببايت لمخرجات LZMA SDK الأصلي (70 حالة).
//   • ملفات .xz الناتجة يفكّها xz-utils / liblzma بلا خطأ (16 حالة: فارغ، عشوائي،
//     حدود الأجزاء 64KB و2MB، أصفار، نص، وقاعدة بيانات 54MB).
//   • اختبار test/maintenance/xz_encoder_test.dart يتحقق أن هذه النسخة تعطي
//     البصمة نفسها (sha256) التي أعطتها النسخة المرجعية، وأن XZDecoder يعيد الأصل.
//
// الحاوية: XZ قياسي — تدفق واحد، كتلة واحدة، مرشح LZMA2، فحص CRC32.
// أجزاء LZMA2: الأول يعيد ضبط القاموس (0xE0)، والبقية تكمل بلا إعادة ضبط (0x80)،
// الجزء ≤ 64KB مضغوطاً و ≤ 2MB أصلاً.
//
// لا يُستدعى مباشرة من الواجهة: استعمل XzBackup (يشغّله في Isolate ويتحقق بفكّه).

import 'dart:typed_data';

/// ضغط [data] إلى ملف .xz كامل.
/// [dictSizeMax]: أقصى قاموس (8MB افتراضياً = xz -6). [fastBytes]: 5..273 (أكبر = أصغر وأبطأ).
/// [onProgress]: (المعالج، الكلي) — يُستدعى كل ~1MB تقريباً.
Uint8List xzCompress(
  Uint8List data, {
  int dictSizeMax = 1 << 23,
  int fastBytes = 64,
  void Function(int done, int total)? onProgress,
}) {
  if (fastBytes < 5 || fastBytes > _kMatchMaxLen) {
    throw ArgumentError('fastBytes يجب أن يكون بين 5 و $_kMatchMaxLen');
  }
  // مواقع باحث التطابقات تبدأ من 1 ولا تُطبَّع: حد آمن أقل من 2^30
  if (data.length > (1 << 30) - (1 << 20)) {
    throw ArgumentError('البيانات أكبر من الحد المدعوم (1GB)');
  }
  // القاموس لا يلزم أن يتجاوز البيانات: جداول أصغر والصيغة نفسها
  var dictSize = 1 << 16;
  while (dictSize < data.length && dictSize < dictSizeMax) {
    dictSize <<= 1;
  }
  final prop = _dictProp(dictSize);
  final o = _Out(data.length ~/ 6 + 1024);

  // ترويسة التدفق: التوقيع، الأعلام (الفحص = CRC32)، CRC32 للأعلام
  for (final m in const [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00]) {
    o.put(m);
  }
  o.put(0x00);
  o.put(0x01);
  _putLE32(o, _crc32(Uint8List.fromList(const [0x00, 0x01]), 0, 2));

  var unpadded = 0;
  if (data.isNotEmpty) {
    // ترويسة الكتلة: الحجم، الأعلام (مرشح واحد بلا أحجام)، LZMA2 (0x21) بخاصية واحدة، حشو، CRC32
    final hStart = o.n;
    o.put(0x02);
    o.put(0x00);
    o.put(0x21);
    o.put(0x01);
    o.put(prop);
    o.put(0);
    o.put(0);
    o.put(0);
    _putLE32(o, _crc32(o.b, hStart, 8));
    final enc = _LzmaEncoder(data, _dictFromProp(prop), fastBytes, true, onProgress);
    final lz = enc.run();
    o.putAll(lz, 0, lz.length);
    while (((o.n - hStart) & 3) != 0) {
      o.put(0);
    }
    _putLE32(o, _crc32(data, 0, data.length));
    unpadded = 12 + lz.length + 4;
  }

  // الفهرس
  final iStart = o.n;
  o.put(0x00);
  if (data.isNotEmpty) {
    _putVarint(o, 1);
    _putVarint(o, unpadded);
    _putVarint(o, data.length);
  } else {
    _putVarint(o, 0);
  }
  while (((o.n - iStart) & 3) != 0) {
    o.put(0);
  }
  _putLE32(o, _crc32(o.b, iStart, o.n - iStart));
  final indexSize = o.n - iStart;

  // التذييل: CRC32(حجم الفهرس + الأعلام)، حجم الفهرس، الأعلام، التوقيع
  final fStart = o.n;
  _putLE32(o, 0);
  _putLE32(o, indexSize ~/ 4 - 1);
  o.put(0x00);
  o.put(0x01);
  final fc = _crc32(o.b, fStart + 4, 6);
  o.b[fStart] = fc & 0xFF;
  o.b[fStart + 1] = (fc >> 8) & 0xFF;
  o.b[fStart + 2] = (fc >> 16) & 0xFF;
  o.b[fStart + 3] = (fc >> 24) & 0xFF;
  o.put(0x59); // Y
  o.put(0x5A); // Z
  return o.bytes();
}

/// مخرجات LZMA الخام (بلا ترويسة) — للاختبار مقابل LZMA SDK فقط.
Uint8List lzma1RawForTest(Uint8List data, int dictSize, int fastBytes) =>
    _LzmaEncoder(data, dictSize, fastBytes, false, null).run();

// ───────────────────────── أدوات الحاوية ─────────────────────────

final Uint32List _crc32Table = () {
  final t = Uint32List(256);
  for (var i = 0; i < 256; i++) {
    var c = i;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
    }
    t[i] = c;
  }
  return t;
}();

int _crc32(Uint8List b, int off, int len) {
  var c = 0xFFFFFFFF;
  final end = off + len;
  for (var i = off; i < end; i++) {
    c = _crc32Table[(c ^ b[i]) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

void _putLE32(_Out o, int v) {
  o.put(v & 0xFF);
  o.put((v >> 8) & 0xFF);
  o.put((v >> 16) & 0xFF);
  o.put((v >> 24) & 0xFF);
}

void _putVarint(_Out o, int v) {
  while (v >= 0x80) {
    o.put((v & 0x7F) | 0x80);
    v >>= 7;
  }
  o.put(v);
}

int _dictProp(int dictSize) {
  for (var b = 0; b < 40; b++) {
    final s = (2 | (b & 1)) << (b ~/ 2 + 11);
    if (s >= dictSize) return b;
  }
  return 40;
}

int _dictFromProp(int b) => (2 | (b & 1)) << (b ~/ 2 + 11);

class _Out {
  Uint8List b;
  int n = 0;
  _Out([int capacity = 1 << 16]) : b = Uint8List(capacity < 64 ? 64 : capacity);

  void _grow(int need) {
    var cap = b.length * 2;
    while (cap < need) {
      cap *= 2;
    }
    final nb = Uint8List(cap);
    nb.setRange(0, n, b);
    b = nb;
  }

  void put(int v) {
    if (n == b.length) _grow(n + 1);
    b[n++] = v;
  }

  void putAll(Uint8List s, int off, int len) {
    if (n + len > b.length) _grow(n + len);
    b.setRange(n, n + len, s, off);
    n += len;
  }

  Uint8List bytes() => Uint8List.sublistView(b, 0, n);
}

// ───────────────────────── مرمّز المدى ─────────────────────────

const int _kNumBitModelTotalBits = 11;
const int _kBitModelTotal = 1 << _kNumBitModelTotalBits;
const int _kNumMoveBits = 5;
const int _kNumMoveReducingBits = 2;
const int _kNumBitPriceShiftBits = 6;

final Int32List _probPrices = () {
  final p = Int32List(_kBitModelTotal >> _kNumMoveReducingBits);
  const kNumBits = _kNumBitModelTotalBits - _kNumMoveReducingBits;
  for (var i = kNumBits - 1; i >= 0; i--) {
    final start = 1 << (kNumBits - i - 1);
    final end = 1 << (kNumBits - i);
    for (var j = start; j < end; j++) {
      p[j] = (i << _kNumBitPriceShiftBits) + (((end - j) << _kNumBitPriceShiftBits) >> (kNumBits - i - 1));
    }
  }
  return p;
}();

int _price(int prob, int symbol) =>
    _probPrices[(((prob - symbol) ^ (-symbol)) & (_kBitModelTotal - 1)) >> _kNumMoveReducingBits];
int _price0(int prob) => _probPrices[prob >> _kNumMoveReducingBits];
int _price1(int prob) => _probPrices[(_kBitModelTotal - prob) >> _kNumMoveReducingBits];
void _initProbs(Uint16List p) => p.fillRange(0, p.length, _kBitModelTotal >> 1);

class _RangeEncoder {
  late _Out out;
  int low = 0; // حتى 33 بتاً
  int range = 0xFFFFFFFF; // 32 بتاً بلا إشارة
  int cacheSize = 1;
  int cache = 0;
  int position = 0;

  void init(_Out o) {
    out = o;
    position = 0;
    low = 0;
    range = 0xFFFFFFFF;
    cacheSize = 1;
    cache = 0;
  }

  void shiftLow() {
    final lowHi = low >> 32;
    if (lowHi != 0 || low < 0xFF000000) {
      position += cacheSize;
      var temp = cache;
      do {
        out.put((temp + lowHi) & 0xFF);
        temp = 0xFF;
      } while (--cacheSize != 0);
      cache = (low >> 24) & 0xFF;
    }
    cacheSize++;
    low = (low & 0xFFFFFF) << 8;
  }

  void flush() {
    for (var i = 0; i < 5; i++) {
      shiftLow();
    }
  }

  /// حجم الجزء لو أُغلق الآن.
  int pending() => cacheSize + position + 4;

  void encode(Uint16List probs, int index, int symbol) {
    final prob = probs[index];
    final newBound = (range >> _kNumBitModelTotalBits) * prob;
    if (symbol == 0) {
      range = newBound;
      probs[index] = prob + ((_kBitModelTotal - prob) >> _kNumMoveBits);
    } else {
      low += newBound;
      range -= newBound;
      probs[index] = prob - (prob >> _kNumMoveBits);
    }
    if ((range & 0xFF000000) == 0) {
      range = (range << 8) & 0xFFFFFFFF;
      shiftLow();
    }
  }

  void encodeDirectBits(int v, int numTotalBits) {
    for (var i = numTotalBits - 1; i >= 0; i--) {
      range >>= 1;
      if (((v >> i) & 1) == 1) low += range;
      if ((range & 0xFF000000) == 0) {
        range = (range << 8) & 0xFFFFFFFF;
        shiftLow();
      }
    }
  }
}

class _BitTree {
  final Uint16List m;
  final int bits;
  _BitTree(this.bits) : m = Uint16List(1 << bits);

  void init() => _initProbs(m);

  void encode(_RangeEncoder rc, int symbol) {
    var x = 1;
    for (var b = bits; b != 0;) {
      b--;
      final bit = (symbol >> b) & 1;
      rc.encode(m, x, bit);
      x = (x << 1) | bit;
    }
  }

  void reverseEncode(_RangeEncoder rc, int symbol) {
    var x = 1;
    for (var i = 0; i < bits; i++) {
      final bit = symbol & 1;
      rc.encode(m, x, bit);
      x = (x << 1) | bit;
      symbol >>= 1;
    }
  }

  int getPrice(int symbol) {
    var p = 0;
    var x = 1;
    for (var b = bits; b != 0;) {
      b--;
      final bit = (symbol >> b) & 1;
      p += _price(m[x], bit);
      x = (x << 1) + bit;
    }
    return p;
  }

  int reverseGetPrice(int symbol) {
    var p = 0;
    var x = 1;
    for (var i = bits; i != 0; i--) {
      final bit = symbol & 1;
      symbol >>= 1;
      p += _price(m[x], bit);
      x = (x << 1) | bit;
    }
    return p;
  }
}

int _reverseGetPrice(Uint16List m, int start, int bits, int symbol) {
  var p = 0;
  var x = 1;
  for (var i = bits; i != 0; i--) {
    final bit = symbol & 1;
    symbol >>= 1;
    p += _price(m[start + x], bit);
    x = (x << 1) | bit;
  }
  return p;
}

void _reverseEncode(Uint16List m, int start, _RangeEncoder rc, int bits, int symbol) {
  var x = 1;
  for (var i = 0; i < bits; i++) {
    final bit = symbol & 1;
    rc.encode(m, start + x, bit);
    x = (x << 1) | bit;
    symbol >>= 1;
  }
}

// ───────────────────────── ثوابت LZMA ─────────────────────────

const int _kNumStates = 12;
const int _kNumPosSlotBits = 6;
const int _kNumLenToPosStatesBits = 2;
const int _kNumLenToPosStates = 4;
const int _kMatchMinLen = 2;
const int _kNumAlignBits = 4;
const int _kAlignTableSize = 16;
const int _kAlignMask = 15;
const int _kStartPosModelIndex = 4;
const int _kEndPosModelIndex = 14;
const int _kNumFullDistances = 128;
const int _kNumPosStatesBitsMax = 4;
const int _kNumPosStatesEncodingMax = 16;
const int _kNumLowLenBits = 3;
const int _kNumMidLenBits = 3;
const int _kNumHighLenBits = 8;
const int _kNumLowLenSymbols = 8;
const int _kNumMidLenSymbols = 8;
const int _kNumLenSymbols = 8 + 8 + 256;
const int _kMatchMaxLen = _kMatchMinLen + _kNumLenSymbols - 1; // 273

int _stateUpdateChar(int i) => i < 4 ? 0 : (i < 10 ? i - 3 : i - 6);
int _stateUpdateMatch(int i) => i < 7 ? 7 : 10;
int _stateUpdateRep(int i) => i < 7 ? 8 : 11;
int _stateUpdateShortRep(int i) => i < 7 ? 9 : 11;
bool _stateIsChar(int i) => i < 7;
int _lenToPosState(int len) {
  len -= _kMatchMinLen;
  return len < _kNumLenToPosStates ? len : _kNumLenToPosStates - 1;
}

final Uint8List _fastPos = () {
  final f = Uint8List(1 << 11);
  var c = 2;
  f[0] = 0;
  f[1] = 1;
  for (var slot = 2; slot < 22; slot++) {
    final k = 1 << ((slot >> 1) - 1);
    for (var j = 0; j < k; j++, c++) {
      f[c] = slot;
    }
  }
  return f;
}();

int _posSlot(int pos) {
  if (pos < (1 << 11)) return _fastPos[pos];
  if (pos < (1 << 21)) return _fastPos[pos >> 10] + 20;
  return _fastPos[pos >> 20] + 40;
}

int _posSlot2(int pos) {
  if (pos < (1 << 17)) return _fastPos[pos >> 6] + 12;
  if (pos < (1 << 27)) return _fastPos[pos >> 16] + 32;
  return _fastPos[pos >> 26] + 52;
}

// ───────────────────────── باحث التطابقات BT4 ─────────────────────────

final Uint32List _hashCrc = () {
  final t = Uint32List(256);
  for (var i = 0; i < 256; i++) {
    var r = i;
    for (var j = 0; j < 8; j++) {
      r = (r & 1) != 0 ? ((r >> 1) ^ 0xEDB88320) : (r >> 1);
    }
    t[i] = r;
  }
  return t;
}();

const int _kHash2Size = 1 << 10;
const int _kHash3Size = 1 << 16;
const int _kHash3Offset = _kHash2Size;
const int _kFixHashSize = _kHash2Size + _kHash3Size;

class _MatchFinder {
  final Uint8List buf; // البايت عند الموقع p هو buf[p - 1]
  int pos = 1;
  final int streamPos;
  int cyclicPos = 0;
  final int cyclicSize;
  final int matchMaxLen;
  final int cutValue;
  final int hashMask;
  final Int32List son;
  final Int32List hash;

  factory _MatchFinder(Uint8List data, int dictSize, int fastBytes) {
    var hs = dictSize - 1;
    hs |= hs >> 1;
    hs |= hs >> 2;
    hs |= hs >> 4;
    hs |= hs >> 8;
    hs >>= 1;
    hs |= 0xFFFF;
    if (hs > (1 << 24)) hs >>= 1;
    return _MatchFinder._(data, dictSize + 1, fastBytes, 16 + (fastBytes >> 1), hs);
  }

  _MatchFinder._(this.buf, this.cyclicSize, this.matchMaxLen, this.cutValue, this.hashMask)
      : streamPos = buf.length + 1,
        son = Int32List(cyclicSize * 2),
        hash = Int32List(hashMask + 1 + _kFixHashSize);

  int indexByte(int index) => buf[pos - 1 + index];
  int available() => streamPos - pos;

  int matchLen(int index, int distance, int limit) {
    if ((pos + index) + limit > streamPos) limit = streamPos - (pos + index);
    distance++;
    final p = pos - 1 + index;
    var i = 0;
    while (i < limit && buf[p + i] == buf[p + i - distance]) {
      i++;
    }
    return i;
  }

  void movePos() {
    if (++cyclicPos >= cyclicSize) cyclicPos = 0;
    pos++;
  }

  int getMatches(Int32List d) {
    int lenLimit;
    if (pos + matchMaxLen <= streamPos) {
      lenLimit = matchMaxLen;
    } else {
      lenLimit = streamPos - pos;
      if (lenLimit < 4) {
        movePos();
        return 0;
      }
    }
    var offset = 0;
    final matchMinPos = pos > cyclicSize ? pos - cyclicSize : 0;
    final cur = pos - 1;
    var maxLen = 1;
    var temp = _hashCrc[buf[cur]] ^ buf[cur + 1];
    final hash2 = temp & (_kHash2Size - 1);
    temp ^= buf[cur + 2] << 8;
    final hash3 = temp & (_kHash3Size - 1);
    final hashValue = (temp ^ (_hashCrc[buf[cur + 3]] << 5)) & hashMask;
    var curMatch = hash[_kFixHashSize + hashValue];
    var curMatch2 = hash[hash2];
    final curMatch3 = hash[_kHash3Offset + hash3];
    hash[hash2] = pos;
    hash[_kHash3Offset + hash3] = pos;
    if (curMatch2 > matchMinPos && buf[curMatch2 - 1] == buf[cur]) {
      d[offset++] = maxLen = 2;
      d[offset++] = pos - curMatch2 - 1;
    }
    if (curMatch3 > matchMinPos && buf[curMatch3 - 1] == buf[cur]) {
      if (curMatch3 == curMatch2) offset -= 2;
      d[offset++] = maxLen = 3;
      d[offset++] = pos - curMatch3 - 1;
      curMatch2 = curMatch3;
    }
    if (offset != 0 && curMatch2 == curMatch) {
      offset -= 2;
      maxLen = 1;
    }
    hash[_kFixHashSize + hashValue] = pos;
    var ptr0 = (cyclicPos << 1) + 1;
    var ptr1 = cyclicPos << 1;
    var len0 = 0;
    var len1 = 0;
    var count = cutValue;
    while (true) {
      if (curMatch <= matchMinPos || count-- == 0) {
        son[ptr0] = 0;
        son[ptr1] = 0;
        break;
      }
      final delta = pos - curMatch;
      final cyc = ((delta <= cyclicPos) ? (cyclicPos - delta) : (cyclicPos - delta + cyclicSize)) << 1;
      final pby1 = curMatch - 1;
      var len = len0 < len1 ? len0 : len1;
      if (buf[pby1 + len] == buf[cur + len]) {
        while (++len != lenLimit) {
          if (buf[pby1 + len] != buf[cur + len]) break;
        }
        if (maxLen < len) {
          d[offset++] = maxLen = len;
          d[offset++] = delta - 1;
          if (len == lenLimit) {
            son[ptr1] = son[cyc];
            son[ptr0] = son[cyc + 1];
            break;
          }
        }
      }
      if (buf[pby1 + len] < buf[cur + len]) {
        son[ptr1] = curMatch;
        ptr1 = cyc + 1;
        curMatch = son[ptr1];
        len1 = len;
      } else {
        son[ptr0] = curMatch;
        ptr0 = cyc;
        curMatch = son[ptr0];
        len0 = len;
      }
    }
    movePos();
    return offset;
  }

  void skip(int num) {
    do {
      int lenLimit;
      if (pos + matchMaxLen <= streamPos) {
        lenLimit = matchMaxLen;
      } else {
        lenLimit = streamPos - pos;
        if (lenLimit < 4) {
          movePos();
          continue;
        }
      }
      final matchMinPos = pos > cyclicSize ? pos - cyclicSize : 0;
      final cur = pos - 1;
      var temp = _hashCrc[buf[cur]] ^ buf[cur + 1];
      hash[temp & (_kHash2Size - 1)] = pos;
      temp ^= buf[cur + 2] << 8;
      hash[_kHash3Offset + (temp & (_kHash3Size - 1))] = pos;
      final hashValue = (temp ^ (_hashCrc[buf[cur + 3]] << 5)) & hashMask;
      var curMatch = hash[_kFixHashSize + hashValue];
      hash[_kFixHashSize + hashValue] = pos;
      var ptr0 = (cyclicPos << 1) + 1;
      var ptr1 = cyclicPos << 1;
      var len0 = 0;
      var len1 = 0;
      var count = cutValue;
      while (true) {
        if (curMatch <= matchMinPos || count-- == 0) {
          son[ptr0] = 0;
          son[ptr1] = 0;
          break;
        }
        final delta = pos - curMatch;
        final cyc = ((delta <= cyclicPos) ? (cyclicPos - delta) : (cyclicPos - delta + cyclicSize)) << 1;
        final pby1 = curMatch - 1;
        var len = len0 < len1 ? len0 : len1;
        if (buf[pby1 + len] == buf[cur + len]) {
          while (++len != lenLimit) {
            if (buf[pby1 + len] != buf[cur + len]) break;
          }
          if (len == lenLimit) {
            son[ptr1] = son[cyc];
            son[ptr0] = son[cyc + 1];
            break;
          }
        }
        if (buf[pby1 + len] < buf[cur + len]) {
          son[ptr1] = curMatch;
          ptr1 = cyc + 1;
          curMatch = son[ptr1];
          len1 = len;
        } else {
          son[ptr0] = curMatch;
          ptr0 = cyc;
          curMatch = son[ptr0];
          len0 = len;
        }
      }
      movePos();
    } while (--num != 0);
  }
}

// ───────────────────────── مرمّز الأطوال ─────────────────────────

class _LenEncoder {
  final Uint16List choice = Uint16List(2);
  final List<_BitTree> low = List.generate(_kNumPosStatesEncodingMax, (_) => _BitTree(_kNumLowLenBits));
  final List<_BitTree> mid = List.generate(_kNumPosStatesEncodingMax, (_) => _BitTree(_kNumMidLenBits));
  final _BitTree high = _BitTree(_kNumHighLenBits);
  final Int32List prices = Int32List(_kNumLenSymbols << 4);
  int tableSize = 0;
  final Int32List counters = Int32List(16);

  void init(int numPosStates) {
    _initProbs(choice);
    for (var i = 0; i < numPosStates; i++) {
      low[i].init();
      mid[i].init();
    }
    high.init();
  }

  void _encodeRaw(_RangeEncoder rc, int symbol, int posState) {
    if (symbol < _kNumLowLenSymbols) {
      rc.encode(choice, 0, 0);
      low[posState].encode(rc, symbol);
    } else {
      symbol -= _kNumLowLenSymbols;
      rc.encode(choice, 0, 1);
      if (symbol < _kNumMidLenSymbols) {
        rc.encode(choice, 1, 0);
        mid[posState].encode(rc, symbol);
      } else {
        rc.encode(choice, 1, 1);
        high.encode(rc, symbol - _kNumMidLenSymbols);
      }
    }
  }

  void _setPrices(int posState, int numSymbols, int st) {
    final a0 = _price0(choice[0]);
    final a1 = _price1(choice[0]);
    final b0 = a1 + _price0(choice[1]);
    final b1 = a1 + _price1(choice[1]);
    var i = 0;
    for (i = 0; i < _kNumLowLenSymbols; i++) {
      if (i >= numSymbols) return;
      prices[st + i] = a0 + low[posState].getPrice(i);
    }
    for (; i < _kNumLowLenSymbols + _kNumMidLenSymbols; i++) {
      if (i >= numSymbols) return;
      prices[st + i] = b0 + mid[posState].getPrice(i - _kNumLowLenSymbols);
    }
    for (; i < numSymbols; i++) {
      prices[st + i] = b1 + high.getPrice(i - _kNumLowLenSymbols - _kNumMidLenSymbols);
    }
  }

  int getPrice(int symbol, int posState) => prices[posState * _kNumLenSymbols + symbol];

  void updateTable(int posState) {
    _setPrices(posState, tableSize, posState * _kNumLenSymbols);
    counters[posState] = tableSize;
  }

  void updateTables(int n) {
    for (var i = 0; i < n; i++) {
      updateTable(i);
    }
  }

  void encode(_RangeEncoder rc, int symbol, int posState) {
    _encodeRaw(rc, symbol, posState);
    if (--counters[posState] == 0) updateTable(posState);
  }
}

class _Optimal {
  int state = 0;
  bool prev1IsChar = false;
  bool prev2 = false;
  int posPrev2 = 0;
  int backPrev2 = 0;
  int price = 0;
  int posPrev = 0;
  int backPrev = 0;
  int backs0 = 0;
  int backs1 = 0;
  int backs2 = 0;
  int backs3 = 0;

  void makeAsChar() {
    backPrev = -1;
    prev1IsChar = false;
  }

  void makeAsShortRep() {
    backPrev = 0;
    prev1IsChar = false;
  }

  bool isShortRep() => backPrev == 0;
}

// ───────────────────────── مرمّز LZMA (مع أجزاء LZMA2) ─────────────────────────

const int _kNumOpts = 1 << 12;
const int _kInfinityPrice = 0xFFFFFFF;
const int _kPb = 2;
const int _kLp = 0;
const int _kLc = 3;
const int _kPosStateMask = 3;

const int _kChunkUnpackedMax = 1 << 21;
const int _kChunkPackedMax = 1 << 16;
const int _kChunkPackedMargin = 128;

class _LzmaEncoder {
  final _MatchFinder mf;
  final _RangeEncoder rc = _RangeEncoder();
  final int numFastBytes;
  final bool lzma2;
  final void Function(int done, int total)? onProgress;
  final int total;

  int state = 0;
  int previousByte = 0;
  final Int32List repDistances = Int32List(4);
  final List<_Optimal> opt = List.generate(_kNumOpts, (_) => _Optimal());
  final Uint16List isMatch = Uint16List(_kNumStates << _kNumPosStatesBitsMax);
  final Uint16List isRep = Uint16List(_kNumStates);
  final Uint16List isRepG0 = Uint16List(_kNumStates);
  final Uint16List isRepG1 = Uint16List(_kNumStates);
  final Uint16List isRepG2 = Uint16List(_kNumStates);
  final Uint16List isRep0Long = Uint16List(_kNumStates << _kNumPosStatesBitsMax);
  final List<_BitTree> posSlotEnc = List.generate(_kNumLenToPosStates, (_) => _BitTree(_kNumPosSlotBits));
  final Uint16List posEncoders = Uint16List(_kNumFullDistances - _kEndPosModelIndex);
  final _BitTree posAlignEnc = _BitTree(_kNumAlignBits);
  final _LenEncoder lenEnc = _LenEncoder();
  final _LenEncoder repLenEnc = _LenEncoder();
  final Uint16List literal = Uint16List(0x300 << (_kLc + _kLp));
  final Int32List matchDistances = Int32List(_kMatchMaxLen * 2 + 2);
  int longestMatchLength = 0;
  int numDistancePairs = 0;
  int additionalOffset = 0;
  int optimumEndIndex = 0;
  int optimumCurrentIndex = 0;
  bool longestMatchWasFound = false;
  final Int32List posSlotPrices = Int32List(1 << (_kNumPosSlotBits + _kNumLenToPosStatesBits));
  final Int32List distancesPrices = Int32List(_kNumFullDistances << _kNumLenToPosStatesBits);
  final Int32List alignPrices = Int32List(_kAlignTableSize);
  int alignPriceCount = 0;
  int matchPriceCount = 0;
  late final int distTableSize;
  final Int32List tempPrices = Int32List(_kNumFullDistances);
  final Int32List reps = Int32List(4);
  final Int32List repLens = Int32List(4);
  int backRes = 0;
  int nowPos = 0;

  // LZMA2
  late _Out lz2;
  late _Out chunk;
  int chunkStartPos = 0;
  bool firstChunk = true;
  int _nextProgress = 0;

  _LzmaEncoder(Uint8List data, int dictSize, this.numFastBytes, this.lzma2, this.onProgress)
      : mf = _MatchFinder(data, dictSize, numFastBytes),
        total = data.length {
    var dicLog = 0;
    while (dictSize > (1 << dicLog)) {
      dicLog++;
    }
    distTableSize = dicLog * 2;
    _initProbs(isMatch);
    _initProbs(isRep0Long);
    _initProbs(isRep);
    _initProbs(isRepG0);
    _initProbs(isRepG1);
    _initProbs(isRepG2);
    _initProbs(posEncoders);
    _initProbs(literal);
    for (final t in posSlotEnc) {
      t.init();
    }
    lenEnc.init(1 << _kPb);
    repLenEnc.init(1 << _kPb);
    posAlignEnc.init();
    _fillDistancesPrices();
    _fillAlignPrices();
    lenEnc.tableSize = numFastBytes + 1 - _kMatchMinLen;
    lenEnc.updateTables(1 << _kPb);
    repLenEnc.tableSize = numFastBytes + 1 - _kMatchMinLen;
    repLenEnc.updateTables(1 << _kPb);
  }

  int _litBase(int pos, int prevByte) => (prevByte >> (8 - _kLc)) * 0x300; // lp = 0

  void _litEncode(int base, int symbol) {
    var ctx = 1;
    for (var i = 7; i >= 0; i--) {
      final bit = (symbol >> i) & 1;
      rc.encode(literal, base + ctx, bit);
      ctx = (ctx << 1) | bit;
    }
  }

  void _litEncodeMatched(int base, int matchByte, int symbol) {
    var ctx = 1;
    var same = true;
    for (var i = 7; i >= 0; i--) {
      final bit = (symbol >> i) & 1;
      var st = ctx;
      if (same) {
        final mb = (matchByte >> i) & 1;
        st += (1 + mb) << 8;
        same = mb == bit;
      }
      rc.encode(literal, base + st, bit);
      ctx = (ctx << 1) | bit;
    }
  }

  int _litPrice(int base, bool matchMode, int matchByte, int symbol) {
    var p = 0;
    var ctx = 1;
    var i = 7;
    if (matchMode) {
      for (; i >= 0; i--) {
        final mb = (matchByte >> i) & 1;
        final bit = (symbol >> i) & 1;
        p += _price(literal[base + ((1 + mb) << 8) + ctx], bit);
        ctx = (ctx << 1) | bit;
        if (mb != bit) {
          i--;
          break;
        }
      }
    }
    for (; i >= 0; i--) {
      final bit = (symbol >> i) & 1;
      p += _price(literal[base + ctx], bit);
      ctx = (ctx << 1) | bit;
    }
    return p;
  }

  int _readMatchDistances() {
    var lenRes = 0;
    numDistancePairs = mf.getMatches(matchDistances);
    if (numDistancePairs > 0) {
      lenRes = matchDistances[numDistancePairs - 2];
      if (lenRes == numFastBytes) {
        lenRes += mf.matchLen(lenRes - 1, matchDistances[numDistancePairs - 1], _kMatchMaxLen - lenRes);
      }
    }
    additionalOffset++;
    return lenRes;
  }

  void _movePos(int num) {
    if (num > 0) {
      mf.skip(num);
      additionalOffset += num;
    }
  }

  int _repLen1Price(int st, int posState) =>
      _price0(isRepG0[st]) + _price0(isRep0Long[(st << _kNumPosStatesBitsMax) + posState]);

  int _pureRepPrice(int repIndex, int st, int posState) {
    int p;
    if (repIndex == 0) {
      p = _price0(isRepG0[st]);
      p += _price1(isRep0Long[(st << _kNumPosStatesBitsMax) + posState]);
    } else {
      p = _price1(isRepG0[st]);
      if (repIndex == 1) {
        p += _price0(isRepG1[st]);
      } else {
        p += _price1(isRepG1[st]);
        p += _price(isRepG2[st], repIndex - 2);
      }
    }
    return p;
  }

  int _repPrice(int repIndex, int len, int st, int posState) =>
      repLenEnc.getPrice(len - _kMatchMinLen, posState) + _pureRepPrice(repIndex, st, posState);

  int _posLenPrice(int pos, int len, int posState) {
    int p;
    final lps = _lenToPosState(len);
    if (pos < _kNumFullDistances) {
      p = distancesPrices[lps * _kNumFullDistances + pos];
    } else {
      p = posSlotPrices[(lps << _kNumPosSlotBits) + _posSlot2(pos)] + alignPrices[pos & _kAlignMask];
    }
    return p + lenEnc.getPrice(len - _kMatchMinLen, posState);
  }

  int _backward(int cur) {
    optimumEndIndex = cur;
    var posMem = opt[cur].posPrev;
    var backMem = opt[cur].backPrev;
    do {
      if (opt[cur].prev1IsChar) {
        opt[posMem].makeAsChar();
        opt[posMem].posPrev = posMem - 1;
        if (opt[cur].prev2) {
          opt[posMem - 1].prev1IsChar = false;
          opt[posMem - 1].posPrev = opt[cur].posPrev2;
          opt[posMem - 1].backPrev = opt[cur].backPrev2;
        }
      }
      final posPrev = posMem;
      final backCur = backMem;
      backMem = opt[posPrev].backPrev;
      posMem = opt[posPrev].posPrev;
      opt[posPrev].backPrev = backCur;
      opt[posPrev].posPrev = cur;
      cur = posPrev;
    } while (cur > 0);
    backRes = opt[0].backPrev;
    optimumCurrentIndex = opt[0].posPrev;
    return optimumCurrentIndex;
  }

  int _getOptimum(int position) {
    if (optimumEndIndex != optimumCurrentIndex) {
      final lenRes = opt[optimumCurrentIndex].posPrev - optimumCurrentIndex;
      backRes = opt[optimumCurrentIndex].backPrev;
      optimumCurrentIndex = opt[optimumCurrentIndex].posPrev;
      return lenRes;
    }
    optimumCurrentIndex = optimumEndIndex = 0;
    int lenMain;
    int nDP;
    if (!longestMatchWasFound) {
      lenMain = _readMatchDistances();
    } else {
      lenMain = longestMatchLength;
      longestMatchWasFound = false;
    }
    nDP = numDistancePairs;
    var numAvailableBytes = mf.available() + 1;
    if (numAvailableBytes < 2) {
      backRes = -1;
      return 1;
    }
    if (numAvailableBytes > _kMatchMaxLen) numAvailableBytes = _kMatchMaxLen;
    var repMaxIndex = 0;
    int i;
    for (i = 0; i < 4; i++) {
      reps[i] = repDistances[i];
      repLens[i] = mf.matchLen(-1, reps[i], _kMatchMaxLen);
      if (repLens[i] > repLens[repMaxIndex]) repMaxIndex = i;
    }
    if (repLens[repMaxIndex] >= numFastBytes) {
      backRes = repMaxIndex;
      final lenRes = repLens[repMaxIndex];
      _movePos(lenRes - 1);
      return lenRes;
    }
    if (lenMain >= numFastBytes) {
      backRes = matchDistances[nDP - 1] + 4;
      _movePos(lenMain - 1);
      return lenMain;
    }
    var currentByte = mf.indexByte(-1);
    var matchByte = mf.indexByte(-repDistances[0] - 1 - 1);
    if (lenMain < 2 && currentByte != matchByte && repLens[repMaxIndex] < 2) {
      backRes = -1;
      return 1;
    }
    opt[0].state = state;
    var posState = position & _kPosStateMask;
    opt[1].price = _price0(isMatch[(state << _kNumPosStatesBitsMax) + posState]) +
        _litPrice(_litBase(position, previousByte), !_stateIsChar(state), matchByte, currentByte);
    opt[1].makeAsChar();
    var matchPrice = _price1(isMatch[(state << _kNumPosStatesBitsMax) + posState]);
    var repMatchPrice = matchPrice + _price1(isRep[state]);
    if (matchByte == currentByte) {
      final shortRepPrice = repMatchPrice + _repLen1Price(state, posState);
      if (shortRepPrice < opt[1].price) {
        opt[1].price = shortRepPrice;
        opt[1].makeAsShortRep();
      }
    }
    var lenEnd = lenMain >= repLens[repMaxIndex] ? lenMain : repLens[repMaxIndex];
    if (lenEnd < 2) {
      backRes = opt[1].backPrev;
      return 1;
    }
    opt[1].posPrev = 0;
    opt[0].backs0 = reps[0];
    opt[0].backs1 = reps[1];
    opt[0].backs2 = reps[2];
    opt[0].backs3 = reps[3];
    var len = lenEnd;
    do {
      opt[len--].price = _kInfinityPrice;
    } while (len >= 2);
    for (i = 0; i < 4; i++) {
      var repLen = repLens[i];
      if (repLen < 2) continue;
      final pr = repMatchPrice + _pureRepPrice(i, state, posState);
      do {
        final curAndLenPrice = pr + repLenEnc.getPrice(repLen - 2, posState);
        final o = opt[repLen];
        if (curAndLenPrice < o.price) {
          o.price = curAndLenPrice;
          o.posPrev = 0;
          o.backPrev = i;
          o.prev1IsChar = false;
        }
      } while (--repLen >= 2);
    }
    var normalMatchPrice = matchPrice + _price0(isRep[state]);
    len = repLens[0] >= 2 ? repLens[0] + 1 : 2;
    if (len <= lenMain) {
      var offs = 0;
      while (len > matchDistances[offs]) {
        offs += 2;
      }
      for (;; len++) {
        final distance = matchDistances[offs + 1];
        final curAndLenPrice = normalMatchPrice + _posLenPrice(distance, len, posState);
        final o = opt[len];
        if (curAndLenPrice < o.price) {
          o.price = curAndLenPrice;
          o.posPrev = 0;
          o.backPrev = distance + 4;
          o.prev1IsChar = false;
        }
        if (len == matchDistances[offs]) {
          offs += 2;
          if (offs == nDP) break;
        }
      }
    }
    var cur = 0;
    while (true) {
      cur++;
      if (cur == lenEnd) return _backward(cur);
      var newLen = _readMatchDistances();
      nDP = numDistancePairs;
      if (newLen >= numFastBytes) {
        longestMatchLength = newLen;
        longestMatchWasFound = true;
        return _backward(cur);
      }
      position++;
      var posPrev = opt[cur].posPrev;
      int st;
      if (opt[cur].prev1IsChar) {
        posPrev--;
        if (opt[cur].prev2) {
          st = opt[opt[cur].posPrev2].state;
          if (opt[cur].backPrev2 < 4) {
            st = _stateUpdateRep(st);
          } else {
            st = _stateUpdateMatch(st);
          }
        } else {
          st = opt[posPrev].state;
        }
        st = _stateUpdateChar(st);
      } else {
        st = opt[posPrev].state;
      }
      if (posPrev == cur - 1) {
        if (opt[cur].isShortRep()) {
          st = _stateUpdateShortRep(st);
        } else {
          st = _stateUpdateChar(st);
        }
      } else {
        int pos;
        if (opt[cur].prev1IsChar && opt[cur].prev2) {
          posPrev = opt[cur].posPrev2;
          pos = opt[cur].backPrev2;
          st = _stateUpdateRep(st);
        } else {
          pos = opt[cur].backPrev;
          if (pos < 4) {
            st = _stateUpdateRep(st);
          } else {
            st = _stateUpdateMatch(st);
          }
        }
        final o = opt[posPrev];
        if (pos < 4) {
          if (pos == 0) {
            reps[0] = o.backs0;
            reps[1] = o.backs1;
            reps[2] = o.backs2;
            reps[3] = o.backs3;
          } else if (pos == 1) {
            reps[0] = o.backs1;
            reps[1] = o.backs0;
            reps[2] = o.backs2;
            reps[3] = o.backs3;
          } else if (pos == 2) {
            reps[0] = o.backs2;
            reps[1] = o.backs0;
            reps[2] = o.backs1;
            reps[3] = o.backs3;
          } else {
            reps[0] = o.backs3;
            reps[1] = o.backs0;
            reps[2] = o.backs1;
            reps[3] = o.backs2;
          }
        } else {
          reps[0] = pos - 4;
          reps[1] = o.backs0;
          reps[2] = o.backs1;
          reps[3] = o.backs2;
        }
      }
      opt[cur].state = st;
      opt[cur].backs0 = reps[0];
      opt[cur].backs1 = reps[1];
      opt[cur].backs2 = reps[2];
      opt[cur].backs3 = reps[3];
      final curPrice = opt[cur].price;
      currentByte = mf.indexByte(-1);
      matchByte = mf.indexByte(-reps[0] - 1 - 1);
      posState = position & _kPosStateMask;
      final curAnd1Price = curPrice +
          _price0(isMatch[(st << _kNumPosStatesBitsMax) + posState]) +
          _litPrice(_litBase(position, mf.indexByte(-2)), !_stateIsChar(st), matchByte, currentByte);
      final next = opt[cur + 1];
      var nextIsChar = false;
      if (curAnd1Price < next.price) {
        next.price = curAnd1Price;
        next.posPrev = cur;
        next.makeAsChar();
        nextIsChar = true;
      }
      matchPrice = curPrice + _price1(isMatch[(st << _kNumPosStatesBitsMax) + posState]);
      repMatchPrice = matchPrice + _price1(isRep[st]);
      if (matchByte == currentByte && !(next.posPrev < cur && next.backPrev == 0)) {
        final shortRepPrice = repMatchPrice + _repLen1Price(st, posState);
        if (shortRepPrice <= next.price) {
          next.price = shortRepPrice;
          next.posPrev = cur;
          next.makeAsShortRep();
          nextIsChar = true;
        }
      }
      var numAvailableBytesFull = mf.available() + 1;
      if (_kNumOpts - 1 - cur < numAvailableBytesFull) numAvailableBytesFull = _kNumOpts - 1 - cur;
      numAvailableBytes = numAvailableBytesFull;
      if (numAvailableBytes < 2) continue;
      if (numAvailableBytes > numFastBytes) numAvailableBytes = numFastBytes;
      if (!nextIsChar && matchByte != currentByte) {
        final t = numAvailableBytesFull - 1 < numFastBytes ? numAvailableBytesFull - 1 : numFastBytes;
        final lenTest2 = mf.matchLen(0, reps[0], t);
        if (lenTest2 >= 2) {
          final state2 = _stateUpdateChar(st);
          final posStateNext = (position + 1) & _kPosStateMask;
          final nextRepMatchPrice = curAnd1Price +
              _price1(isMatch[(state2 << _kNumPosStatesBitsMax) + posStateNext]) +
              _price1(isRep[state2]);
          final offset = cur + 1 + lenTest2;
          while (lenEnd < offset) {
            opt[++lenEnd].price = _kInfinityPrice;
          }
          final curAndLenPrice = nextRepMatchPrice + _repPrice(0, lenTest2, state2, posStateNext);
          final o = opt[offset];
          if (curAndLenPrice < o.price) {
            o.price = curAndLenPrice;
            o.posPrev = cur + 1;
            o.backPrev = 0;
            o.prev1IsChar = true;
            o.prev2 = false;
          }
        }
      }
      var startLen = 2;
      for (var repIndex = 0; repIndex < 4; repIndex++) {
        var lenTest = mf.matchLen(-1, reps[repIndex], numAvailableBytes);
        if (lenTest < 2) continue;
        final lenTestTemp = lenTest;
        do {
          while (lenEnd < cur + lenTest) {
            opt[++lenEnd].price = _kInfinityPrice;
          }
          final curAndLenPrice = repMatchPrice + _repPrice(repIndex, lenTest, st, posState);
          final o = opt[cur + lenTest];
          if (curAndLenPrice < o.price) {
            o.price = curAndLenPrice;
            o.posPrev = cur;
            o.backPrev = repIndex;
            o.prev1IsChar = false;
          }
        } while (--lenTest >= 2);
        lenTest = lenTestTemp;
        if (repIndex == 0) startLen = lenTest + 1;
        if (lenTest < numAvailableBytesFull) {
          final rem = numAvailableBytesFull - 1 - lenTest;
          final t = rem < numFastBytes ? rem : numFastBytes;
          final lenTest2 = mf.matchLen(lenTest, reps[repIndex], t);
          if (lenTest2 >= 2) {
            var state2 = _stateUpdateRep(st);
            var posStateNext = (position + lenTest) & _kPosStateMask;
            final curAndLenCharPrice = repMatchPrice +
                _repPrice(repIndex, lenTest, st, posState) +
                _price0(isMatch[(state2 << _kNumPosStatesBitsMax) + posStateNext]) +
                _litPrice(_litBase(position + lenTest, mf.indexByte(lenTest - 1 - 1)), true,
                    mf.indexByte(lenTest - 1 - (reps[repIndex] + 1)), mf.indexByte(lenTest - 1));
            state2 = _stateUpdateChar(state2);
            posStateNext = (position + lenTest + 1) & _kPosStateMask;
            final nextMatchPrice = curAndLenCharPrice + _price1(isMatch[(state2 << _kNumPosStatesBitsMax) + posStateNext]);
            final nextRepMatchPrice = nextMatchPrice + _price1(isRep[state2]);
            final offset = lenTest + 1 + lenTest2;
            while (lenEnd < cur + offset) {
              opt[++lenEnd].price = _kInfinityPrice;
            }
            final curAndLenPrice = nextRepMatchPrice + _repPrice(0, lenTest2, state2, posStateNext);
            final o = opt[cur + offset];
            if (curAndLenPrice < o.price) {
              o.price = curAndLenPrice;
              o.posPrev = cur + lenTest + 1;
              o.backPrev = 0;
              o.prev1IsChar = true;
              o.prev2 = true;
              o.posPrev2 = cur;
              o.backPrev2 = repIndex;
            }
          }
        }
      }
      if (newLen > numAvailableBytes) {
        newLen = numAvailableBytes;
        for (nDP = 0; newLen > matchDistances[nDP]; nDP += 2) {}
        matchDistances[nDP] = newLen;
        nDP += 2;
      }
      if (newLen >= startLen) {
        normalMatchPrice = matchPrice + _price0(isRep[st]);
        while (lenEnd < cur + newLen) {
          opt[++lenEnd].price = _kInfinityPrice;
        }
        var offs = 0;
        while (startLen > matchDistances[offs]) {
          offs += 2;
        }
        for (var lenTest = startLen;; lenTest++) {
          final curBack = matchDistances[offs + 1];
          var curAndLenPrice = normalMatchPrice + _posLenPrice(curBack, lenTest, posState);
          var o = opt[cur + lenTest];
          if (curAndLenPrice < o.price) {
            o.price = curAndLenPrice;
            o.posPrev = cur;
            o.backPrev = curBack + 4;
            o.prev1IsChar = false;
          }
          if (lenTest == matchDistances[offs]) {
            if (lenTest < numAvailableBytesFull) {
              final rem = numAvailableBytesFull - 1 - lenTest;
              final t = rem < numFastBytes ? rem : numFastBytes;
              final lenTest2 = mf.matchLen(lenTest, curBack, t);
              if (lenTest2 >= 2) {
                var state2 = _stateUpdateMatch(st);
                var posStateNext = (position + lenTest) & _kPosStateMask;
                final curAndLenCharPrice = curAndLenPrice +
                    _price0(isMatch[(state2 << _kNumPosStatesBitsMax) + posStateNext]) +
                    _litPrice(_litBase(position + lenTest, mf.indexByte(lenTest - 1 - 1)), true,
                        mf.indexByte(lenTest - (curBack + 1) - 1), mf.indexByte(lenTest - 1));
                state2 = _stateUpdateChar(state2);
                posStateNext = (position + lenTest + 1) & _kPosStateMask;
                final nextMatchPrice =
                    curAndLenCharPrice + _price1(isMatch[(state2 << _kNumPosStatesBitsMax) + posStateNext]);
                final nextRepMatchPrice = nextMatchPrice + _price1(isRep[state2]);
                final offset = lenTest + 1 + lenTest2;
                while (lenEnd < cur + offset) {
                  opt[++lenEnd].price = _kInfinityPrice;
                }
                curAndLenPrice = nextRepMatchPrice + _repPrice(0, lenTest2, state2, posStateNext);
                o = opt[cur + offset];
                if (curAndLenPrice < o.price) {
                  o.price = curAndLenPrice;
                  o.posPrev = cur + lenTest + 1;
                  o.backPrev = 0;
                  o.prev1IsChar = true;
                  o.prev2 = true;
                  o.posPrev2 = cur;
                  o.backPrev2 = curBack + 4;
                }
              }
            }
            offs += 2;
            if (offs == nDP) break;
          }
        }
      }
    }
  }

  void _fillDistancesPrices() {
    for (var i = _kStartPosModelIndex; i < _kNumFullDistances; i++) {
      final ps = _posSlot(i);
      final footerBits = (ps >> 1) - 1;
      final baseVal = (2 | (ps & 1)) << footerBits;
      tempPrices[i] = _reverseGetPrice(posEncoders, baseVal - ps - 1, footerBits, i - baseVal);
    }
    for (var lps = 0; lps < _kNumLenToPosStates; lps++) {
      final enc = posSlotEnc[lps];
      final st = lps << _kNumPosSlotBits;
      for (var ps = 0; ps < distTableSize; ps++) {
        posSlotPrices[st + ps] = enc.getPrice(ps);
      }
      for (var ps = _kEndPosModelIndex; ps < distTableSize; ps++) {
        posSlotPrices[st + ps] += (((ps >> 1) - 1) - _kNumAlignBits) << _kNumBitPriceShiftBits;
      }
      final st2 = lps * _kNumFullDistances;
      var i = 0;
      for (i = 0; i < _kStartPosModelIndex; i++) {
        distancesPrices[st2 + i] = posSlotPrices[st + i];
      }
      for (; i < _kNumFullDistances; i++) {
        distancesPrices[st2 + i] = posSlotPrices[st + _posSlot(i)] + tempPrices[i];
      }
    }
    matchPriceCount = 0;
  }

  void _fillAlignPrices() {
    for (var i = 0; i < _kAlignTableSize; i++) {
      alignPrices[i] = posAlignEnc.reverseGetPrice(i);
    }
    alignPriceCount = 0;
  }

  // ─── أجزاء LZMA2 ───

  void _beginChunk() {
    chunk = _Out(_kChunkPackedMax + 1024);
    rc.init(chunk);
    chunkStartPos = nowPos;
  }

  void _endChunk() {
    final u = nowPos - chunkStartPos;
    if (u == 0) return;
    final predicted = rc.pending();
    rc.flush();
    final p = chunk.n;
    // ضمانات الصيغة — أي خلل هنا يُوقف الضغط بدل إخراج ملف تالف
    if (p != predicted) throw StateError('LZMA2: حجم الجزء $p ≠ المتوقع $predicted');
    if (p > _kChunkPackedMax || u > _kChunkUnpackedMax) throw StateError('LZMA2: جزء أكبر من المسموح $p/$u');
    lz2.put((firstChunk ? 0xE0 : 0x80) | ((u - 1) >> 16));
    lz2.put(((u - 1) >> 8) & 0xFF);
    lz2.put((u - 1) & 0xFF);
    lz2.put(((p - 1) >> 8) & 0xFF);
    lz2.put((p - 1) & 0xFF);
    if (firstChunk) lz2.put((_kPb * 5 + _kLp) * 9 + _kLc);
    lz2.putAll(chunk.b, 0, p);
    firstChunk = false;
  }

  bool _chunkFull() =>
      (nowPos - chunkStartPos) + _kMatchMaxLen > _kChunkUnpackedMax ||
      rc.pending() + _kChunkPackedMargin > _kChunkPackedMax;

  void _progress() {
    final cb = onProgress;
    if (cb != null && nowPos >= _nextProgress) {
      _nextProgress = nowPos + (1 << 20);
      cb(nowPos, total);
    }
  }

  Uint8List run() {
    lz2 = _Out(total ~/ 6 + 1024);
    if (lzma2) {
      _beginChunk();
    } else {
      chunk = _Out(total ~/ 6 + 1024);
      rc.init(chunk);
    }
    nowPos = 0;
    if (mf.available() == 0) return _finish();
    _readMatchDistances();
    var posState = nowPos & _kPosStateMask;
    rc.encode(isMatch, (state << _kNumPosStatesBitsMax) + posState, 0);
    state = _stateUpdateChar(state);
    var curByte = mf.indexByte(-additionalOffset);
    _litEncode(_litBase(nowPos, previousByte), curByte);
    previousByte = curByte;
    additionalOffset--;
    nowPos++;
    if (mf.available() == 0) return _finish();
    while (true) {
      if (lzma2 && _chunkFull()) {
        _endChunk();
        _beginChunk();
      }
      final len = _getOptimum(nowPos);
      var pos = backRes;
      posState = nowPos & _kPosStateMask;
      final complexState = (state << _kNumPosStatesBitsMax) + posState;
      if (len == 1 && pos == -1) {
        rc.encode(isMatch, complexState, 0);
        curByte = mf.indexByte(-additionalOffset);
        final base = _litBase(nowPos, previousByte);
        if (!_stateIsChar(state)) {
          _litEncodeMatched(base, mf.indexByte(-repDistances[0] - 1 - additionalOffset), curByte);
        } else {
          _litEncode(base, curByte);
        }
        previousByte = curByte;
        state = _stateUpdateChar(state);
      } else {
        rc.encode(isMatch, complexState, 1);
        if (pos < 4) {
          rc.encode(isRep, state, 1);
          if (pos == 0) {
            rc.encode(isRepG0, state, 0);
            rc.encode(isRep0Long, complexState, len == 1 ? 0 : 1);
          } else {
            rc.encode(isRepG0, state, 1);
            if (pos == 1) {
              rc.encode(isRepG1, state, 0);
            } else {
              rc.encode(isRepG1, state, 1);
              rc.encode(isRepG2, state, pos - 2);
            }
          }
          if (len == 1) {
            state = _stateUpdateShortRep(state);
          } else {
            repLenEnc.encode(rc, len - _kMatchMinLen, posState);
            state = _stateUpdateRep(state);
          }
          final distance = repDistances[pos];
          if (pos != 0) {
            for (var i = pos; i >= 1; i--) {
              repDistances[i] = repDistances[i - 1];
            }
            repDistances[0] = distance;
          }
        } else {
          rc.encode(isRep, state, 0);
          state = _stateUpdateMatch(state);
          lenEnc.encode(rc, len - _kMatchMinLen, posState);
          pos -= 4;
          final ps = _posSlot(pos);
          posSlotEnc[_lenToPosState(len)].encode(rc, ps);
          if (ps >= _kStartPosModelIndex) {
            final footerBits = (ps >> 1) - 1;
            final baseVal = (2 | (ps & 1)) << footerBits;
            final posReduced = pos - baseVal;
            if (ps < _kEndPosModelIndex) {
              _reverseEncode(posEncoders, baseVal - ps - 1, rc, footerBits, posReduced);
            } else {
              rc.encodeDirectBits(posReduced >> _kNumAlignBits, footerBits - _kNumAlignBits);
              posAlignEnc.reverseEncode(rc, posReduced & _kAlignMask);
              alignPriceCount++;
            }
          }
          for (var i = 3; i >= 1; i--) {
            repDistances[i] = repDistances[i - 1];
          }
          repDistances[0] = pos;
          matchPriceCount++;
        }
        previousByte = mf.indexByte(len - 1 - additionalOffset);
      }
      additionalOffset -= len;
      nowPos += len;
      if (additionalOffset == 0) {
        if (matchPriceCount >= (1 << 7)) _fillDistancesPrices();
        if (alignPriceCount >= _kAlignTableSize) _fillAlignPrices();
        if (mf.available() == 0) return _finish();
        _progress();
      }
    }
  }

  Uint8List _finish() {
    onProgress?.call(total, total);
    if (lzma2) {
      _endChunk();
      lz2.put(0x00);
      return lz2.bytes();
    }
    rc.flush();
    return chunk.bytes();
  }
}
