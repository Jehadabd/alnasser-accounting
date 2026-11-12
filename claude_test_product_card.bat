@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion
cd /d "%~dp0"
rem ==========================================================================
rem  claude_test_product_card.bat — حركة المادة (بطاقة المادة وتقرير الحركة)
rem   البيع بكميته الأصلية، كل تعديل «كانت X صارت Y» بتاريخه، رقم الفاتورة المطبوع،
rem   الرصيد بعد كل حركة، ومطابقة آخر رصيد لكمية المادة. النتيجة: test_results\product_card\
rem ==========================================================================
if not exist test_results mkdir test_results
if not exist test_results\product_card mkdir test_results\product_card
for /f "tokens=1-3 delims=/:. " %%a in ("%time: =0%") do set T=%%a%%b%%c
set OUT=test_results\product_card\card_%date:~-4%%date:~-7,2%%date:~-10,2%_!T!.txt
echo حركة المادة — النتيجة في %OUT%
echo يأخذ 1 إلى 3 دقائق. لا تغلق النافذة.
call flutter test test\erp\product_card_moves_test.dart test\sync_harness\product_card_test.dart --reporter expanded > %OUT% 2>&1
set RC=%ERRORLEVEL%
echo.
findstr /c:"✓ " /c:"هنا وقع خطأ" /c:"نجح:" /c:"All tests passed" /c:"Some tests failed" %OUT%
echo.
if "%RC%"=="0" (echo ✅ نجح الاختبار) else (echo ❌ هنا وقع خطأ — أرسل لي الملف %OUT%)
endlocal & exit /b %RC%
