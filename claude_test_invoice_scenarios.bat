@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion
cd /d "%~dp0"
rem ==========================================================================
rem  claude_test_invoice_scenarios.bat              = السريع: 300 سيناريو
rem  claude_test_invoice_scenarios.bat full         = الكامل: 10,000 سيناريو (ساعات)
rem  claude_test_invoice_scenarios.bat quick 123456 = بقرعة محددة (لإعادة خطأ ظهر بالضبط)
rem  كل سيناريو: عميل واحد وفاتورة واحدة تُعدَّل مراراً — دين ⇄ نقد قبل الحفظ وبعده، كمية، سعر،
rem  إضافة وحذف صنف، خصم، نقل، مسدد، تغيير اسم العميل، نقلها لاسم جديد — والحفظ بينها.
rem  النتيجة: test_results\invoice_scenarios\ والملخص summary.txt
rem ==========================================================================
set MODE=%~1
set SEEDARG=
if not "%~2"=="" set SEEDARG=--dart-define=SEED=%~2
set QUICKARG=--dart-define=QUICK=true
if /i "%MODE%"=="full" set QUICKARG=
if not exist test_results mkdir test_results
if not exist test_results\invoice_scenarios mkdir test_results\invoice_scenarios
for /f "tokens=1-3 delims=/:. " %%a in ("%time: =0%") do set T=%%a%%b%%c
set OUT=test_results\invoice_scenarios\scen_%date:~-4%%date:~-7,2%%date:~-10,2%_!T!.txt
set PROG=test_results\invoice_scenarios\progress.txt
set DONE=test_results\invoice_scenarios\done.txt
set SUMMARY=test_results\invoice_scenarios\summary.txt
del /q %PROG% %DONE% %SUMMARY% 2>nul
echo اختبار سيناريوهات الفاتورة %MODE% — النتيجة في %OUT%
echo لا تغلق النافذة. البناء يأخذ دقيقة أو اثنتين قبل أن يظهر العداد.
echo.
start "" /b cmd /c "flutter test test\sync_harness\invoice_scenarios_test.dart --dart-define=FAST_DISK=true %QUICKARG% %SEEDARG% --reporter expanded > %OUT% 2>&1 && (echo ok> %DONE%) || (echo fail> %DONE%)"
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
