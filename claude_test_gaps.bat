@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion
cd /d "%~dp0"
rem ==========================================================================
rem  claude_test_gaps.bat — اختبارات مسارات المال التي لم يمر بها اختبار
rem   (من تقرير claude_money_coverage.bat). تُضاف إليه الدفعات تباعاً.
rem  النتيجة: test_results\gaps\
rem ==========================================================================
if not exist test_results mkdir test_results
if not exist test_results\gaps mkdir test_results\gaps
for /f "tokens=1-3 delims=/:. " %%a in ("%time: =0%") do set T=%%a%%b%%c
set OUT=test_results\gaps\gaps_%date:~-4%%date:~-7,2%%date:~-10,2%_!T!.txt
echo مسارات المال غير المغطاة — النتيجة في %OUT%
echo يأخذ دقائق. لا تغلق النافذة.
call flutter test --concurrency=1 ^
  test\sync_harness\archive_mark_test.dart ^
  --reporter expanded > %OUT% 2>&1
set RC=%ERRORLEVEL%
echo.
findstr /c:"✓ " /c:"هنا وقع خطأ" /c:"نجح:" /c:"All tests passed" /c:"Some tests failed" %OUT%
echo.
if "%RC%"=="0" (echo ✅ نجح الاختبار) else (echo ❌ هنا وقع خطأ — أرسل لي الملف %OUT%)
endlocal & exit /b %RC%
