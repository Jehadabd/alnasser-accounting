@echo off
chcp 65001 >nul
rem رفع الخادم إلى خادم Oracle Cloud (أو أي Ubuntu) من هذه الحاسبة عبر SSH المدمج في ويندوز
cd /d "%~dp0"
set /p IP=عنوان IP لخادم Oracle: 
set /p KEYFILE=مسار ملف المفتاح الخاص (.key) الذي نزّلته من Oracle: 
set /p USR=اسم المستخدم [ubuntu]: 
if "%USR%"=="" set USR=ubuntu
set /p API_KEY=الصق «مفتاح الخادم» من البرنامج: 
ssh -i "%KEYFILE%" -o StrictHostKeyChecking=accept-new %USR%@%IP% "mkdir -p ~/alnaser-wa"
scp -i "%KEYFILE%" server.js package.json install-oracle.sh %USR%@%IP%:~/alnaser-wa/
ssh -i "%KEYFILE%" %USR%@%IP% "cd ~/alnaser-wa && sudo bash install-oracle.sh %API_KEY%"
pause
