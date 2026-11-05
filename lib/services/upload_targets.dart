// lib/services/upload_targets.dart
//
// ☁️ وجهات زر «رفع البيانات» وترتيبها (من الإعدادات ← النسخ الاحتياطي).
//   • تيليغرام: قاعدة البيانات + الفواتير + الملخص الشهري.
//   • دروب بوكس: نسخة احتياطية كاملة.
//   • ديسكورد: يستلم نسخة من كل ما يُرسل لتيليغرام؛ إن أُوقف تيليغرام تُرسل
//     له قاعدة البيانات مضغوطة مباشرة.
//   • Google Drive (لكل المستخدمين): قاعدة البيانات مضغوطة + سجل الديون PDF.

import '../models/app_settings.dart';

class UploadTargets {
  UploadTargets._();

  static const telegram = 'telegram';
  static const dropbox = 'dropbox';
  static const discord = 'discord';
  static const gdrive = 'gdrive';

  static const all = [telegram, dropbox, discord, gdrive];

  static const labels = {
    telegram: 'تيليغرام',
    dropbox: 'دروب بوكس',
    discord: 'ديسكورد',
    gdrive: 'Google Drive',
  };

  static const hints = {
    telegram: 'قاعدة البيانات، الفواتير، والملخص الشهري',
    dropbox: 'نسخة احتياطية كاملة',
    discord: 'نسخة مما يُرسل لتيليغرام (أو قاعدة البيانات وحدها إن أُوقف تيليغرام)',
    gdrive: 'قاعدة البيانات مضغوطة + سجل الديون PDF',
  };

  /// الترتيب المحفوظ مكمّلاً بأي وجهة ناقصة.
  static List<String> ordered(List<String> saved) {
    final out = <String>[
      for (final t in saved)
        if (all.contains(t)) t,
      for (final t in all)
        if (!saved.contains(t)) t,
    ];
    return out;
  }

  /// الوجهات المفعّلة بالترتيب
  static List<String> enabledInOrder(AppSettings s) =>
      ordered(s.uploadOrder).where((t) => !s.uploadDisabled.contains(t)).toList();
}
