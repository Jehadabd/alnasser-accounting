@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion
cd /d "%~dp0"
rem ==========================================================================
rem  claude_test_armored.bat — المطابقة المحصّنة لا تكتب على جهاز آخر دون موافقة صاحبه
rem  النتيجة: test_results\armored\
rem ==========================================================================
if not exist test_results mkdir test_results
if not exist test_results\armored mkdir test_results\armored
for /f "tokens=1-3 delims=/:. " %%a in ("%time: =0%") do set T=%%a%%b%%c
set OUT=test_results\armored\arm_%date:~-4%%date:~-7,2%%date:~-10,2%_!T!.txt
echo المطابقة المحصّنة — النتيجة في %OUT%
echo يأخذ 3 إلى 10 دقائق. لا تغلق النافذة.
call flutter test --dart-define=FAST_DISK=true test\sync_harness\armored_approval_test.dart --reporter expanded > %OUT% 2>&1
set RC=%ERRORLEVEL%
echo.
findstr /c:"✓ " /c:"هنا وقع خطأ" /c:"نجح:" %OUT%
echo.
if "%RC%"=="0" (echo ✅ نجح الاختبار) else (echo ❌ هنا وقع خطأ — أرسل لي الملف %OUT%)
endlocal
