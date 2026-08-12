@echo off
echo ========================================
echo حذف المفاتيح من تاريخ Git - الطريقة الصحيحة
echo ========================================
echo.
echo هذا سيحذف المفاتيح من جميع الـ commits
echo باستخدام git filter-repo
echo.
echo تحذير: سيعيد كتابة التاريخ!
echo.
pause
echo.
echo ========================================
echo الخطوة 1: التحقق من git filter-repo
echo ========================================
echo.
where git-filter-repo >nul 2>&1
if %errorlevel% neq 0 (
    echo ❌ git-filter-repo غير مثبت!
    echo.
    echo لتثبيته:
    echo 1. حمل من: https://github.com/newren/git-filter-repo/releases
    echo 2. ضع الملف في: C:\Program Files\Git\usr\bin\
    echo 3. اعد تشغيل هذا الملف
    echo.
    pause
    exit /b 1
)
echo ✅ git-filter-repo مثبت
echo.
echo ========================================
echo الخطوة 2: نسخة احتياطية
echo ========================================
git branch backup-before-filter-%date:~-4,4%%date:~-10,2%%date:~-7,2%
echo ✅ تم انشاء branch احتياطي
echo.
echo ========================================
echo الخطوة 3: حذف الملفات من التاريخ
echo ========================================
echo.
echo سيتم حذف هذه الملفات من جميع الـ commits:
echo   - AI_EXTRACTION_README.md
echo   - IMPLEMENTATION_SUMMARY.md
echo   - FIX_GIT_SECRET.md
echo.
pause
echo.
git filter-repo --path AI_EXTRACTION_README.md --path IMPLEMENTATION_SUMMARY.md --path FIX_GIT_SECRET.md --invert-paths --force
echo.
echo ✅ تم حذف الملفات من التاريخ
echo.
echo ========================================
echo الخطوة 4: اعادة اضافة الملفات النظيفة
echo ========================================
git add AI_EXTRACTION_README.md IMPLEMENTATION_SUMMARY.md FIX_GIT_SECRET.md
git commit -m "Re-add documentation files without API keys"
echo.
echo ========================================
echo الخطوة 5: دفع التغييرات
echo ========================================
echo.
echo سيتم استخدام --force لاعادة كتابة التاريخ
pause
echo.
git push origin main --force
echo.
echo ========================================
echo ✅ تم! الان:
echo ========================================
echo 1. غير مفتاح Groq من: https://console.groq.com/keys
echo 2. غير مفتاح Gemini من: https://console.cloud.google.com
echo 3. حدث ملف .env المحلي
echo.
echo للتراجع:
echo git checkout backup-before-filter-*
echo.
pause
