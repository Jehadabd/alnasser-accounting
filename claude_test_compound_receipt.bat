@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion
cd /d "%~dp0"
rem ==========================================================================
rem  claude_test_compound_receipt.bat — الوصل المركّب بعد انقطاع في منتصفه
rem  النتيجة: test_results\compound_receipt\
rem ==========================================================================
if not exist test_results mkdir test_results
if not exist test_results\compound_receipt mkdir test_results\compound_receipt
for /f "tokens=1-3 delims=/:. " %%a in ("%time: =0%") do set T=%%a%%b%%c
set OUT=test_results\compound_receipt\rcpt_%date:~-4%%date:~-7,2%%date:~-10,2%_!T!.txt
echo الوصل المركّب — النتيجة في %OUT%
echo يأخذ 3 إلى 8 دقائق. لا تغلق النافذة.
call flutter test --dart-define=FAST_DISK=true test\sync_harness\compound_receipt_test.dart --reporter expanded > %OUT% 2>&1
set RC=%ERRORLEVEL%
echo.
findstr /c:"✓ " /c:"هنا وقع خطأ" /c:"نجح:" %OUT%
echo.
if "%RC%"=="0" (echo ✅ نجح الاختبار) else (echo ❌ هنا وقع خطأ — أرسل لي الملف %OUT%)
endlocal
