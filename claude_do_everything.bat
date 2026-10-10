@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo ALL_START %date% %time% > build\claude_all_steps.txt
call "%~dp0claude_check_files.bat"
cd /d "%~dp0"
echo CHECK_DONE %time% >> build\claude_all_steps.txt
call "%~dp0claude_build_all.bat"
cd /d "%~dp0"
echo BUILD_ALL_DONE %time% >> build\claude_all_steps.txt
call "%USERPROFILE%\Desktop\admintool\claude_build_admin.bat"
cd /d "%~dp0"
echo ADMIN_DONE %time% >> build\claude_all_steps.txt
call "%USERPROFILE%\Desktop\shop-maniger-MBmain\claude_check_build_v4.bat"
cd /d "%~dp0"
echo OLD_DONE %time% >> build\claude_all_steps.txt
