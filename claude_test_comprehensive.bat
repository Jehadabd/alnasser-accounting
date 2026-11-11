@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion
cd /d "%~dp0"
rem ==========================================================================
rem  claude_test_comprehensive.bat              = الشامل السريع (3 أجهزة، 8 عملاء × 3 فواتير × 12 تعديلاً، ~10 دقائق)
rem  claude_test_comprehensive.bat full         = الكامل: 3 أجهزة، 50 عميلاً × 10 فواتير × 100 تعديل = 50,000 (ساعات)
rem  claude_test_comprehensive.bat full 123456  = بقرعة محددة (لإعادة خطأ ظهر بالضبط)
rem  شغّله وحده (لا اختبار آخر معه): كل جهاز وهمي نسخة كاملة من التطبيق في الذاكرة.
rem  كل تشغيل بلا رقم = قرعة جديدة، تُطبع في أول النتيجة وآخرها (seed=...)
rem  عداد حي: شريط ونسبة الإنجاز والوقت المتبقي في عنوان النافذة كل 5 ثوانٍ، وسطر في النافذة كل 30 ثانية.
rem  النتيجة: test_results\comprehensive\comprehensive_<الوقت>.txt
rem ==========================================================================
set MODE=%~1
set SEEDARG=
if not "%~2"=="" set SEEDARG=--dart-define=SEED=%~2
set QUICKARG=--dart-define=QUICK=true
if /i "%MODE%"=="full" set QUICKARG=
if not exist test_results mkdir test_results
if not exist test_results\comprehensive mkdir test_results\comprehensive
for /f "tokens=1-3 delims=/:. " %%a in ("%time: =0%") do set T=%%a%%b%%c
set OUT=test_results\comprehensive\comprehensive_%date:~-4%%date:~-7,2%%date:~-10,2%_!T!.txt
set PROG=test_results\comprehensive\progress.txt
set DONE=test_results\comprehensive\done.txt
set SUMMARY=test_results\comprehensive\summary.txt
del /q %PROG% %DONE% %SUMMARY% 2>nul
echo الاختبار الشامل %MODE% — النتيجة في %OUT%
echo لا تغلق النافذة. البناء يأخذ دقيقة أو اثنتين قبل أن يظهر العداد.
echo.
start "" /b cmd /c "flutter test test\sync_harness\comprehensive_test.dart --dart-define=FAST_DISK=true %QUICKARG% %SEEDARG% --reporter expanded > %OUT% 2>&1 && (echo ok> %DONE%) || (echo fail> %DONE%)"
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
