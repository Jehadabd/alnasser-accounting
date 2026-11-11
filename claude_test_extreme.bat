@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion
cd /d "%~dp0"
rem ==========================================================================
rem  claude_test_extreme.bat          = السيناريوهات الغريبة والقصوى (12 سيناريو مقصوداً، دقائق)
rem  claude_test_extreme.bat 123456   = بقرعة محددة
rem  أسماء غريبة، مبالغ ضخمة وأقل من نصف دينار، تسديد مزدوج بلا إنترنت، انقطاعات متتالية،
rem  شيكات وأقساط غريبة، مطابقة إلى سالب، موردون في أقصى الحالات، استيراد مرتين...
rem  النتيجة: test_results\extreme\summary.txt (المشاكل + ملاحظات لصاحب المحل)
rem ==========================================================================
set SEEDARG=
if not "%~1"=="" set SEEDARG=--dart-define=SEED=%~1
set QUICKARG=
if not exist test_results mkdir test_results
if not exist test_results\extreme mkdir test_results\extreme
for /f "tokens=1-3 delims=/:. " %%a in ("%time: =0%") do set T=%%a%%b%%c
set OUT=test_results\extreme\extreme_%date:~-4%%date:~-7,2%%date:~-10,2%_!T!.txt
set PROG=test_results\extreme\progress.txt
set DONE=test_results\extreme\done.txt
set SUMMARY=test_results\extreme\summary.txt
del /q %PROG% %DONE% %SUMMARY% 2>nul
echo السيناريوهات الغريبة والقصوى — النتيجة في %OUT%
echo لا تغلق النافذة. البناء يأخذ دقيقة أو اثنتين قبل أن يظهر العداد.
echo.
start "" /b cmd /c "flutter test test\sync_harness\extreme_scenarios_test.dart --dart-define=FAST_DISK=true %QUICKARG% %SEEDARG% --reporter expanded > %OUT% 2>&1 && (echo ok> %DONE%) || (echo fail> %DONE%)"
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
