#ifndef PRINTER_SETTINGS_PLUGIN_H_
#define PRINTER_SETTINGS_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

// A plugin to open printer settings on Windows.
class PrinterSettingsPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  PrinterSettingsPlugin();

  virtual ~PrinterSettingsPlugin();

 private:
  // Called when a method is invoked on this plugin's channel.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

#endif  // PRINTER_SETTINGS_PLUGIN_H_ 