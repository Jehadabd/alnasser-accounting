// services/gemini_service.dart
import 'package:flutter/foundation.dart' show debugPrint;
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

/// خدمة Gemini مع دعم 3 مفاتيح API للتبديل التلقائي
class GeminiService {
  GeminiService({
    required this.apiKey,
    this.apiKey2,
    this.apiKey3,
  }) {
    // بناء قائمة المفاتيح المتاحة
    _apiKeys = [apiKey];
    if (apiKey2 != null && apiKey2!.isNotEmpty) _apiKeys.add(apiKey2!);
    if (apiKey3 != null && apiKey3!.isNotEmpty) _apiKeys.add(apiKey3!);
    debugPrint('🔑 Gemini: تم تحميل ${_apiKeys.length} مفتاح/مفاتيح API');
  }

  final String apiKey;
  final String? apiKey2;
  final String? apiKey3;
  
  // قائمة المفاتيح المتاحة
  late final List<String> _apiKeys;
  
  // فهرس المفتاح الحالي
  int _currentKeyIndex = 0;
  
  String get _currentApiKey => _apiKeys[_currentKeyIndex];
  
  /// التبديل للمفتاح التالي
  bool _switchToNextKey() {
    if (_currentKeyIndex < _apiKeys.length - 1) {
      _currentKeyIndex++;
      debugPrint('🔄 Gemini: التبديل للمفتاح ${_currentKeyIndex + 1} من ${_apiKeys.length}');
      return true;
    }
    debugPrint('❌ Gemini: لا توجد مفاتيح إضافية للتبديل');
    return false;
  }

  static const String _endpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent';

  /// تنفيذ الطلب مع التبديل التلقائي بين المفاتيح
  Future<http.Response> _postWithRetry({
    required Map<String, dynamic> body,
  }) async {
    final uri = Uri.parse(_endpoint);
    const int maxAttemptsPerKey = 2;
    
    // المحاولة مع كل مفتاح
    while (true) {
      int attempt = 0;
      
      while (attempt < maxAttemptsPerKey) {
        attempt++;
        try {
          debugPrint('🔑 Gemini: استخدام المفتاح ${_currentKeyIndex + 1}/${_apiKeys.length} (محاولة $attempt)');
          
          final response = await http
              .post(
                uri,
                headers: {
                  'Content-Type': 'application/json',
                  'X-goog-api-key': _currentApiKey,
                },
                body: jsonEncode(body),
              )
              .timeout(const Duration(seconds: 30));

          // خطأ 429 (تجاوز الحصة) - تبديل فوري للمفتاح التالي
          if (response.statusCode == 429) {
            debugPrint('⚠️ Gemini: تجاوز الحصة (429) للمفتاح ${_currentKeyIndex + 1}');
            if (_switchToNextKey()) {
              attempt = 0; // إعادة تعيين المحاولات للمفتاح الجديد
              continue;
            }
            return response; // لا توجد مفاتيح إضافية
          }
          
          // خطأ في المفتاح - تبديل فوري
          if (response.statusCode == 401 || response.statusCode == 403) {
            debugPrint('🔑 Gemini: مفتاح غير صالح (${response.statusCode}) للمفتاح ${_currentKeyIndex + 1}');
            if (_switchToNextKey()) {
              attempt = 0;
              continue;
            }
            return response;
          }
          
          // أخطاء الخادم - إعادة المحاولة
          if (response.statusCode == 500 ||
              response.statusCode == 502 ||
              response.statusCode == 503 ||
              response.statusCode == 504) {
            if (attempt >= maxAttemptsPerKey) {
              if (_switchToNextKey()) {
                attempt = 0;
                continue;
              }
              return response;
            }
          } else if (response.statusCode == 200) {
            return response; // نجاح
          } else {
            // أي خطأ آخر (400, 404, etc) - تبديل فوري
            debugPrint('⚠️ Gemini: خطأ عام (${response.statusCode}) للمفتاح ${_currentKeyIndex + 1}');
            if (_switchToNextKey()) {
              attempt = 0;
              continue;
            }
            return response;
          }
        } on TimeoutException catch (_) {
          debugPrint('⏱️ Gemini: انتهت المهلة للمفتاح ${_currentKeyIndex + 1}');
          if (attempt >= maxAttemptsPerKey) {
            if (!_switchToNextKey()) rethrow;
            attempt = 0;
          }
        } on SocketException catch (_) {
          debugPrint('🌐 Gemini: خطأ في الاتصال');
          if (attempt >= maxAttemptsPerKey) {
            if (!_switchToNextKey()) rethrow;
            attempt = 0;
          }
        }

        // تراجع أسي
        final delayMs = math.pow(2, attempt).toInt() * 300;
        final jitter = math.Random().nextInt(200);
        await Future.delayed(Duration(milliseconds: delayMs + jitter));
      }
      
      // إذا وصلنا هنا، فشلت كل المحاولات مع المفتاح الحالي
      if (!_switchToNextKey()) {
        throw const HttpException('فشلت جميع مفاتيح Gemini API');
      }
    }
  }
  
  /// إعادة تعيين لاستخدام المفتاح الأول
  void resetToFirstKey() {
    _currentKeyIndex = 0;
  }
  
  /// الحصول على فهرس المفتاح الحالي
  int get currentKeyIndex => _currentKeyIndex;
  
  /// عدد المفاتيح المتاحة
  int get totalKeys => _apiKeys.length;

  /// إرسال رسالة نصية إلى Gemini والحصول على رد
  Future<String> sendMessage(String message, {List<String>? conversationHistory}) async {
    debugPrint('🤖 Gemini: إرسال رسالة...');
    
    final contents = <Map<String, dynamic>>[];
    
    if (conversationHistory != null && conversationHistory.isNotEmpty) {
      for (var i = 0; i < conversationHistory.length; i++) {
        contents.add({
          'role': i % 2 == 0 ? 'user' : 'model',
          'parts': [{'text': conversationHistory[i]}]
        });
      }
    }
    
    contents.add({
      'role': 'user',
      'parts': [{'text': message}]
    });
    
    final requestBody = {
      'contents': contents,
      'generationConfig': {
        'temperature': 0.7,
        'topK': 40,
        'topP': 0.95,
        'maxOutputTokens': 1024,
      },
    };

    final response = await _postWithRetry(body: requestBody);

    if (response.statusCode != 200) {
      debugPrint('❌ Gemini: خطأ ${response.statusCode}');
      throw HttpException('Gemini error: ${response.statusCode} ${response.body}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = decoded['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      debugPrint('❌ Gemini: لا توجد نتائج');
      return '';
    }
    final content = candidates.first['content'] as Map<String, dynamic>? ?? const {};
    final parts = content['parts'] as List? ?? [];
    if (parts.isEmpty) {
      debugPrint('❌ Gemini: رد فارغ');
      return '';
    }
    final text = parts.first['text'] as String? ?? '';
    
    debugPrint('✅ Gemini: تم استلام الرد (${text.length} حرف)');
    return text;
  }

  Future<String> extractTextFromPrompt(String prompt) async {
    final requestBody = {
      'contents': [
        {
          'parts': [{'text': prompt}]
        }
      ],
      'generationConfig': {
        'response_mime_type': 'application/json'
      }
    };

    final response = await _postWithRetry(body: requestBody);

    if (response.statusCode != 200) {
      throw HttpException('Gemini error: ${response.statusCode} ${response.body}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = decoded['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) return '';
    final content = candidates.first['content'] as Map<String, dynamic>? ?? const {};
    final parts = content['parts'] as List? ?? [];
    if (parts.isEmpty) return '';
    return parts.first['text'] as String? ?? '';
  }

  String _buildInvoiceExtractionPrompt({List<Map<String, dynamic>>? products}) {
    final productsJson = products != null && products.isNotEmpty
        ? jsonEncode(products)
        : '[]';
    
    return '''أنت محاسب ذكي خبير في تحليل الفواتير التجارية العراقية. تعمل كإنسان يقرأ الفاتورة ويبحث عن المنتجات في قاعدة البيانات.

## مهمتك الأساسية:
1. اقرأ صورة الفاتورة واستخرج كل المنتجات بدقة
2. لكل منتج في الفاتورة، ابحث عن أقرب تطابق في قائمة المنتجات أدناه
3. استخدم اسم المنتج من القاعدة (وليس من الفاتورة) إذا وجدت تطابق

## قائمة المنتجات الموجودة في قاعدة البيانات:
$productsJson

## كيف تُطابق المنتجات (تعلم من البيانات):

### الخطوة 1: حلل أسماء المنتجات في القاعدة
انظر للأسماء الموجودة وافهم التنسيق المستخدم. مثلاً إذا رأيت:
- "سيمنس 2×1.5 بيرلي" → التنسيق هو: [نوع] [عدد×مقاس] [ماركة]
- "فلكس 3×2.5 ناشيونال" → نفس التنسيق

### الخطوة 2: استخرج العناصر من اسم المنتج في الفاتورة
مثال: "Berly 80M 1.5*2 سيمس" يحتوي على:
- ماركة: Berly (بالإنجليزي)
- طول اللفة: 80M (يُحذف - ليس جزء من الاسم)
- مقاس: 1.5*2
- نوع: سيمس

### الخطوة 3: طابق مع القاعدة
ابحث عن منتج يحتوي على نفس العناصر (ماركة + نوع + مقاس)

## قواعد أساسية ثابتة:

### 1. طول اللفة يُحذف دائماً:
- 80M, 90M, 100M, 250M, 80 متر, 90 متر → تُحذف من الاسم
- هذه أطوال اللفات وليست جزء من اسم المنتج

### 2. ترتيب المقاس قد يكون معكوساً:
- في الفاتورة: 1.5*2 (مقاس×عدد)
- في القاعدة: 2×1.5 (عدد×مقاس)
- المهم: نفس الأرقام = نفس المنتج

### 3. التعبئة والكميات تُحذف:
- "كوب ماء تعبئة 20" → "كوب ماء" (التعبئة = عدد القطع في الكرتون، ليست جزء من الاسم)
- "صابون تعبئة 12" → "صابون"
- "درزن", "شدة", "كرتون", "باكيت" → تُحذف من الاسم عند المطابقة

### 3. الترجمة بين الإنجليزي والعربي:
ابحث عن الكلمات المتشابهة صوتياً:
- Berly/BERLY ≈ بيرلي
- Flex/FLEX ≈ فلكس  
- National ≈ ناشيونال
- Pioneer ≈ بايونير
- SIMS/Siemens/سيمس ≈ سيمنس

### 4. الرموز المختصرة:
- B = بيرلي (Berly)
- XW/W = سيمنس
- F = فلكس
- مثال: B2-4-80XW = بيرلي 2×4 سيمنس 80 متر

## البنية المطلوبة (JSON فقط):
{
  "invoice_date": "YYYY-MM-DD",
  "invoice_number": "",
  "currency": "IQD",
  "line_items": [
    {
      "name": "اسم المنتج من قاعدة البيانات (إذا وُجد تطابق) أو الاسم المُنظف",
      "original_name": "الاسم الأصلي كما في الفاتورة بالضبط",
      "qty": 0,
      "price": 0,
      "amount": 0,
      "matched_product_id": null,
      "old_cost_price": null,
      "is_new_product": false,
      "confidence": 0.0,
      "reason": "شرح المطابقة"
    }
  ],
  "totals": {"subtotal": 0, "discount": 0, "grand_total": 0},
  "amount_paid": 0,
  "remaining": 0,
  "status": "نقد|دين"
}

## قواعد الحقول:

### confidence (0.0 - 1.0):
- 0.90-1.0: تطابق مؤكد (كل العناصر متطابقة)
- 0.70-0.89: تطابق جيد (معظم العناصر متطابقة)
- 0.50-0.69: تطابق محتمل (بعض العناصر متطابقة)
- أقل من 0.50: منتج جديد

### reason (مهم جداً):
اشرح بالعربي كيف طابقت المنتج:
- "تطابق: Berly=بيرلي، سيمس=سيمنس، 1.5*2=2×1.5"
- "منتج جديد: لم أجد ماركة X في القاعدة"

### is_new_product:
- true: إذا confidence < 0.50 أو لم تجد تطابق
- false: إذا وجدت تطابق في القاعدة

### matched_product_id و old_cost_price:
- إذا وجدت تطابق: استخدم id و cost_price من القاعدة
- إذا منتج جديد: اتركهم null

## تنبيهات:
- أرجع JSON فقط بدون أي نص إضافي
- اقرأ الأرقام بدقة (الكمية، السعر، المبلغ)
- إذا السعر غير واضح: احسبه من المبلغ ÷ الكمية
- الأسعار بالدينار العراقي (IQD)''';
  }


  Future<Map<String, dynamic>> extractInvoiceOrReceiptStructured({
    required List<int> fileBytes,
    required String fileMimeType,
    required String extractType,
    List<Map<String, dynamic>>? products,
  }) async {
    final base64Data = base64Encode(fileBytes);

    final prompt = extractType == 'invoice'
        ? _buildInvoiceExtractionPrompt(products: products)
        : 'حلل هذا السند وأعد JSON فقط بالمفاتيح: {"receipt_date":"YYYY-MM-DD","receipt_number":"","amount":0,"payment_method":"نقد","currency":"IQD","notes":""}. لا تُدرج أي نص آخر غير JSON.';

    final requestBody = {
      'contents': [
        {
          'parts': [
            {'text': prompt},
            {
              'inline_data': {
                'mime_type': fileMimeType,
                'data': base64Data,
              }
            }
          ]
        }
      ],
      'generationConfig': {
        'response_mime_type': 'application/json'
      }
    };

    final response = await _postWithRetry(body: requestBody);

    if (response.statusCode != 200) {
      throw HttpException('Gemini error: ${response.statusCode} ${response.body}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = decoded['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) return {};
    
    final content = candidates.first['content'] as Map<String, dynamic>? ?? const {};
    final parts = content['parts'] as List? ?? [];
    if (parts.isEmpty) return {};
    
    final text = parts.first['text'] as String? ?? '{}';
    
    debugPrint('📄 Gemini Raw Response:');
    debugPrint(text);
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    
    try {
      final extracted = jsonDecode(text) as Map<String, dynamic>;
      if (extractType == 'invoice') {
        final items = extracted['line_items'] ?? extracted['items'] ?? [];
        debugPrint('📦 عدد العناصر المستخرجة: ${items is List ? items.length : 0}');
      }
      return extracted;
    } catch (e) {
      debugPrint('⚠️ فشل تحليل JSON من Gemini: $e');
      return {'raw': text};
    }
  }
}
