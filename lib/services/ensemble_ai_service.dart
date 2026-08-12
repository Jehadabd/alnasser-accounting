import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';
import 'dart:ui' as ui;
import 'template_service.dart'; 
import 'ocr_service.dart';
import 'vision_service.dart';
import 'python_service.dart';

/// 🧠 Ensemble AI Service
/// Priority: Table Extractor (OpenCV+EasyOCR) → LayoutLMv3 → Fallback
class EnsembleAIService {
  final _ocrService = OcrService();
  final _visionService = VisionService();
  final _templateService = TemplateService();
  final _pythonService = PythonService();

  Future<Map<String, dynamic>> extractInvoiceData(File file) async {
    debugPrint("🧠 Ensemble: Starting Smart Pipeline for ${file.path}");
    File workingFile = file;
    bool isTempFile = false;

    try {
      // 0. Pre-processing: Convert PDF to Image if needed (for Flutter-side fallback)
      if (file.path.toLowerCase().endsWith('.pdf')) {
         debugPrint("📄 PDF Detected. Converting to Image...");
         try {
           workingFile = await _convertPdfToImage(file);
           isTempFile = true;
           debugPrint("✅ Converted to: ${workingFile.path}");
         } catch (e) {
           return {"error": "PDF Conversion Failed: $e"};
         }
      }

      // ═══════════════════════════════════════════════════════════════
      // 1. 🥇 PRIMARY: Table Extractor (Python - OpenCV + EasyOCR)
      //    This is the most reliable method for structured invoices
      // ═══════════════════════════════════════════════════════════════
      debugPrint("🥇 Trying PRIMARY: Table Extractor (OpenCV)...");
      
      Map<String, dynamic> tableResult = await _pythonService.extractTable(
        file.path.toLowerCase().endsWith('.pdf') ? file : workingFile
      );
      
      if (tableResult['status'] == 'success' && 
          tableResult['items'] != null &&
          (tableResult['items'] as List).isNotEmpty) {
        debugPrint("✅ Table Extractor SUCCESS: ${(tableResult['items'] as List).length} items found");
        
        // Convert to standard format
        Map<String, dynamic> result = _convertTableResult(tableResult);
        result = _verifyMathematics(result);
        return result;
      }
      
      debugPrint("⚠️ Table Extractor returned 0 items or failed: ${tableResult['error'] ?? 'no items'}");

      // ═══════════════════════════════════════════════════════════════
      // 2. 🥈 FALLBACK: LayoutLMv3 + OCR (Legacy Pipeline)
      // ═══════════════════════════════════════════════════════════════
      debugPrint("🥈 Falling back to Legacy Pipeline (LayoutLMv3 + OCR)...");
      
      // Load Knowledge Base
      await _templateService.loadTemplates();
  
      // OCR Layer
      String hocrOutput = await _ocrService.extractText(workingFile);
      if (hocrOutput.isEmpty || hocrOutput.contains("Error")) {
        // If OCR also failed but table extractor had metadata...
        if (tableResult['status'] == 'success') {
          return _convertTableResult(tableResult);
        }
        return {"error": "OCR Phase Failed: $hocrOutput"};
      }
  
      // Template Matching
      InvoiceTemplate? matchedTemplate = _templateService.findMatchingTemplate(hocrOutput);
      List<OCRWord> words = _parseHocr(hocrOutput);

      if (matchedTemplate != null) {
         debugPrint("🚀 Fast-Path: Using Template '${matchedTemplate.name}'");
      }
  
      // Vision AI (Dart/ONNX)
      List<VisionToken> aiTokens = [];
      try {
        await _visionService.loadModel(); 
        aiTokens = await _visionService.analyzeDocument(words, imageFile: workingFile);
      } catch (e) {
        debugPrint("⚠️ Vision Service Error: $e");
      }

      // LayoutLMv3 (Python Legacy)
      Map<String, dynamic> pythonLegacyResult = {};
      try {
        pythonLegacyResult = await _pythonService.analyzeImage(workingFile);
      } catch (e) {
        debugPrint("⚠️ Python Legacy Error: $e");
      }

      // Fusion
      Map<String, dynamic> result = _mergeAndStructure(words, aiTokens, matchedTemplate);

      // Enrich with Python LayoutLMv3 data
      if (pythonLegacyResult['status'] == 'success') {
          _fusePythonData(result, pythonLegacyResult);
      }

      // Also enrich with Table Extractor metadata if available
      if (tableResult['status'] == 'success') {
        _fuseTableMetadata(result, tableResult);
      }
  
      result = _verifyMathematics(result);
      return result;

    } catch (e) {
      return {"error": "Pipeline Error: $e"};
    } finally {
      if (isTempFile && await workingFile.exists()) {
        try {
          await workingFile.delete();
          debugPrint("🧹 Temp file cleaned up.");
        } catch (e) { /* ignore */ }
      }
    }
  }

  /// Convert Table Extractor result to standard app format
  Map<String, dynamic> _convertTableResult(Map<String, dynamic> tableResult) {
    List<Map<String, dynamic>> items = [];
    
    if (tableResult['items'] != null) {
      for (var item in tableResult['items']) {
        items.add({
          "name": (item['description'] ?? '').toString(),
          "qty": _toDouble(item['quantity']),
          "price": _toDouble(item['unit_price']),
          "line_total": _toDouble(item['total_price']),
          "unit": (item['unit'] ?? '').toString(),
          "confidence": 0.95,
        });
      }
    }
    
    return {
      "vendor": (tableResult['vendor_name'] ?? '').toString(),
      "invoice_number": (tableResult['invoice_number'] ?? '').toString(),
      "date": (tableResult['invoice_date'] ?? '').toString(),
      "items": items,
      "total": _toDouble(tableResult['total_amount']),
      "discount": _toDouble(tableResult['discount']),
      "net": _toDouble(tableResult['net_amount']),
      "currency": "IQD",
      "detection_method": tableResult['detection_method'] ?? 'unknown',
    };
  }

  /// Merge Table Extractor metadata into legacy result
  void _fuseTableMetadata(Map<String, dynamic> result, Map<String, dynamic> tableResult) {
    if (tableResult['vendor_name'] != null && tableResult['vendor_name'].toString().isNotEmpty) {
      if (result['vendor'] == 'غير محدد' || result['vendor'] == '') {
        result['vendor'] = tableResult['vendor_name'];
      }
    }
    if (tableResult['invoice_date'] != null && tableResult['invoice_date'].toString().isNotEmpty) {
      if (result['date'] == null || result['date'] == '') {
        result['date'] = tableResult['invoice_date'];
      }
    }
    if (tableResult['invoice_number'] != null && tableResult['invoice_number'].toString().isNotEmpty) {
      if (result['invoice_number'] == null || result['invoice_number'] == '') {
        result['invoice_number'] = tableResult['invoice_number'];
      }
    }
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString().replaceAll(',', '')) ?? 0.0;
  }

  /// Merges Python LayoutLMv3 data into the result map
  void _fusePythonData(Map<String, dynamic> result, Map<String, dynamic> pythonData) {
      debugPrint("🧬 Fusing Legacy AI Data... RAW: $pythonData");

      if (pythonData['vendor_name'] != null && pythonData['vendor_name'].toString().isNotEmpty) {
        result['vendor'] = pythonData['vendor_name'];
      }
      
      if (pythonData['invoice_date'] != null && pythonData['invoice_date'].toString().isNotEmpty) {
        result['date'] = pythonData['invoice_date'];
      }
      
      if (pythonData['total_amount'] != null) {
         double? val = double.tryParse(pythonData['total_amount'].toString());
         if (val != null && val > 0) result['total'] = val;
      }
  }

  /// Helper to convert PDF Page 1 to Image (High-Res)
  Future<File> _convertPdfToImage(File pdfFile) async {
      try {
           final doc = await PdfDocument.openFile(pdfFile.path);
           final page = doc.pages[0];
           
           final pdfImage = await page.render(
             width: (page.width * 3).toInt(), 
             height: (page.height * 3).toInt(),
             backgroundColor: Colors.white,
           );
           
           if (pdfImage == null) throw Exception("Failed to render PDF page");
           
           final ui.Image image = await pdfImage.createImage();
           final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
           if (byteData == null) throw Exception("Failed to convert PDF page to PNG data");
           
           final tempDir = Directory.systemTemp;
           final safeName = 'ensemble_pdf_${DateTime.now().millisecondsSinceEpoch}.png';
           final tempFile = File('${tempDir.path}\\$safeName');
           
           await tempFile.writeAsBytes(byteData.buffer.asUint8List());
           image.dispose();
           
           return tempFile;
      } catch (e) {
         throw Exception("PDF Render Logic Error: $e");
      }
  }

  List<OCRWord> _parseHocr(String hocr) {
    List<OCRWord> words = [];
    final spanPattern = RegExp(r'<span class=.ocrx_word.[^>]*>([^<]+)</span>');
    final matches = spanPattern.allMatches(hocr);
    final bboxPattern = RegExp(r"bbox (\d+) (\d+) (\d+) (\d+)");

    for (var m in matches) {
      String elementHtml = m.group(0) ?? '';
      String text = m.group(1) ?? '';
      final bboxMatch = bboxPattern.firstMatch(elementHtml);
      if (bboxMatch != null) {
        double x = double.parse(bboxMatch.group(1)!);
        double y = double.parse(bboxMatch.group(2)!);
        double w = double.parse(bboxMatch.group(3)!) - x;
        double h = double.parse(bboxMatch.group(4)!) - y;
        words.add(OCRWord(text, x, y, w, h));
      }
    }
    return words;
  }

  Map<String, dynamic> _mergeAndStructure(List<OCRWord> words, List<VisionToken> tokens, InvoiceTemplate? template) {
    Map<String, dynamic> extracted = {
      "vendor": "غير محدد",
      "invoice_number": "",
      "date": "",
      "items": [],
      "total": 0.0,
      "currency": "IQD"
    };

    if (template != null) {
      extracted["vendor"] = template.vendorName;
      extracted["is_template_match"] = true;
    } else {
       List<VisionToken> vendorTokens = tokens.where((t) => t.label.contains("VENDOR")).toList();
       if (vendorTokens.isNotEmpty) {
         extracted["vendor"] = vendorTokens.map((t) => t.text).join(" ");
       }
    }

    List<VisionToken> numTokens = tokens.where((t) => t.label.contains("INVOICE_NUM")).toList();
    if (numTokens.isNotEmpty) {
      extracted["invoice_number"] = numTokens.first.text;
    }

    _groupItems(tokens, extracted);

    return extracted;
  }

  void _groupItems(List<VisionToken> tokens, Map<String, dynamic> result) {
    List<VisionToken> tableTokens = tokens.where((t) => 
      t.label == "B-DESC" || t.label == "I-DESC" ||
      t.label == "B-QTY" || t.label == "I-QTY" ||
      t.label == "B-PRICE" || t.label == "I-PRICE" ||
      t.label == "B-LINE_TOTAL" || t.label == "I-LINE_TOTAL"
    ).toList();

    if (tableTokens.isEmpty) return;

    tableTokens.sort((a, b) => a.rect.top.compareTo(b.rect.top));

    List<List<VisionToken>> rows = [];
    if (tableTokens.isNotEmpty) {
      List<VisionToken> currentRow = [tableTokens.first];
      rows.add(currentRow);
      
      double avgHeight = tableTokens.map((t) => t.rect.height).reduce((a, b) => a + b) / tableTokens.length;
      double rowThreshold = avgHeight * 0.6; 

      for (int i = 1; i < tableTokens.length; i++) {
        VisionToken t = tableTokens[i];
        VisionToken prev = currentRow.last;
        
        double centerYCurrent = t.rect.top + t.rect.height/2;
        double centerYPrev = prev.rect.top + prev.rect.height/2;

        if ((centerYCurrent - centerYPrev).abs() < rowThreshold) {
           currentRow.add(t);
        } else {
           currentRow = [t];
           rows.add(currentRow);
        }
      }
    } else {
       return; 
    }

    for (var row in rows) {
      row.sort((a, b) => a.rect.left.compareTo(b.rect.left)); 

      String name = "";
      double qty = 0;
      double price = 0;
      double lineTotal = 0;
      
      var descTokens = row.where((t) => t.label.contains("DESC")).toList();
      if (descTokens.isNotEmpty) {
        name = descTokens.map((t) => t.text).join(" ");
      } 
      
      List<VisionToken> potentialNumbers = row.where((t) => 
         t.label.contains("QTY") || t.label.contains("PRICE") || t.label.contains("TOTAL") ||
         (t.label == "O" && RegExp(r'^\d*[.,]?\d+$').hasMatch(t.text))
      ).toList();

      for (var t in potentialNumbers) {
         double val = double.tryParse(t.text.replaceAll(RegExp(r'[^\d.]'), '')) ?? 0.0;
         if (val == 0) continue;

         if (t.label.contains("QTY")) qty = val;
         else if (t.label.contains("PRICE")) price = val;
         else if (t.label.contains("LINE_TOTAL")) lineTotal = val;
         else if (t.label == "O") {
            if (val < 50 && val % 1 == 0 && qty == 0) qty = val;
            else if (price == 0) price = val;
         }
      }

      if (qty == 0 && price > 0 && lineTotal > 0) {
        qty = (lineTotal / price).roundToDouble();
      }
      if (lineTotal == 0 && qty > 0 && price > 0) {
        lineTotal = qty * price;
      }
      if (qty == 0 && price > 0) {
        qty = 1;
        if (lineTotal == 0) lineTotal = price;
      }

      if (name.length > 2 || price > 0) {
         result["items"].add({
           "name": name.isEmpty ? "منتج غير معرّف" : name,
           "qty": qty == 0 ? 1.0 : qty,
           "price": price,
           "line_total": lineTotal, 
           "confidence": 0.9
         });
      }
    }

    var totalTokens = tokens.where((t) => t.label == "B-TOTAL" || t.label == "I-TOTAL");
    if (totalTokens.isNotEmpty) {
       double maxTotal = 0.0;
       for (var t in totalTokens) {
          String s = t.text.replaceAll(RegExp(r'[^\d.]'), '');
          double val = double.tryParse(s) ?? 0.0;
          if (val > maxTotal) maxTotal = val;
       }
       if (maxTotal > result["total"]) {
         result["total"] = maxTotal;
       }
    }
  }

  /// 🛒 Product Database Matching
  Future<List<Map<String, dynamic>>> matchProducts(List<Map<String, dynamic>> items, List<dynamic> dbProducts) async {
    for (var item in items) {
       String name = item["name"].toString().toLowerCase();
       double bestScore = 0;
       dynamic matchedProduct;

       for (var p in dbProducts) {
          String pName = p['name'].toString().toLowerCase();
          double score = _calculateOverlap(name, pName);
          if (score > bestScore) {
             bestScore = score;
             matchedProduct = p;
          }
       }

       if (bestScore > 0.6) {
          item["matched_product_id"] = matchedProduct['id'];
          item["matched_name"] = matchedProduct['name'];
          item["is_new_product"] = false;
       } else {
          item["is_new_product"] = true;
       }
    }
    return items;
  }

  double _calculateOverlap(String s1, String s2) {
    var set1 = s1.split(" ").toSet();
    var set2 = s2.split(" ").toSet();
    var intersection = set1.intersection(set2);
    return intersection.length / max(set1.length, set2.length);
  }

  Map<String, dynamic> _verifyMathematics(Map<String, dynamic> data) {
    double calculatedTotal = 0.0;
    for (var item in data["items"]) {
      double itemTotal = (item["qty"] as double) * (item["price"] as double);
      // Only override line_total if it was 0
      if ((item["line_total"] as double) == 0) {
        item["line_total"] = itemTotal;
      }
      calculatedTotal += item["line_total"] as double;
    }
    
    if (data["total"] == 0.0) {
      data["total"] = calculatedTotal;
    }
    
    return data;
  }
}
