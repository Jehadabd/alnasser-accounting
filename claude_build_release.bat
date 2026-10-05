@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo START %date% %time% > build\claude_build_release.txt
call flutter build windows --release >> build\claude_build_release.txt 2>&1
echo BUILD_EXIT %errorlevel% %time% >> build\claude_build_release.txt
copy /y ".env" "build\windows\x64\runner\Release\" >> build\claude_build_release.txt 2>&1
for %%D in (msvcp140.dll vcruntime140.dll vcruntime140_1.dll) do copy /y "%SystemRoot%\System32\%%D" "build\windows\x64\runner\Release\" >> build\claude_build_release.txt 2>&1
if exist "%USERPROFILE%\Desktop\alnaser_pc2.zip" del /q "%USERPROFILE%\Desktop\alnaser_pc2.zip"
powershell -NoProfile -Command "Compress-Archive -Path 'build\windows\x64\runner\Release\*' -DestinationPath \"$env:USERPROFILE\Desktop\alnaser_pc2.zip\" -Force" >> build\claude_build_release.txt 2>&1
echo EXIT %errorlevel% %time% >> build\claude_build_release.txt
