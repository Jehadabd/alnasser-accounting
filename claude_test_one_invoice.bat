@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion
cd /d "%~dp0"
rem ==========================================================================
rem  claude_test_one_invoice.bat          = فاتورة واحدة بين عميلين: 1000 سيناريو + 200 معاملة × 20 تعديل
rem  claude_test_one_invoice.bat 123456   = بقرعة محددة لإعادة خطأ ظهر بالضبط
rem  لا يلمس قاعدة البرنامج: الناتج في test_results\one_invoice\debt_book.db
rem  ثم claude_install_test_db.bat يضعها مكان قاعدة البرنامج بعد تأكيدك
rem ==========================================================================
set SEEDARG=
if not "%~1"=="" set SEEDARG=--dart-define=SEED=%~1
if not exist test_results mkdir test_results
if not exist test_results\one_invoice mkdir test_results\one_invoice
for /f "tokens=1-3 delims=/:. " %%a in ("%time: =0%") do set T=%%a%%b%%c
set OUT=test_results\one_invoice\run_%date:~-4%%date:~-7,2%%date:~-10,2%_!T!.txt
set PROG=test_results\one_invoice\progress.txt
set DONE=test_results\one_invoice\done.txt
set SUMMARY=test_results\one_invoice\summary.txt
del /q %PROG% %DONE% %SUMMARY% 2>nul
echo اختبار الفاتورة الواحدة — السجل الكامل في %OUT%
echo لا تغلق النافذة. البناء يأخذ دقيقة أو اثنتين قبل أن يظهر العداد.
echo.
start "" /b cmd /c "flutter test test\sync_harness\one_invoice_history_test.dart --dart-define=FAST_DISK=true %SEEDARG% --reporter expanded > %OUT% 2>&1 && (echo ok> %DONE%) || (echo fail> %DONE%)"
set LAST=
set /a TICK=0
:wait
timeout /t 5 /nobreak >nul
set /a TICK+=1
if exist %PROG% (
  set P=
  set /p P=<%PROG%
  title !P!
  set /a M=TICK %% 6
  if "!M!"=="1" if not "!P!"=="!LAST!" (
    echo   !P!
    set LAST=!P!
  )
)
if not exist %DONE% goto wait
set RES=
set /p RES=<%DONE%
echo.
if exist %SUMMARY% type %SUMMARY%
echo.
if /i "!RES!"=="ok" (
  title نجح
  echo ===== نجح الاختبار =====
) else (
  title هنا وقع خطأ
  echo ===== هنا وقع خطأ — أرسل لـClaude الملفين %SUMMARY% و %OUT% =====
)
if exist test_results\one_invoice\debt_book.db (
  echo القاعدة جاهزة: test_results\one_invoice\debt_book.db
  echo لوضعها في البرنامج: claude_install_test_db.bat
) else (
  echo لم تُكتب القاعدة — لا شيء للتثبيت.
)
pause
