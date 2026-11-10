@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion
cd /d "%~dp0"
rem ==========================================================================
rem  claude_test_multi.bat              = تعذيب متعدد الأجهزة السريع (~20-40 دقيقة)
rem  claude_test_multi.bat full         = الكامل: 4 أجهزة، 25 عميلاً، 70,000 عملية (ساعات)
rem  claude_test_multi.bat full 123456  = بقرعة محددة (لإعادة خطأ ظهر بالضبط)
rem  كل تشغيل بلا رقم = قرعة جديدة، تُطبع في أول النتيجة وآخرها (seed=...)
rem  عداد حي: نسبة الإنجاز في عنوان النافذة كل 5 ثوانٍ، وسطر في النافذة كل دقيقة.
rem  النتيجة: test_results\multi\multi_<الوقت>.txt
rem ==========================================================================
set MODE=%~1
set SEEDARG=
if not "%~2"=="" set SEEDARG=--dart-define=SEED=%~2
set QUICKARG=--dart-define=QUICK=true
if /i "%MODE%"=="full" set QUICKARG=
if not exist test_results mkdir test_results
if not exist test_results\multi mkdir test_results\multi
for /f "tokens=1-3 delims=/:. " %%a in ("%time: =0%") do set T=%%a%%b%%c
set OUT=test_results\multi\multi_%date:~-4%%date:~-7,2%%date:~-10,2%_!T!.txt
set PROG=test_results\multi\progress.txt
set DONE=test_results\multi\done.txt
set SUMMARY=test_results\multi\summary.txt
del /q %PROG% %DONE% %SUMMARY% 2>nul
echo تعذيب متعدد الأجهزة %MODE% — النتيجة في %OUT%
echo لا تغلق النافذة. البناء يأخذ دقيقة أو اثنتين قبل أن يظهر العداد.
echo.
start "" /b cmd /c "flutter test test\sync_harness\multi_device_torture_test.dart %QUICKARG% %SEEDARG% --reporter expanded > %OUT% 2>&1 && (echo ok> %DONE%) || (echo fail> %DONE%)"
set LAST=
set /a TICK=0
:wait
timeout /t 5 /nobreak >nul
set /a TICK+=1
if exist %PROG% (
  set P=
  set /p P=<%PROG%
  title !P!
  set /a M=TICK %% 12
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
