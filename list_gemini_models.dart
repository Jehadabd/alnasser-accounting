import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

Future<void> main() async {
  print('🔍 Listing Available Gemini Models...');

  // 1. Load .env manually
  final envFile = File('.env');
  String? apiKey;
  
  if (await envFile.exists()) {
    final lines = await envFile.readAsLines();
    for (var line in lines) {
      if (line.startsWith('GEMINI_API_KEY=')) {
        apiKey = line.split('=')[1].trim();
        break;
      }
    }
  }

  if (apiKey == null || apiKey.isEmpty) {
    print('❌ GEMINI_API_KEY not found in .env');
    return;
  }
  print('🔑 Using API Key: ${apiKey.substring(0, 5)}...');

  // 2. Query Models Endpoint
  final uri = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models?key=$apiKey');
  
  try {
    final response = await http.get(uri);
    
    print('📥 Response Status: ${response.statusCode}');
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final models = data['models'] as List;
      
      print('\n📋 Available Models:');
      print('════════════════════════════════════════');
      for (var model in models) {
        final name = model['name'].toString().replaceFirst('models/', '');
        final methods = model['supportedGenerationMethods'] as List;
        
        if (methods.contains('generateContent')) {
          print('✅ $name');
        } else {
          print('⚠️ $name (No generateContent support)');
        }
      }
      print('════════════════════════════════════════');
    } else {
      print('❌ Error Listing Models:');
      print(response.body);
    }
  } catch (e) {
    print('❌ Exception: $e');
  }
}
