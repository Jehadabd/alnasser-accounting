import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';

class FontManager {
  static const String _windowsFontsPath = r'C:\Windows\Fonts';
  
  // خطوط عربية محملة من assets
  static pw.Font? _amiriFont;
  static pw.Font? _cairoFont;
  static pw.Font? _algerFont;
  
  // خريطة للخطوط المخصصة المحملة
  static final Map<String, pw.Font> _customFonts = {};
  
  // قائمة بأوزان الخطوط المتاحة
  static const Map<String, FontWeight> fontWeights = {
    'عادي': FontWeight.normal,
    'متوسط': FontWeight.w500,
    'غامق': FontWeight.bold,
    'غامق جداً': FontWeight.w800,
    'غامق جداً جداً جداً': FontWeight.w900,
  };

  // قائمة بأوزان الخطوط للـ PDF
  static const Map<String, pw.FontWeight> pdfFontWeights = {
    'عادي': pw.FontWeight.normal,
    'متوسط': pw.FontWeight.normal,
    'غامق': pw.FontWeight.bold,
    'غامق جداً': pw.FontWeight.bold,
    'غامق جداً جداً جداً': pw.FontWeight.bold,
  };

  /// قراءة جميع الخطوط المتاحة من مجلد Windows Fonts
  static Future<List<FontInfo>> getAvailableFonts() async {
    List<FontInfo> fonts = [];
    
    // إضافة الخطوط العربية من assets أولاً
    fonts.addAll([
      FontInfo(
        name: 'Amiri-Regular', 
        fileName: 'Amiri-Regular.ttf',
        filePath: 'assets/fonts/Amiri-Regular.ttf',
        weight: 'عادي', 
        extension: '.ttf'
      ),
      FontInfo(
        name: 'Cairo-Regular', 
        fileName: 'Cairo-Regular.ttf',
        filePath: 'assets/fonts/Cairo-Regular.ttf',
        weight: 'عادي', 
        extension: '.ttf'
      ),
      FontInfo(
        name: 'ALGER', 
        fileName: 'ALGER.TTF',
        filePath: 'assets/fonts/ALGER.TTF',
        weight: 'عادي', 
        extension: '.ttf'
      ),
    ]);
    
    try {
      final directory = Directory(_windowsFontsPath);
      if (!await directory.exists()) {
        print('مجلد الخطوط غير موجود: $_windowsFontsPath');
        return fonts;
      }

      await for (final entity in directory.list()) {
        if (entity is File) {
          final fileName = path.basename(entity.path);
          final extension = path.extension(fileName).toLowerCase();
          
          // دعم أنواع الخطوط المختلفة
          if (['.ttf', '.otf', '.ttc'].contains(extension)) {
            final fontName = _extractFontName(fileName);
            final fontWeight = _extractFontWeight(fileName);
            
            fonts.add(FontInfo(
              name: fontName,
              fileName: fileName,
              filePath: entity.path,
              weight: fontWeight,
              extension: extension,
            ));
          }
        }
      }
    } catch (e) {
      print('خطأ في قراءة الخطوط: $e');
    }

    // ترتيب الخطوط حسب الاسم
    fonts.sort((a, b) => a.name.compareTo(b.name));
    
    // إزالة التكرارات
    return _removeDuplicates(fonts);
  }

  /// استخراج اسم الخط من اسم الملف
  static String _extractFontName(String fileName) {
    String name = path.basenameWithoutExtension(fileName);
    
    // تنظيف الاسم مع الحفاظ على المعلومات الكاملة
    // إزالة الشرطات السفلية واستبدالها بمسافات
    name = name.replaceAll('_', ' ');
    
    // إزالة الشرطات المتعددة واستبدالها بشرطة واحدة
    name = name.replaceAll(RegExp(r'-+'), ' - ');
    
    // تنظيف المسافات الزائدة
    name = name.replaceAll(RegExp(r'\s+'), ' ').trim();
    
    return name.isEmpty ? fileName : name;
  }

  /// استخراج وزن الخط من اسم الملف
  static String _extractFontWeight(String fileName) {
    final lowerName = fileName.toLowerCase();
    
    if (lowerName.contains('black') || lowerName.contains('heavy') || lowerName.contains('ultra') || lowerName.contains('extra')) {
      return 'غامق جداً جداً جداً';
    } else if (lowerName.contains('bold') || lowerName.contains('demibold') || lowerName.contains('semibold')) {
      return 'غامق جداً';
    } else if (lowerName.contains('medium') || lowerName.contains('demi') || lowerName.contains('semi')) {
      return 'متوسط';
    } else {
      return 'عادي';
    }
  }

  /// إزالة التكرارات من قائمة الخطوط
  static List<FontInfo> _removeDuplicates(List<FontInfo> fonts) {
    Map<String, FontInfo> uniqueFonts = {};
    
    for (final font in fonts) {
      // استخدام اسم الملف كمعرف فريد بدلاً من الاسم المعالج
      final key = font.fileName.toLowerCase();
      if (!uniqueFonts.containsKey(key)) {
        uniqueFonts[key] = font;
      } else {
        // إذا كان الخط موجود، احتفظ بالخط الذي له وزن أعلى
        final existing = uniqueFonts[key]!;
        if (_getWeightPriority(font.weight) > _getWeightPriority(existing.weight)) {
          uniqueFonts[key] = font;
        }
      }
    }
    
    return uniqueFonts.values.toList();
  }

  /// تحديد أولوية وزن الخط
  static int _getWeightPriority(String weight) {
    switch (weight) {
      case 'غامق جداً جداً جداً': return 5;
      case 'غامق جداً': return 4;
      case 'غامق': return 3;
      case 'متوسط': return 2;
      case 'عادي': return 1;
      default: return 0;
    }
  }

  /// تحميل خط جديد إلى مجلد الخطوط
  static Future<bool> installFont(String fontPath) async {
    try {
      final sourceFile = File(fontPath);
      if (!await sourceFile.exists()) {
        print('ملف الخط غير موجود: $fontPath');
        return false;
      }

      final fileName = path.basename(fontPath);
      final destinationPath = path.join(_windowsFontsPath, fileName);
      final destinationFile = File(destinationPath);

      // نسخ الملف إلى مجلد الخطوط
      await sourceFile.copy(destinationPath);
      
      print('تم تثبيت الخط بنجاح: $fileName');
      return true;
    } catch (e) {
      print('خطأ في تثبيت الخط: $e');
      return false;
    }
  }

  /// إضافة خط جديد من ملف محلي إلى النظام
  static Future<bool> addCustomFont(String fontPath) async {
    try {
      final sourceFile = File(fontPath);
      if (!await sourceFile.exists()) {
        print('ملف الخط غير موجود: $fontPath');
        return false;
      }

      final fileName = path.basename(fontPath);
      final extension = path.extension(fileName).toLowerCase();
      
      // التحقق من نوع الملف
      if (!['.ttf', '.otf', '.ttc'].contains(extension)) {
        print('نوع الملف غير مدعوم: $extension');
        return false;
      }

      // نسخ الملف إلى مجلد الخطوط
      final destinationPath = path.join(_windowsFontsPath, fileName);
      await sourceFile.copy(destinationPath);
      
      // تحميل الخط إلى الذاكرة للاستخدام الفوري
      final fontName = _extractFontName(fileName);
      final customFont = await loadCustomFont(destinationPath);
      if (customFont != null) {
        _customFonts[fontName] = customFont;
      }
      
      print('تم إضافة الخط بنجاح: $fileName');
      return true;
    } catch (e) {
      print('خطأ في إضافة الخط: $e');
      return false;
    }
  }

  /// تحديث قائمة الخطوط المتاحة
  static Future<List<FontInfo>> refreshFonts() async {
    return await getAvailableFonts();
  }

  /// الحصول على خط Flutter من اسم الخط
  static TextStyle getFlutterFont(String fontFamily, String weight) {
    final fontWeight = fontWeights[weight] ?? FontWeight.normal;
    // إذا كان الخط غير موجود، استخدم الخط الافتراضي
    try {
      return TextStyle(fontFamily: fontFamily, fontWeight: fontWeight);
    } catch (e) {
      return TextStyle(fontFamily: 'Amiri-Regular', fontWeight: fontWeight);
    }
  }

  /// تحميل الخطوط العربية من assets
  static Future<void> loadArabicFonts() async {
    try {
      // تحميل خط Amiri
      final amiriData = await rootBundle.load('assets/fonts/Amiri-Regular.ttf');
      _amiriFont = pw.Font.ttf(amiriData);
      
      // تحميل خط Cairo
      final cairoData = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
      _cairoFont = pw.Font.ttf(cairoData);
      
      // تحميل خط Alger
      final algerData = await rootBundle.load('assets/fonts/ALGER.TTF');
      _algerFont = pw.Font.ttf(algerData);
    } catch (e) {
      print('خطأ في تحميل الخطوط العربية: $e');
    }
  }

  /// الحصول على خط PDF من اسم الخط
  static pw.Font? getPdfFont(String fontFamily) {
    if (fontFamily.isEmpty || fontFamily.toLowerCase() == 'default') return null;
    
    try {
      // البحث في الخطوط المخصصة أولاً
      if (_customFonts.containsKey(fontFamily)) {
        return _customFonts[fontFamily]!;
      }
      
      // البحث في الخطوط العربية المحملة
      if (fontFamily.toLowerCase().contains('amiri') && _amiriFont != null) {
        return _amiriFont!;
      } else if (fontFamily.toLowerCase().contains('cairo') && _cairoFont != null) {
        return _cairoFont!;
      } else if (fontFamily.toLowerCase().contains('alger') && _algerFont != null) {
        return _algerFont!;
      }
      
      return null; // نعيد null ليقوم المستدعي باستخدام الخط الاحتياطي الخاص به
    } catch (e) {
      return null;
    }
  }

  /// الحصول على خط PDF مع وزن محدد
  static pw.Font? getPdfFontWithWeight(String fontFamily, String fontWeight) {
    return getPdfFont(fontFamily);
  }

  /// الحصول على وزن الخط للـ PDF
  static pw.FontWeight getPdfFontWeight(String fontWeight) {
    return pdfFontWeights[fontWeight] ?? pw.FontWeight.normal;
  }

  /// تحميل خط مخصص من ملف
  static Future<pw.Font?> loadCustomFont(String fontPath) async {
    try {
      final file = File(fontPath);
      if (!await file.exists()) {
        print('ملف الخط غير موجود: $fontPath');
        return null;
      }

      final fontBytes = await file.readAsBytes();
      return pw.Font.ttf(ByteData.view(fontBytes.buffer));
    } catch (e) {
      print('خطأ في تحميل الخط المخصص: $e');
      return null;
    }
  }
}

/// نموذج معلومات الخط
class FontInfo {
  final String name;
  final String fileName;
  final String filePath;
  final String weight;
  final String extension;

  FontInfo({
    required this.name,
    required this.fileName,
    required this.filePath,
    required this.weight,
    required this.extension,
  });

  @override
  String toString() {
    return 'FontInfo(name: $name, weight: $weight)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FontInfo &&
        other.name == name &&
        other.weight == weight;
  }

  @override
  int get hashCode => name.hashCode ^ weight.hashCode;
}
