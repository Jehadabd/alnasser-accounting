@echo off
chcp 65001 >nul
cd /d "%~dp0"
rem 📱 تجهيز خادم واتساب على الهاتف قبل بناء نسخة أندرويد (tool\wa_android_setup.ps1)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tool\wa_android_setup.ps1"
echo EXIT %errorlevel%
pause
