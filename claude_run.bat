@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo START %date% %time% > build\claude_run.txt
build\windows\x64\runner\Debug\debt_book.exe >> build\claude_run.txt 2>&1
echo EXIT %errorlevel% %time% >> build\claude_run.txt
