// lib/services/upload_progress.dart
//
// 📶 رفع يُبلغ بعدد البايتات التي خرجت فعلاً — لقياس سرعة الإنترنت الحية أثناء الرفع.
// الملف يُرسل أجزاءً (64KB)؛ الجزء التالي لا يُسحب إلا حين يقبل الاتصال ما قبله
// (ضغط التدفق الخلفي في HttpClient)، فالعدّ يتبع الشبكة لا الذاكرة.
// إن انقطع الإنترنت يتوقف العدّ — وهذا ما يُظهر «الرفع متوقف» ويطيل الوقت المتبقي.

import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// [sent] = ما أُرسل حتى الآن، [total] = حجم الملف.
typedef SentCallback = void Function(int sent, int total);

const _chunk = 64 * 1024;

/// أجزاء [bytes] بالترتيب؛ يُبلغ [onSent] كلما سُحب جزء (أي قبِل الاتصال ما قبله).
Stream<List<int>> countedChunks(List<int> bytes, SentCallback? onSent) async* {
  final view = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  onSent?.call(0, view.length);
  for (var i = 0; i < view.length; i += _chunk) {
    final end = i + _chunk < view.length ? i + _chunk : view.length;
    yield Uint8List.sublistView(view, i, end);
    onSent?.call(end, view.length);
  }
}

/// يرسل [req] بجسم [body] مع إبلاغ التقدم. [timeout] للعملية كلها (كالسابق).
Future<http.Response> sendCounted(
  http.StreamedRequest req,
  List<int> body,
  SentCallback? onSent, {
  http.Client? client,
  Duration timeout = const Duration(minutes: 10),
}) async {
  req.contentLength = body.length;
  final sending = client != null ? client.send(req) : req.send();
  // الخطأ (اتصال مقطوع...) يظهر من sending — لا نتركه «غير معالج» أثناء الكتابة
  unawaited(sending.then<void>((_) {}, onError: (_) {}));
  try {
    await req.sink.addStream(countedChunks(body, onSent)).timeout(timeout);
  } on TimeoutException {
    rethrow; // الرفع لم يكتمل خلال المهلة
  } catch (_) {
    // السبب الحقيقي (اتصال مقطوع، رفض الخادم...) يأتي من sending أدناه
  }
  try {
    await req.sink.close();
  } catch (_) {}
  final streamed = await sending.timeout(timeout);
  return http.Response.fromStream(streamed).timeout(timeout);
}
