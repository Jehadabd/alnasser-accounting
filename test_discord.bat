@echo off
chcp 65001 > nul
echo ═══════════════════════════════════════
echo 🧪 اختبار Discord Backup Service
echo ═══════════════════════════════════════
echo.

dart run test_discord_backup.dart

echo.
echo ═══════════════════════════════════════
pause
