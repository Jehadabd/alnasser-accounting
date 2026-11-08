// lib/owner/wa_auto/wa_desktop.dart
//
// 💬 إرسال رسالة عبر تطبيق WhatsApp Desktop الرسمي على ويندوز (ميزة مالك).
// على غير ويندوز: لا شيء (stub).

export 'wa_desktop_stub.dart' if (dart.library.ffi) 'wa_desktop_io.dart';
