// lib/services/backup_space_planner.dart
//
// 🧮 خطة حذف النسخ الاحتياطية القديمة عند الرفع (Dropbox و Google Drive) — منطق نقي مختبر.
//
//   • للمساحة: إن لم يكفِ المكان الفارغ للنسخة الجديدة (مع هامش أمان) تُحذف الأقدم
//     فالأقدم — قبل الرفع — حتى يكفي.
//   • للعدد: بعد نجاح الرفع، إن زاد عدد النسخ عن الحد تُحذف الأقدم.
//   • لا تُحذف أحدث [keepNewest] نسخ أبداً (افتراضياً 2).
//   • إن لم يكفِ المكان حتى بعد حذف كل ما يجوز حذفه ⇒ لا يُحذف شيء ولا يُرفع
//     (المساحة تشغلها ملفات أخرى للمستخدم؛ الحذف لن يفيد وقد يُفقد نسخاً).
//   • لا يُعرف حجم الحساب (مساحة غير محدودة أو تعذّر السؤال) ⇒ قاعدة العدد وحدها.

class BackupItem<T> {
  const BackupItem(this.ref, this.time, this.size);
  final T ref;
  final DateTime time;
  final int size;
}

class SpacePlan<T> {
  const SpacePlan({
    required this.beforeUpload,
    required this.afterUpload,
    required this.fits,
    required this.needed,
    required this.freeBefore,
  });

  /// تُحذف قبل الرفع لإفساح المكان (الأقدم أولاً).
  final List<BackupItem<T>> beforeUpload;

  /// تُحذف بعد نجاح الرفع لأن العدد زاد عن الحد (الأقدم أولاً).
  final List<BackupItem<T>> afterUpload;

  /// يكفي المكان بعد الحذف.
  final bool fits;

  /// المطلوب للنسخة الجديدة مع هامش الأمان (بايت).
  final int needed;

  /// المكان الفارغ قبل أي حذف (null = غير معروف).
  final int? freeBefore;

  int get freedBefore => beforeUpload.fold(0, (a, b) => a + b.size);
}

class BackupSpacePlanner {
  BackupSpacePlanner._();

  /// هامش الأمان: 10 ميغابايت + 5% من حجم النسخة.
  static int margin(int newSize) => 10 * 1024 * 1024 + newSize ~/ 20;

  static SpacePlan<T> plan<T>({
    required List<BackupItem<T>> existing,
    required int newSize,
    required int? free,
    required int maxCount,
    int keepNewest = 2,
  }) {
    final sorted = [...existing]..sort((a, b) => a.time.compareTo(b.time)); // الأقدم أولاً
    final keep = keepNewest < 0 ? 0 : keepNewest;
    final deletable = sorted.length > keep ? sorted.sublist(0, sorted.length - keep) : <BackupItem<T>>[];
    final needed = newSize + margin(newSize);

    // 1) المساحة (قبل الرفع)
    final before = <BackupItem<T>>[];
    var fits = true;
    if (free != null) {
      var room = free;
      var i = 0;
      while (room < needed && i < deletable.length) {
        room += deletable[i].size;
        before.add(deletable[i]);
        i++;
      }
      fits = room >= needed;
      if (!fits) {
        return SpacePlan(beforeUpload: const [], afterUpload: const [], fits: false, needed: needed, freeBefore: free);
      }
    }

    // 2) العدد (بعد الرفع): الباقي + الجديدة ≤ الحد
    final after = <BackupItem<T>>[];
    final max = maxCount < 1 ? 1 : maxCount;
    var remaining = sorted.length - before.length + 1;
    for (final b in deletable.skip(before.length)) {
      if (remaining <= max) break;
      after.add(b);
      remaining--;
    }
    return SpacePlan(beforeUpload: before, afterUpload: after, fits: fits, needed: needed, freeBefore: free);
  }

  /// «1.4 غيغابايت» / «820 ميغابايت».
  static String human(int bytes) {
    const mb = 1024 * 1024;
    const gb = 1024 * mb;
    if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(bytes >= 10 * gb ? 0 : 1)} غيغابايت';
    if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(bytes >= 100 * mb ? 0 : 1)} ميغابايت';
    return '${(bytes / 1024).ceil()} كيلوبايت';
  }
}
