// lib/services/database/business/snapshot_chain.dart
//
// 🧬 سلسلة نسخ الفاتورة بالفروق — بدل حفظ الفاتورة كاملة في كل تعديل.
//
// الفكرة (مثال الماء والبيبسي):
//   النسخة الأولى تُحفظ كاملة: [ماء 2، بيبسي 1].
//   تعديل أضاف عصيراً وجعل الماء 3: يُحفظ الفرق فقط —
//     حُذف: [ماء 2]   أُضيف: [ماء 3، عصير 1]
//   إعادة البناء: النسخة السابقة − المحذوف + المضاف = [ماء 3، بيبسي 1، عصير 1].
//
// الأسطر تُقارن نصاً كاملاً (كل حقول السطر: الكمية، السعر، الكلفة، الوحدة...)، والطرح
// والجمع «متعدد المجموعات»: سطران متطابقان تماماً يُعدّان اثنين. لذلك إعادة البناء
// دقيقة حرفياً، لا تقريبية.
//
// التحقق الذاتي: كل فرق يحمل بصمة القائمة الناتجة (fp). إن لم تطابق البصمة ما أعيد
// بناؤه — أو كان سطر «محذوف» غير موجود في السابقة — تُعلَّم النسخة «أصنافها غير
// معروفة» ولا يُخمَّن شيء. الإجماليات (المبلغ، الخصم، المدفوع...) لا تتأثر لأنها
// تُحفظ كاملة في كل نسخة.
//
// كل نسخة كاملة بعد [kFullEvery] فروق متتالية، فلا تطول السلسلة ولا ينتشر خطأ.

import 'dart:convert';

import 'package:crypto/crypto.dart';

class SnapshotChain {
  SnapshotChain._();

  /// بعد كم فرقاً متتالياً تُحفظ نسخة كاملة.
  static const int kFullEvery = 15;

  /// نص السطر الثابت (للمقارنة): المفاتيح بترتيبها كما جاءت من القاعدة.
  static String lineKey(Map<String, dynamic> row) => jsonEncode(row);

  /// بصمة قائمة أسطر (لا تتأثر بترتيبها).
  static String fingerprint(Iterable<String> lines) {
    final sorted = lines.toList()..sort();
    return sha1.convert(utf8.encode(sorted.join('\n'))).toString().substring(0, 16);
  }

  /// هل النص فرقٌ لا قائمة كاملة؟
  static bool isDelta(String text) {
    final t = text.trimLeft();
    return t.startsWith('{') && t.contains('"delta"');
  }

  /// يقرأ أسطر قائمة كاملة (نص JSON لقائمة) — null إن تعذّر.
  static List<String>? _fullLines(String text) {
    try {
      final v = jsonDecode(text);
      if (v is! List) return null;
      return [for (final e in v) if (e is Map) lineKey(Map<String, dynamic>.from(e))];
    } catch (_) {
      return null;
    }
  }

  /// الطرح متعدد المجموعات: يعيد (ما في a وليس في b، ما في b وليس في a).
  static (List<String>, List<String>) multisetDiff(List<String> a, List<String> b) {
    final counts = <String, int>{};
    for (final x in b) {
      counts[x] = (counts[x] ?? 0) + 1;
    }
    final onlyA = <String>[];
    for (final x in a) {
      final n = counts[x] ?? 0;
      if (n > 0) {
        counts[x] = n - 1;
      } else {
        onlyA.add(x);
      }
    }
    final onlyB = <String>[];
    for (final e in counts.entries) {
      for (var i = 0; i < e.value; i++) {
        onlyB.add(e.key);
      }
    }
    // ترتيب ثابت لما في b (كما ورد فيها)
    final order = <String, int>{};
    for (var i = 0; i < b.length; i++) {
      order.putIfAbsent(b[i], () => i);
    }
    onlyB.sort((x, y) => (order[x] ?? 0).compareTo(order[y] ?? 0));
    return (onlyA, onlyB);
  }

  /// نص الفرق بين قائمة سابقة كاملة [prevFull] وقائمة جديدة كاملة [nextFull] (نصّا JSON).
  /// يعيد null إن تعذّرت القراءة أو لم يكن الفرق أصغر (فتُحفظ النسخة كاملة).
  static String? encodeDelta(String prevFull, String nextFull, {required int chainLength}) {
    if (chainLength >= kFullEvery) return null;
    final prev = _fullLines(prevFull);
    final next = _fullLines(nextFull);
    if (prev == null || next == null) return null;
    final (del, add) = multisetDiff(prev, next);
    final text = '{"delta":1,"fp":"${fingerprint(next)}",'
        '"del":[${del.join(',')}],"add":[${add.join(',')}]}';
    return text.length < nextFull.length ? text : null;
  }

  /// يطبّق فرقاً على أسطر سابقة. null = لا يمكن إعادة البناء بدقة.
  static List<String>? applyDelta(List<String> prev, String deltaText) {
    try {
      final d = jsonDecode(deltaText) as Map<String, dynamic>;
      final del = [for (final e in (d['del'] as List)) lineKey(Map<String, dynamic>.from(e as Map))];
      final add = [for (final e in (d['add'] as List)) lineKey(Map<String, dynamic>.from(e as Map))];
      final out = List<String>.from(prev);
      for (final x in del) {
        final i = out.indexOf(x);
        if (i < 0) return null; // سطر «محذوف» غير موجود في السابقة ⇒ السلسلة مكسورة
        out.removeAt(i);
      }
      out.addAll(add);
      final fp = d['fp'] as String?;
      if (fp != null && fp != fingerprint(out)) return null;
      return out;
    } catch (_) {
      return null;
    }
  }

  /// هل القائمتان (نصّا JSON كاملان) بالأسطر نفسها، بغض النظر عن ترتيبها؟
  static bool sameItems(String a, String b) {
    if (a == b) return true;
    final la = _fullLines(a);
    final lb = _fullLines(b);
    if (la == null || lb == null) return false;
    return la.length == lb.length && fingerprint(la) == fingerprint(lb);
  }

  /// كم فرقاً متتالياً في آخر السلسلة (منذ آخر نسخة كاملة).
  static int trailingDeltas(List<String> itemTexts) {
    var n = 0;
    for (var i = itemTexts.length - 1; i >= 0; i--) {
      if (!isDelta(itemTexts[i])) break;
      n++;
    }
    return n;
  }

  /// يحوّل نسخ فاتورة (أو عدة فواتير) إلى نسخ كاملة جاهزة للعرض.
  /// [rows]: صفوف invoice_snapshots مرتبة حسب (invoice_id, version_number).
  /// [decode]: يفكّ عمود items_json (نص أو مضغوط) إلى نص.
  /// النسخة التي لا تُبنى بدقة يصير items_json فيها null و items_unknown = 1.
  static List<Map<String, dynamic>> materialize(
    List<Map<String, dynamic>> rows,
    String Function(dynamic raw) decode,
  ) {
    final out = <Map<String, dynamic>>[];
    Object? currentInvoice;
    List<String>? prev;
    for (final r in rows) {
      final row = Map<String, dynamic>.from(r);
      if (row['invoice_id'] != currentInvoice) {
        currentInvoice = row['invoice_id'];
        prev = null;
      }
      final text = decode(row['items_json']);
      if (isDelta(text)) {
        final full = prev == null ? null : applyDelta(prev, text);
        if (full == null) {
          row['items_json'] = null;
          row['items_unknown'] = 1;
          prev = null;
        } else {
          row['items_json'] = '[${full.join(',')}]';
          prev = full;
        }
      } else {
        row['items_json'] = text;
        prev = _fullLines(text);
      }
      out.add(row);
    }
    return out;
  }
}
