// lib/screens/web_hosting_guide_screen.dart
// 🌐 دليل ومعالج رفع واستضافة التطبيق على الويب (Web App)
// يشمل 3 منصات رئيسية:
// 1. Netlify Drop (السحب والإفلات الأسرع)
// 2. Vercel (المنصة الأحدث والأسرع عالمياً)
// 3. Firebase Hosting (المربوطة بقاعدة البيانات - مع معالج النشر الذكي "الفكرة A")

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import '../services/firebase_sync/firebase_custom_config.dart';

/// نموذج بيانات خطوة فرعية داخل بطاقة الخطوة التفصيلية
class _SubStep {
  final IconData icon;
  final String text;
  const _SubStep({required this.icon, required this.text});
}

class WebHostingGuideScreen extends StatefulWidget {
  const WebHostingGuideScreen({super.key});

  @override
  State<WebHostingGuideScreen> createState() => _WebHostingGuideScreenState();
}

class _WebHostingGuideScreenState extends State<WebHostingGuideScreen> {
  // 0: Netlify Drop, 1: Vercel, 2: Firebase Hosting
  int _selectedPlatformIndex = 0;
  final TextEditingController _storeUrlController = TextEditingController();
  final TextEditingController _projectIdInputController = TextEditingController();

  bool _isPackaging = false;
  String _packageStatus = '';
  String? _packageSavedPath;
  String? _firebaseProjectId;

  // 🚀 حالة النشر الذكي على Firebase Hosting (الفكرة A)
  bool _isDeploying = false;
  int _deployStep = 0; // 0: Idle, 1: Node, 2: Firebase Tools, 3: Prep & Config, 4: Login, 5: Deploying, 6: Success, -1: Error
  String _deployStatusMessage = '';
  String _deployLog = '';
  String? _deployedUrl;
  Process? _activeDeployProcess;
  bool _showLogs = true;

  final ScrollController _logScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadSavedData();
  }

  @override
  void dispose() {
    _storeUrlController.dispose();
    _projectIdInputController.dispose();
    _logScrollController.dispose();
    _activeDeployProcess?.kill();
    super.dispose();
  }

  Future<void> _loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString('custom_store_web_url') ?? '';
    if (savedUrl.isNotEmpty) {
      setState(() {
        _storeUrlController.text = savedUrl;
      });
    }

    final options = await FirebaseCustomConfig.getCustomOptions();
    if (options != null && options.projectId.isNotEmpty) {
      setState(() {
        _firebaseProjectId = options.projectId;
        _projectIdInputController.text = options.projectId;
      });
    } else {
      final defaultId = await FirebaseCustomConfig.getProjectId();
      if (defaultId != null && defaultId.isNotEmpty) {
        setState(() {
          _firebaseProjectId = defaultId;
          _projectIdInputController.text = defaultId;
        });
      }
    }
  }

  Future<void> _saveStoreUrl(String url) async {
    if (url.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('custom_store_web_url', url.trim());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ تم حفظ رابط متجرك بنجاح'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _launchExternalUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر فتح الرابط: $url')),
        );
      }
    }
  }

  void _copyToClipboard(String text, String successMessage) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(successMessage),
        backgroundColor: Colors.blue.shade800,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 📦 تجهيز وتصدير حزمة الويب (web_app.zip)
  // ═══════════════════════════════════════════════════════════════════════════
  Future<void> _generateWebPackage() async {
    setState(() {
      _isPackaging = true;
      _packageStatus = 'جاري تجهيز حزمة الويب...';
      _packageSavedPath = null;
    });

    try {
      const batContent = '''@echo off
chcp 65001 >nul
echo ========================================================
echo   🌐 جاري تجهيز ورفع تطبيق المتجر للويب تلقائياً...
echo ========================================================
echo.
cd /d "%~dp0"
if exist "build\\web" (
    echo [1/2] مجلد الويب مبني وجاهز.
) else (
    echo [1/2] جاري بناء نسخة الويب...
    call flutter build web --release
)
echo.
echo [2/2] جاري رفع الاستضافة إلى Firebase...
call firebase deploy --only hosting
echo.
echo ========================================================
echo   ✅ اكتملت العملية بنجاح! افتح رابط متجرك الآن.
echo ========================================================
pause
''';

      if (kIsWeb) {
        setState(() {
          _isPackaging = false;
          _packageStatus =
              'ℹ️ تجهيز الحزمة يتم من تطبيق الكمبيوتر (الإعدادات ← استضافة ورفع نسخة المتصفح).\n'
              'من هنا يمكنك متابعة خطوات الرفع للمنصات أدناه.';
        });
      } else {
        Directory? targetDir;
        final separator = Platform.isWindows ? '\\' : '/';

        if (Platform.isWindows) {
          final userProfile = Platform.environment['USERPROFILE'];
          if (userProfile != null) {
            final downloads = Directory('$userProfile${separator}Downloads');
            if (await downloads.exists()) {
              targetDir = downloads;
            } else {
              final desktop = Directory('$userProfile${separator}Desktop');
              if (await desktop.exists()) targetDir = desktop;
            }
          }
        }

        if (targetDir == null) {
          try {
            targetDir = await getDownloadsDirectory();
          } catch (_) {}
          targetDir ??= await getApplicationDocumentsDirectory();
        }

        final outDir = targetDir?.path ?? (Platform.isWindows ? 'C:\\' : '/sdcard/Download');
        final zipFilePath = '$outDir${separator}web_app.zip';
        final batFilePath = '$outDir${separator}تجهيز_ورفع_الويب_تلقائياً.bat';

        final buildWebDir = Directory(p.join('build', 'web'));
        bool usedLiveBuild = false;

        // فحص إمكانية استخدام البناء الحي (لبيئة التطوير)
        if (await buildWebDir.exists()) {
          final engineFile = File(p.join(buildWebDir.path, 'sqlite3.wasm'));
          final mainJs = File(p.join(buildWebDir.path, 'main.dart.js'));

          if (await engineFile.exists() && await mainJs.exists()) {
            // ضمان وجود ملفات التهيئة للمنصات الثلاث داخل المجلد قبل الضغط
            final vercelJson = File(p.join(buildWebDir.path, 'vercel.json'));
            if (!await vercelJson.exists()) {
              await vercelJson.writeAsString('{\n  "rewrites": [{ "source": "/(.*)", "destination": "/index.html" }]\n}\n');
            }

            final firebaseJson = File(p.join(buildWebDir.path, 'firebase.json'));
            await firebaseJson.writeAsString('{\n  "hosting": {\n    "public": ".",\n    "ignore": ["firebase.json", "**/.*", "**/node_modules/**", "**/*.exe", "**/*.bat", "**/*.cmd", "**/*.dll", "**/*.so", "**/*.dylib"],\n    "rewrites": [{ "source": "**", "destination": "/index.html" }],\n    "headers": [{ "source": "/sqlite3.wasm", "headers": [{"key": "Cache-Control", "value": "no-cache"}] }]\n  }\n}\n');

            final redirectsFile = File(p.join(buildWebDir.path, '_redirects'));
            if (!await redirectsFile.exists()) {
              await redirectsFile.writeAsString('/*    /index.html   200\n');
            }

            // ضغط المجلد
            final encoder = ZipFileEncoder();
            encoder.create(zipFilePath);
            encoder.addDirectory(buildWebDir, includeDirName: false);
            encoder.close();
            usedLiveBuild = true;
          }
        }

        // إذا لم يتوفر بناء حي (على أجهزة المستخدمين)، استخراج الحزمة المضمنة الجاهزة مباشرة
        if (!usedLiveBuild) {
          final byteData = await rootBundle.load('assets/web_app.zip');
          final bytes = byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes);
          final outFile = File(zipFilePath);
          await outFile.writeAsBytes(bytes);
        }

        final zipSizeMb = (await File(zipFilePath).length()) / (1024 * 1024);

        if (Platform.isWindows) {
          final batFile = File(batFilePath);
          await batFile.writeAsString(batContent);
        }

        if (Platform.isAndroid || Platform.isIOS) {
          try {
            await Share.shareXFiles(
              [XFile(zipFilePath, mimeType: 'application/zip', name: 'web_app.zip')],
              text: '🌐 حزمة تطبيق المتجر للرفع على Netlify / Vercel / Firebase',
            );
          } catch (_) {}
        }

        setState(() {
          _isPackaging = false;
          _packageSavedPath = zipFilePath;
          _packageStatus = '✅ تم تصدير حزمة الويب بنجاح (${zipSizeMb.toStringAsFixed(1)} ميغابايت):\n$zipFilePath\n\n'
              'تتضمن: التطبيق + المحرك (sqlite3.wasm) + ملفات التهيئة لـ Vercel و Netlify و Firebase — جاهزة للرفع المباشر.';
        });
      }
    } catch (e) {
      setState(() {
        _isPackaging = false;
        _packageStatus = '❌ حدث خطأ أثناء تجهيز الحزمة: $e';
      });
    }
  }

  void _openSavedFolder() {
    if (_packageSavedPath != null && !kIsWeb && Platform.isWindows) {
      final file = File(_packageSavedPath!);
      Process.run('explorer.exe', ['/select,', file.path]);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🚀 محرك النشر الذكي والشفاف لمنصة Firebase Hosting (الفكرة A)
  // ═══════════════════════════════════════════════════════════════════════════

  void _logDeploy(String line) {
    if (!mounted) return;
    setState(() {
      _deployLog += '$line\n';
    });
    // التمرير لأسفل السجل تلقائياً
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.animateTo(
          _logScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// تنفيذ أمر مع بث المخرجات لحظياً وإمكانية الإلغاء
  Future<int> _executeStreamedCommand(String executable, List<String> arguments, {String? workingDir}) async {
    _logDeploy('💻 تشغيل: $executable ${arguments.join(' ')}');
    try {
      final process = await Process.start(
        executable,
        arguments,
        workingDirectory: workingDir,
        runInShell: true,
      );
      _activeDeployProcess = process;

      process.stdout.transform(utf8.decoder).listen((data) {
        final lines = data.split('\n');
        for (final line in lines) {
          if (line.trim().isNotEmpty) {
            _logDeploy('  $line');
          }
        }
      });

      process.stderr.transform(utf8.decoder).listen((data) {
        final lines = data.split('\n');
        for (final line in lines) {
          if (line.trim().isNotEmpty) {
            _logDeploy('  ⚠️ $line');
          }
        }
      });

      final exitCode = await process.exitCode;
      _activeDeployProcess = null;
      return exitCode;
    } catch (e) {
      _activeDeployProcess = null;
      _logDeploy('❌ خطأ أثناء تشغيل الأمر ($executable): $e');
      return -1;
    }
  }

  /// إلغاء عملية النشر الحالية
  void _cancelDeploy() {
    if (_activeDeployProcess != null) {
      _activeDeployProcess!.kill();
      _activeDeployProcess = null;
      _logDeploy('🛑 تم إلغاء العملية بناءً على طلبك.');
      setState(() {
        _isDeploying = false;
        _deployStep = -1;
        _deployStatusMessage = 'تم إلغاء عملية النشر.';
      });
    }
  }

  /// تجهيز مجلد النشر واستخراج الحزمة وتوليد ملفات التهيئة
  Future<Directory?> _prepareDeploySiteDirectory(String projectId) async {
    final buildWeb = Directory(p.join('build', 'web'));
    Directory? deployDir;

    // استخدام البناء الحي إن وجد
    if (await buildWeb.exists() &&
        await File(p.join(buildWeb.path, 'sqlite3.wasm')).exists() &&
        await File(p.join(buildWeb.path, 'main.dart.js')).exists()) {
      _logDeploy('✅ استخدام البناء الحي المباشر (build/web)');
      deployDir = buildWeb;
    } else {
      // استخراج حزمة الويب المضمنة
      try {
        final temp = await getTemporaryDirectory();
        final siteDir = Directory(p.join(temp.path, 'firebase_deploy_${DateTime.now().millisecondsSinceEpoch}'));
        await siteDir.create(recursive: true);

        final byteData = await rootBundle.load('assets/web_app.zip');
        final bytes = byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes);
        final archive = ZipDecoder().decodeBytes(bytes);
        for (final file in archive) {
          final filePath = p.join(siteDir.path, file.name);
          if (file.isFile) {
            final outFile = File(filePath);
            await outFile.parent.create(recursive: true);
            await outFile.writeAsBytes(file.content as List<int>);
          } else {
            await Directory(filePath).create(recursive: true);
          }
        }
        _logDeploy('✅ تم استخراج حزمة الويب بنجاح (${archive.files.length} ملف)');
        deployDir = siteDir;
      } catch (e) {
        _logDeploy('❌ تعذر تجهيز ملفات الموقع من الحزمة: $e');
        return null;
      }
    }

    // توليد ملف firebase.json الصحيح لـ Flutter Web
    final hostingConfig = '''{
  "hosting": {
    "public": ".",
    "ignore": [
      "firebase.json",
      "**/.*",
      "**/node_modules/**",
      "**/*.exe",
      "**/*.bat",
      "**/*.cmd",
      "**/*.dll",
      "**/*.so",
      "**/*.dylib"
    ],
    "rewrites": [
      {
        "source": "**",
        "destination": "/index.html"
      }
    ],
    "headers": [
      {
        "source": "/sqlite3.wasm",
        "headers": [
          {
            "key": "Cache-Control",
            "value": "no-cache, no-store, must-revalidate"
          },
          {
            "key": "Content-Type",
            "value": "application/wasm"
          }
        ]
      }
    ]
  }
}
''';
    await File(p.join(deployDir.path, 'firebase.json')).writeAsString(hostingConfig);
    _logDeploy('📄 تم توليد ملف إعدادات الاستضافة (firebase.json)');

    // توليد ملف .firebaserc
    final firebasercConfig = '''{
  "projects": {
    "default": "$projectId"
  }
}
''';
    await File(p.join(deployDir.path, '.firebaserc')).writeAsString(firebasercConfig);
    _logDeploy('📄 تم ضبط مشروع الهدف في (.firebaserc)');

    return deployDir;
  }

  /// التشغيل الفعلي لمعالج النشر الذكي
  Future<void> _deployToFirebaseHostingSmart() async {
    if (kIsWeb) {
      setState(() {
        _deployStatusMessage = 'النشر التلقائي متاح من تطبيق سطح المكتب (Windows).';
        _deployLog = 'النشر متاح من تطبيق الكمبيوتر فقط.';
      });
      return;
    }
    if (!Platform.isWindows) {
      setState(() {
        _deployStatusMessage = 'النشر التلقائي الذكي مدعوم على Windows حالياً.';
        _deployLog = 'على الأنظمة الأخرى يمكنك استخدام دليل Netlify أو Vercel أو النشر اليدوي.';
      });
      return;
    }

    final targetProjectId = _projectIdInputController.text.trim().isNotEmpty
        ? _projectIdInputController.text.trim()
        : (_firebaseProjectId ?? await FirebaseCustomConfig.getProjectId());

    if (targetProjectId == null || targetProjectId.isEmpty) {
      setState(() {
        _deployStep = -1;
        _deployStatusMessage = '❌ لم يتم تحديد معرّف مشروع Firebase.';
        _deployLog = 'يرجى إدخال اسم المشروع في الخانة أدناه أو ضبطه من إعدادات مزامنة Firebase.\n';
      });
      return;
    }

    setState(() {
      _isDeploying = true;
      _deployStep = 1;
      _deployStatusMessage = '🔍 [1/5] جاري فحص بيئة Node.js...';
      _deployLog = '═══════════════════════════════════════════════════════\n'
          '🚀 بدء عملية النشر الذكي على Firebase Hosting\n'
          '🎯 المشروع الهدف: $targetProjectId\n'
          '⏰ التوقيت: ${DateTime.now().toString().split('.').first}\n'
          '═══════════════════════════════════════════════════════\n\n';
      _deployedUrl = null;
    });

    try {
      // ─────────────────────────────────────────────────────────────────
      // المرحلة 1: فحص Node.js وتثبيته تلقائياً إن لم يوجد
      // ─────────────────────────────────────────────────────────────────
      _logDeploy('🔍 [المرحلة 1] فحص برنامج Node.js...');
      final nodeCheckCode = await _executeStreamedCommand('node', ['--version']);
      if (nodeCheckCode != 0) {
        _logDeploy('⚠️ Node.js غير موجود على الجهاز. جاري محاولة التثبيت التلقائي الصامت عبر ويندوز (winget)...');
        setState(() {
          _deployStatusMessage = '📦 [1/5] جاري تثبيت Node.js تلقائياً عبر ويندوز... قد يستغرق دقيقة';
        });

        final wingetCode = await _executeStreamedCommand('winget', [
          'install',
          '--id',
          'OpenJS.NodeJS.LTS',
          '-e',
          '--accept-package-agreements',
          '--accept-source-agreements',
          '--silent',
        ]);

        if (wingetCode != 0) {
          _logDeploy('❌ تعذر التثبيت التلقائي لـ Node.js.');
          _logDeploy('💡 يرجى تنزيل Node.js يدوياً وتثبيته من الرابط: https://nodejs.org');
          setState(() {
            _deployStep = -1;
            _deployStatusMessage = '❌ تعذر تثبيت Node.js تلقائياً. يرجى تثبيته يدوياً من nodejs.org';
          });
          return;
        }
        _logDeploy('✅ اكتمل تثبيت Node.js بنجاح!');
      } else {
        _logDeploy('✅ Node.js متوفر وجاهز.');
      }

      // ─────────────────────────────────────────────────────────────────
      // المرحلة 2: فحص وتثبيت أدوات Firebase CLI (firebase-tools)
      // ─────────────────────────────────────────────────────────────────
      setState(() {
        _deployStep = 2;
        _deployStatusMessage = '🛠️ [2/5] جاري فحص وتجهيز أدوات Firebase CLI...';
      });
      _logDeploy('\n🛠️ [المرحلة 2] فحص أدوات Firebase (firebase-tools)...');
      var fbCheckCode = await _executeStreamedCommand('firebase', ['--version']);
      if (fbCheckCode != 0) {
        _logDeploy('⚠️ أدوات Firebase غير مثبتة عالمياً. جاري التثبيت عبر npm (يتم مرة واحدة فقط)...');
        setState(() {
          _deployStatusMessage = '⏳ [2/5] جاري تثبيت firebase-tools عبر npm... انتظر قليلاً';
        });
        final npmInstallCode = await _executeStreamedCommand('npm', ['install', '-g', 'firebase-tools']);
        if (npmInstallCode != 0) {
          _logDeploy('❌ فشل تثبيت firebase-tools عبر npm.');
          setState(() {
            _deployStep = -1;
            _deployStatusMessage = '❌ فشل تثبيت firebase-tools.';
          });
          return;
        }
        _logDeploy('✅ تم تثبيت firebase-tools بنجاح.');
      } else {
        _logDeploy('✅ أدوات Firebase مثبتة وجاهزة.');
      }

      // ─────────────────────────────────────────────────────────────────
      // المرحلة 3: تجهيز واستخراج حزمة الويب وتوليد الملفات
      // ─────────────────────────────────────────────────────────────────
      setState(() {
        _deployStep = 3;
        _deployStatusMessage = '📦 [3/5] جاري استخراج حزمة الويب وتوليد إعدادات firebase.json...';
      });
      _logDeploy('\n📦 [المرحلة 3] تجهيز حزمة الموقع وتوليد ملفات التهيئة...');
      final siteDirectory = await _prepareDeploySiteDirectory(targetProjectId);
      if (siteDirectory == null) {
        setState(() {
          _deployStep = -1;
          _deployStatusMessage = '❌ تعذر تجهيز ملفات الموقع.';
        });
        return;
      }
      _logDeploy('📂 مسار مجلد الموقع للنشر: ${siteDirectory.path}');

      // ─────────────────────────────────────────────────────────────────
      // المرحلة 4: تسجيل الدخول (firebase login)
      // ─────────────────────────────────────────────────────────────────
      setState(() {
        _deployStep = 4;
        _deployStatusMessage = '🔐 [4/5] تسجيل الدخول — ستفتح نافذة المتصفح...';
      });
      _logDeploy('\n🔐 [المرحلة 4] تسجيل الدخول إلى حساب Google / Firebase...');
      _logDeploy('ℹ️ ستفتح نافذة متصفحك الآن لتسجيل الدخول بالحساب المالك للمشروع ($targetProjectId).');

      final loginCode = await _executeStreamedCommand('firebase', ['login', '--interactive']);
      if (loginCode != 0) {
        _logDeploy('⚠️ تنبيه حول أمر تسجيل الدخول (قد تكون مسجلاً بالفعل مسبقاً، سنتابع عملية النشر).');
      } else {
        _logDeploy('✅ تم تأكيد تسجيل الدخول بنجاح.');
      }

      // ─────────────────────────────────────────────────────────────────
      // المرحلة 5: الرفع والنشر النهائي (firebase deploy)
      // ─────────────────────────────────────────────────────────────────
      setState(() {
        _deployStep = 5;
        _deployStatusMessage = '🚀 [5/5] جاري الرفع والنشر إلى استضافة Firebase...';
      });
      _logDeploy('\n🚀 [المرحلة 5] جاري رفع ونشر الموقع (firebase deploy)...');

      final deployCode = await _executeStreamedCommand(
        'firebase',
        ['deploy', '--only', 'hosting', '--project', targetProjectId],
        workingDir: siteDirectory.path,
      );

      if (deployCode != 0) {
        _logDeploy('❌ لم تكتمل عملية النشر بنجاح.');
        _logDeploy('💡 تأكد أن حساب Google المسجل يملك صلاحية التعديل على المشروع "$targetProjectId".');
        setState(() {
          _deployStep = -1;
          _deployStatusMessage = '❌ فشل النشر. راجع السجل لمعرفة السبب.';
        });
        return;
      }

      final finalUrl = 'https://$targetProjectId.web.app';
      _logDeploy('\n🎉🎉🎉 تهانينا! اكتمل النشر بنجاح على استضافة Google Firebase!');
      _logDeploy('🌐 رابط متجرك المباشر: $finalUrl\n');

      setState(() {
        _deployStep = 6;
        _deployedUrl = finalUrl;
        _deployStatusMessage = '✅ تم النشر بنجاح!';
        _storeUrlController.text = finalUrl;
      });

      // حفظ الرابط تلقائياً
      await _saveStoreUrl(finalUrl);
    } catch (e) {
      _logDeploy('❌ خطأ غير متوقع أثناء النشر: $e');
      setState(() {
        _deployStep = -1;
        _deployStatusMessage = '❌ حدث خطأ غير متوقع: $e';
      });
    } finally {
      setState(() {
        _isDeploying = false;
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 📱 واجهة المستخدم الرئيسية
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F7FB),
        appBar: AppBar(
          title: const Text(
            '🌐 استضافة ورفع المتجر على الإنترنت',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          centerTitle: true,
          backgroundColor: const Color(0xFF0D47A1),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          children: [
            _buildFreePlanGuaranteeBanner(),
            const SizedBox(height: 12),
            _buildPackageDownloaderCard(),
            const SizedBox(height: 20),

            // 🌟 عنوان قسم اختيار الاستضافة
            const Text(
              'اختر منصة الاستضافة المناسبة لك (3 منصات مجانية):',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0D47A1)),
            ),
            const SizedBox(height: 10),

            // 🌟 كروت اختيار المنصات الثلاث
            _buildPlatformChoiceCards(),
            const SizedBox(height: 20),

            // 🌟 المحتوى التفصيلي المشروح حسب المنصة المختارة
            if (_selectedPlatformIndex == 0)
              _buildNetlifyDropDetailedGuide()
            else if (_selectedPlatformIndex == 1)
              _buildVercelDetailedGuide()
            else
              _buildFirebaseHostingSmartSection(),

            const SizedBox(height: 20),
            _buildIosPwaTipCard(),
            const SizedBox(height: 40),
          ],
        ),
        bottomNavigationBar: _buildBottomStoreUrlBar(),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🌟 كروت اختيار المنصات الثلاث
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildPlatformChoiceCards() {
    return Column(
      children: [
        _buildChoiceCard(
          index: 0,
          title: '1. منصة Netlify Drop (السحب والإفلات الأسرع)',
          subtitle: 'الأسهل عالمياً للمبتدئين — تسحب ملف الـ ZIP وتفلته في المتصفح فيظهر موقعك فوراً في 10 ثوانٍ دون تعقيد.',
          icon: Icons.touch_app_rounded,
          iconColor: const Color(0xFF00AD9F),
          badgeText: '⚡ الأسهل والأسرع (10 ثوانٍ)',
          badgeColor: Colors.teal,
        ),
        const SizedBox(height: 10),
        _buildChoiceCard(
          index: 1,
          title: '2. منصة Vercel (الأحدث والأسرع عالمياً)',
          subtitle: 'شبكة حافة عالمية فائقة السرعة — استضافة مجانية وموثوقة برابط .vercel.app سريع عبر المتصفح أو Vercel CLI.',
          icon: Icons.change_history_rounded,
          iconColor: const Color(0xFF1E293B),
          badgeText: '🚀 شبكة حافة فائقة السرعة',
          badgeColor: const Color(0xFF0F172A),
        ),
        const SizedBox(height: 10),
        _buildChoiceCard(
          index: 2,
          title: '3. استضافة Firebase Hosting (المربوطة بقاعدتك ومزامنتك)',
          subtitle: 'استضافة Google المباشرة على نفس مشروع محلك — مع زر نشر ذكي وشامل بضغطة واحدة من داخل التطبيق.',
          icon: Icons.local_fire_department_rounded,
          iconColor: const Color(0xFFFFA000),
          badgeText: '🔥 نقرة واحدة (الفكرة A)',
          badgeColor: Colors.amber.shade900,
        ),
      ],
    );
  }

  Widget _buildChoiceCard({
    required int index,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required String badgeText,
    required Color badgeColor,
  }) {
    final isSelected = _selectedPlatformIndex == index;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedPlatformIndex = index;
        });
      },
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.white.withOpacity(0.88),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFF0D47A1) : Colors.grey.shade300,
            width: isSelected ? 2.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected ? const Color(0xFF0D47A1).withOpacity(0.12) : Colors.black.withOpacity(0.03),
              blurRadius: isSelected ? 12 : 6,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14.5,
                            color: isSelected ? const Color(0xFF0D47A1) : Colors.black87,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: badgeColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          badgeText,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: badgeColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12.5, height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              color: isSelected ? const Color(0xFF0D47A1) : Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 1️⃣ الشرح التفصيلي لـ Netlify Drop
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildNetlifyDropDetailedGuide() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('📖 خطوات النشر عبر Netlify Drop — السحب والإفلات الأسرع:'),
        const SizedBox(height: 12),

        _buildDetailedStepCard(
          stepNumber: '1',
          stepColor: const Color(0xFF00695C),
          title: '📥 تنزيل ملف الموقع (web_app.zip)',
          subSteps: const [
            _SubStep(icon: Icons.touch_app_rounded, text: 'اضغط على زر (📥 تجهيز وتنزيل الحزمة) بالأعلى لتوليد ملف web_app.zip.'),
            _SubStep(icon: Icons.folder_rounded, text: 'ستجد الملف في مجلد "التنزيلات" (Downloads) أو "سطح المكتب" (Desktop).'),
          ],
          actionButton: null,
        ),
        const SizedBox(height: 12),

        _buildDetailedStepCard(
          stepNumber: '2',
          stepColor: const Color(0xFF1565C0),
          title: '📂 فك الضغط عن الملف',
          subSteps: const [
            _SubStep(icon: Icons.mouse_rounded, text: 'اضغط كليك يمين على ملف web_app.zip واختر (Extract All... / استخراج الكل).'),
            _SubStep(icon: Icons.check_circle_rounded, text: 'سينتج مجلد عادي باسم web_app يحتوي على كافة ملفات المتجر.'),
          ],
          actionButton: null,
        ),
        const SizedBox(height: 12),

        _buildDetailedStepCard(
          stepNumber: '3',
          stepColor: const Color(0xFF00AD9F),
          title: '🌐 فتح موقع Netlify Drop',
          subSteps: const [
            _SubStep(icon: Icons.touch_app_rounded, text: 'اضغط الزر أدناه لفتح صفحة السحب والإفلات المباشرة:'),
          ],
          actionButton: ElevatedButton.icon(
            onPressed: () => _launchExternalUrl('https://app.netlify.com/drop'),
            icon: const Icon(Icons.open_in_browser_rounded, size: 20),
            label: const Text('🚀 افتح موقع Netlify Drop الآن', style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00AD9F),
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 46),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        const SizedBox(height: 12),

        _buildVisualDragDropSimulationCard(),
        const SizedBox(height: 12),

        _buildDetailedStepCard(
          stepNumber: '4',
          stepColor: const Color(0xFF6A1B9A),
          title: '📤 سحب مجلد الموقع وإفلاته بالمتصفح',
          subSteps: const [
            _SubStep(icon: Icons.drag_indicator_rounded, text: 'اسحب مجلد (web_app) بالماوس وأفلته داخل الدائرة الكبيرة في صفحة Netlify Drop.'),
            _SubStep(icon: Icons.hourglass_bottom_rounded, text: 'انتظر 5 إلى 10 ثوانٍ وسيصبح موقعك منشوراً وفورياً!'),
          ],
          actionButton: null,
        ),
        const SizedBox(height: 12),

        _buildDetailedStepCard(
          stepNumber: '5',
          stepColor: const Color(0xFF2E7D32),
          title: '🎉 نسخ الرابط وحفظه',
          subSteps: const [
            _SubStep(icon: Icons.celebration_rounded, text: 'انسخ الرابط الذي سيظهر لك وضعه في الخانة السفلية واضغط (حفظ).'),
          ],
          actionButton: null,
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 2️⃣ الشرح التفصيلي لمنصة Vercel (جديد)
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildVercelDetailedGuide() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('📖 خطوات النشر عبر منصة Vercel — سرعة حافة فائقة:'),
        const SizedBox(height: 12),

        // بطاقة نبذة عن Vercel
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFCBD5E1)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.change_history_rounded, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '⚡ لماذا منصة Vercel؟',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'تعد Vercel من أسرع منصات الاستضافة في العالم بفضل شبكتها العالمية (Edge CDN). تقدم خطة مجانية 100% مدى الحياة، وتدعم نطاقات .vercel.app المجانية مع شهادة أمان SSL تلقائية.',
                      style: TextStyle(fontSize: 12.5, color: Color(0xFF475569), height: 1.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // الخطوة 1: تنزيل الحزمة وفك الضغط
        _buildDetailedStepCard(
          stepNumber: '1',
          stepColor: const Color(0xFF0F172A),
          title: '📥 تنزيل حزمة الويب وفك ضغطها',
          subSteps: const [
            _SubStep(icon: Icons.touch_app_rounded, text: 'اضغط على زر (📥 تجهيز وتنزيل الحزمة) في أعلى الشاشة.'),
            _SubStep(icon: Icons.folder_zip_rounded, text: 'فك الضغط عن ملف web_app.zip إلى مجلد عادي على سطح المكتب.'),
          ],
          actionButton: null,
        ),
        const SizedBox(height: 12),

        // الخطوة 2: الدخول لـ Vercel
        _buildDetailedStepCard(
          stepNumber: '2',
          stepColor: const Color(0xFF2563EB),
          title: '🌐 فتح منصة Vercel وتسجيل الدخول',
          subSteps: const [
            _SubStep(icon: Icons.open_in_new_rounded, text: 'افتح موقع Vercel وسجّل دخولك بحساب Google أو GitHub أو البريد مجاناً.'),
          ],
          actionButton: ElevatedButton.icon(
            onPressed: () => _launchExternalUrl('https://vercel.com/new'),
            icon: const Icon(Icons.open_in_browser_rounded, size: 20),
            label: const Text('🚀 فتح موقع Vercel (vercel.com/new)', style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F172A),
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 46),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // الخطوة 3: تهيئة Single Page App (vercel.json)
        _buildDetailedStepCard(
          stepNumber: '3',
          stepColor: const Color(0xFF7C3AED),
          title: '⚙️ ملف توجيه المسارات لـ Vercel (vercel.json)',
          subSteps: const [
            _SubStep(icon: Icons.info_rounded, text: 'لضمان عمل روابط متجرك دون أخطاء 404، يحتوي مجلد الموقع على ملف vercel.json الذي يوجه كل الصفحات إلى index.html.'),
            _SubStep(icon: Icons.code_rounded, text: 'يمكنك نسخ محتوى الملف من الزر أدناه إن أردت إنشاءه يدوياً:'),
          ],
          actionButton: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildCommandTile(
                '📄 محتوى vercel.json المطلوب:',
                '{\n  "rewrites": [{ "source": "/(.*)", "destination": "/index.html" }]\n}',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // الخطوة 4: الرفع عبر Vercel CLI (سريع جداً)
        _buildDetailedStepCard(
          stepNumber: '4',
          stepColor: const Color(0xFF059669),
          title: '⚡ النشر السريع عبر سطر الأوامر (Vercel CLI)',
          subSteps: const [
            _SubStep(icon: Icons.terminal_rounded, text: 'إذا كان لديك Node.js على جهازك، يمكنك النشر في 10 ثوانٍ فقط عبر هذه الأوامر:'),
          ],
          actionButton: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildCommandTile('① تثبيت أداة Vercel (مرة واحدة):', 'npm install -g vercel'),
              const SizedBox(height: 6),
              _buildCommandTile('② تسجيل الدخول بحسابك:', 'vercel login'),
              const SizedBox(height: 6),
              _buildCommandTile('③ نشر الموقع فورياً للإنتاج:', 'vercel --prod'),
              const SizedBox(height: 8),
              const Text(
                '⬆️ بعد تنفيذ vercel --prod سيظهر لك رابط موقعك المباشر بصيغة: https://your-shop.vercel.app',
                style: TextStyle(fontSize: 12, color: Color(0xFF065F46), height: 1.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // الخطوة 5: حفظ الرابط
        _buildDetailedStepCard(
          stepNumber: '5',
          stepColor: const Color(0xFF0D47A1),
          title: '💾 الخطوة الأخيرة: حفظ رابط متجرك',
          subSteps: const [
            _SubStep(icon: Icons.copy_rounded, text: 'انسخ الرابط الذي حصلت عليه (مثال: https://my-store.vercel.app) والصقه في الخانة أسفل الشاشة ثم اضغط حفظ.'),
          ],
          actionButton: null,
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 3️⃣ قسم النشر الذكي لـ Firebase Hosting (الفكرة A)
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildFirebaseHostingSmartSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('🚀 معالج النشر الذكي على Firebase Hosting (الفكرة A):'),
        const SizedBox(height: 12),

        _buildSparkPlanNoticeCard(),
        const SizedBox(height: 12),

        // بطاقة التحكم في النشر الذكي
        _buildSmartDeploymentCard(),
        const SizedBox(height: 16),

        // شاشة السجل الحي واللوغات
        _buildLiveConsoleCard(),
        const SizedBox(height: 16),

        // خطوات الدليل اليدوي البديل (للمعلومة والأنظمة الأخرى)
        _buildManualGuideAccordion(),
      ],
    );
  }

  /// بطاقة معالج النشر الذكي
  Widget _buildSmartDeploymentCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [Colors.amber.shade50, Colors.white],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
          border: Border.all(color: Colors.amber.shade300),
        ),
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFFE65100), size: 28),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'النشر بنقرة زر واحدة (أتمتة شاملة)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFFB45309)),
                      ),
                      Text(
                        'فحص وتثبيت الأدوات ← تسجيل الدخول ← تجهيز الحزمة ← الرفع المباشر',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // خانة معرّف المشروع
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.folder_shared_rounded, size: 18, color: Color(0xFFE65100)),
                      SizedBox(width: 6),
                      Text(
                        'معرّف مشروع Firebase المستهدف (Project ID):',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _projectIdInputController,
                    enabled: !_isDeploying,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                      hintText: 'مثال: alnasser-store-12345',
                      hintTextDirection: TextDirection.ltr,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.refresh_rounded, size: 20),
                        tooltip: 'استعادة من إعدادات المزامنة',
                        onPressed: () async {
                          final pId = await FirebaseCustomConfig.getProjectId();
                          if (pId != null) {
                            setState(() {
                              _projectIdInputController.text = pId;
                            });
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // شريط مؤشر المراحل المرئية (Stepper)
            _buildVisualDeploymentStepper(),
            const SizedBox(height: 16),

            // زر النشر الرئيسي وزر الإلغاء
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _isDeploying ? null : _deployToFirebaseHostingSmart,
                      icon: _isDeploying
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                            )
                          : const Icon(Icons.rocket_launch_rounded, size: 24),
                      label: Text(
                        _isDeploying ? 'جاري النشر...' : '🚀 نشر المتجر الآن بنقرة واحدة',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE65100),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 2,
                      ),
                    ),
                  ),
                ),
                if (_isDeploying) ...[
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 50,
                    child: OutlinedButton.icon(
                      onPressed: _cancelDeploy,
                      icon: const Icon(Icons.stop_circle_rounded, color: Colors.red),
                      label: const Text('إلغاء', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ],
            ),

            // رسالة الحالة
            if (_deployStatusMessage.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _deployStep == -1
                      ? Colors.red.shade50
                      : (_deployStep == 6 ? Colors.green.shade50 : Colors.amber.shade50),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _deployStep == -1
                        ? Colors.red.shade300
                        : (_deployStep == 6 ? Colors.green.shade300 : Colors.amber.shade300),
                  ),
                ),
                child: Text(
                  _deployStatusMessage,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: _deployStep == -1
                        ? Colors.red.shade900
                        : (_deployStep == 6 ? Colors.green.shade900 : Colors.amber.shade900),
                  ),
                ),
              ),
            ],

            // بطاقة النجاح الاحتفالية مع الرابط
            if (_deployedUrl != null) ...[
              const SizedBox(height: 16),
              _buildDeploymentSuccessCard(_deployedUrl!),
            ],
          ],
        ),
      ),
    );
  }

  /// شريط المراحل المرئي لنشر Firebase
  Widget _buildVisualDeploymentStepper() {
    final steps = [
      {'num': '1', 'title': 'Node.js'},
      {'num': '2', 'title': 'Firebase CLI'},
      {'num': '3', 'title': 'تجهيز الحزمة'},
      {'num': '4', 'title': 'الدخول'},
      {'num': '5', 'title': 'الرفع'},
    ];

    return Row(
      children: steps.asMap().entries.map((entry) {
        final idx = entry.key + 1;
        final step = entry.value;
        final isDone = _deployStep > idx || _deployStep == 6;
        final isCurrent = _deployStep == idx;
        final isError = _deployStep == -1 && isCurrent;

        Color circleColor;
        if (isDone) {
          circleColor = Colors.green;
        } else if (isCurrent) {
          circleColor = Colors.orange;
        } else if (isError) {
          circleColor = Colors.red;
        } else {
          circleColor = Colors.grey.shade400;
        }

        return Expanded(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: circleColor,
                        shape: BoxShape.circle,
                        boxShadow: isCurrent
                            ? [
                                BoxShadow(
                                  color: Colors.orange.withOpacity(0.4),
                                  blurRadius: 8,
                                  spreadRadius: 2,
                                )
                              ]
                            : null,
                      ),
                      child: Center(
                        child: isDone
                            ? const Icon(Icons.check, color: Colors.white, size: 16)
                            : (isCurrent
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                  )
                                : Text(
                                    step['num']!,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                                  )),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      step['title']!,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                        color: isCurrent ? Colors.orange.shade900 : Colors.grey.shade700,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (entry.key < steps.length - 1)
                Container(
                  width: 16,
                  height: 2,
                  color: isDone ? Colors.green : Colors.grey.shade300,
                  margin: const EdgeInsets.only(bottom: 16),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }

  /// بطاقة النجاح عند اكتمال النشر
  Widget _buildDeploymentSuccessCard(String url) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF86EFAC), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.celebration_rounded, color: Color(0xFF16A34A), size: 24),
              SizedBox(width: 8),
              Text(
                '🎉 تم نشر متجرك بنجاح على الإنترنت!',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF166534)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Row(
              children: [
                const Icon(Icons.link_rounded, color: Colors.green, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    url,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                      color: Color(0xFF15803D),
                    ),
                    textDirection: TextDirection.ltr,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _launchExternalUrl(url),
                  icon: const Icon(Icons.open_in_browser_rounded, size: 16),
                  label: const Text('فتح المتجر'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              ElevatedButton.icon(
                onPressed: () => _copyToClipboard(url, '✅ تم نسخ الرابط'),
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('نسخ'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F766E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                ),
              ),
              const SizedBox(width: 6),
              ElevatedButton.icon(
                onPressed: () {
                  Share.share('🌐 رابط متجري على الإنترنت:\n$url');
                },
                icon: const Icon(Icons.share_rounded, size: 16),
                label: const Text('مشاركة'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1D4ED8),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// شاشة السجل الحي للعمليات (Live Console)
  Widget _buildLiveConsoleCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF334155)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // شريط رأس الكونسول
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF1E293B),
              borderRadius: BorderRadius.vertical(top: Radius.circular(13)),
            ),
            child: Row(
              children: [
                Container(width: 10, height: 10, decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Container(width: 10, height: 10, decoration: const BoxDecoration(color: Colors.amber, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Container(width: 10, height: 10, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
                const SizedBox(width: 12),
                const Icon(Icons.terminal_rounded, size: 16, color: Colors.white70),
                const SizedBox(width: 6),
                const Text(
                  'سجل العمليات المباشر (Deployment Logs)',
                  style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(_showLogs ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: Colors.white70, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: _showLogs ? 'طي السجل' : 'عرض السجل',
                  onPressed: () {
                    setState(() {
                      _showLogs = !_showLogs;
                    });
                  },
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.copy_rounded, color: Colors.white70, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'نسخ السجل بالكامل',
                  onPressed: () => _copyToClipboard(_deployLog, '✅ تم نسخ سجل العمليات'),
                ),
              ],
            ),
          ),

          // منطقة النصوص للسجل
          if (_showLogs)
            Container(
              height: 180,
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              child: SingleChildScrollView(
                controller: _logScrollController,
                child: Text(
                  _deployLog.isEmpty ? 'جاهز للبدء... اضغط على زر النشر أعلاه.' : _deployLog,
                  style: const TextStyle(
                    color: Color(0xFF38BDF8),
                    fontFamily: 'monospace',
                    fontSize: 11.5,
                    height: 1.5,
                  ),
                  textDirection: TextDirection.ltr,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// أكورديون الدليل اليدوي البديل
  Widget _buildManualGuideAccordion() {
    final hasProject = _firebaseProjectId != null && _firebaseProjectId!.isNotEmpty;
    final hostingUrl = hasProject
        ? 'https://console.firebase.google.com/project/$_firebaseProjectId/hosting'
        : 'https://console.firebase.google.com';

    return ExpansionTile(
      title: const Text(
        '📚 أو خطوات النشر اليدوي البديل (خطوة بخطوة للمحترفين):',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Color(0xFF0D47A1)),
      ),
      children: [
        _buildDetailedStepCard(
          stepNumber: '1',
          stepColor: const Color(0xFFFFA000),
          title: '🔥 فتح Firebase Console وتفعيل Hosting',
          subSteps: const [
            _SubStep(icon: Icons.open_in_browser_rounded, text: 'افتح لوحة تحكم Firebase وتأكد من تفعيل قسم Hosting بمشروعك.'),
          ],
          actionButton: ElevatedButton.icon(
            onPressed: () => _launchExternalUrl(hostingUrl),
            icon: const Icon(Icons.local_fire_department_rounded, size: 20),
            label: const Text('🔥 فتح صفحة Hosting للمشروع'),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFA000), foregroundColor: Colors.white),
          ),
        ),
        const SizedBox(height: 10),
        _buildDetailedStepCard(
          stepNumber: '2',
          stepColor: const Color(0xFF1565C0),
          title: '⚙️ أوامر سطر الأوامر (CMD):',
          subSteps: const [
            _SubStep(icon: Icons.terminal_rounded, text: 'انسخ الأوامر التالية بالترتيب:'),
          ],
          actionButton: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildCommandTile('① تثبيت Firebase CLI:', 'npm install -g firebase-tools'),
              const SizedBox(height: 6),
              _buildCommandTile('② تسجيل الدخول:', 'firebase login'),
              const SizedBox(height: 6),
              _buildCommandTile('③ بناء نسخة الويب:', 'flutter build web --release'),
              const SizedBox(height: 6),
              _buildCommandTile('④ رفع الاستضافة:', 'firebase deploy --only hosting'),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🎨 بطاقات وأدوات مساعدة
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCommandTile(String label, String cmd) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                const SizedBox(height: 4),
                Text(
                  cmd,
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontFamily: 'monospace',
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                  ),
                  textDirection: TextDirection.ltr,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy_rounded, color: Colors.white, size: 20),
            tooltip: 'نسخ الأمر',
            onPressed: () => _copyToClipboard(cmd, '✅ تم نسخ الأمر: $cmd'),
          ),
        ],
      ),
    );
  }

  Widget _buildPackageDownloaderCard() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [Colors.blue.shade50, Colors.white],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
        ),
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.archive_rounded, color: Color(0xFF0288D1), size: 28),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ملف حزمة الويب (web_app.zip)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        'هذا الملف هو موقعك جاهزاً للرفع على أي من المنصات الثلاث',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _isPackaging ? null : _generateWebPackage,
                icon: _isPackaging
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.download_for_offline_rounded, size: 22),
                label: Text(
                  _isPackaging
                      ? 'جاري التجهيز...'
                      : (kIsWeb
                          ? '📥 تنزيل حزمة الويب (web_app.zip) عبر المتصفح'
                          : '📥 تجهيز وتنزيل الحزمة إلى التنزيلات / سطح المكتب'),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            if (_packageStatus.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _packageStatus.contains('❌') ? Colors.red.shade50 : Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _packageStatus.contains('❌') ? Colors.red.shade200 : Colors.green.shade200,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _packageStatus,
                      style: TextStyle(
                        color: _packageStatus.contains('❌') ? Colors.red.shade900 : Colors.green.shade900,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (_packageSavedPath != null) ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _openSavedFolder,
                        icon: const Icon(Icons.folder_open_rounded, size: 18),
                        label: const Text('📂 فتح المجلد الذي يحتوي على الحزمة'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.green.shade900,
                          side: BorderSide(color: Colors.green.shade400),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildVisualDragDropSimulationCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
            ),
            child: Row(
              children: [
                Row(
                  children: [
                    Container(width: 10, height: 10, decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Container(width: 10, height: 10, decoration: const BoxDecoration(color: Colors.amber, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Container(width: 10, height: 10, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      '🔒 https://app.netlify.com/drop',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                      textDirection: TextDirection.ltr,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF00AD9F),
                  width: 2,
                  style: BorderStyle.solid,
                ),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.cloud_upload_rounded,
                    size: 46,
                    color: Color(0xFF00AD9F),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'اسحب ملف (web_app.zip) أو مجلد الموقع وأفلته هنا داخل الصفحة',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF00695C)),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Drag and drop your site folder here',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontFamily: 'monospace'),
                    textDirection: TextDirection.ltr,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFreePlanGuaranteeBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF81C784)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_user_rounded, color: Color(0xFF2E7D32), size: 26),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '🔒 استضافة مجانية 100% مدى الحياة',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1B5E20)),
                ),
                SizedBox(height: 4),
                Text(
                  'جميع المنصات المعروضة (Netlify, Vercel, Firebase) توفر خططاً مجانية بالكامل دون الحاجة لإدخال أي بطاقة دفع أو فيزا.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF2E7D32), height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSparkPlanNoticeCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade400),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.star_rounded, color: Colors.orange, size: 26),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '⭐ الخطة المجانية Spark في Firebase',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Color(0xFFE65100)),
                ),
                SizedBox(height: 4),
                Text(
                  'تمنحك استضافة فايربيز 10 جيجابايت تخزين مجاناً مدى الحياة دون إدخال أي وسيلة دفع. ابقَ دائماً على الخطة المجانية Spark.',
                  style: TextStyle(fontSize: 12, color: Color(0xFFBF360C), height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIosPwaTipCard() {
    return Card(
      color: Colors.blue.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: const Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.phone_iphone_rounded, color: Color(0xFF0288D1), size: 22),
                SizedBox(width: 8),
                Text(
                  '📱 نصيحة مهمة لهواتف iPhone والآيباد:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF01579B)),
                ),
              ],
            ),
            SizedBox(height: 6),
            Text(
              'عند فتح الرابط في متصفح Safari، اضغط على زر المشاركة (المربع ذو السهم لأعلى ⎋) ثم اختر "إضافة إلى الشاشة الرئيسية (Add to Home Screen)". سيتحول الموقع إلى تطبيق مستقل ويحمي بياناتك المخزنة من الحذف التلقائي.',
              style: TextStyle(fontSize: 12, color: Color(0xFF0277BD), height: 1.6),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0D47A1)),
    );
  }

  Widget _buildDetailedStepCard({
    required String stepNumber,
    required Color stepColor,
    required String title,
    required List<_SubStep> subSteps,
    Widget? actionButton,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: stepColor,
                  child: Text(
                    stepNumber,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...subSteps.map((step) {
              return Padding(
                padding: const EdgeInsets.only(right: 44, bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: stepColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(step.icon, color: stepColor, size: 16),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        step.text,
                        style: TextStyle(
                          color: Colors.grey.shade800,
                          fontSize: 12.5,
                          height: 1.55,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
            if (actionButton != null) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(right: 44),
                child: actionButton,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBottomStoreUrlBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '🔗 رابط متجرك المباشر (احفظه هنا للوصول السريع والمشاركة):',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _storeUrlController,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                      hintText: 'https://my-shop.netlify.app أو https://my-shop.vercel.app أو https://project.web.app',
                      hintTextDirection: TextDirection.ltr,
                      prefixIcon: const Icon(Icons.link_rounded, color: Colors.blueAccent),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                    onSubmitted: _saveStoreUrl,
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => _saveStoreUrl(_storeUrlController.text),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0D47A1),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('حفظ'),
                ),
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.open_in_browser_rounded, color: Colors.green),
                  tooltip: 'فتح في المتصفح',
                  onPressed: () {
                    final url = _storeUrlController.text.trim();
                    if (url.isNotEmpty) _launchExternalUrl(url);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.share_rounded, color: Colors.blue),
                  tooltip: 'مشاركة الرابط',
                  onPressed: () {
                    final url = _storeUrlController.text.trim();
                    if (url.isNotEmpty) {
                      Share.share('🌐 رابط متجري على الإنترنت:\n$url');
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
