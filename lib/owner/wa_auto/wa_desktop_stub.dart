// lib/owner/wa_auto/wa_desktop_stub.dart — منصات بلا ويندوز/FFI

class WaDesktop {
  WaDesktop._();

  static bool get supported => false;

  static String? foregroundTitle() => null;

  /// null = أُرسل؛ نص = سبب الفشل.
  static Future<String?> send(String phone, String text, {Duration loadWait = const Duration(seconds: 4)}) async =>
      'متاح على ويندوز فقط';
}
