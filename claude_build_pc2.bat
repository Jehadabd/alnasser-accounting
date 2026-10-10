@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo START %date% %time% > build\claude_build_pc2.txt
call flutter build windows --release >> build\claude_build_pc2.txt 2>&1
echo BUILD_EXIT %errorlevel% %time% >> build\claude_build_pc2.txt
copy /y ".env" "build\windows\x64\runner\Release\" >> build\claude_build_pc2.txt 2>&1
robocopy "build\windows\x64\runner\Release" "%USERPROFILE%\Desktop\alnaser_pc2_sim" /MIR /NFL /NDL /NJH /NP >> build\claude_build_pc2.txt 2>&1
echo EXIT %errorlevel% %time% >> build\claude_build_pc2.txt
