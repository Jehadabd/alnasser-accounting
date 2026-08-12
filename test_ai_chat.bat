@echo off
echo ========================================
echo اختبار ميزة الدردشة مع الذكاء الاصطناعي
echo ========================================
echo.

echo [1/3] التحقق من الملفات المطلوبة...
if exist "lib\services\ai_chat_service.dart" (
    echo ✓ ai_chat_service.dart موجود
) else (
    echo ✗ ai_chat_service.dart مفقود
    exit /b 1
)

if exist "lib\screens\ai_chat_screen.dart" (
    echo ✓ ai_chat_screen.dart موجود
) else (
    echo ✗ ai_chat_screen.dart مفقود
    exit /b 1
)

echo.
echo [2/3] فحص الأخطاء البرمجية...
flutter analyze lib\services\ai_chat_service.dart
if %errorlevel% neq 0 (
    echo ✗ توجد أخطاء في ai_chat_service.dart
    exit /b 1
)

flutter analyze lib\screens\ai_chat_screen.dart
if %errorlevel% neq 0 (
    echo ✗ توجد أخطاء في ai_chat_screen.dart
    exit /b 1
)

echo ✓ لا توجد أخطاء برمجية
echo.

echo [3/3] بناء التطبيق...
flutter build windows --release
if %errorlevel% neq 0 (
    echo ✗ فشل البناء
    exit /b 1
)

echo.
echo ========================================
echo ✓ نجح الاختبار! الميزة جاهزة للاستخدام
echo ========================================
echo.
echo للتشغيل:
echo 1. افتح التطبيق
echo 2. اضغط على أيقونة الدردشة في الشريط العلوي
echo 3. جرب الاقتراحات السريعة
echo.
pause
