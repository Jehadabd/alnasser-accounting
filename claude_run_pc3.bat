@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo START %date% %time% > build\claude_run_pc3.txt
"%USERPROFILE%\Desktop\alnaser_pc3_sim\debt_book.exe" >> build\claude_run_pc3.txt 2>&1
echo EXIT %errorlevel% %time% >> build\claude_run_pc3.txt
