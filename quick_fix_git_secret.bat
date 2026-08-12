@echo off
echo ========================================
echo حل سريع لمشكلة GitHub Secret Scanning
echo ========================================
echo.
echo المشكلة: GitHub يمنع push بسبب Groq API Key مكشوف
echo.
echo ========================================
echo الحل السريع (موصى به):
echo ========================================
echo.
echo 1. افتح هذا الرابط في المتصفح:
echo    https://github.com/Jehadabd/bebet/security/secret-scanning/unblock-secret/360gSdiKZoYQzZ7ULbwaRLO7pyz
echo.
echo 2. اضغط على "Allow secret"
echo.
echo 3. ثم ارجع هنا واضغط اي مفتاح للمتابعة...
pause
echo.
echo ========================================
echo محاولة Push مرة اخرى...
echo ========================================
git push origin main
echo.
echo ========================================
echo مهم جدا: غير الـ API Key فورا!
echo ========================================
echo.
echo 1. افتح: https://console.groq.com/keys
echo 2. احذف المفتاح القديم
echo 3. انشئ مفتاح جديد
echo 4. حدث ملف .env المحلي
echo.
echo ========================================
pause
