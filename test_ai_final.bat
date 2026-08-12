@echo off
echo ========================================
echo اختبار نظام الذكاء الاصطناعي - الإصدار النهائي
echo ========================================
echo.
echo الإصلاحات المطبقة:
echo   1. HuggingFace: wait_for_model + timeout اطول
echo   2. Groq: llama-3.2-11b-vision-preview
echo   3. Gemini: logging محسن
echo.
echo الترتيب:
echo   1. HuggingFace (الاولوية)
echo   2. Groq (احتياطي اول)
echo   3. Gemini (احتياطي اخير)
echo.
echo ========================================
echo.
echo تنظيف المشروع...
flutter clean
echo.
echo تحميل المكتبات...
flutter pub get
echo.
echo ========================================
echo تشغيل التطبيق...
echo راقب السجلات للتأكد من:
echo   - HuggingFace ينتظر النموذج
echo   - Groq يستخدم النموذج الجديد
echo   - Gemini يطبع البيانات الخام
echo ========================================
echo.
flutter run
