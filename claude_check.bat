@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo START %date% %time% > build\claude_analyze.txt
call flutter analyze --no-pub lib test\schema_healer_test.dart >> build\claude_analyze.txt 2>&1
echo EXIT %errorlevel% %time% >> build\claude_analyze.txt
