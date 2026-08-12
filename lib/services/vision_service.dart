import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:fixnum/fixnum.dart'; // Fixed: Import Int64
import 'package:image/image.dart' as img;
import 'ocr_service.dart';

/// Service responsible for running the AI Layout Understanding Model (LayoutLMv3).
class VisionService {
  OrtSession? _session;
  bool _isModelLoaded = false;

  // Labels from the fine-tuned model (standard FUNSD/CORD schema)
  static const List<String> _labels = [
    "O", "B-TOTAL", "I-TOTAL", "B-DATE", "I-DATE", "B-VENDOR", "I-VENDOR",
    "B-INVOICE_NUM", "I-INVOICE_NUM", "B-DESC", "I-DESC", "B-QTY", "I-QTY",
    "B-PRICE", "I-PRICE", "B-LINE_TOTAL", "I-LINE_TOTAL"
  ];

  Future<void> loadModel() async {
    if (_isModelLoaded) return;

    try {
      debugPrint("VisionService: Loading AI Model...");
      OrtEnv.instance.init();

      const assetName = 'assets/models/model.onnx';
      // Copy asset to temp file for ONNX Runtime
      final byteData = await rootBundle.load(assetName);
      // final tempDir = Directory.systemTemp;
      // final tempFile = File('${tempDir.path}/model.onnx');
      // await tempFile.writeAsBytes(byteData.buffer.asUint8List());

      final sessionOptions = OrtSessionOptions();
      // Use fromBuffer to avoid Windows path encoding issues (Mojibake)
      final modelBytes = byteData.buffer.asUint8List();
      _session = OrtSession.fromBuffer(modelBytes, sessionOptions);

      _isModelLoaded = true;
      debugPrint("VisionService: AI Model Loaded Successfully from Buffer! 🧠✅");

    } catch (e) {
      debugPrint("VisionService Error: Failed to load model. $e");
      // Don't crash app, just disable AI features
    }
  }

  Future<List<VisionToken>> analyzeDocument(List<OCRWord> words, {File? imageFile}) async {
    if (!_isModelLoaded || _session == null) {
      debugPrint("VisionService: Model not ready. Skipping.");
      return [];
    }

    try {
      debugPrint("VisionService: Running Inference on ${words.length} words...");

      // 1. Calculate Page Dimensions for Normalization
      double maxX = 0;
      double maxY = 0;
      for (var w in words) {
        if (w.x + w.width > maxX) maxX = w.x + w.width;
        if (w.y + w.height > maxY) maxY = w.y + w.height;
      }
      // Avoid division by zero
      if (maxX == 0) maxX = 1000;
      if (maxY == 0) maxY = 1000;

      // 2. Prepare Text/Layout Inputs
      final int batchSize = 1;
      final int seqLength = 512;

      Int64List inputIds = Int64List(batchSize * seqLength);
      Int64List attentionMask = Int64List(batchSize * seqLength);
      Int64List bboxes = Int64List(batchSize * seqLength * 4); // [x1, y1, x2, y2]

      // Fill tensors
      for (int i = 0; i < min(words.length, seqLength); i++) {
        OCRWord w = words[i];

        // Pseudo-Tokenization: Use UNK (3)
        inputIds[i] = 3;

        attentionMask[i] = 1;

        // Normalize BBox 0-1000 relative to page size
        int x1 = ((w.x / maxX) * 1000).clamp(0, 1000).toInt();
        int y1 = ((w.y / maxY) * 1000).clamp(0, 1000).toInt();
        int x2 = (((w.x + w.width) / maxX) * 1000).clamp(0, 1000).toInt();
        int y2 = (((w.y + w.height) / maxY) * 1000).clamp(0, 1000).toInt();

        int bboxIdx = i * 4;
        bboxes[bboxIdx] = x1;
        bboxes[bboxIdx + 1] = y1;
        bboxes[bboxIdx + 2] = x2;
        bboxes[bboxIdx + 3] = y2;
      }

      // 3. Prepare Image Input (Real Pixel Values)
      Float32List pixelValues;
      if (imageFile != null && await imageFile.exists()) {
         try {
           pixelValues = await _imageToTensor(imageFile);
           debugPrint("VisionService: Image processed successfully 🖼️");
         } catch (e) {
           debugPrint("VisionService: Image processing failed ($e). Using dummy.");
           pixelValues = Float32List(1 * 3 * 224 * 224);
         }
      } else {
         pixelValues = Float32List(1 * 3 * 224 * 224);
      }

      // 4. Create OrtTensors
      final inputIdsTensor = OrtValueTensor.createTensorWithDataList(inputIds, [batchSize, seqLength]);
      final maskTensor = OrtValueTensor.createTensorWithDataList(attentionMask, [batchSize, seqLength]);
      final bboxTensor = OrtValueTensor.createTensorWithDataList(bboxes, [batchSize, seqLength, 4]);
      final pixelTensor = OrtValueTensor.createTensorWithDataList(pixelValues, [batchSize, 3, 224, 224]);

      // 3. Run Inference
      final runOptions = OrtRunOptions();
      final inputs = {
        'input_ids': inputIdsTensor,
        'attention_mask': maskTensor,
        'bbox': bboxTensor,
        'pixel_values': pixelTensor
      };

      final outputs = _session!.run(runOptions, inputs);

      // 4. Decode Output (Logits -> Labels)
      final outputTensor = outputs[0];
      final outputData = outputTensor?.value as List<List<List<double>>>?;

      if (outputData == null || outputData.isEmpty) return [];

      List<VisionToken> detectedTokens = [];
      final predictions = outputData[0]; // Batch 0

      // Debug: Print first 10 RAW predictions
      debugPrint("VisionService Debug: Top 10 Raw Predictions:");
      for (int i = 0; i < min(10, words.length); i++) {
         final logits = predictions[i];
         int bestIdx = 0;
         double maxVal = -99999.0;
         for (int k = 0; k < logits.length; k++) {
           if (logits[k] > maxVal) { maxVal = logits[k]; bestIdx = k; }
         }
         debugPrint("  [$i] '${words[i].text}' -> ${_labels[bestIdx]} (${maxVal.toStringAsFixed(2)})");
      }

      for (int i = 0; i < min(words.length, seqLength); i++) {
        final logits = predictions[i];

        // ArgMax manually
        int bestIdx = 0;
        double maxVal = -99999.0;
        for (int k = 0; k < logits.length; k++) {
          if (logits[k] > maxVal) {
            maxVal = logits[k];
            bestIdx = k;
          }
        }

        final label = _labels[bestIdx];

        // Filter "O" (Outside) tags? Optional. Let's keep meaningful ones.
        if (label != 'O') {
           detectedTokens.add(VisionToken(
             text: words[i].text,
             label: label,
             confidence: 1.0, // Softmax would give real conf, simplfied for now
             rect: Rect.fromLTWH(words[i].x, words[i].y, words[i].width, words[i].height)
           ));
        }
      }

      debugPrint("VisionService: AI Extracted ${detectedTokens.length} meaningful tokens.");
      for (var t in detectedTokens.take(5)) { // Show sample
         debugPrint(" - ${t.text} -> ${t.label}");
      }

      inputIdsTensor.release();
      maskTensor.release();
      bboxTensor.release();
      pixelTensor.release();
      runOptions.release();
      outputTensor?.release();

      return detectedTokens;

    } catch (e) {
      debugPrint("VisionService Inference Error: $e");
      return [];
    }
  }

  Future<Float32List> _imageToTensor(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) throw Exception("Failed to decode image");

    // Resize to 224x224 (Standard ViT)
    final resized = img.copyResize(image, width: 224, height: 224);

    // NCHW format: [Batch, Channels, Height, Width] -> [1, 3, 224, 224]
    // Planar: All Reds, then all Greens, then all Blues
    final floatList = Float32List(1 * 3 * 224 * 224);

    // ImageNet Means/Stds
    final mean = [0.485, 0.456, 0.406];
    final std = [0.229, 0.224, 0.225];

    int offset = 0;
    // Outer loop: Channels (0=R, 1=G, 2=B) to ensure RRR...GGG...BBB structure
    for (var c = 0; c < 3; c++) {
      for (var y = 0; y < 224; y++) {
        for (var x = 0; x < 224; x++) {
          final pixel = resized.getPixel(x, y);

          double val = 0;
          if (c == 0) val = pixel.r.toDouble();
          if (c == 1) val = pixel.g.toDouble();
          if (c == 2) val = pixel.b.toDouble();

          // Normalize: (pixel/255 - mean) / std
          val = (val / 255.0 - mean[c]) / std[c];

          floatList[offset++] = val;
        }
      }
    }
    return floatList;
  }

  void dispose() {
    _session?.release();
  }
}

/// Represents a word classified by the AI
class VisionToken {
  final String text;
  final String label; // e.g., "B-TOTAL", "I-VENDOR"
  final double confidence;
  final Rect rect;

  VisionToken({
    required this.text,
    required this.label,
    required this.confidence,
    required this.rect,
  });
}
