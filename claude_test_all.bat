@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion
cd /d "%~dp0"
rem ==========================================================================
rem  claude_test_all.bat         = كل الاختبارات + اختبار التعذيب السريع (دقائق)
rem  claude_test_all.bat full    = كل الاختبارات + اختبار التعذيب الكامل (ساعات)
rem  النتائج: test_results\all\  — والملخص: test_results\all\summary.txt
rem ==========================================================================
set MODE=%~1
set OUT=test_results\all
if not exist test_results mkdir test_results
if not exist %OUT% mkdir %OUT%
del /q %OUT%\*.txt 2>nul
set FAILS=0
echo ملخص الاختبارات — %date% %time% > %OUT%\summary.txt

rem كل مجلدات test عدا sync_harness + ملفات test الجذرية
set UNIT=
for /d %%D in (test\*) do if /i not "%%~nxD"=="sync_harness" set UNIT=!UNIT! %%D
for %%F in (test\*_test.dart) do set UNIT=!UNIT! %%F

echo [01] flutter pub get
call flutter pub get > %OUT%\01_pubget.txt 2>&1
call :result 01_pubget "flutter pub get"

echo [02] flutter analyze lib
call flutter analyze lib > %OUT%\02_analyze.txt 2>&1
call :result 02_analyze "flutter analyze lib"

echo [03] اختبارات الوحدات (كل المجلدات عدا sync_harness)
call flutter test %UNIT% > %OUT%\03_unit.txt 2>&1
call :result 03_unit "اختبارات الوحدات"

echo [04] حسابات الفاتورة على الكود الحقيقي
call flutter test test\sync_harness\invoice_math_test.dart > %OUT%\04_invoice_math.txt 2>&1
call :result 04_invoice_math "حسابات الفاتورة"

echo [05] سيناريوهات محاسبية شاملة
call flutter test test\sync_harness\full_accounting_scenarios_test.dart > %OUT%\05_full_accounting.txt 2>&1
call :result 05_full_accounting "سيناريوهات محاسبية شاملة"

echo [06] الموردون
call flutter test test\sync_harness\supplier_flows_test.dart > %OUT%\06_suppliers.txt 2>&1
call :result 06_suppliers "الموردون"

echo [07] المزامنة: دخان، مخاطر متبقية، دمج الأصناف، ترحيل المخزون
call flutter test test\sync_harness\smoke_test.dart test\sync_harness\residual_risks_test.dart test\sync_harness\product_merge_test.dart test\sync_harness\stock_migration_test.dart > %OUT%\07_sync.txt 2>&1
call :result 07_sync "المزامنة"

echo [08] فوضى المزامنة
call flutter test test\sync_harness\chaos_test.dart > %OUT%\08_chaos.txt 2>&1
call :result 08_chaos "فوضى المزامنة"

if /i "%MODE%"=="full" (
  echo [09] اختبار التعذيب الكامل — ساعات، لا تغلق النافذة
  call flutter test test\sync_harness\invoice_torture_test.dart --reporter expanded > %OUT%\09_torture_full.txt 2>&1
  call :result 09_torture_full "اختبار التعذيب الكامل"
) else (
  echo [09] اختبار التعذيب السريع
  call flutter test test\sync_harness\invoice_torture_test.dart --dart-define=QUICK=true --reporter expanded > %OUT%\09_torture_quick.txt 2>&1
  call :result 09_torture_quick "اختبار التعذيب السريع"
)

echo.
type %OUT%\summary.txt
echo.
if !FAILS! GTR 0 (
  echo ===== هنا وقع خطأ: !FAILS! خطوة فشلت — أرسل لـClaude ملفات %OUT% =====
) else (
  echo ===== كل الخطوات نجحت =====
)
echo DONE > %OUT%\done.txt
pause
exit /b 0

:result
if errorlevel 1 (
  echo   FAIL  %~1  %~2 >> %OUT%\summary.txt
  echo   FAIL
  set /a FAILS+=1
) else (
  echo   PASS  %~1  %~2 >> %OUT%\summary.txt
  echo   PASS
)
exit /b 0
