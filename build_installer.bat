@echo off
chcp 65001 > nul
setlocal enabledelayedexpansion

echo =====================================================================
echo   🚀 نظام البناء الشامل والذكي لتطبيق الناصر (Alnaser Build System)
echo =====================================================================
echo.

REM --- 1. فحص وجود Inno Setup ---
set "INNO_EXE="
if exist "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" (
    set "INNO_EXE=C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
) else if exist "C:\Program Files\Inno Setup 6\ISCC.exe" (
    set "INNO_EXE=C:\Program Files\Inno Setup 6\ISCC.exe"
)

REM --- المرحلة 1: بناء نسخة الويب الأحدث ---
echo 🌐 [المرحلة 1/4] جاري بناء نسخة الويب (Flutter Web Release)...
call flutter build web --release
if %ERRORLEVEL% neq 0 (
    echo ❌ فشل بناء نسخة الويب!
    pause
    exit /b %ERRORLEVEL%
)
echo ✅ اكتمل بناء الويب بنجاح.
echo.

REM --- المرحلة 2: تحديث الحزمة المضمنة assets/web_app.zip ديناميكياً ---
echo 📦 [المرحلة 2/4] جاري ضغط وتحديث حزمة assets/web_app.zip تلقائياً...
powershell -NoProfile -Command ^
    "Copy-Item 'web/firebase.json' 'build/web/firebase.json' -Force -ErrorAction SilentlyContinue; " ^
    "Copy-Item 'web/vercel.json' 'build/web/vercel.json' -Force -ErrorAction SilentlyContinue; " ^
    "Copy-Item 'web/_redirects' 'build/web/_redirects' -Force -ErrorAction SilentlyContinue; " ^
    "Remove-Item 'build/web/assets/packages/win_ble/assets/BLEServer.exe' -Force -ErrorAction SilentlyContinue; " ^
    "Remove-Item 'build/web/web_app.zip' -Force -ErrorAction SilentlyContinue; " ^
    "Remove-Item 'build/web/assets/assets/web_app.zip' -Force -ErrorAction SilentlyContinue; " ^
    "Remove-Item 'assets/web_app.zip' -Force -ErrorAction SilentlyContinue; " ^
    "Compress-Archive -Path 'build/web/*' -DestinationPath 'assets/web_app.zip' -Force"

if not exist "assets/web_app.zip" (
    echo ❌ فشل تجهيز ملف assets/web_app.zip!
    pause
    exit /b 1
)
echo ✅ تم تحديث assets/web_app.zip بنجاح وبأحدث التعديلات.
echo.

REM --- المرحلة 3: بناء تطبيق ويندوز المكتبي ---
echo 💻 [المرحلة 3/4] جاري بناء تطبيق ويندوز (Flutter Windows Release)...
call flutter build windows --release
if %ERRORLEVEL% neq 0 (
    echo ❌ فشل بناء تطبيق ويندوز!
    pause
    exit /b %ERRORLEVEL%
)
echo ✅ اكتمل بناء تطبيق ويندوز بنجاح.
echo.

REM --- المرحلة 4: توليد برنامج التثبيت النهائي (Inno Setup) ---
echo 🛠️ [المرحلة 4/4] جاري إنشاء برنامج التثبيت النهائي (AlnaserSetup.exe)...
if not defined INNO_EXE (
    echo ⚠️ لم يتم العثور على Inno Setup 6 تلقائياً.
    echo يرجى تثبيت Inno Setup أو تجميع AlnaserSetup.iss يدوياً.
) else (
    echo ⚙️ تشغيل Inno Setup: "%INNO_EXE%"
    "%INNO_EXE%" "AlnaserSetup.iss"
    if %ERRORLEVEL% equ 0 (
        echo.
        echo =====================================================================
        echo 🎉 تم بنجاح إنشاء برنامج التثبيت النهائي للعملاء!
        echo 📂 مسار الملف: installer_output\AlnaserSetup.exe
        echo 🌟 هذا الملف يحتوي تلقائياً على آخر نسخة ويب ومستعد للتوزيع فوراً!
        echo =====================================================================
    ) else (
        echo ❌ حدث خطأ أثناء تجميع ملف التثبيت بواسطة Inno Setup.
    )
)

echo.
pause 