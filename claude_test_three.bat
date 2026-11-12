@echo off
chcp 65001 >nul
cd /d "%~dp0"
rem ==========================================================================
rem  claude_test_three.bat — بالترتيب، كل واحد بعد انتهاء الذي قبله:
rem   1) الشبكة المحلية   2) نقاط المزامنة النادرة (مع خريطتها)   3) فحص الطفرات
rem  يكمل للتالي حتى إن فشل السابق، وفي النهاية ملخّص الثلاثة.
rem ==========================================================================
echo ===== 1/3 الشبكة المحلية =====
call claude_test_lan.bat
set R1=%ERRORLEVEL%
echo.
echo ===== 2/3 نقاط المزامنة النادرة =====
call claude_test_rare_sync.bat cover
set R2=%ERRORLEVEL%
echo.
echo ===== 3/3 فحص الطفرات =====
call claude_test_mutations.bat
set R3=%ERRORLEVEL%
echo.
echo ===== الملخّص =====
if "%R1%"=="0" (echo ✅ الشبكة المحلية) else (echo ❌ الشبكة المحلية)
if "%R2%"=="0" (echo ✅ المزامنة النادرة) else (echo ❌ المزامنة النادرة)
if "%R3%"=="0" (echo ✅ فحص الطفرات) else (echo ❌ فحص الطفرات)
echo انسخ لي كل ما في النافذة، ومعه test_results\rare_sync\rare_points.txt و test_results\mutations\report.txt
