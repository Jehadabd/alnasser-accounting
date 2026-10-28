// lib/services/keyboard_layout/keyboard_layout.dart
//
// ⌨️ تبديل لغة لوحة المفاتيح تلقائياً (ويندوز): الإنجليزية داخل خانة «رمز المادة»،
// ثم إرجاع اللغة التي كانت قبلها عند الخروج. على غير ويندوز (والويب) لا يفعل شيئاً.
export 'keyboard_layout_stub.dart' if (dart.library.ffi) 'keyboard_layout_io.dart';
