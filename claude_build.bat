@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo START %date% %time% > build\claude_build.txt
call flutter build windows --debug >> build\claude_build.txt 2>&1
echo EXIT %errorlevel% %time% >> build\claude_build.txt
