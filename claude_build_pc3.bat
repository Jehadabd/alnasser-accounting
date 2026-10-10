@echo off
chcp 65001 >nul
cd /d "%~dp0"
set LOG=build\claude_build_pc3.txt
echo START %date% %time% > %LOG%
copy /y "build\Runner.rc.pc3" "windows\runner\Runner.rc" >> %LOG% 2>&1
call flutter build windows --release >> %LOG% 2>&1
echo BUILD_EXIT %errorlevel% %time% >> %LOG%
copy /y "build\Runner.rc.orig" "windows\runner\Runner.rc" >> %LOG% 2>&1
copy /y ".env" "build\windows\x64\runner\Release\" >> %LOG% 2>&1
robocopy "build\windows\x64\runner\Release" "%USERPROFILE%\Desktop\alnaser_pc3_sim" /MIR /NFL /NDL /NJH /NP >> %LOG% 2>&1
echo === DEBUG BUILD (PC1) %time% >> %LOG%
call flutter build windows --debug >> %LOG% 2>&1
echo DEBUG_EXIT %errorlevel% %time% >> %LOG%
echo EXIT %time% >> %LOG%
