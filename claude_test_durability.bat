@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion
cd /d "%~dp0"
rem ==========================================================================
rem  claude_test_durability.bat — «تم الحفظ» يعني على القرص فعلاً
rem   1) لا سطر في التطبيق يُنزل الكتابة على القرص عن FULL
rem   2) الإعداد FULL منذ الفتح وبعد كل عملية مال (دين، تسديد، فاتورة، تحويل)
rem   3) قتل مفاجئ للتطبيق بعد الحفظ مباشرة: لا شيء يضيع
rem   4) تحويل دين إلى نقد: يُقبض دين الفاتورة نفسها فقط، ولا يمس غيرها
rem      ومعه «سند قبض — تسديد فاتورة» بما قُبض، وسؤال الطباعة (اختبار الواجهة)
rem  بلا FAST_DISK عمداً: يُختبر إعداد القرص الحقيقي كما في التطبيق.
rem  النتيجة: test_results\durability\
rem ==========================================================================
if not exist test_results mkdir test_results
if not exist test_results\durability mkdir test_results\durability
for /f "tokens=1-3 delims=/:. " %%a in ("%time: =0%") do set T=%%a%%b%%c
set OUT=test_results\durability\dur_%date:~-4%%date:~-7,2%%date:~-10,2%_!T!.txt
echo اختبار الحفظ على القرص — النتيجة في %OUT%
echo يأخذ دقيقتين إلى خمس. لا تغلق النافذة.
call flutter test test\widgets\voucher_print_prompt_test.dart test\sync_harness\durability_test.dart --reporter expanded > %OUT% 2>&1
set RC=%ERRORLEVEL%
echo.
findstr /c:"هنا وقع خطأ" /c:"✓ بعد" /c:"✗" /c:"الخطة:" /c:"نجح:" /c:"All tests passed" /c:"Some tests failed" %OUT%
echo.
if "%RC%"=="0" (echo ✅ نجح الاختبار) else (echo ❌ هنا وقع خطأ — أرسل لي الملف %OUT%)
endlocal
