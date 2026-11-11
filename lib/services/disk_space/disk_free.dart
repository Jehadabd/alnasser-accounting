// lib/services/disk_space/disk_free.dart
//
// 💽 المساحة الفارغة على القرص الذي فيه مسار معيّن (ويندوز). على غيره وعلى الويب: null
// (غير معروفة)، فلا يُمنع شيء بسببها.
export 'disk_free_stub.dart' if (dart.library.ffi) 'disk_free_io.dart';
