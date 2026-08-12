#include "printer_settings_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <shellapi.h>

void PrinterSettingsPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "printer_settings",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<PrinterSettingsPlugin>();

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

PrinterSettingsPlugin::PrinterSettingsPlugin() {}

PrinterSettingsPlugin::~PrinterSettingsPlugin() {}

void PrinterSettingsPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  
  if (method_call.method_name().compare("openWindowsPrinterSettings") == 0) {
    // فتح إعدادات الطابعة في Windows
    ShellExecute(
        NULL,
        L"open",
        L"control.exe",
        L"/name Microsoft.DevicesAndPrinters",
        NULL,
        SW_SHOW
    );
    result->Success();
  } else {
    result->NotImplemented();
  }
} 