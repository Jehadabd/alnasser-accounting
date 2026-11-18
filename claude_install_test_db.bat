@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion
cd /d "%~dp0"
rem ==========================================================================
rem  claude_install_test_db.bat
rem  يحذف قاعدة البرنامج الحالية نهائياً — بلا نسخة — ويضع مكانها قاعدة الاختبار
rem  test_results\one_invoice\debt_book.db التي كتبها claude_test_one_invoice.bat
rem  لا يغيّر أي إعداد ولا الترخيص ولا النسخة الاحتياطية debt_book_safety_backup.db
rem ==========================================================================
set "SRC=%~dp0test_results\one_invoice\debt_book.db"
set "DST=%APPDATA%\Alnaser\AlnaserAccounting"
if not exist "%SRC%" (
  echo هنا وقع خطأ: لا توجد قاعدة اختبار. شغّل claude_test_one_invoice.bat أولاً.
  pause
  exit /b 1
)
if not exist "%DST%\" (
  echo هنا وقع خطأ: مجلد البرنامج غير موجود: %DST%
  pause
  exit /b 1
)
tasklist /FI "IMAGENAME eq debt_book.exe" 2>nul | find /I "debt_book.exe" >nul
if not errorlevel 1 (
  echo البرنامج مفتوح. أغلقه تماماً ثم شغّل هذا الملف من جديد.
  pause
  exit /b 1
)
set SYNC=?
for /f "usebackq delims=" %%v in (`powershell -NoProfile -Command "try { $j = Get-Content -Raw -Encoding UTF8 '%DST%\shared_preferences.json' | ConvertFrom-Json; [string]$j.'flutter.firebase_sync_enabled' } catch { 'ERR' }"`) do set "SYNC=%%v"
if /i "!SYNC!"=="True" (
  echo توقف: مزامنة Firebase مفعّلة على هذا الجهاز.
  echo بقاعدة جديدة سيسحب البرنامج بيانات السحابة إليها فتختلط بالفاتورة،
  echo ويرفع آلاف تعديلات الاختبار إلى السحابة والأجهزة الأخرى.
  echo افتح البرنامج، أوقف المزامنة من إعداداتها، أغلقه، ثم شغّل هذا الملف من جديد.
  pause
  exit /b 1
)
if /i "!SYNC!"=="ERR" (
  echo هنا وقع خطأ: تعذّرت قراءة إعدادات البرنامج لمعرفة حالة المزامنة. لم يُحذف شيء.
  pause
  exit /b 1
)
if exist "%DST%\demo_mode.flag" (
  echo تنبيه: الوضع التجريبي مفعّل — البرنامج سيفتح القاعدة التجريبية لا هذه. أوقفه من البرنامج بعد التثبيت.
)
echo.
echo سيُحذف نهائياً — بلا نسخة ولا رجعة:
for %%f in ("%DST%\debt_book.db" "%DST%\debt_book.db-wal" "%DST%\debt_book.db-shm") do if exist %%f echo    %%~f   %%~zf بايت
echo وتوضع مكانها قاعدة الاختبار: %SRC%
echo.
set ANS=
set /p ANS=للمتابعة اكتب DELETE ثم Enter: 
if not "!ANS!"=="DELETE" (
  echo أُلغي. لم يُحذف شيء.
  pause
  exit /b 0
)
del /f /q "%DST%\debt_book.db-wal" "%DST%\debt_book.db-shm" "%DST%\debt_book.db" 2>nul
if exist "%DST%\debt_book.db" (
  echo هنا وقع خطأ: تعذّر حذف القاعدة — هل البرنامج ما زال مفتوحاً؟ لم يُنسخ شيء.
  pause
  exit /b 1
)
if exist "%DST%\debt_book.db-wal" (
  echo هنا وقع خطأ: بقي ملف debt_book.db-wal — احذفه يدوياً قبل فتح البرنامج.
  pause
  exit /b 1
)
copy /y "%SRC%" "%DST%\debt_book.db" >nul
if errorlevel 1 (
  echo هنا وقع خطأ: فشل نسخ قاعدة الاختبار. مجلد البرنامج الآن بلا قاعدة.
  pause
  exit /b 1
)
for %%f in ("%DST%\debt_book.db") do echo تم: %%~f   %%~zf بايت
echo.
echo افتح البرنامج: القاعدة بلا مستخدمين، فسيطلب إنشاء حساب المدير أول مرة.
echo ابحث عن «زبون الاختبار الأول» و«زبون الاختبار الثاني»، وافتح فاتورتهما ثم «سجل التعديلات».
pause
