@echo off
echo ========================================
echo تنظيف تاريخ Git من المفاتيح
echo ========================================
echo.
echo هذا سيزيل المفاتيح من جميع الـ commits
echo.
echo تحذير: سيعيد كتابة التاريخ!
echo.
pause
echo.
echo الخطوة 1: نسخة احتياطية...
git branch backup-before-clean-%date:~-4,4%%date:~-10,2%%date:~-7,2%
echo ✅ تم انشاء branch احتياطي
echo.
echo الخطوة 2: انشاء ملف المفاتيح المراد ازالتها...
echo [YOUR_GROQ_KEY_HERE] > secrets_to_remove.txt
echo [YOUR_GEMINI_KEY_HERE] >> secrets_to_remove.txt
echo ✅ تم انشاء ملف المفاتيح
echo.
echo الخطوة 3: تنظيف التاريخ...
echo (قد يستغرق دقيقة...)
echo.

git filter-branch --force --index-filter "git rm --cached --ignore-unmatch AI_EXTRACTION_README.md IMPLEMENTATION_SUMMARY.md" --prune-empty --tag-name-filter cat -- --all

echo.
echo الخطوة 4: تنظيف المراجع...
git for-each-ref --format="delete %%(refname)" refs/original | git update-ref --stdin
git reflog expire --expire=now --all
git gc --prune=now --aggressive
echo.
echo الخطوة 5: دفع التغييرات...
git push --force origin main
echo.
echo ========================================
echo تم! الان:
echo 1. غير المفتاح من Groq Console
echo 2. غير المفتاح من Gemini Console
echo 3. حدث ملف .env المحلي
echo ========================================
echo.
echo للتراجع عن التغييرات:
echo git checkout backup-before-clean-*
echo.
pause
