// lib/services/telegram_net/tdlib_engine.dart
//
// ⭐ محرك MTProto: مكتبة تيليجرام الرسمية TDLib (tdjson.dll) لنظام Windows.
//
// تيليجرام لا تنشر نسخة Windows جاهزة؛ نأخذها من حزمة tdlib.native (ترخيص BSL-1.0 مثل TDLib،
// https://github.com/ForNeVeR/tdlib.native) من مستودع NuGet الرسمي، بنسخة مثبّتة [version].
// قبل الاستخراج تُطابق بصمة SHA-512 للحزمة مع بصمتها المسجّلة في فهرس NuGet؛ حزمة لا تطابق
// تُحذف. يُستخرج أربعة ملفات فقط: tdjson.dll ومكتباتها (OpenSSL و zlib).

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../simplex/simplex_engine.dart' show SimplexEngine, SimplexException;

class TdlibEngine {
  TdlibEngine._();

  static const version = '1.8.70';
  static const _pkg = 'tdlib.native.win-x64';
  static const _nupkgUrl = 'https://api.nuget.org/v3-flatcontainer/$_pkg/$version/$_pkg.$version.nupkg';
  static const _registrationUrl = 'https://api.nuget.org/v3/registration5-semver1/$_pkg/$version.json';

  /// ترتيب التحميل: المكتبات التي يعتمد عليها tdjson أولاً (Windows لا يبحث عنها في مجلد tdjson).
  static const dlls = ['z.dll', 'libcrypto-3-x64.dll', 'libssl-3-x64.dll', 'tdjson.dll'];

  static bool get supported => !kIsWeb && Platform.isWindows;

  static Future<String> root() async => p.join((await getApplicationSupportDirectory()).path, 'tdlib');
  static Future<String> binDir() async => p.join(await root(), 'bin');
  static Future<File> _stamp() async => File(p.join(await binDir(), 'installed.json'));

  static Future<bool> isInstalled() async {
    if (!supported) return false;
    try {
      final st = jsonDecode(await (await _stamp()).readAsString()) as Map;
      if (st['version'] != version) return false;
      final files = (st['files'] as Map).cast<String, dynamic>();
      for (final d in dlls) {
        final f = File(p.join(await binDir(), d));
        if (!await f.exists() || await f.length() != files[d]) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  static bool _installing = false;

  static Future<void> install({void Function(String text, [double? progress])? step}) async {
    if (!supported) throw SimplexException('MTProto متاح حالياً على Windows فقط');
    if (_installing) throw SimplexException('التثبيت جارٍ بالفعل');
    _installing = true;
    void s(String t, [double? f]) => step?.call(t, f);
    try {
      final bin = Directory(await binDir());
      await bin.create(recursive: true);
      s('قراءة بصمة الحزمة من فهرس NuGet ($version)…');
      final want = await _officialSha512();
      final tmp = File(p.join(bin.path, 'download.nupkg'));
      if (await tmp.exists()) await tmp.delete();
      s('تنزيل محرك MTProto (مرة واحدة)…', 0);
      await SimplexEngine.fetchFile(_nupkgUrl, tmp, (f) => s('تنزيل محرك MTProto…', f));
      final bytes = await tmp.readAsBytes();
      await tmp.delete();
      final got = base64.encode(sha512.convert(bytes).bytes);
      if (got != want) throw SimplexException('بصمة الحزمة المنزّلة لا تطابق فهرس NuGet — حُذفت ولم تُستعمل. أعد المحاولة');

      s('استخراج الملفات…');
      final files = extractDlls(bytes);
      final sizes = <String, int>{};
      for (final e in files.entries) {
        final out = File(p.join(bin.path, e.key));
        try {
          await out.writeAsBytes(e.value, flush: true);
        } on FileSystemException {
          throw SimplexException('ملفات المحرك قيد الاستعمال — أغلق البرنامج وافتحه ثم أعد المحاولة');
        }
        sizes[e.key] = e.value.length;
      }
      await (await _stamp()).writeAsString(jsonEncode({'version': version, 'sha512': got, 'files': sizes, 'at': DateTime.now().toIso8601String()}));
      s('تم تثبيت محرك MTProto (TDLib $version)');
    } finally {
      _installing = false;
    }
  }

  static Future<String> _officialSha512() async {
    final reg = jsonDecode(await SimplexEngine.fetchText(_registrationUrl));
    final entryUrl = reg is Map ? reg['catalogEntry'] : null;
    if (entryUrl is! String || !entryUrl.startsWith('https://api.nuget.org/')) {
      throw SimplexException('تعذّر قراءة بيانات الحزمة من NuGet');
    }
    final entry = jsonDecode(await SimplexEngine.fetchText(entryUrl));
    final h = entry is Map ? entry['packageHash'] : null;
    final alg = entry is Map ? entry['packageHashAlgorithm'] : null;
    if (h is! String || '$alg'.toUpperCase() != 'SHA512') throw SimplexException('لا توجد بصمة للحزمة في NuGet — لا يُنزَّل ما لا يمكن التحقق منه');
    return h;
  }

  /// الملفات الأربعة من الحزمة (أي مسار تحت runtimes/win-x64/). حزمة ناقصة ⇒ خطأ.
  @visibleForTesting
  static Map<String, List<int>> extractDlls(List<int> nupkg) {
    final arc = ZipDecoder().decodeBytes(nupkg);
    final out = <String, List<int>>{};
    for (final f in arc.files) {
      if (!f.isFile) continue;
      final name = f.name.replaceAll('\\', '/');
      if (!name.toLowerCase().startsWith('runtimes/win-x64/')) continue;
      final base = name.split('/').last;
      final match = dlls.where((d) => d.toLowerCase() == base.toLowerCase());
      if (match.isEmpty) continue;
      out[match.first] = f.content as List<int>;
    }
    final missing = dlls.where((d) => !out.containsKey(d)).toList();
    if (missing.isNotEmpty) throw SimplexException('الحزمة لا تحتوي: ${missing.join(', ')}');
    return out;
  }
}
