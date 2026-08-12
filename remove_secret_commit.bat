@echo off
echo ========================================
echo ازالة الـ Commit الذي يحتوي على المفتاح
echo ========================================
echo.
echo تحذير: هذا سيعيد كتابة تاريخ Git!
echo.
echo الـ Commit المراد ازالته:
echo 22307e35216fb40000c687edaee385acb4bc5909
echo.
echo ========================================
pause
echo.
echo الخطوة 1: عمل نسخة احتياطية...
git branch backup-before-rebase
echo ✅ تم انشاء branch احتياطي: backup-before-rebase
echo.
echo الخطوة 2: البحث عن الـ commit...
git log --oneline | findstr "22307e3"
echo.
echo الخطوة 3: اعادة كتابة التاريخ...
echo.
echo سيتم فتح محرر Git. اتبع هذه الخطوات:
echo   1. ابحث عن السطر الذي يبدأ بـ "pick 22307e3"
echo   2. غير "pick" الى "drop" او احذف السطر بالكامل
echo   3. احفظ واغلق المحرر
echo.
pause
echo.
git rebase -i 22307e35216fb40000c687edaee385acb4bc5909^
echo.
echo ========================================
echo الخطوة 4: دفع التغييرات...
echo ========================================
git push --force origin main
echo.
echo ========================================
echo تم! الان غير المفتاح من Groq Console
echo ========================================
pause
