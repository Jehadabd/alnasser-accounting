@echo off
chcp 65001 >nul
rem تشغيل خادم واتساب على هذه الحاسبة — الرابط في البرنامج: http://127.0.0.1:8080
cd /d "%~dp0"
where node >nul 2>nul || (echo ثبّت Node.js 20 أو أحدث من https://nodejs.org ثم أعد التشغيل & pause & exit /b 1)
where git >nul 2>nul || (echo ثبّت Git من https://git-scm.com ثم أعد التشغيل & pause & exit /b 1)
if not exist .env (
  set /p API_KEY=الصق «مفتاح الخادم» من البرنامج: 
  call echo API_KEY=%%API_KEY%%> .env
)
if not exist node_modules (call npm install --omit=dev --no-audit --no-fund || (pause & exit /b 1))
node server.js
pause
