@echo off
chcp 65001 >nul
echo.
echo ═══════════════════════════════════════════════════════
echo 🧪 اختبار سريع لـ Firebase
echo ═══════════════════════════════════════════════════════
echo.
echo 1. تنظيف المشروع...
call flutter clean
echo.
echo 2. تحميل المكتبات...
call flutter pub get
echo.
echo 3. تشغيل سكريبت الاختبار...
echo.
call flutter run -d windows --target=test_firebase_connection.dart
echo.
echo ═══════════════════════════════════════════════════════
echo ✅ انتهى الاختبار
echo ═══════════════════════════════════════════════════════
echo.
pause
