@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion
cd /d "%~dp0"
rem ==========================================================================
rem  claude_test_warranty.bat — ضمان المادة على سطر الفاتورة (جهازان متزامنان)
rem   الحساب، بطاقة المادة، الفاتورة الجديدة والتعديل والمعلّقة والكاشير، من تاريخ الشراء،
rem   أعمدة الطباعة، ووصول الضمان المثبَّت إلى الجهاز الآخر. النتيجة: test_results\warranty\
rem ==========================================================================
if not exist test_results mkdir test_results
if not exist test_results\warranty mkdir test_results\warranty
for /f "tokens=1-3 delims=/:. " %%a in ("%time: =0%") do set T=%%a%%b%%c
set OUT=test_results\warranty\warranty_%date:~-4%%date:~-7,2%%date:~-10,2%_!T!.txt
echo اختبار الضمان — النتيجة في %OUT%
echo يأخذ 1 إلى 3 دقائق. لا تغلق النافذة.
call flutter test test\sync_harness\warranty_test.dart --reporter expanded > %OUT% 2>&1
set RC=%ERRORLEVEL%
echo.
findstr /c:"✓ " /c:"هنا وقع خطأ" /c:"نجح:" /c:"All tests passed" /c:"Some tests failed" %OUT%
echo.
if "%RC%"=="0" (echo ✅ نجح الاختبار) else (echo ❌ هنا وقع خطأ — أرسل لي الملف %OUT%)
endlocal & exit /b %RC%
