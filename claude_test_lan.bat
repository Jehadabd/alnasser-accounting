@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion
cd /d "%~dp0"
rem ==========================================================================
rem  claude_test_lan.bat — الشبكة المحلية بكود التطبيق: سيرفر وطرفيتان
rem   ديون وفواتير من الأجهزة معاً، سقوط الشبكة وسط معاملة وبين عمليتين،
rem   طرفية تحاول إضعاف الحفظ على القرص، وسيرفر بإصدار أقدم.
rem  بلا FAST_DISK عمداً (يُفحص إعداد القرص الحقيقي). النتيجة: test_results\lan\
rem ==========================================================================
if not exist test_results mkdir test_results
if not exist test_results\lan mkdir test_results\lan
for /f "tokens=1-3 delims=/:. " %%a in ("%time: =0%") do set T=%%a%%b%%c
set OUT=test_results\lan\lan_%date:~-4%%date:~-7,2%%date:~-10,2%_!T!.txt
echo الشبكة المحلية — النتيجة في %OUT%
echo يأخذ 3 إلى 10 دقائق. لا تغلق النافذة.
call flutter test test\lan\lan_roundtrip_test.dart test\sync_harness\lan_money_test.dart --reporter expanded > %OUT% 2>&1
set RC=%ERRORLEVEL%
echo.
findstr /c:"✓ " /c:"هنا وقع خطأ" /c:"نجح:" /c:"All tests passed" /c:"Some tests failed" %OUT%
echo.
if "%RC%"=="0" (echo ✅ نجح الاختبار) else (echo ❌ هنا وقع خطأ — أرسل لي الملف %OUT%)
endlocal & exit /b %RC%
