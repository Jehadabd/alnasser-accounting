@echo off
chcp 65001 >nul
rem رفع الخادم إلى خادم Oracle Cloud (أو أي Ubuntu) من هذه الحاسبة عبر SSH المدمج في ويندوز
cd /d "%~dp0"
where ssh >nul 2>nul || (echo برنامج SSH غير موجود: الإعدادات - التطبيقات - ميزات اختيارية - أضف OpenSSH Client & pause & exit /b 1)
set /p IP=عنوان IP لخادم Oracle (Public IP address): 
set /p KEYFILE=مسار ملف المفتاح الخاص (.key): 
set KEYFILE=%KEYFILE:"=%
if not exist "%KEYFILE%" (echo لم أجد ملف المفتاح: %KEYFILE% & pause & exit /b 1)
set /p USR=اسم المستخدم - اضغط Enter فقط إن كان ubuntu: 
if "%USR%"=="" set USR=ubuntu
set /p API_KEY=الصق «مفتاح الخادم» من البرنامج: 
rem ويندوز يرفض المفتاح إن كان مقروءاً لغيرك: نجعله لك وحدك
icacls "%KEYFILE%" /inheritance:r >nul
icacls "%KEYFILE%" /grant:r "%USERNAME%:R" >nul
echo.
echo == الاتصال بالخادم ورفع الملفات...
ssh -i "%KEYFILE%" -o StrictHostKeyChecking=accept-new %USR%@%IP% "mkdir -p ~/alnaser-wa" || (echo تعذّر الاتصال — راجع العنوان وملف المفتاح & pause & exit /b 1)
scp -i "%KEYFILE%" server.js package.json install-oracle.sh %USR%@%IP%:~/alnaser-wa/ || (pause & exit /b 1)
echo == التثبيت (3 إلى 8 دقائق)...
ssh -i "%KEYFILE%" %USR%@%IP% "cd ~/alnaser-wa && sudo bash install-oracle.sh %API_KEY%"
pause
