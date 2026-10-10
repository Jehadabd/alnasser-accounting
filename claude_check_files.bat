@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo START %date% %time% > build\claude_analyze_files.txt
call flutter analyze --no-pub lib\services\license_v4 lib\services\license_service.dart lib\screens\license_screen.dart lib\screens\license_devices_screen.dart lib\screens\login_screen.dart lib\services\auth_service.dart lib\services\password_service.dart lib\screens\general_settings_screen.dart lib\services\firebase_sync\firebase_sync_service.dart lib\services\firebase_sync\users_sync_service.dart lib\services\sync\sync_security.dart lib\screens\user_management_screen.dart lib\lan\windows_autostart.dart lib\services\database\business\invoice_customer_claim.dart lib\services\database\business\customer_locking.dart lib\screens\invoice_actions.dart lib\lan\lan_settings.dart lib\lan\lan_bootstrap.dart lib\lan\network_settings_screen.dart lib\main.dart lib\screens\main_screen.dart lib\screens\inventory_menu_screen.dart lib\screens\create_invoice_screen.dart lib\screens\customer_details_screen.dart lib\widgets\app_side_nav.dart lib\services\database\business\customer_locking.dart test\license_v4_test.dart >> build\claude_analyze_files.txt 2>&1
echo ANALYZE_EXIT %errorlevel% %time% >> build\claude_analyze_files.txt
call flutter test --no-pub test\license_v4_test.dart >> build\claude_analyze_files.txt 2>&1
echo TEST_EXIT %errorlevel% %time% >> build\claude_analyze_files.txt
