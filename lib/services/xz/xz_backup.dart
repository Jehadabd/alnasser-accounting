// lib/services/xz/xz_backup.dart
//
// 🗜️ ضغط نسخة الرفع بـ XZ حقيقي — في Isolate منفصل (الواجهة لا تتجمد)، ثم تحقق:
//   1) يُضغط الأرشيف بـ xzCompress (LZMA2، قاموس 8MB).
//   2) يُفكّ الناتج بـ XZDecoder من مكتبة archive مع فحص CRC32 — وهو نفسه مسار
//      الاستعادة في BackupFiles.extractDatabase.
//   3) يُقارن المفكوك بالأصل بايتاً ببايت.
// أي فشل أو اختلاف ⇒ يعيد null، ولا يُرفع ملف XZ إطلاقاً (المستدعي يختار البديل).
// بهذا لا يمكن أن تُرفع نسخة XZ لا تستطيع هذه النسخة من البرنامج استعادتها.

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart' show XZDecoder;
import 'package:flutter/foundation.dart' show debugPrint;

import 'xz_encoder.dart';

class XzBackup {
  XzBackup._();

  /// يعيد ملف .xz متحققاً منه، أو null عند أي فشل.
  /// [onProgress] من 0 إلى 1 (الضغط حتى 0.85، ثم التحقق).
  static Future<Uint8List?> compressVerified(
    Uint8List input, {
    void Function(double p)? onProgress,
    int fastBytes = 64,
  }) async {
    final port = ReceivePort();
    final done = Completer<Uint8List?>();
    final sw = Stopwatch()..start();
    void finish(Uint8List? r, [String? why]) {
      if (done.isCompleted) return;
      if (why != null) debugPrint('⚠️ ضغط XZ: $why');
      done.complete(r);
    }

    final sub = port.listen((msg) {
      if (msg is double) {
        onProgress?.call(msg);
      } else if (msg is TransferableTypedData) {
        finish(msg.materialize().asUint8List());
      } else if (msg is String) {
        finish(null, msg);
      } else if (msg is List) {
        finish(null, 'خطأ في المعالج: ${msg.isNotEmpty ? msg.first : msg}');
      } else if (msg == null) {
        finish(null, 'انتهى المعالج بلا نتيجة');
      }
    });
    try {
      await Isolate.spawn<_XzJob>(
        _worker,
        _XzJob(port.sendPort, TransferableTypedData.fromList([input]), fastBytes),
        onError: port.sendPort,
        onExit: port.sendPort,
        debugName: 'xz-backup',
      );
    } catch (e) {
      finish(null, 'تعذّر تشغيل المعالج: $e');
    }
    final result = await done.future;
    await sub.cancel();
    port.close();
    if (result != null) {
      debugPrint('🗜️ XZ: ${input.length} ← ${result.length} بايت في ${sw.elapsed.inMilliseconds} ms (متحقق منه)');
    }
    return result;
  }

  static void _worker(_XzJob job) {
    try {
      final data = job.input.materialize().asUint8List();
      final xz = xzCompress(data, fastBytes: job.fastBytes, onProgress: (d, t) {
        job.port.send(t == 0 ? 0.85 : 0.85 * d / t);
      });
      job.port.send(0.88);
      final back = XZDecoder().decodeBytes(xz, verify: true);
      if (back.length != data.length) {
        job.port.send('التحقق فشل: الحجم بعد الفك ${back.length} ≠ ${data.length}');
        return;
      }
      for (var i = 0; i < data.length; i++) {
        if (back[i] != data[i]) {
          job.port.send('التحقق فشل: اختلاف عند البايت $i');
          return;
        }
      }
      job.port.send(1.0);
      job.port.send(TransferableTypedData.fromList([xz]));
    } catch (e) {
      job.port.send('فشل الضغط/التحقق: $e');
    }
  }
}

class _XzJob {
  final SendPort port;
  final TransferableTypedData input;
  final int fastBytes;
  _XzJob(this.port, this.input, this.fastBytes);
}
