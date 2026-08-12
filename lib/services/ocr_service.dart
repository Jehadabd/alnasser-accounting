import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';
import 'dart:ui' as ui;
import 'dart:convert';
import 'dart:math' as math;
import 'vision_service.dart';

class OcrService {
  final _visionService = VisionService();
  
  Future<String> extractText(File file) async {
    await _visionService.loadModel();
    try {
      if (Platform.isWindows) {
        return await _extractWindows(file);
      } else if (Platform.isAndroid || Platform.isIOS) {
        return await _extractMobile(file);
      }
    } catch (e) {
      debugPrint('OCR Error: $e');
      return "Error extracting text: $e";
    }
    return "";
  }

  Future<String> _extractWindows(File file) async {
    try {
      String exeDir = File(Platform.resolvedExecutable).parent.path;
      String tesseractDir = '$exeDir\\tesseract';
      String tesseractPath = '$tesseractDir\\tesseract.exe';
      
      bool isBundled = await File(tesseractPath).exists();
      if (!isBundled) {
        try {
           final check = await Process.run('tesseract', ['--version']);
           if (check.exitCode == 0) tesseractPath = 'tesseract';
           else return "Error: Tesseract not found.";
        } catch (e) {
           return "Error: Tesseract not found at $tesseractPath and not in PATH.";
        }
      }

      final tempDir = Directory.systemTemp;
      File processedFile;
      
      if (file.path.toLowerCase().endsWith('.pdf')) {
        try {
           final doc = await PdfDocument.openFile(file.path);
           final page = doc.pages[0];
           
           // High DPI rendering for Geometry Accuracy
           final pdfImage = await page.render(
             width: (page.width * 4).toInt(), 
             height: (page.height * 4).toInt(),
           );
           
           if (pdfImage == null) throw Exception("Failed to render PDF page");
           
           final ui.Image image = await pdfImage.createImage();
           final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
           if (byteData == null) throw Exception("Failed to convert PDF page to PNG data");
           
           final safeName = 'ocr_pdf_input_${DateTime.now().millisecondsSinceEpoch}.png';
           final safePath = '${tempDir.path}\\$safeName';
           processedFile = File(safePath);
           await processedFile.writeAsBytes(byteData.buffer.asUint8List());
           
           image.dispose();
        } catch (e) {
           debugPrint("PDF Conversion Error: $e");
           return "Error Converting PDF: $e";
        }
      } else {
         final safeName = 'ocr_input_${DateTime.now().millisecondsSinceEpoch}.${file.uri.pathSegments.last.split('.').last}';
         final safePath = '${tempDir.path}\\$safeName';
         processedFile = await file.copy(safePath);
      }

      Map<String, String> env = {};
      if (isBundled) {
         env['TESSDATA_PREFIX'] = '$tesseractDir\\tessdata'; 
      }

      // NO PSM 6 - Defaulting to standard page segmentation
      final result = await Process.run(
        tesseractPath, 
        [
          processedFile.path,
          'stdout',
          '-l', 'ara+eng', // Arabic + English
          'hocr' 
        ],
        environment: env,
        stdoutEncoding: utf8,
      );
      
      if (await processedFile.exists()) await processedFile.delete(); 

      if (result.exitCode != 0) {
        if (result.stderr.toString().contains("Failed loading language")) {
            return "Error: Language data missing (ara.traineddata).";
        }
        return "Tesseract Error: ${result.stderr}";
      }

      String output = result.stdout.toString();
      return output.isEmpty ? "Tesseract returned empty output." : output;

    } catch (e) {
      debugPrint("OCR Process Error: $e");
      return "Native OCR Error: $e";
    }
  }

  Future<String> _extractMobile(File file) async {
    return "Mobile OCR Not Implemented Yet";
  }

  // ==============================================================================
  // 🧠 HUMAN-LIKE INVOICE UNDERSTANDING (Geometric Pipeline)
  // Logic: Image -> HOCR -> Layout Analysis (Rows/Cols) -> Role Assignment -> Assembly
  // ==============================================================================

  Future<List<Map<String, dynamic>>> parseInvoiceText(String xmlOutput, {File? imageFile}) async {
    if (!xmlOutput.contains("ocr_page")) return [];
    
    // 1. Vision: Extract Objects (Words + Boxes)
    List<OCRWord> objects = _parseHocrWords(xmlOutput);
    if (objects.isEmpty) return [];

    // --- AI VISION LAYER 🧠 ---
    try {
      List<VisionToken> aiTokens = await _visionService.analyzeDocument(objects, imageFile: imageFile);
      if (aiTokens.isNotEmpty) {
        debugPrint("AI Vision found ${aiTokens.length} tokens. (Merging logic TBD)");
        // return _parseAiTokens(aiTokens); // Future Step
      }
    } catch (e) {
      debugPrint("AI Prediction Failed: $e");
    }
    // ---------------------------

    double pageWidth = 0;
    // Estimate page width from max X
    for (var o in objects) if ((o.x + o.width) > pageWidth) pageWidth = o.x + o.width;
    
    debugPrint("Pipeline: Vision OK. Objects: ${objects.length}, PageWidth: $pageWidth");

    // 2. Geometry: Detect Rows (Y-Clustering)
    List<List<OCRWord>> rows = _groupRows(objects, threshold: 15); // 15px threshold
    debugPrint("Pipeline: Geometry OK. Rows detected: ${rows.length}");

    // 3. Geometry: Detect Columns (X-Histogram) - Optional for advanced logic,
    // but here we use relative role assignment per row as requested.
    List<double> colCentroids = _detectColumnCentroids(objects, pageWidth);
    debugPrint("Pipeline: Columns Detected: $colCentroids");
    
    List<Map<String, dynamic>> items = [];

    // 4. Logic: Role Assignment & Assembly
    for (var row in rows) {
      // Filter Header/Summary Rows using Keywords
      String rowText = row.map((e) => e.text).join(' ');
      if (_isSummaryRow(rowText)) continue;

      var parsedItem = _parseRowGeometric(row, pageWidth, colCentroids);
      if (parsedItem != null) {
        // Post-Assembly Verification
        if (_validateMath(parsedItem)) {
          items.add(parsedItem);
          debugPrint("✅ Item: ${parsedItem['name']} (Q:${parsedItem['quantity']} P:${parsedItem['price']} T:${parsedItem['total']})");
        } else {
             // Fallback: If math fails but we have Name + Price, maybe Qty is 1?
             if (parsedItem['quantity'] == null && parsedItem['price'] != null) {
                parsedItem['quantity'] = 1.0;
                parsedItem['total'] = parsedItem['price'];
                items.add(parsedItem);
                debugPrint("⚠️ Item (Assumed Qty=1): ${parsedItem['name']}");
             }
        }
      }
    }

    return items;
  }

  // --- Phase 1: Vision (HOCR Parsing including Images) ---
  List<OCRWord> _parseHocrWords(String hocrXml) {
    List<OCRWord> words = [];
    
    // Words
    final spanPattern = RegExp(r'<span class=.ocrx_word.[^>]*>([^<]+)</span>');
    final matches = spanPattern.allMatches(hocrXml);
    for (var m in matches) {
      _addWordFromBbox(words, m.group(0) ?? '', m.group(1) ?? '');
    }
    
    // Images/Photos (Hidden Text)
    final photoPattern = RegExp(r"<(div|span) class=['\u0022]ocr_photo['\u0022][^>]*>");
    final photoMatches = photoPattern.allMatches(hocrXml);
    for (var m in photoMatches) {
       _addWordFromBbox(words, m.group(0)!, "[[IMAGE]]"); 
    }
    return words;
  }
  
  void _addWordFromBbox(List<OCRWord> words, String elementHtml, String text) {
      final bboxMatch = RegExp(r"bbox (\d+) (\d+) (\d+) (\d+)").firstMatch(elementHtml);
      if (bboxMatch != null) {
        double x1 = double.parse(bboxMatch.group(1)!);
        double y1 = double.parse(bboxMatch.group(2)!);
        double x2 = double.parse(bboxMatch.group(3)!);
        double y2 = double.parse(bboxMatch.group(4)!);
        words.add(OCRWord(text, x1, y1, x2 - x1, y2 - y1));
      }
  }

  // --- Phase 2: Row Grouping ---
  List<List<OCRWord>> _groupRows(List<OCRWord> boxes, {double threshold = 15}) {
    // Sort by Y first
    boxes.sort((a, b) => a.y.compareTo(b.y));
    
    List<List<OCRWord>> rows = [];
    for (var box in boxes) {
      bool placed = false;
      for (var row in rows) {
        // Check if box overlaps vertically with the row's average/first element
        // Simple heuristic: compare with first element of row
        if ((row.first.y - box.y).abs() < threshold) {
          row.add(box);
          placed = true;
          break;
        }
      }
      if (!placed) {
        rows.add([box]);
      }
    }
    
    // Sort each row by X (Left to Right)
    for (var row in rows) {
      row.sort((a, b) => a.x.compareTo(b.x));
    }
    return rows;
  }

  // --- Phase 3: Column Detection (Centroids) ---
  List<double> _detectColumnCentroids(List<OCRWord> words, double pageWidth) {
    final Map<int, int> histogram = {};
    for (var w in words) {
       int center = (w.x + w.width / 2).round();
       int bin = (center / 30).round() * 30; // 30px binning
       histogram[bin] = (histogram[bin] ?? 0) + 1;
    }
    List<double> peaks = [];
    histogram.forEach((bin, count) {
       if (count > 5) peaks.add(bin.toDouble());
    });
    peaks.sort();
    return peaks;
  }

  // --- Phase 4 & 5: Classification & Assembly ---
  Map<String, dynamic>? _parseRowGeometric(List<OCRWord> row, double pageWidth, List<double> colCentroids) {
     String name = "";
     double? qty;
     double? price;
     double? total;
     
     // 1. Classification Loop
     List<_ClassifiedBox> classified = [];
     for (var box in row) {
        if (box.text == "[[IMAGE]]") {
           classified.add(_ClassifiedBox(box, _Role.IMAGE));
           continue;
        }

        // Clean text
        String clean = box.text.replaceAll(',', '.').replaceAll(RegExp(r'[^\d.]'), '');
        bool isNumber = double.tryParse(clean) != null && clean.isNotEmpty;
        
        // Geometric Logic: Position Ratio
        // For Arabic: Text is roughly Right (> 0.4), Numbers Left (< 0.4) usually, OR mixed.
        // We rely on Content + Context first.
        
        if (isNumber) {
           double val = double.parse(clean);
           // Heuristic: Qty is usually integer-like and small. Price/Total are money.
           // Position Heuristic:
           // If we have multiple numbers, we need to distinguish.
           classified.add(_ClassifiedBox(box, _Role.NUMBER, value: val));
        } else {
           // Skip short noise
           if (box.text.trim().length > 1) {
             classified.add(_ClassifiedBox(box, _Role.TEXT));
           }
        }
     }
     
     // 2. Role Assignment (Constraint Satisfaction)
     // We look for patterns: [NUMBER, NUMBER, NUMBER] or [NUMBER, NUMBER] in the row
     List<_ClassifiedBox> numbers = classified.where((c) => c.role == _Role.NUMBER).toList();
     List<_ClassifiedBox> texts = classified.where((c) => c.role == _Role.TEXT || c.role == _Role.IMAGE).toList();
     
     if (texts.isEmpty && numbers.isEmpty) return null;
     if (numbers.length < 2 && numbers.length > 0) {
        // Only 1 number? Probably Price or Total.
        // If we assumed Qty=1, we can match.
        price = numbers.first.value;
     } else if (numbers.length >= 2) {
        // Try all permutations for Math Match
        // Target: Q * P = T
        bool match = false;
        // Search backwards (Right to Left often has Price/Total in Arabic/English hybrid)
        // Or just brute force triplet
        if (numbers.length >= 3) {
           for (var c in numbers) { // Candidate C (Total)
             for (var a in numbers) { // Candidate A (Qty)
                if (a == c) continue;
                for (var b in numbers) { // Candidate B (Price)
                   if (b == c || b == a) continue;
                   if ((a.value! * b.value! - c.value!).abs() < 0.5) {
                      qty = a.value;
                      price = b.value;
                      total = c.value;
                      match = true;
                      break;
                   }
                }
                if (match) break;
             }
             if (match) break;
           }
        }
        
        // Fallback: 2 numbers (Qty, Price) or (Price, Total)
        if (!match && numbers.length == 2) {
           // Heuristic: Smaller is Qty, Larger is Price/Total
           numbers.sort((a, b) => a.value!.compareTo(b.value!));
           double small = numbers[0].value!;
           double big = numbers[1].value!;
           
           if (small < 50 && (small == small.roundToDouble())) {
              qty = small;
              price = big; // Assume big is unit price
              total = small * big;
           } else {
              // Maybe Price and Total? -> Qty = 1
              price = small;
              total = big;
              qty = 1.0;
           }
        }
     }
     
     // 3. Name Assembly
     if (texts.isNotEmpty) {
        name = texts.map((e) {
             if (e.role == _Role.IMAGE) return "منتج (صورة)";
             return e.box.text;
        }).join(" ");
     } else {
        // No text name found? 
        return null; 
     }

     return {
        'name': name.trim(),
        'quantity': qty,
        'price': price,
        'total': total,
     };
  }
  
  bool _validateMath(Map<String, dynamic> item) {
    if (item['quantity'] == null || item['price'] == null) return false;
    // Basic sanity
    if (item['quantity'] <= 0) return false;
    return true; 
  }

  bool _isSummaryRow(String text) {
    final keywords = RegExp(r'(total|vat|tax|summary|subtotal|discount|paid|net|due|الاجمالي|المجموع|الخصم|الصافي|المدفوع|المتبقي)', caseSensitive: false);
    return keywords.hasMatch(text);
  }
}

enum _Role { TEXT, NUMBER, IMAGE }

class _ClassifiedBox {
  final OCRWord box;
  final _Role role;
  final double? value;
  
  _ClassifiedBox(this.box, this.role, {this.value});
}

class OCRWord {
  final String text;
  final double x, y, width, height;
  OCRWord(this.text, this.x, this.y, this.width, this.height);
}
