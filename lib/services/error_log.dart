// lib/services/error_log.dart
//
// 🧯 سجل أخطاء Dart في ملف — حتى نعرف سبب أي خروج مفاجئ بدل التخمين.
//   ويندوز:  %LOCALAPPDATA%\alnaser_logs\dart_errors.log   (بجانب native_errors.log)
//   أندرويد: <مجلد التطبيق>/alnaser_logs/dart_errors.log
// يكتب فقط ولا يغيّر السلوك. الملف يُقصّ إن تجاوز 1 ميجا.
// ويغذّي أداة «تشخيص الأخطاء» (ErrorJournal) بالأخطاء نفسها.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'diagnostics/error_journal.dart'; // 🩺 أداة «تشخيص الأخطاء»

class ErrorLog {
  ErrorLog._();

  static File? _file;
  static int _written = 0;

  static Future<void> install() async {
    if (kIsWeb) {
      await ErrorJournal.install(null); // في الذاكرة فقط
      return;
    }
    Directory? journalDir;
    try {
      Directory dir;
      final local = Platform.environment['LOCALAPPDATA'];
      if (Platform.isWindows && local != null && local.isNotEmpty) {
        dir = Directory('$local${Platform.pathSeparator}alnaser_logs');
      } else {
        dir = Directory('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}alnaser_logs');
      }
      await dir.create(recursive: true);
      final f = File('${dir.path}${Platform.pathSeparator}dart_errors.log');
      if (await f.exists() && await f.length() > 1024 * 1024) {
        await f.writeAsString('');
      }
      _file = f;
      journalDir = dir;
      _write('===== start ${DateTime.now().toIso8601String()} (${Platform.operatingSystem}) =====');
    } catch (_) {}
    await ErrorJournal.install(journalDir);

    final prevFlutter = FlutterError.onError;
    FlutterError.onError = (details) {
      _write('[FlutterError] ${details.exceptionAsString()}\n${details.stack ?? ''}');
      ErrorJournal.record(
          source: ErrorSource.flutter, error: details.exceptionAsString(), stack: details.stack, context: details.context?.toString());
      unawaited(ErrorJournal.save()); // قد يُغلق البرنامج بعدها
      if (prevFlutter != null) {
        prevFlutter(details);
      } else {
        FlutterError.presentError(details);
      }
    };

    final prevPlatform = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      _write('[Uncaught] $error\n$stack');
      ErrorJournal.record(source: ErrorSource.uncaught, error: error, stack: stack);
      unawaited(ErrorJournal.save());
      // نُبقي البرنامج يعمل: الخطأ سُجّل، ولا داعي لإغلاقه
      return prevPlatform?.call(error, stack) ?? true;
    };
  }

  /// تسجيل يدوي (لحالات نعالجها ونريد أثرها)
  static void note(String message) => _write('[note] $message');

  static void _write(String text) {
    final f = _file;
    if (f == null || _written > 2000) return;
    _written++;
    try {
      f.writeAsStringSync('[${DateTime.now().toIso8601String()}] $text\n', mode: FileMode.append, flush: true);
    } catch (_) {}
  }
}
