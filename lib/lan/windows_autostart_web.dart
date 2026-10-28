// الويب: لا سجل ويندوز ولا تشغيل تلقائي.
class WindowsAutostart {
  WindowsAutostart._();
  static bool get supported => false;
  static String? current() => null;
  static bool isEnabled() => false;
  static void sync(bool want) {}
}
