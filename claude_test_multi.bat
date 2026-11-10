@echo off
chcp 65001 >nul
cd /d "%~dp0"
rem ==========================================================================
rem  claude_test_multi.bat              = تعذيب متعدد الأجهزة السريع (~20-40 دقيقة)
rem  claude_test_multi.bat full         = الكامل: 4 أجهزة، 25 عميلاً، 70,000 عملية (ساعات)
rem  claude_test_multi.bat full 123456  = بقرعة محددة (لإعادة خطأ ظهر بالضبط)
rem  كل تشغيل بلا رقم = قرعة جديدة، تُطبع في أول النتيجة وآخرها (seed=...)
rem  النتيجة: test_results\multi\multi_<الوقت>.txt
rem ==========================================================================
set MODE=%~1
set SEEDARG=
if not "%~2"=="" set SEEDARG=--dart-define=SEED=%~2
set QUICKARG=--dart-define=QUICK=true
if /i "%MODE%"=="full" set QUICKARG=
if not exist test_results mkdir test_results
if not exist test_results\multi mkdir test_results\multi
for /f "tokens=1-4 delims=/:. " %%a in ("%time: =0%") do set T=%%a%%b%%c
set OUT=test_results\multi\multi_%date:~-4%%date:~-7,2%%date:~-10,2%_%T%.txt
echo تعذيب متعدد الأجهزة %MODE% — النتيجة في %OUT%
echo لا تغلق النافذة. سطر كل 1000 عملية فيه الوقت المتبقي وعدد المشاكل.
call flutter test test\sync_harness\multi_device_torture_test.dart %QUICKARG% %SEEDARG% --reporter expanded > "%OUT%" 2>&1
set RC=%errorlevel%
findstr /C:"seed=" "%OUT%" | findstr /C:"🎲"
findstr /C:"══" /C:"❌" /C:"✅" "%OUT%"
if %RC% neq 0 (
  echo ===== هنا وقع خطأ — أرسل لـClaude الملف %OUT% =====
) else (
  echo ===== نجح التشغيل =====
)
pause
