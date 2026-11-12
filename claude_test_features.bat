@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion
cd /d "%~dp0"
rem ==========================================================================
rem  claude_test_features.bat              = اختبار الميزات المتبقية السريع (300 عملية)
rem  claude_test_features.bat full         = الكامل: 3000 عملية
rem  claude_test_features.bat quick 123456 = بقرعة محددة (لإعادة خطأ ظهر بالضبط)
rem  يختبر: مطابقة البنك، كلفة الشحن والتخليص، الدفعات وتواريخ الصلاحية، السند المركّب،
rem  إقفال السنة، إعادة تقييم الدولار، سند تعديل الفاتورة النقدية، حذف المعلّقة فقط،
rem  وسند القبض المؤرشف. النتيجة: test_results\features\ والملخص summary.txt
rem ==========================================================================
set MODE=%~1
set SEEDARG=
if not "%~2"=="" set SEEDARG=--dart-define=SEED=%~2
set QUICKARG=--dart-define=QUICK=true
if /i "%MODE%"=="full" set QUICKARG=
if not exist test_results mkdir test_results
if not exist test_results\features mkdir test_results\features
for /f "tokens=1-3 delims=/:. " %%a in ("%time: =0%") do set T=%%a%%b%%c
set OUT=test_results\features\feat_%date:~-4%%date:~-7,2%%date:~-10,2%_!T!.txt
set PROG=test_results\features\progress.txt
set DONE=test_results\features\done.txt
set SUMMARY=test_results\features\summary.txt
del /q %PROG% %DONE% %SUMMARY% 2>nul
echo اختبار الميزات المتبقية %MODE% — النتيجة في %OUT%
echo لا تغلق النافذة. البناء يأخذ دقيقة أو اثنتين قبل أن يظهر العداد.
echo.
start "" /b cmd /c "flutter test test\sync_harness\features_torture_test.dart --dart-define=FAST_DISK=true %QUICKARG% %SEEDARG% --reporter expanded > %OUT% 2>&1 && (echo ok> %DONE%) || (echo fail> %DONE%)"
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
if /i "!RES!"=="ok" (
  title نجح
  echo ===== نجح التشغيل =====
) else (
  title هنا وقع خطأ
  echo ===== هنا وقع خطأ — أرسل لـClaude الملف %OUT% =====
)
pause
