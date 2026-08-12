import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class PythonService {
  static const String _baseUrl = "http://127.0.0.1:5000";

  /// 🧠 NEW: Sends image to the Table Extractor endpoint
  /// Uses OpenCV line detection + EasyOCR per-cell
  Future<Map<String, dynamic>> extractTable(File imageFile) async {
    try {
      debugPrint("🐍 PythonService: Calling /extract_table...");

      final uri = Uri.parse("$_baseUrl/extract_table");
      final request = http.MultipartRequest('POST', uri);

      final fileStream = http.MultipartFile.fromBytes(
        'image',
        await imageFile.readAsBytes(),
        filename: imageFile.path.split(Platform.pathSeparator).last,
      );

      request.files.add(fileStream);

      final streamedResponse = await request.send()
          .timeout(const Duration(seconds: 120)); // Table extraction may take time
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        debugPrint("🐍 PythonService: /extract_table Success!");
        final json = jsonDecode(response.body);
        return json;
      } else {
        debugPrint("🐍 PythonService: /extract_table Failed: ${response.statusCode}");
        return {"error": "Server Error ${response.statusCode}", "details": response.body};
      }
    } catch (e) {
      debugPrint("🐍 PythonService /extract_table Error: $e");
      return {
        "error": "Connection Failed",
        "details": "Make sure the Python Backend is running. Error: $e"
      };
    }
  }

  /// Legacy: Sends image to the LayoutLMv3 endpoint
  Future<Map<String, dynamic>> analyzeImage(File imageFile) async {
    try {
      debugPrint("🐍 PythonService: Calling /analyze_invoice (legacy)...");

      final uri = Uri.parse("$_baseUrl/analyze_invoice");
      final request = http.MultipartRequest('POST', uri);

      final fileStream = http.MultipartFile.fromBytes(
        'image',
        await imageFile.readAsBytes(),
        filename: imageFile.path.split(Platform.pathSeparator).last,
      );

      request.files.add(fileStream);

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        debugPrint("🐍 PythonService: Success! Response: ${response.body}");
        final json = jsonDecode(response.body);
        json['status'] = 'success';
        return json;
      } else {
        debugPrint("🐍 PythonService: Failed with status ${response.statusCode}");
        return {"error": "Server Error ${response.statusCode}", "details": response.body};
      }
    } catch (e) {
      debugPrint("🐍 PythonService Connection Error: $e");
      return {
        "error": "Connection Failed",
        "details": "Make sure the Python Backend is running. Error: $e"
      };
    }
  }

  bool _isStarting = false;

  /// Check if the Python backend is running, and start it if not.
  Future<void> ensureBackendRunning() async {
    if (_isStarting) return;
    
    bool running = await isBackendHealthy();
    if (running) {
      debugPrint("🐍 PythonService: Backend is already running.");
      return;
    }

    _isStarting = true;
    debugPrint("🐍 PythonService: Backend not reachable. Attempting to start...");

    try {
      // 1. Try to find the bundled executable (for Release/Frozen app)
      // It should be in the same directory as the main executable
      String exePath = "invoice_ai_server.exe"; 
      File exeFile = File(exePath);
      
      if (!await exeFile.exists()) {
        // Fallback for Debug mode: look in python_backend/dist...
        exePath = "python_backend/dist/invoice_ai_server/invoice_ai_server.exe";
        exeFile = File(exePath);
      }

      if (await exeFile.exists()) {
        debugPrint("🚀 Starting Bundled Backend: $exePath");
        // Start process detached so it survives if app crashes (optional, or keep attached to kill on exit)
        // For now, we keep it simple.
        await Process.start(
          exePath, 
          [], 
          mode: ProcessStartMode.detached, 
          workingDirectory: File(Platform.script.toFilePath()).parent.path
        );
        
        // Wait for it to boot
        int retries = 0;
        while (retries < 10) {
          await Future.delayed(const Duration(seconds: 1));
          if (await isBackendHealthy()) {
             debugPrint("✅ Bundled Backend Started Successfully!");
             _isStarting = false;
             return;
          }
          retries++;
        }
        debugPrint("⚠️ Bundled Backend started but failed health check.");
      } else {
        debugPrint("⚠️ Backend executable not found at $exePath. (Dev Mode?)");
        // In Dev mode, you might want to run from source, but usually we just run manually.
      }

    } catch (e) {
      debugPrint("❌ Failed to start backend: $e");
    } finally {
      _isStarting = false;
    }
  }

  /// Check if the Python backend is running
  Future<bool> isBackendHealthy() async {
    try {
      final response = await http.get(Uri.parse("$_baseUrl/health"))
          .timeout(const Duration(seconds: 1)); // fast check
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
