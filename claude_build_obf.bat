@echo off
chcp 65001 >nul
cd /d "%~dp0"
set LOG=build\claude_build_obf.txt
echo START %date% %time% > %LOG%
copy /y "build\Runner.rc.orig" "windows\runner\Runner.rc" >> %LOG% 2>&1
call flutter build windows --release --obfuscate --split-debug-info=build\symbols >> %LOG% 2>&1
echo BUILD_EXIT %errorlevel% %time% >> %LOG%
copy /y ".env" "build\windows\x64\runner\Release\" >> %LOG% 2>&1
robocopy "build\windows\x64\runner\Release" "%USERPROFILE%\Desktop\alnaser_release_obf" /E /NFL /NDL /NJH /NP >> %LOG% 2>&1
echo EXIT %time% >> %LOG%
