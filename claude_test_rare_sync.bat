@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion
cd /d "%~dp0"
rem ==========================================================================
rem  claude_test_rare_sync.bat        = فروع المزامنة النادرة (سيناريوهات موجّهة)
rem  claude_test_rare_sync.bat cover  = نفسه مع خريطة الأسطر التي مرّ بها (أبطأ)
rem  النتيجة: test_results\rare_sync\
rem ==========================================================================
if not exist test_results mkdir test_results
if not exist test_results\rare_sync mkdir test_results\rare_sync
for /f "tokens=1-3 delims=/:. " %%a in ("%time: =0%") do set T=%%a%%b%%c
set OUT=test_results\rare_sync\rare_%date:~-4%%date:~-7,2%%date:~-10,2%_!T!.txt
set COV=
if /i "%~1"=="cover" set COV=--coverage --dart-define=COVERAGE=true
echo فروع المزامنة النادرة — النتيجة في %OUT%
echo يأخذ 10 إلى 30 دقيقة. لا تغلق النافذة.
call flutter test %COV% --dart-define=FAST_DISK=true test\sync_harness\rare_sync_branches_test.dart --reporter expanded > %OUT% 2>&1
set RC=%ERRORLEVEL%
echo.
findstr /c:"━━" /c:"✓ " /c:"هنا وقع خطأ" /c:"نجح:" %OUT%
if /i "%~1"=="cover" (
  echo.
  echo الخريطة:
  call dart run tool\money_coverage.dart
  copy /y test_results\money_coverage\report.txt test_results\rare_sync\coverage_report.txt >nul
)
echo.
if "%RC%"=="0" (echo ✅ نجح الاختبار) else (echo ❌ هنا وقع خطأ — أرسل لي الملف %OUT%)
endlocal
