// lib/services/pdf_rtl.dart
//
// ↔️ جداول PDF بالعربية: جدول مكتبة pdf (pw.Table / TableHelper.fromTextArray) يرسم
// العمود الأول على اليسار دائماً، حتى مع textDirection: rtl للصفحة. لذلك كانت سندات
// المرتجع والسندات المحاسبية والتقارير تظهر «من اليسار إلى اليمين» (التسلسل على اليسار).
// الفاتورة وكشف الحساب يكتبان أعمدتهما معكوسة يدوياً منذ البداية؛ هذا الملف يفعل الشيء نفسه
// للجداول التي تُبنى بالترتيب المنطقي (الأول = أقصى اليمين). لا يغيّر أي قيمة — ترتيب فقط.

class PdfRtl {
  PdfRtl._();

  /// صف بالترتيب المنطقي ⇐ ترتيب الرسم (الأول يُرسم أقصى اليمين).
  static List<T> row<T>(List<T> cells) => cells.reversed.toList();

  /// صفوف كاملة؛ الصف الأقصر من [width] يُكمَّل بخلايا فارغة قبل العكس كي لا تنزاح أعمدته.
  static List<List<String>> rows(List<List<String>> data, int width) => [
        for (final r in data)
          [
            for (var i = width - 1; i >= 0; i--) i < r.length ? r[i] : '',
            // خلايا زائدة عن عدد الرؤوس (لا يُفترض وجودها) تبقى في آخر الرسم
            for (var i = width; i < r.length; i++) r[i],
          ],
      ];

  /// خريطة عمود ⇐ قيمة (عرض/محاذاة) بأرقام الترتيب المنطقي ⇐ أرقام الرسم.
  static Map<int, V> columns<V>(Map<int, V> byLogical, int width) => {
        for (final e in byLogical.entries)
          if (e.key >= 0 && e.key < width) width - 1 - e.key: e.value,
      };
}
