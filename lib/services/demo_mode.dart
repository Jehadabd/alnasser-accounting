// lib/services/demo_mode.dart
//
// 🧪 الوضع التجريبي: قاعدة بيانات منفصلة (debt_book_demo.db) فيها بيانات سنة
// وهمية للتجربة والتدريب. القاعدة الحقيقية لا تُفتح ولا تُلمس أبداً في هذا
// الوضع، والمزامنة (Firebase) والشبكة المحلية ورفع البيانات متوقفة.
//
// الحالة ملف علامة صغير بجانب القاعدة (demo_mode.flag) يُقرأ مرة واحدة عند
// الإقلاع قبل فتح أي قاعدة؛ التبديل يتطلب إعادة تشغيل البرنامج.

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

class DemoMode {
  DemoMode._();

  static const String demoDatabaseName = 'debt_book_demo.db';
  static const String _flagName = 'demo_mode.flag';
  static const String _regenName = 'demo_regen.flag';

  static bool _on = false;

  /// هل يعمل البرنامج الآن على القاعدة التجريبية؟
  static bool get isOn => _on;

  static Future<File?> _flag() async {
    if (kIsWeb) return null;
    final dir = await getApplicationSupportDirectory();
    return File(join(dir.path, _flagName));
  }

  /// يُستدعى مرة واحدة في main() قبل أي فتح لقاعدة البيانات.
  static Future<void> load() async {
    try {
      final f = await _flag();
      _on = f != null && await f.exists();
      // طلب «ابدأ البيانات التجريبية من جديد»: تُحذف القاعدة التجريبية قبل فتحها
      final dir = await getApplicationSupportDirectory();
      final regen = File(join(dir.path, _regenName));
      if (_on && await regen.exists()) {
        for (final suffix in ['', '-wal', '-shm', '-journal']) {
          final db = File(join(dir.path, '$demoDatabaseName$suffix'));
          if (await db.exists()) await db.delete();
        }
        await regen.delete();
        debugPrint('🧪 [DemoMode] حُذفت القاعدة التجريبية القديمة — ستُولَّد بيانات جديدة');
      }
    } catch (e) {
      debugPrint('⚠️ [DemoMode] تعذّرت قراءة حالة الوضع التجريبي: $e');
    }
    if (_on) debugPrint('🧪 [DemoMode] الوضع التجريبي مفعّل — القاعدة: $demoDatabaseName');
  }

  /// يغيّر الوضع للإقلاع القادم (لا يغيّر القاعدة المفتوحة الآن).
  static Future<void> setForNextLaunch(bool on) async {
    final f = await _flag();
    if (f == null) return;
    if (on) {
      await f.writeAsString(DateTime.now().toIso8601String());
    } else if (await f.exists()) {
      await f.delete();
    }
  }

  /// في الإقلاع القادم: تُحذف القاعدة التجريبية (فقط) وتُولَّد بيانات جديدة.
  static Future<void> requestRegenerate() async {
    if (kIsWeb) return;
    final dir = await getApplicationSupportDirectory();
    await File(join(dir.path, _regenName)).writeAsString(DateTime.now().toIso8601String());
  }
}
